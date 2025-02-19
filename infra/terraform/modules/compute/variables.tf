variable "template_name" {}
variable "machine_type" {}
variable "health_check_name" {}
variable "network" {}
variable "subnetwork" {}
variable "source_image" {}
variable "auto_delete" {}
variable "boot" {}
variable "port_specification" {}
variable "startup_script" {}
variable "request_path" {}
# variable "service_account" {
#   type = list(object({
#     email  = string
#     scopes = list(string)
#   }))
# }
