# -----------------------------------------------------------------------------------------
# Registering vault provider
# -----------------------------------------------------------------------------------------
data "vault_generic_secret" "sql" {
  path = "secret/sql"
}

# -----------------------------------------------------------------------------------------
# Getting project information
# -----------------------------------------------------------------------------------------
data "google_project" "project" {}
data "google_storage_project_service_account" "carshub_gcs_account" {}

# -----------------------------------------------------------------------------------------
# Enable APIS
# -----------------------------------------------------------------------------------------
module "carshub_apis" {
  source = "../../../modules/apis"
  apis = [
    "compute.googleapis.com",
    "secretmanager.googleapis.com",
    "artifactregistry.googleapis.com",
    "run.googleapis.com",
    "cloudfunctions.googleapis.com",
    "eventarc.googleapis.com",
    "sqladmin.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "cloudtrace.googleapis.com",
    "cloudprofiler.googleapis.com"
  ]
  disable_on_destroy = false
  project_id         = data.google_project.project.project_id
}

# -----------------------------------------------------------------------------------------
# VPC Configuration
# -----------------------------------------------------------------------------------------
module "carshub_vpc" {
  source                          = "../../../modules/vpc"
  vpc_name                        = "carshub-vpc"
  delete_default_routes_on_create = false
  auto_create_subnetworks         = false
  routing_mode                    = "REGIONAL"
  region                          = var.location
  subnets                         = []
  firewall_data                   = []
}

# -----------------------------------------------------------------------------------------
# Serverless VPC Connectors
# -----------------------------------------------------------------------------------------
module "carshub_vpc_connectors" {
  source   = "../../../modules/network/vpc-connector"
  vpc_name = module.carshub_vpc.vpc_name
  serverless_vpc_connectors = [
    {
      name          = "carshub-connector"
      ip_cidr_range = "10.8.0.0/28"
      min_instances = 2
      max_instances = 3
      machine_type  = "e2-micro"
    }
  ]
}

# -----------------------------------------------------------------------------------------
# Service Accounts
# -----------------------------------------------------------------------------------------
module "carshub_function_app_service_account" {
  source        = "../../../modules/service-account"
  account_id    = "carshub-service-account"
  display_name  = "CarsHub Service Account"
  project_id    = data.google_project.project.project_id
  member_prefix = "serviceAccount"
  permissions = [
    "roles/run.invoker",
    "roles/eventarc.eventReceiver",
    "roles/cloudsql.client",
    "roles/artifactregistry.reader",
    # "roles/secretmanager.admin",
    "roles/secretmanager.secretAccessor",
    "roles/pubsub.publisher"
  ]
}

# -----------------------------------------------------------------------------------------
# Cloud Armor WAF protection for Load Balancers
# -----------------------------------------------------------------------------------------
module "cloud_armor" {
  source  = "GoogleCloudPlatform/cloud-armor/google"
  version = "~> 5.0"

  project_id  = data.google_project.project.project_id
  name        = "carshub-security-policy"
  description = "CarHub Cloud Armor security policy with WAF rules"

  default_rule_action = "allow"
  type                = "CLOUD_ARMOR"

  layer_7_ddos_defense_enable          = true
  layer_7_ddos_defense_rule_visibility = "STANDARD"
  user_ip_request_headers              = ["True-Client-IP"]

  security_rules = {
    # Rate limiting
    "rate_limit_rule" = {
      action        = "rate_based_ban"
      priority      = 1
      description   = "Rate limiting rule"
      src_ip_ranges = ["*"]

      rate_limit_options = {
        conform_action                    = "allow"
        exceed_action                     = "deny(429)"
        enforce_on_key                    = "IP"
        ban_duration_sec                  = 600
        rate_limit_threshold_count        = 100
        rate_limit_threshold_interval_sec = 60
      }

      match = {
        versioned_expr = "SRC_IPS_V1"
        config = {
          src_ip_ranges = ["*"]
        }
      }
    }

    # Block known bad IPs (you should maintain this list)
    "block_bad_ips" = {
      action        = "deny(403)"
      priority      = 10
      description   = "Block known malicious IPs"
      src_ip_ranges = ["*"]

      match = {
        versioned_expr = "SRC_IPS_V1"
        config = {
          src_ip_ranges = [
            # Add known malicious IPs here
            # "1.2.3.4/32",
            # "5.6.7.8/32",
          ]
        }
      }
    }

    # Geographic restrictions (if needed)
    "geo_blocking" = {
      action        = "deny(403)"
      priority      = 11
      description   = "Block traffic from specific countries"
      src_ip_ranges = ["*"]

      match = {
        expr = {
          expression = "origin.region_code in ['CN', 'RU']"
        }
      }
    }
  }

  pre_configured_rules = {
    "xss-stable_level_2" = {
      action            = "deny(403)"
      priority          = 2
      target_rule_set   = "xss-v33-stable"
      sensitivity_level = 2
    }

    "sqli-stable_level_2" = {
      action            = "deny(403)"
      priority          = 3
      target_rule_set   = "sqli-v33-stable"
      sensitivity_level = 2
    }

    "lfi-stable_level_2" = {
      action            = "deny(403)"
      priority          = 4
      target_rule_set   = "lfi-v33-stable"
      sensitivity_level = 2
    }

    "rce-stable_level_2" = {
      action            = "deny(403)"
      priority          = 5
      target_rule_set   = "rce-v33-stable"
      sensitivity_level = 2
    }

    "rfi-stable_level_2" = {
      action            = "deny(403)"
      priority          = 6
      target_rule_set   = "rfi-v33-stable"
      sensitivity_level = 2
    }

    "scannerdetection-stable_level_2" = {
      action            = "deny(403)"
      priority          = 7
      target_rule_set   = "scannerdetection-v33-stable"
      sensitivity_level = 2
    }

    "protocolattack-stable_level_2" = {
      action            = "deny(403)"
      priority          = 8
      target_rule_set   = "protocolattack-v33-stable"
      sensitivity_level = 2
    }

    "sessionfixation-stable_level_2" = {
      action            = "deny(403)"
      priority          = 9
      target_rule_set   = "sessionfixation-v33-stable"
      sensitivity_level = 2
    }
  }
}

# -----------------------------------------------------------------------------------------
# SECURITY: SSL/TLS Configuration
# -----------------------------------------------------------------------------------------
resource "google_compute_managed_ssl_certificate" "carshub_frontend_ssl_cert" {
  name = "carshub-frontend-ssl-cert"
  managed {
    domains = ["carshub-frontend.${var.domain}"]
  }
}

resource "google_compute_managed_ssl_certificate" "carshub_backend_ssl_cert" {
  name = "carshub-backend-ssl-cert"
  managed {
    domains = ["carshub-api.${var.domain}"]
  }
}

# -----------------------------------------------------------------------------------------
# Instance templates
# -----------------------------------------------------------------------------------------
module "carshub_frontend_instance" {
  source        = "../../../modules/compute"
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
  source             = "../../../modules/compute"
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
    UN      = module.carshub_sql_username_secret.secret_id
  })
  location               = var.location
  mig_base_instance_name = var.base_instance_name
  instance_template_name = var.backend_template_name
  mig_named_port_name    = var.backend_named_port_name
  mig_named_port_port    = var.named_port_backend
  mig_name               = var.backend_mig_name
  mig_target_size        = var.target_size
}

# -----------------------------------------------------------------------------------------
# Load Balancers
# -----------------------------------------------------------------------------------------
module "frontend_lb" {
  source                                  = "../../../modules/load-balancer"
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
  # security_policy                         = module.cloud_armor.policy.id
  backend_service_backends = [
    {
      group           = "${module.carshub_frontend_instance.instance_group}"
      balancing_mode  = "UTILIZATION"
      capacity_scaler = 1.0
    }
  ]
}

module "backend_lb" {
  source                                  = "../../../modules/load-balancer"
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
  # security_policy                         = module.cloud_armor.policy.id
  backend_service_backends = [
    {
      group           = "${module.carshub_backend_instance.instance_group}"
      balancing_mode  = "UTILIZATION"
      capacity_scaler = 1.0
    }
  ]
}

# -----------------------------------------------------------------------------------------
# Google Cloud Storage Configuration
# -----------------------------------------------------------------------------------------
module "carshub_media_bucket" {
  source   = "../../../modules/gcs"
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
  source   = "../../../modules/gcs"
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

# -----------------------------------------------------------------------------------------
# Secret Manager Configuration
# -----------------------------------------------------------------------------------------
module "carshub_sql_password_secret" {
  source      = "../../../modules/secret-manager"
  secret_data = tostring(data.vault_generic_secret.sql.data["password"])
  secret_id   = "carshub_db_password_secret"
  depends_on  = [module.carshub_apis]
}

module "carshub_sql_username_secret" {
  source      = "../../../modules/secret-manager"
  secret_data = tostring(data.vault_generic_secret.sql.data["username"])
  secret_id   = "carshub_db_username_secret"
  depends_on  = [module.carshub_apis]
}

# -----------------------------------------------------------------------------------------
# Cloud SQL Configuration
# -----------------------------------------------------------------------------------------
module "carshub_db" {
  source                      = "../../../modules/cloud-sql"
  name                        = "carshub-db-instance"
  db_name                     = "carshub"
  db_user                     = module.carshub_sql_username_secret.secret_data
  db_version                  = "MYSQL_8_0"
  location                    = var.location
  tier                        = "db-custom-2-8192"
  availability_type           = "REGIONAL"
  disk_size                   = 100 # GB
  disk_type                   = "PD_SSD"
  disk_autoresize             = true
  disk_autoresize_limit       = 500 # GB
  ipv4_enabled                = false
  deletion_protection_enabled = false
  backup_configuration = [
    {
      enabled                        = true
      binary_log_enabled             = true
      start_time                     = "03:00"
      location                       = var.location
      point_in_time_recovery_enabled = false
      backup_retention_settings = [
        {
          retained_backups = 30
          retention_unit   = "COUNT"
        }
      ]
    }
  ]
  database_flags = [
    {
      name  = "max_connections"
      value = "1000"
    },
    {
      name  = "skip_show_database"
      value = "on"
    },
    {
      name  = "slow_query_log"
      value = "on"
    },
    {
      name  = "long_query_time"
      value = "2"
    },
    {
      name  = "log_output"
      value = "FILE"
    },
    # Performance tuning
    {
      name  = "innodb_buffer_pool_size"
      value = "10737418240" # 10GB for 16GB instance
    },
    {
      name  = "innodb_log_file_size"
      value = "536870912" # 512MB
    }
  ]
  vpc_self_link = module.carshub_vpc.self_link
  vpc_id        = module.carshub_vpc.vpc_id
  password      = module.carshub_sql_password_secret.secret_data
  depends_on    = [module.carshub_sql_password_secret]
}

# -----------------------------------------------------------------------------------------
# CDN Configuration
# -----------------------------------------------------------------------------------------
module "carshub_cdn" {
  source                = "../../../modules/cdn"
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

# -----------------------------------------------------------------------------------------
# PubSub Configuration
# -----------------------------------------------------------------------------------------
resource "google_pubsub_topic_iam_binding" "binding" {
  topic   = module.carshub_media_bucket_pubsub.topic_id
  role    = "roles/pubsub.publisher"
  members = ["serviceAccount:${data.google_storage_project_service_account.carshub_gcs_account.email_address}"]
}

# Creating a Pub/Sub topic to send cloud storage events
module "carshub_media_bucket_pubsub" {
  source = "../../../modules/pubsub"
  topic  = "carshub_media_bucket_events"
}

# -----------------------------------------------------------------------------------------
# Cloud Run Function Configuration
# -----------------------------------------------------------------------------------------
module "carshub_media_update_function" {
  source                       = "../../../modules/cloud-run-function"
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
  event_filters                       = []
  depends_on                          = [module.carshub_function_app_service_account]
}

# -----------------------------------------------------------------------------------------
# Uptime checks
# -----------------------------------------------------------------------------------------
module "frontend_uptime_check" {
  source              = "../../../modules/observability/uptime_checks"
  display_name        = "Frontend Uptime Check"
  timeout             = "30s"
  period              = "60s"
  http_path           = "/auth/signin"
  http_port           = "80"
  http_request_method = "GET"
  http_validate_ssl   = false
  resource_type       = "uptime_url"
  resource_host       = module.frontend_lb.address
  checker_type        = "STATIC_IP_CHECKERS"
}

module "backend_uptime_check" {
  source              = "../../../modules/observability/uptime_checks"
  display_name        = "Backend Uptime Check"
  timeout             = "30s"
  period              = "60s"
  http_path           = "/"
  http_port           = "80"
  http_request_method = "GET"
  http_validate_ssl   = false
  resource_type       = "uptime_url"
  resource_host       = module.backend_lb.address
  checker_type        = "STATIC_IP_CHECKERS"
}

# -----------------------------------------------------------------------------------------
# Email notification channel
# -----------------------------------------------------------------------------------------
resource "google_monitoring_notification_channel" "email_alerts" {
  display_name = "Email Alerts"
  type         = "email"
  labels = {
    email_address = "mohitfury1997@gmail.com"
  }
  enabled = true
}

# -----------------------------------------------------------------------------------------
# Observability Metrics for Production Monitoring
# -----------------------------------------------------------------------------------------
module "http_4xx_errors" {
  source       = "../../../modules/observability/metrics"
  name         = "http_4xx_errors"
  filter       = <<-EOT
    resource.type="http_load_balancer"
    httpRequest.status>=400
    httpRequest.status<500
  EOT
  metric_kind  = "DELTA"
  value_type   = "INT64"
  display_name = "HTTP 4xx Errors"
  label_extractors = {
    "status_code" = "EXTRACT(httpRequest.status)"
    "url_map"     = "EXTRACT(resource.labels.url_map_name)"
  }
}

module "http_5xx_errors" {
  source       = "../../../modules/observability/metrics"
  name         = "http_5xx_errors"
  filter       = <<-EOT
    resource.type="http_load_balancer"
    httpRequest.status>=500
  EOT
  metric_kind  = "DELTA"
  value_type   = "INT64"
  display_name = "HTTP 5xx Errors"
  label_extractors = {
    "status_code" = "EXTRACT(httpRequest.status)"
    "url_map"     = "EXTRACT(resource.labels.url_map_name)"
  }
}

module "database_connection_errors" {
  source           = "../../../modules/observability/metrics"
  name             = "database_connection_errors"
  filter           = <<-EOT
    resource.type="cloudsql_database"
    (textPayload:"connection" OR textPayload:"timeout" OR textPayload:"failed")
    severity="ERROR"
  EOT
  metric_kind      = "DELTA"
  value_type       = "INT64"
  display_name     = "Database Connection Errors"
  label_extractors = {}
}

# Response Time Tracking
module "response_time_metric" {
  source       = "../../../modules/observability/metrics"
  name         = "http_response_time"
  filter       = <<-EOT
    resource.type="http_load_balancer"
    httpRequest.latency>0
  EOT
  metric_kind  = "DELTA"
  value_type   = "DISTRIBUTION"
  display_name = "HTTP Response Time"
  label_extractors = {
    "url_map"  = "EXTRACT(resource.labels.url_map_name)"
    "backend"  = "EXTRACT(resource.labels.backend_service_name)"
  }
  bucket_options = {
    exponential_buckets = {
      num_finite_buckets = 64
      growth_factor      = 2
      scale              = 0.01
    }
  }
}

# Request Rate Tracking
module "request_rate_metric" {
  source       = "../../../modules/observability/metrics"
  name         = "http_request_rate"
  filter       = <<-EOT
    resource.type="http_load_balancer"
  EOT
  metric_kind  = "DELTA"
  value_type   = "INT64"
  display_name = "HTTP Request Rate"
  label_extractors = {
    "url_map"     = "EXTRACT(resource.labels.url_map_name)"
    "status_code" = "EXTRACT(httpRequest.status)"
    "method"      = "EXTRACT(httpRequest.requestMethod)"
  }
}

# Cloud SQL Performance Metrics
module "sql_query_duration" {
  source       = "../../../modules/observability/metrics"
  name         = "sql_slow_query_count"
  filter       = <<-EOT
    resource.type="cloudsql_database"
    (textPayload:"query" OR textPayload:"SELECT" OR textPayload:"UPDATE")
    jsonPayload.duration>1000
  EOT
  metric_kind  = "DELTA"
  value_type   = "INT64"
  display_name = "Slow SQL Query Count"
  label_extractors = {
    "database" = "EXTRACT(resource.labels.database_id)"
  }
}

# Database Connection Pool Metrics
module "db_connection_pool_exhaustion" {
  source       = "../../../modules/observability/metrics"
  name         = "db_connection_pool_exhaustion"
  filter       = <<-EOT
    resource.type="cloudsql_database"
    (textPayload:"pool" OR textPayload:"max connections")
    severity="WARNING"
  EOT
  metric_kind  = "DELTA"
  value_type   = "INT64"
  display_name = "Database Connection Pool Exhaustion"
  label_extractors = {}
}

# Cloud Function Execution Metrics
module "function_execution_errors" {
  source       = "../../../modules/observability/metrics"
  name         = "function_execution_errors"
  filter       = <<-EOT
    resource.type="cloud_function"
    severity="ERROR"
  EOT
  metric_kind  = "DELTA"
  value_type   = "INT64"
  display_name = "Cloud Function Execution Errors"
  label_extractors = {
    "function_name" = "EXTRACT(resource.labels.function_name)"
  }
}

# Cloud Function Cold Start Metrics
module "function_cold_starts" {
  source       = "../../../modules/observability/metrics"
  name         = "function_cold_starts"
  filter       = <<-EOT
    resource.type="cloud_function"
    textPayload:"cold start"
  EOT
  metric_kind  = "DELTA"
  value_type   = "INT64"
  display_name = "Cloud Function Cold Starts"
  label_extractors = {
    "function_name" = "EXTRACT(resource.labels.function_name)"
  }
}

# Security Metrics - WAF Blocks
module "waf_blocked_requests" {
  source       = "../../../modules/observability/metrics"
  name         = "waf_blocked_requests"
  filter       = <<-EOT
    resource.type="http_load_balancer"
    httpRequest.status=403
    jsonPayload.enforcedSecurityPolicy.name:"carshub-security-policy"
  EOT
  metric_kind  = "DELTA"
  value_type   = "INT64"
  display_name = "WAF Blocked Requests"
  label_extractors = {
    "rule_name" = "EXTRACT(jsonPayload.enforcedSecurityPolicy.name)"
  }
}

# CDN Cache Hit Ratio
module "cdn_cache_hits" {
  source       = "../../../modules/observability/metrics"
  name         = "cdn_cache_hits"
  filter       = <<-EOT
    resource.type="http_load_balancer"
    jsonPayload.cacheId!=""
    jsonPayload.cacheHit=true
  EOT
  metric_kind  = "DELTA"
  value_type   = "INT64"
  display_name = "CDN Cache Hits"
  label_extractors = {}
}

module "cdn_cache_misses" {
  source       = "../../../modules/observability/metrics"
  name         = "cdn_cache_misses"
  filter       = <<-EOT
    resource.type="http_load_balancer"
    jsonPayload.cacheId!=""
    jsonPayload.cacheHit=false
  EOT
  metric_kind  = "DELTA"
  value_type   = "INT64"
  display_name = "CDN Cache Misses"
  label_extractors = {}
}

# User Authentication Failures
module "auth_failures" {
  source       = "../../../modules/observability/metrics"
  name         = "authentication_failures"
  filter       = <<-EOT
    resource.type="http_load_balancer"
    httpRequest.requestUrl:"/auth/"
    httpRequest.status=401
  EOT
  metric_kind  = "DELTA"
  value_type   = "INT64"
  display_name = "Authentication Failures"
  label_extractors = {
    "path" = "EXTRACT(httpRequest.requestUrl)"
  }
}

# PubSub Message Processing Metrics
module "pubsub_message_failures" {
  source       = "../../../modules/observability/metrics"
  name         = "pubsub_message_failures"
  filter       = <<-EOT
    resource.type="cloud_pubsub_subscription"
    severity="ERROR"
  EOT
  metric_kind  = "DELTA"
  value_type   = "INT64"
  display_name = "PubSub Message Processing Failures"
  label_extractors = {
    "subscription" = "EXTRACT(resource.labels.subscription_id)"
  }
}

# Alerting Policies
module "high_error_rate_alert" {
  source                = "../../../modules/observability/alerts"
  display_name          = "High Error Rate Alert"
  combiner              = "OR"
  notification_channels = [google_monitoring_notification_channel.email_alerts.id]
  conditions = [
    {
      display_name = "HTTP 5xx Error Rate"
      condition_threshold = {
        filter          = "resource.type=\"http_load_balancer\" AND httpRequest.status>=500"
        duration        = "300s"
        comparison      = "COMPARISON_GREATER_THAN"
        threshold_value = 10
      }
    }
  ]
}

module "database_connection_alert" {
  source                = "../../../modules/observability/alerts"
  display_name          = "Database Connection Alert"
  combiner              = "OR"
  notification_channels = [google_monitoring_notification_channel.email_alerts.id]
  conditions = [
    {
      display_name = "Database Connection Errors"
      condition_threshold = {
        filter          = "resource.type=\"cloudsql_database\" AND severity=\"ERROR\""
        duration        = "300s"
        comparison      = "COMPARISON_GREATER_THAN"
        threshold_value = 5
      }
    }
  ]
}

# High Response Time Alert
module "high_latency_alert" {
  source                = "../../../modules/observability/alerts"
  display_name          = "High Response Time Alert"
  combiner              = "OR"
  notification_channels = [
    google_monitoring_notification_channel.email_alerts.id,
    google_monitoring_notification_channel.slack_alerts.id
  ]
  conditions = [
    {
      display_name = "P95 Latency > 2s"
      condition_threshold = {
        filter          = "metric.type=\"logging.googleapis.com/user/http_response_time\" resource.type=\"http_load_balancer\""
        duration        = "300s"
        comparison      = "COMPARISON_GREATER_THAN"
        threshold_value = 2000
        aggregations = {
          alignment_period     = "60s"
          per_series_aligner   = "ALIGN_PERCENTILE_95"
          cross_series_reducer = "REDUCE_MEAN"
        }
      }
    }
  ]
}

# Critical - Service Unavailable
module "service_unavailable_alert" {
  source                = "../../../modules/observability/alerts"
  display_name          = "CRITICAL: Service Unavailable"
  combiner              = "OR"
  notification_channels = [
    google_monitoring_notification_channel.email_alerts.id,
    google_monitoring_notification_channel.slack_alerts.id,
    google_monitoring_notification_channel.pagerduty_critical.id
  ]
  conditions = [
    {
      display_name = "Service Down for 3 minutes"
      condition_threshold = {
        filter          = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" resource.type=\"uptime_url\""
        duration        = "180s"
        comparison      = "COMPARISON_LESS_THAN"
        threshold_value = 1
      }
    }
  ]
}

# Database CPU Alert
module "database_cpu_alert" {
  source                = "../../../modules/observability/alerts"
  display_name          = "Database High CPU Usage"
  combiner              = "OR"
  notification_channels = [google_monitoring_notification_channel.email_alerts.id]
  conditions = [
    {
      display_name = "CPU Usage > 80%"
      condition_threshold = {
        filter          = "metric.type=\"cloudsql.googleapis.com/database/cpu/utilization\" resource.type=\"cloudsql_database\""
        duration        = "300s"
        comparison      = "COMPARISON_GREATER_THAN"
        threshold_value = 0.80
        aggregations = {
          alignment_period     = "60s"
          per_series_aligner   = "ALIGN_MEAN"
        }
      }
    }
  ]
}

# Database Memory Alert
module "database_memory_alert" {
  source                = "../../../modules/observability/alerts"
  display_name          = "Database High Memory Usage"
  combiner              = "OR"
  notification_channels = [google_monitoring_notification_channel.email_alerts.id]
  conditions = [
    {
      display_name = "Memory Usage > 85%"
      condition_threshold = {
        filter          = "metric.type=\"cloudsql.googleapis.com/database/memory/utilization\" resource.type=\"cloudsql_database\""
        duration        = "300s"
        comparison      = "COMPARISON_GREATER_THAN"
        threshold_value = 0.85
        aggregations = {
          alignment_period     = "60s"
          per_series_aligner   = "ALIGN_MEAN"
        }
      }
    }
  ]
}

# Cloud Function Failure Rate Alert
module "function_failure_alert" {
  source                = "../../../modules/observability/alerts"
  display_name          = "Cloud Function High Failure Rate"
  combiner              = "OR"
  notification_channels = [google_monitoring_notification_channel.email_alerts.id]
  conditions = [
    {
      display_name = "Function Error Rate > 5%"
      condition_threshold = {
        filter          = "metric.type=\"cloudfunctions.googleapis.com/function/execution_count\" resource.type=\"cloud_function\" metric.label.status!=\"ok\""
        duration        = "300s"
        comparison      = "COMPARISON_GREATER_THAN"
        threshold_value = 5
        aggregations = {
          alignment_period     = "60s"
          per_series_aligner   = "ALIGN_RATE"
          cross_series_reducer = "REDUCE_SUM"
        }
      }
    }
  ]
}

# Disk Space Alert
module "disk_space_alert" {
  source                = "../../../modules/observability/alerts"
  display_name          = "High Disk Usage Alert"
  combiner              = "OR"
  notification_channels = [google_monitoring_notification_channel.email_alerts.id]
  conditions = [
    {
      display_name = "Disk Usage > 85%"
      condition_threshold = {
        filter          = "metric.type=\"compute.googleapis.com/instance/disk/utilization\" resource.type=\"gce_instance\""
        duration        = "300s"
        comparison      = "COMPARISON_GREATER_THAN"
        threshold_value = 0.85
      }
    }
  ]
}

# Network Traffic Spike Alert
module "traffic_spike_alert" {
  source                = "../../../modules/observability/alerts"
  display_name          = "Unusual Traffic Spike Detected"
  combiner              = "OR"
  notification_channels = [
    google_monitoring_notification_channel.email_alerts.id,
    google_monitoring_notification_channel.slack_alerts.id
  ]
  conditions = [
    {
      display_name = "Request Rate 200% Above Normal"
      condition_threshold = {
        filter          = "metric.type=\"logging.googleapis.com/user/http_request_rate\" resource.type=\"http_load_balancer\""
        duration        = "120s"
        comparison      = "COMPARISON_GREATER_THAN"
        threshold_value = 1000
        aggregations = {
          alignment_period     = "60s"
          per_series_aligner   = "ALIGN_RATE"
        }
      }
    }
  ]
}

# SSL Certificate Expiry Alert
module "ssl_cert_expiry_alert" {
  source                = "../../../modules/observability/alerts"
  display_name          = "SSL Certificate Expiring Soon"
  combiner              = "OR"
  notification_channels = [google_monitoring_notification_channel.email_alerts.id]
  conditions = [
    {
      display_name = "Certificate Expires in 30 Days"
      condition_threshold = {
        filter          = "metric.type=\"loadbalancing.googleapis.com/https/certificate/expiration_time\" resource.type=\"ssl_certificate\""
        duration        = "3600s"
        comparison      = "COMPARISON_LESS_THAN"
        threshold_value = 2592000 # 30 days in seconds
      }
    }
  ]
}