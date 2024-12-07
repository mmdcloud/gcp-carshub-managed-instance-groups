# Backend MIG
resource "google_compute_instance_group_manager" "carshub_backend_mig" {
  name = "l7-xlb-mig1"
  zone = "us-central1-c"
  named_port {
    name = "http"
    port = 3000
  }
  version {
    instance_template = google_compute_instance_template.carshub_backend_template.id
    name              = "primary"
  }
  base_instance_name = "vm"
  target_size        = 2
}

# Frontend MIG
resource "google_compute_instance_group_manager" "carshub_frontend_mig" {
  name = "l7-xlb-mig1"
  zone = "us-central1-c"
  named_port {
    name = "http"
    port = 3000
  }
  version {
    instance_template = google_compute_instance_template.carshub_frontend_template.id
    name              = "primary"
  }
  base_instance_name = "vm"
  target_size        = 2
}