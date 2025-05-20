variable "global_address_name" {}
variable "global_address_type" {}
variable "url_map_name" {}
variable "forwarding_scheme" {}
variable "forwarding_rule_name" {}
variable "security_policy" {
  type = string
  default = null
}
variable "target_proxy_name" {}
variable "url_map_service" {
    default = ""
}
variable "forwarding_port_range" {}

variable "backend_service_name" {
    default = ""
}
variable "backend_service_protocol" {
    default = ""
}
variable "backend_service_port_name" {
    default = ""
}
variable "backend_service_load_balancing_scheme" {
    default = ""
}
variable "backend_service_timeout_sec" {
    default = 0
}
variable "backend_service_enable_cdn" {
    default = false
}
variable "backend_service_custom_request_headers" {
    default = []
}
variable "backend_service_custom_response_headers" {
    default = []
}
variable "backend_service_health_checks" {
    default = []
}
variable "backend_service_backends" {
    default = []
}