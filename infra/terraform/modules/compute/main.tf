resource "google_compute_instance_template" "instance_template" {
  name         = var.template_name
  machine_type = var.machine_type
  tags         = [var.health_check_name]
  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
  }
  network_interface {
    network    = var.network
    subnetwork = var.subnetwork
    access_config {

    }
  }
  disk {
    source_image = var.source_image
    auto_delete  = var.auto_delete
    boot         = var.boot
  }
  metadata = {
    startup-script = var.startup_script
  }
  lifecycle {
    create_before_destroy = true
  }

}

# health check
resource "google_compute_health_check" "health_check" {
  name = var.health_check_name
  http_health_check {
    request_path       = var.request_path
    port_specification = var.port_specification
  }
}

# Managed Instance Groups
resource "google_compute_instance_group_manager" "mig" {
  name = var.mig_name
  zone = "${var.location}-c"
  named_port {
    name = var.mig_named_port_name
    port = var.mig_named_port_port
  }
  version {
    instance_template = google_compute_instance_template.instance_template.id
    name              = var.template_name
  }
  base_instance_name = var.mig_base_instance_name
  target_size        = var.mig_target_size
}
