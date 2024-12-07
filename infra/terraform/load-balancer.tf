# Reserve an external IP for CDN
resource "google_compute_global_address" "carshub_cdn_lb_global_address" {
  name         = "carshub-cdn-lb-global-address"
  address_type = "EXTERNAL"
}

# GCP URL MAP
resource "google_compute_url_map" "carshub_cdn_compute_url_map" {
  name            = "carshub-cdn-compute-url-map"
  default_service = google_compute_backend_bucket.carshub_media_cdn.self_link
  host_rule {
    hosts        = ["*"]
    path_matcher = "allpaths"
  }
  path_matcher {
    name            = "allpaths"
    default_service = google_compute_backend_bucket.carshub_media_cdn.self_link
  }
}

# GCP target proxy
resource "google_compute_target_http_proxy" "carshub_cdn_target_proxy" {
  provider = google
  name     = "carshub-cdn-target-proxy"
  url_map  = google_compute_url_map.carshub_cdn_compute_url_map.self_link
}

# GCP forwarding rule
resource "google_compute_global_forwarding_rule" "carshub_cdn_global_forwarding_rule" {
  name                  = "carshub_cdn-global-forwarding-rule"
  load_balancing_scheme = "EXTERNAL"
  ip_address            = google_compute_global_address.carshub_cdn_lb_global_address.address
  port_range            = "80"
  target                = google_compute_target_http_proxy.carshub_cdn_target_proxy.self_link
}




# Backend reserved IP address
resource "google_compute_global_address" "carshub_backend_lb_global_address" {
  name = "carshub-backend-lb-global-address"
}

# Backend forwarding rule
resource "google_compute_global_forwarding_rule" "carshub_backend_forwarding_rule" {
  name                  = "carshub-backend-forwarding-rule"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "80"
  target                = google_compute_target_http_proxy.carshub-backend-target-http-proxy.id
  ip_address            = google_compute_global_address.carshub_backend_lb_global_address.id
}

# Backend http proxy
resource "google_compute_target_http_proxy" "carshub-backend-target-http-proxy" {
  name    = "carshub-backend-target-http-proxy"
  url_map = google_compute_url_map.carshub-backend-url-map.id
}

# Backend url map
resource "google_compute_url_map" "carshub-backend-url-map" {
  name            = "carshub-backend-url-map"
  default_service = google_compute_backend_service.carshub-backend-service.id
}

# Backend service with custom request and response headers
resource "google_compute_backend_service" "carshub-backend-service" {
  name                    = "carshub-backend-service"
  protocol                = "HTTP"
  port_name               = "carshub-backend-port"
  load_balancing_scheme   = "EXTERNAL"
  timeout_sec             = 10
  enable_cdn              = true
  custom_request_headers  = ["X-Client-Geo-Location: {client_region_subdivision}, {client_city}"]
  custom_response_headers = ["X-Cache-Hit: {cdn_cache_status}"]
  health_checks           = [google_compute_health_check.carshub_backend_health_check.id]
  backend {
    group           = google_compute_instance_group_manager.carshub_backend_mig.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
}




# Frontend reserved IP address
resource "google_compute_global_address" "carshub_frontend_lb_global_address" {
  name = "carshub-frontend-lb-global-address"
}

# Frontend forwarding rule
resource "google_compute_global_forwarding_rule" "carshub_frontend_forwarding_rule" {
  name                  = "carshub-frontend-forwarding-rule"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "80"
  target                = google_compute_target_http_proxy.carshub-frontend-target-http-proxy.id
  ip_address            = google_compute_global_address.carshub_frontend_lb_global_address.id
}

# Frontend http proxy
resource "google_compute_target_http_proxy" "carshub-frontend-target-http-proxy" {
  name    = "carshub-frontend-target-http-proxy"
  url_map = google_compute_url_map.carshub-frontend-url-map.id
}

# Frontend url map
resource "google_compute_url_map" "carshub-frontend-url-map" {
  name            = "carshub-frontend-url-map"
  default_service = google_compute_backend_service.carshub-frontend-service.id
}

# Frontend service with custom request and response headers
resource "google_compute_backend_service" "carshub-frontend-service" {
  name                    = "carshub-frontend-service"
  protocol                = "HTTP"
  port_name               = "carshub-frontend-port"
  load_balancing_scheme   = "EXTERNAL"
  timeout_sec             = 10
  enable_cdn              = true
  custom_request_headers  = ["X-Client-Geo-Location: {client_region_subdivision}, {client_city}"]
  custom_response_headers = ["X-Cache-Hit: {cdn_cache_status}"]
  health_checks           = [google_compute_health_check.carshub_backend_health_check.id]
  backend {
    group           = google_compute_instance_group_manager.carshub_backend_mig.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
}
