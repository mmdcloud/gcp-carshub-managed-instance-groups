# Registering vault provider
data "vault_generic_secret" "sql" {
  path = "secret/sql"
}

# Getting project information
data "google_project" "project" {}
data "google_storage_project_service_account" "carshub_gcs_account" {}

# Enable APIS
module "carshub_apis" {
  source = "../../modules/apis"
  apis = [
    "compute.googleapis.com",
    "secretmanager.googleapis.com",
    "artifactregistry.googleapis.com",
    "run.googleapis.com",
    "cloudfunctions.googleapis.com",
    "eventarc.googleapis.com",
    "sqladmin.googleapis.com"
  ]
  disable_on_destroy = false
  project_id         = data.google_project.project.project_id
}

# VPC Creation
module "carshub_vpc" {
  source                  = "../../modules/network/vpc"
  auto_create_subnetworks = false
  vpc_name                = "carshub-vpc"
}

# Subnets Creation
module "carshub_public_subnets" {
  source                   = "../../modules/network/subnet"
  name                     = "carshub-public-subnet"
  subnets                  = var.public_subnets
  vpc_id                   = module.carshub_vpc.vpc_id
  private_ip_google_access = false
  location                 = var.location
}

module "carshub_private_subnets" {
  source                   = "../../modules/network/subnet"
  name                     = "carshub-private-subnet"
  subnets                  = var.private_subnets
  vpc_id                   = module.carshub_vpc.vpc_id
  private_ip_google_access = true
  location                 = var.location
}

# Firewall Creation
module "carshub_firewall" {
  source = "../../modules/network/firewall"
  firewall_data = [
    {
      allow_list = [
        {
          ports    = ["80"]
          protocol = "tcp"
        },
        {
          ports    = ["22"]
          protocol = "tcp"
        },
        {
          ports    = ["3000"]
          protocol = "tcp"
        }
      ]
      firewall_name      = "carshub-firewall"
      firewall_direction = "INGRESS"
      source_ranges      = ["0.0.0.0/0"]
      source_tags        = []
      target_tags        = [var.frontend_health_check, var.backend_health_check]
    }
  ]
  vpc_id = module.carshub_vpc.vpc_id
}

# Serverless VPC Creation
module "carshub_vpc_connectors" {
  source   = "../../modules/network/vpc-connector"
  vpc_name = module.carshub_vpc.vpc_name
  serverless_vpc_connectors = [
    {
      name          = "carshub-connector"
      ip_cidr_range = "10.8.0.0/28"
      min_instances = 2
      max_instances = 5
      machine_type  = "f1-micro"
    }
  ]
}

# Instance templates
module "carshub_frontend_instance" {
  source        = "../../modules/compute"
  auto_delete   = var.ubuntu_auto_delete
  boot          = var.ubuntu_boot
  source_image  = var.ubuntu_source_os_image
  template_name = var.frontend_template_name
  machine_type  = var.ubuntu_machine_type
  network       = module.carshub_vpc.vpc_id
  subnetwork    = module.carshub_private_subnets.subnets[0].id
  startup_script = templatefile("${path.module}/../../scripts/user_data_frontend.sh", {
    BASE_URL = "http://${module.backend_lb.address}"
    CDN_URL  = module.carshub_cdn.cdn_ip_address
  })
  port_specification     = var.port_specification
  request_path           = "/auth/signin"
  health_check_name      = var.frontend_health_check
  location               = var.location
  mig_base_instance_name = var.base_instance_name
  instance_template_name = var.frontend_template_name
  mig_named_port_name    = var.frontend_named_port_name
  mig_named_port_port    = var.named_port_frontend
  mig_name               = var.frontend_mig_name
  mig_target_size        = var.target_size
}

module "carshub_backend_instance" {
  source             = "../../modules/compute"
  auto_delete        = var.ubuntu_auto_delete
  boot               = var.ubuntu_boot
  source_image       = var.ubuntu_source_os_image
  template_name      = var.backend_template_name
  machine_type       = var.ubuntu_machine_type
  network            = module.carshub_vpc.vpc_id
  subnetwork         = module.carshub_private_subnets.subnets[1].id
  port_specification = var.port_specification
  health_check_name  = var.backend_health_check
  request_path       = "/"
  startup_script = templatefile("${path.module}/../../scripts/user_data_backend.sh", {
    DB_PATH = module.carshub_db.db_ip_address
    CREDS   = module.carshub_sql_password_secret.secret_data
    UN      = "mohit"
  })
  location               = var.location
  mig_base_instance_name = var.base_instance_name
  instance_template_name = var.backend_template_name
  mig_named_port_name    = var.backend_named_port_name
  mig_named_port_port    = var.named_port_backend
  mig_name               = var.backend_mig_name
  mig_target_size        = var.target_size
}

# Frontend Load Balancer
module "frontend_lb" {
  source                                  = "../../modules/load-balancer"
  forwarding_port_range                   = "80"
  forwarding_rule_name                    = "carshub-frontend-global-forwarding-rule"
  forwarding_scheme                       = "EXTERNAL"
  global_address_type                     = "EXTERNAL"
  url_map_name                            = "carshub-frontend-url-map"
  global_address_name                     = "carshub-frontend-lb-global-address"
  target_proxy_name                       = "carshub-frontend-target-proxy"
  backend_service_name                    = "carshub-frontend-service"
  backend_service_enable_cdn              = false
  backend_service_port_name               = "carshub-frontend-port"
  backend_service_protocol                = "HTTP"
  backend_service_timeout_sec             = 10
  backend_service_load_balancing_scheme   = "EXTERNAL"
  backend_service_custom_request_headers  = ["X-Client-Geo-Location: {client_region_subdivision}, {client_city}"]
  backend_service_custom_response_headers = ["X-Cache-Hit: {cdn_cache_status}"]
  backend_service_health_checks           = [module.carshub_frontend_instance.health_check_id]
  backend_service_backends = [
    {
      group           = "${module.carshub_frontend_instance.instance_group}"
      balancing_mode  = "UTILIZATION"
      capacity_scaler = 1.0
    }
  ]
}

# Backend Load Balancer
module "backend_lb" {
  source                                  = "../../modules/load-balancer"
  forwarding_port_range                   = "80"
  forwarding_rule_name                    = "carshub-backend-global-forwarding-rule"
  forwarding_scheme                       = "EXTERNAL"
  global_address_type                     = "EXTERNAL"
  url_map_name                            = "carshub-backend-url-map"
  global_address_name                     = "carshub-backend-lb-global-address"
  target_proxy_name                       = "carshub-backend-target-proxy"
  backend_service_name                    = "carshub-backend-service"
  backend_service_enable_cdn              = false
  backend_service_port_name               = "carshub-backend-port"
  backend_service_protocol                = "HTTP"
  backend_service_timeout_sec             = 10
  backend_service_load_balancing_scheme   = "EXTERNAL"
  backend_service_custom_request_headers  = ["X-Client-Geo-Location: {client_region_subdivision}, {client_city}"]
  backend_service_custom_response_headers = ["X-Cache-Hit: {cdn_cache_status}"]
  backend_service_health_checks           = [module.carshub_backend_instance.health_check_id]
  backend_service_backends = [
    {
      group           = "${module.carshub_backend_instance.instance_group}"
      balancing_mode  = "UTILIZATION"
      capacity_scaler = 1.0
    }
  ]
}

# GCS
module "carshub_media_bucket" {
  source   = "../../modules/gcs"
  location = var.location
  name     = "carshub-media"
  cors = [
    {
      origin          = ["http://${module.frontend_lb.address}"]
      max_age_seconds = 3600
      method          = ["GET", "POST", "PUT", "DELETE"]
      response_header = ["*"]
    }
  ]
  contents = [
    {
      name        = "images/"
      content     = " "
      source_path = ""
    },
    {
      name        = "documents/"
      content     = " "
      source_path = ""
    }
  ]
  versioning = true
  lifecycle_rules = [
    {
      condition = {
        age = 1
      }
      action = {
        type          = "AbortIncompleteMultipartUpload"
        storage_class = null
      }
    },
    {
      condition = {
        age = 1095
      }
      action = {
        storage_class = "ARCHIVE"
        type          = "SetStorageClass"
      }
    }
  ]
  notifications = [
    {
      topic_id = module.carshub_media_bucket_pubsub.topic_id
    }
  ]
  force_destroy               = true
  uniform_bucket_level_access = true
}

module "carshub_media_bucket_code" {
  source   = "../../modules/gcs"
  location = var.location
  name     = "carshub-media-code"
  cors     = []
  contents = [
    {
      name        = "code.zip"
      source_path = "${path.root}/../../files/code.zip"
      content     = ""
    }
  ]
  force_destroy               = true
  uniform_bucket_level_access = true
}

# Cloud storage IAM binding
resource "google_storage_bucket_iam_binding" "storage_iam_binding" {
  bucket = module.carshub_media_bucket.bucket_name
  role   = "roles/storage.objectViewer"

  members = [
    "allUsers"
  ]
}

# Secret Manager
module "carshub_sql_password_secret" {
  source      = "../../modules/secret-manager"
  secret_data = tostring(data.vault_generic_secret.sql.data["password"])
  secret_id   = var.sql_password_secret_id
  depends_on  = [module.carshub_apis]
}

# Cloud SQL
module "carshub_db" {
  source                      = "../../modules/cloud-sql"
  name                        = "carshub-db-instance"
  db_name                     = "carshub"
  db_user                     = "mohit"
  db_version                  = "MYSQL_8_0"
  location                    = var.location
  tier                        = "db-f1-micro"
  ipv4_enabled                = false
  availability_type           = "ZONAL"
  disk_size                   = 10
  deletion_protection_enabled = false
  backup_configuration        = []
  vpc_self_link               = module.carshub_vpc.self_link
  vpc_id                      = module.carshub_vpc.vpc_id
  password                    = module.carshub_sql_password_secret.secret_data
  depends_on                  = [module.carshub_sql_password_secret]
}

# CDN for handling media files
module "carshub_cdn" {
  source                = "../../modules/cdn"
  bucket_name           = module.carshub_media_bucket.bucket_name
  enable_cdn            = true
  description           = "Content delivery network for media files"
  name                  = "carshub-media-cdn"
  forwarding_port_range = "80"
  forwarding_rule_name  = "carshub-cdn-global-forwarding-rule"
  forwarding_scheme     = "EXTERNAL"
  global_address_type   = "EXTERNAL"
  url_map_name          = "carshub-cdn-compute-url-map"
  global_address_name   = "carshub-cdn-lb-global-address"
  target_proxy_name     = "carshub-cdn-target-proxy"
}

# Service Account
module "carshub_function_app_service_account" {
  source       = "../../modules/service-account"
  account_id   = "carshub-service-account"
  display_name = "CarsHub Service Account"
  project_id   = data.google_project.project.project_id
  permissions = [
    "roles/run.invoker",
    "roles/eventarc.eventReceiver",
    "roles/cloudsql.client",
    "roles/artifactregistry.reader",
    "roles/secretmanager.admin",
    "roles/pubsub.admin"
  ]
}

// Create a Pub/Sub topic.
resource "google_pubsub_topic_iam_binding" "binding" {
  topic   = module.carshub_media_bucket_pubsub.topic_id
  role    = "roles/pubsub.publisher"
  members = ["serviceAccount:${data.google_storage_project_service_account.carshub_gcs_account.email_address}"]
}

# Creating a Pub/Sub topic to send cloud storage events
module "carshub_media_bucket_pubsub" {
  source = "../../modules/pubsub"
  topic  = "carshub_media_bucket_events"
}

# Cloud Run Function
module "carshub_media_update_function" {
  source                       = "../../modules/cloud-run-function"
  function_name                = "carshub-media-function"
  function_description         = "A function to update media details in SQL database after the upload trigger"
  handler                      = "handler"
  runtime                      = "python312"
  location                     = var.location
  storage_source_bucket        = module.carshub_media_bucket_code.bucket_name
  storage_source_bucket_object = module.carshub_media_bucket_code.object_name[0].name
  build_env_variables = {
    DB_USER     = module.carshub_db.db_user
    DB_NAME     = module.carshub_db.db_name
    SECRET_NAME = module.carshub_sql_password_secret.secret_name
    DB_PATH     = module.carshub_db.db_ip_address
  }
  all_traffic_on_latest_revision      = true
  vpc_connector                       = module.carshub_vpc_connectors.vpc_connectors[0].id
  vpc_connector_egress_settings       = "ALL_TRAFFIC"
  ingress_settings                    = "ALLOW_INTERNAL_ONLY"
  function_app_service_account_email  = module.carshub_function_app_service_account.sa_email
  max_instance_count                  = 3
  min_instance_count                  = 1
  available_memory                    = "256M"
  timeout_seconds                     = 60
  event_trigger_event_type            = "google.cloud.pubsub.topic.v1.messagePublished"
  event_trigger_topic                 = module.carshub_media_bucket_pubsub.topic_id
  event_trigger_retry_policy          = "RETRY_POLICY_RETRY"
  event_trigger_service_account_email = module.carshub_function_app_service_account.sa_email
  event_filters = [
    # {
    #   attribute = "bucket"
    #   value     = module.carshub_media_bucket.bucket_name
    # }
  ]
  depends_on = [module.carshub_function_app_service_account]
}
