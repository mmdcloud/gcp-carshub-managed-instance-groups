# Backend MIG
resource "google_compute_instance_group_manager" "carshub_backend_mig" {
  name = "carshub-backend-mig"
  zone = "${var.location}-c"
  named_port {
    name = "carshub-backend-named-port"
    port = 3000
  }
  version {
    instance_template = google_compute_instance_template.carshub_backend_template.id
    name              = "backend"
  }
  base_instance_name = "vm"
  target_size        = 1
}

# Frontend MIG
resource "google_compute_instance_group_manager" "carshub_frontend_mig" {
  name = "carshub-frontend-mig"
  zone = "${var.location}-c"
  named_port {
    name = "carshub-frontend-named-port"
    port = 80
  }
  version {
    instance_template = google_compute_instance_template.carshub_frontend_template.id
    name              = "frontend"
  }
  base_instance_name = "vm"
  target_size        = 1
}