resource "google_compute_backend_service" "backend_service" {
  name                    = var.name
  protocol                = var.protocol
  port_name               = var.port_name
  load_balancing_scheme   = var.load_balancing_scheme
  timeout_sec             = var.timeout_sec
  enable_cdn              = var.enable_cdn
  custom_request_headers  = var.custom_request_headers
  custom_response_headers = var.custom_response_headers
  health_checks           = var.health_checks
  dynamic "backend" {
    for_each = var.backends
    content {
      group           = backend.value["group"]
      balancing_mode  = backend.value["balancing_mode"]
      capacity_scaler = backend.value["capacity_scaler"]
    }
  }
}
