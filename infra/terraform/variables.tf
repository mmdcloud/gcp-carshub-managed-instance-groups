variable "location" {
  type    = string
  default = "us-central1"
}
variable "backup_location" {
  type    = string
  default = "us-east1"
}
variable "project_id" {
  type    = string
  default = "carshub-447206"
}

# VPC Data
variable "vpc_name" {
  type    = string
  default = "carshub-vpc"
}

# Instance Template Variables
variable "ubuntu_source_os_image" {
  type    = string
  default = "ubuntu-os-cloud/ubuntu-2204-lts"
}
variable "ubuntu_machine_type" {
  type    = string
  default = "e2-small"
}
variable "ubuntu_auto_delete" {
  type    = bool
  default = true
}
variable "ubuntu_boot" {
  type    = bool
  default = true
}
variable "frontend_template_name" {
  type    = string
  default = "carshub-frontend-template"
}
variable "backend_template_name" {
  type    = string
  default = "carshub-backend-template"
}
variable "port_specification" {
  type    = string
  default = "USE_SERVING_PORT"
}

# MIG Variables
variable "base_instance_name" {
  type    = string
  default = "vm"
}
variable "frontend_instance_template_name" {
  type    = string
  default = "frontend"
}
variable "backend_instance_template_name" {
  type    = string
  default = "backend"
}
variable "frontend_named_port_name" {
  type    = string
  default = "frontendnamedport"
}
variable "backend_named_port_name" {
  type    = string
  default = "backendnamedport"
}
variable "frontend_mig_name" {
  type    = string
  default = "carshub-frontend-mig"
}
variable "backend_mig_name" {
  type    = string
  default = "carshub-backend-mig"
}
variable "target_size" {
  type    = number
  default = 1
}
variable "named_port_frontend" {
  type    = number
  default = 3000
}

variable "named_port_backend" {
  type    = number
  default = 3000
}

# GCS 
variable "force_destroy" {
  type    = bool
  default = true
}
variable "uniform_bucket_level_access" {
  type    = bool
  default = true
}

# Secret Manager
variable "sql_password_secret_data" {
  type    = string
  default = "Mohitdixit12345!"
}
variable "sql_password_secret_id" {
  type    = string
  default = "carshub_db_password_secret"
}


variable "frontend_health_check" {
  type    = string
  default = "carshub-frontend-health-check"
}

variable "backend_health_check" {
  type    = string
  default = "carshub-backend-health-check"
}
