output "frontend_url" {
  value = google_compute_global_address.carshub_backend_lb_global_address.address
}

output "backend_url" {
  value = google_compute_global_address.carshub_backend_lb_global_address.address
}
