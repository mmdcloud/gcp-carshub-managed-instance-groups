# Getting project information
data "google_project" "project" {}
data "google_storage_project_service_account" "carshub_gcs_account" {}

# Enable APIS
module "carshub_apis" {
  source = "./modules/apis"
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

# VPC Module
module "carshub_vpc" {
  source                  = "./modules/vpc"
  auto_create_subnetworks = false
  vpc_name                = var.vpc_name
  location                = var.location
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
      target_tags        = [var.frontend_health_check, var.backend_health_check]
    }
  ]
  subnets = [
    {
      name          = "carshub-subnet"
      ip_cidr_range = "10.0.1.0/24"
    }
  ]
}

# Creating a Serverless VPC connector
module "carshub_connector" {
  source        = "./modules/serverless-vpc"
  name          = "carshub-connector"
  ip_cidr_range = "10.8.0.0/28"
  network_name  = module.carshub_vpc.vpc_name
  min_instances = 2
  max_instances = 5
  machine_type  = "f1-micro"
}


# Instance templates
module "carshub_frontend_instance_template" {
  source             = "./modules/compute"
  auto_delete        = var.ubuntu_auto_delete
  boot               = var.ubuntu_boot
  source_image       = var.ubuntu_source_os_image
  template_name      = var.frontend_template_name
  machine_type       = var.ubuntu_machine_type
  network            = module.carshub_vpc.vpc_id
  subnetwork         = module.carshub_vpc.subnet_info[0].id
  startup_script     = <<-EOT
#!/bin/bash
sudo apt-get update -y
sudo apt-get upgrade -y
# Installing Nginx
sudo apt-get install -y nginx
# Installing Node.js
curl -sL https://deb.nodesource.com/setup_20.x -o nodesource_setup.sh
sudo bash nodesource_setup.sh
sudo apt install nodejs -y
# Installing PM2
sudo npm i -g pm2

cd /home/ubuntu
mkdir nodeapp
# Checking out from Version Control
git clone https://github.com/mmdcloud/carshub-gcp-managed-instance-groups
cd carshub-gcp-managed-instance-groups/frontend
cp -r . /home/ubuntu/nodeapp/
cd /home/ubuntu/nodeapp/
# Setting up env variables
cat > .env <<EOL
BASE_URL="${module.backend_lb.address}"
CDN_URL="${module.cdn_lb.address}"
EOL
# Copying Nginx config
cp scripts/default /etc/nginx/sites-available/
# Installing dependencies
sudo npm i

# Building the project
sudo npm run build
# Starting PM2 app
pm2 start ecosystem.config.js
sudo service nginx restart
    EOT
  port_specification = var.port_specification
  health_check_name  = var.frontend_health_check
}

module "carshub_backend_instance_template" {
  source             = "./modules/compute"
  auto_delete        = var.ubuntu_auto_delete
  boot               = var.ubuntu_boot
  source_image       = var.ubuntu_source_os_image
  template_name      = var.backend_template_name
  machine_type       = var.ubuntu_machine_type
  network            = module.carshub_vpc.vpc_id
  subnetwork         = module.carshub_vpc.subnet_info[0].id
  port_specification = var.port_specification
  health_check_name  = var.backend_health_check
  startup_script     = <<-EOT
#! /bin/bash
apt-get update -y
apt-get upgrade -y
# Installing Nginx
apt-get install -y nginx
# Installing Node.js
curl -sL https://deb.nodesource.com/setup_20.x -o nodesource_setup.sh
bash nodesource_setup.sh
apt install nodejs -y
# Installing PM2
npm i -g pm2
# Installing Nest CLI
npm install -g @nestjs/cli
mkdir nodeapp
# Checking out from Version Control
git clone https://github.com/mmdcloud/carshub-gcp-managed-instance-groups
cd carshub-gcp-managed-instance-groups/backend/api
cp -r . ../nodeapp/
cd ../nodeapp/
# Copying Nginx config
cp scripts/default /etc/nginx/sites-available/
# Installing dependencies
npm i

cat > .env <<EOL
DB_PATH="${module.carshub_db.db_ip_address}"
UN="mohit"
CREDS="${module.carshub_sql_password_secret.secret_data}"
EOL
# Building the project
npm run build
# Starting PM2 app
pm2 start dist/main.js
service nginx restart
    EOT
}

# Managed Instane Groups
module "carshub_frontend_mig" {
  source                 = "./modules/mig"
  base_instance_name     = var.base_instance_name
  instance_template      = module.carshub_frontend_instance_template.template_id
  instance_template_name = var.frontend_template_name
  named_port_name        = var.frontend_named_port_name
  named_port_port        = var.named_port_frontend
  mig_name               = var.frontend_mig_name
  location               = var.location
  target_size            = var.target_size
}

module "carshub_backend_mig" {
  source                 = "./modules/mig"
  base_instance_name     = var.base_instance_name
  instance_template      = module.carshub_backend_instance_template.template_id
  instance_template_name = var.backend_template_name
  named_port_name        = var.backend_named_port_name
  named_port_port        = var.named_port_backend
  mig_name               = var.backend_mig_name
  location               = var.location
  target_size            = var.target_size
}

# Frontend Load Balancer
module "frontend_lb" {
  source                = "./modules/load-balancer"
  forwarding_port_range = "80"
  forwarding_rule_name  = "carshub-frontend-global-forwarding-rule"
  forwarding_scheme     = "EXTERNAL"
  global_address_type   = "EXTERNAL"
  url_map_name          = "carshub-frontend-url-map"
  global_address_name   = "carshub-frontend-lb-global-address"
  target_proxy_name     = "carshub-frontend-target-proxy"
  url_map_service       = module.frontend_lb_service.self_link
}

# Frontend Load Balancer Service
module "frontend_lb_service" {
  source     = "./modules/compute/backend"
  name       = "carshub-frontend-service"
  enable_cdn = true
  port_name  = "carshub-frontend-port"
  protocol   = "HTTP"
  backends = [
    {
      group           = "${module.carshub_frontend_mig.instance_group}"
      balancing_mode  = "UTILIZATION"
      capacity_scaler = 1.0
    }
  ]
  timeout_sec             = 10
  load_balancing_scheme   = "EXTERNAL"
  custom_request_headers  = ["X-Client-Geo-Location: {client_region_subdivision}, {client_city}"]
  custom_response_headers = ["X-Cache-Hit: {cdn_cache_status}"]
  health_checks           = [module.carshub_frontend_instance_template.health_check_id]
}

# Backend Load Balancer
module "backend_lb" {
  source                = "./modules/load-balancer"
  forwarding_port_range = "80"
  forwarding_rule_name  = "carshub-backend-global-forwarding-rule"
  forwarding_scheme     = "EXTERNAL"
  global_address_type   = "EXTERNAL"
  url_map_name          = "carshub-backend-url-map"
  global_address_name   = "carshub-backend-lb-global-address"
  target_proxy_name     = "carshub-backend-target-proxy"
  url_map_service       = module.backend_lb_service.self_link
}

# Backend Load Balancer Service
module "backend_lb_service" {
  source     = "./modules/compute/backend"
  name       = "carshub-backend-service"
  enable_cdn = true
  port_name  = "carshub-backend-port"
  protocol   = "HTTP"
  backends = [
    {
      group           = "${module.carshub_backend_mig.instance_group}"
      balancing_mode  = "UTILIZATION"
      capacity_scaler = 1.0
    }
  ]
  timeout_sec             = 10
  load_balancing_scheme   = "EXTERNAL"
  custom_request_headers  = ["X-Client-Geo-Location: {client_region_subdivision}, {client_city}"]
  custom_response_headers = ["X-Cache-Hit: {cdn_cache_status}"]
  health_checks           = [module.carshub_backend_instance_template.health_check_id]
}


# GCS
module "carshub_media_bucket" {
  source   = "./modules/gcs"
  location = var.location
  name     = "carshub-media"
  cors = [
    {
      origin          = [module.frontend_lb.address]
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
  force_destroy               = true
  uniform_bucket_level_access = true
}

module "carshub_media_bucket_code" {
  source   = "./modules/gcs"
  location = var.location
  name     = "carshub-media-code"
  cors     = []
  contents = [
    {
      name        = "code.zip"
      source_path = "${path.root}/files/code.zip"
      content     = ""
    }
  ]
  force_destroy               = true
  uniform_bucket_level_access = true
}

# Cloud storage IAM binding
resource "google_storage_bucket_iam_binding" "storage_iam_binding" {
  bucket = module.carshub_media_bucket.bucket_name
  role   = "roles/storage.objectAdmin"

  members = [
    "allUsers"
  ]
}

# Secret Manager
module "carshub_sql_password_secret" {
  source      = "./modules/secret-manager"
  secret_data = var.sql_password_secret_data
  secret_id   = var.sql_password_secret_id
  depends_on  = [module.carshub_apis]
}

# Cloud SQL
module "carshub_db" {
  source        = "./modules/cloud-sql"
  name          = "carshub-db-instance"
  db_name       = "carshub"
  db_user       = "mohit"
  db_version    = "MYSQL_8_0"
  location      = var.location
  tier          = "db-f1-micro"
  ipv4_enabled  = false
  vpc_self_link = module.carshub_vpc.self_link
  vpc_id        = module.carshub_vpc.vpc_id
  password      = module.carshub_sql_password_secret.secret_data
  depends_on    = [module.carshub_sql_password_secret]
}

# CDN for handling media files
module "carshub_cdn" {
  source      = "./modules/cdn"
  bucket_name = module.carshub_media_bucket.bucket_name
  enable_cdn  = true
  description = "Content delivery network for media files"
  name        = "carshub-media-cdn"
}

# Load Balancer
module "cdn_lb" {
  source                = "./modules/load-balancer"
  forwarding_port_range = "80"
  forwarding_rule_name  = "carshub-cdn-global-forwarding-rule"
  forwarding_scheme     = "EXTERNAL"
  global_address_type   = "EXTERNAL"
  url_map_name          = "carshub-cdn-compute-url-map"
  global_address_name   = "carshub-cdn-lb-global-address"
  target_proxy_name     = "carshub-cdn-target-proxy"
  url_map_service       = module.carshub_cdn.cdn_self_link
  depends_on            = [module.carshub_apis]
}

# Service Account
module "carshub_service_account" {
  source       = "./modules/service-account"
  account_id   = "carshub-service-account"
  display_name = "CarsHub Service Account"
}

# Service Account Permissions
module "carshub_gcs_account_pubsub_publishing" {
  source  = "./modules/service-account-iam"
  project = data.google_project.project.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${data.google_storage_project_service_account.carshub_gcs_account.email_address}"
}

module "invoking_permission" {
  source     = "./modules/service-account-iam"
  project    = data.google_project.project.project_id
  role       = "roles/run.invoker"
  member     = "serviceAccount:${module.carshub_service_account.sa_email}"
  depends_on = [module.carshub_gcs_account_pubsub_publishing]
}

module "storage_admin" {
  source     = "./modules/service-account-iam"
  project    = data.google_project.project.project_id
  role       = "roles/storage.admin"
  member     = "serviceAccount:${module.carshub_service_account.sa_email}"
  depends_on = [module.carshub_gcs_account_pubsub_publishing]
}

module "event_receiving_permission" {
  source     = "./modules/service-account-iam"
  project    = data.google_project.project.project_id
  role       = "roles/eventarc.eventReceiver"
  member     = "serviceAccount:${module.carshub_service_account.sa_email}"
  depends_on = [module.invoking_permission]
}

module "cloud_sql_access_permission" {
  source  = "./modules/service-account-iam"
  project = data.google_project.project.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${module.carshub_service_account.sa_email}"
}

module "artifactregistry_reader_permission" {
  source     = "./modules/service-account-iam"
  project    = data.google_project.project.project_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${module.carshub_service_account.sa_email}"
  depends_on = [module.event_receiving_permission]
}

module "secret_manager_accessor" {
  source     = "./modules/service-account-iam"
  project    = data.google_project.project.project_id
  role       = "roles/secretmanager.secretAccessor"
  member     = "serviceAccount:${module.carshub_service_account.sa_email}"
  depends_on = [module.event_receiving_permission]
}

module "service_account_token_creator" {
  source     = "./modules/service-account-iam"
  project    = data.google_project.project.project_id
  role       = "roles/iam.serviceAccountTokenCreator"
  member     = "serviceAccount:${module.carshub_service_account.sa_email}"
  depends_on = [module.event_receiving_permission]
}

# Cloud Run Function
module "carshub_media_update_function" {
  source               = "./modules/cloud-run-function"
  function_name        = "carshub-media-function"
  function_description = "A function to update media details in SQL database after the upload trigger"
  handler              = "handler"
  runtime              = "python312"
  location             = var.location
  storage_source = [
    {
      bucket = module.carshub_media_bucket_code.bucket_name
      object = module.carshub_media_bucket_code.object_name[0].name
    }
  ]
  build_env_variables = {
    INSTANCE_CONNECTION_NAME = "${data.google_project.project.project_id}:${var.location}:${module.carshub_db.db_name}"
    DB_USER                  = module.carshub_db.db_user
    DB_NAME                  = module.carshub_db.db_name
    DB_PASSWORD              = module.carshub_sql_password_secret.secret_data
    DB_PATH                  = module.carshub_db.db_ip_address
  }
  all_traffic_on_latest_revision = true
  vpc_connector                  = module.carshub_connector.connector_id
  vpc_connector_egress_settings  = "ALL_TRAFFIC"
  ingress_settings               = "ALLOW_ALL"
  sa                             = module.carshub_service_account.sa_email
  max_instance_count             = 3
  min_instance_count             = 1
  available_memory               = "256M"
  timeout_seconds                = 60
  event_triggers = [
    {
      event_type            = "google.cloud.storage.object.v1.finalized"
      retry_policy          = "RETRY_POLICY_RETRY"
      service_account_email = module.carshub_service_account.sa_email
      event_filters = [
        {
          attribute = "bucket"
          value     = module.carshub_media_bucket.bucket_name
        }
      ]
    }
  ]
  depends_on = [
    module.event_receiving_permission,
    module.artifactregistry_reader_permission,
    module.cloud_sql_access_permission
  ]
}
