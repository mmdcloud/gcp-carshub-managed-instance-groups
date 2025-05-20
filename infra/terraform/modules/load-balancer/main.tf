# Backend service for load balancing
resource "google_compute_backend_service" "backend_service" {
  name                    = var.backend_service_name
  protocol                = var.backend_service_protocol
  port_name               = var.backend_service_port_name
  load_balancing_scheme   = var.backend_service_load_balancing_scheme
  timeout_sec             = var.backend_service_timeout_sec
  enable_cdn              = var.backend_service_enable_cdn
  custom_request_headers  = var.backend_service_custom_request_headers
  custom_response_headers = var.backend_service_custom_response_headers
  health_checks           = var.backend_service_health_checks
  security_policy         = var.security_policy
  dynamic "backend" {
    for_each = var.backend_service_backends
    content {
      group           = backend.value["group"]
      balancing_mode  = backend.value["balancing_mode"]
      capacity_scaler = backend.value["capacity_scaler"]
    }
  }
}

# Reserve an external IP for CDN
resource "google_compute_global_address" "global_address" {
  name         = var.global_address_name
  address_type = var.global_address_type
}

# GCP URL MAP
resource "google_compute_url_map" "url_map" {
  name            = var.url_map_name
  default_service = var.url_map_service != "" ? var.url_map_service : google_compute_backend_service.backend_service.self_link
  host_rule {
    hosts        = ["*"]
    path_matcher = "allpaths"
  }
  path_matcher {
    name            = "allpaths"
    default_service = var.url_map_service != "" ? var.url_map_service : google_compute_backend_service.backend_service.self_link
  }
}

# GCP target proxy
resource "google_compute_target_http_proxy" "target_http_proxy" {
  name    = var.target_proxy_name
  url_map = google_compute_url_map.url_map.self_link
}

# GCP forwarding rule
resource "google_compute_global_forwarding_rule" "global_forwarding_rule" {
  name                  = var.forwarding_rule_name
  load_balancing_scheme = var.forwarding_scheme
  ip_address            = google_compute_global_address.global_address.address
  port_range            = var.forwarding_port_range
  target                = google_compute_target_http_proxy.target_http_proxy.self_link
}

