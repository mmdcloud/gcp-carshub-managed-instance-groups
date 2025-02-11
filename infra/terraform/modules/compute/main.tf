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
    port_specification = var.port_specification
  }
}
