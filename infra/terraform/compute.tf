# Backend Instance Template
resource "google_compute_instance_template" "carshub_backend_template" {
  name         = "carshub-backend-template"
  machine_type = "e2-small"
  tags         = ["carshub-backend-health-check"]

  network_interface {
    network    = google_compute_network.carshub_vpc.id
    subnetwork = google_compute_subnetwork.carshub_subnet.id
    access_config {
      # add external ip to fetch packages
    }
  }
  disk {
    source_image = "ubuntu-os-cloud/ubuntu-2204-lts"
    auto_delete  = true
    boot         = true
  }

  metadata_startup_script = base64encode(templatefile("${path.module}/scripts/user_data_backend.sh", {
    DB_PATH  = "${google_sql_database_instance.carshub_db_instance.first_ip_address}"
    USERNAME = "admin"
    PASSWORD = "${google_secret_manager_secret_version.carshub_db_secret_version_data.secret_data}"
  }))

  lifecycle {
    create_before_destroy = true
  }
}

# Backend health check
resource "google_compute_health_check" "carshub_backend_health_check" {
  name = "carshub-backend-health-check"
  http_health_check {
    port_specification = "USE_SERVING_PORT"
  }
}


# Frontend Instance Template
resource "google_compute_instance_template" "carshub_frontend_template" {
  name         = "carshub-frontend-template"
  machine_type = "e2-small"
  tags         = ["carshub-frontend-health-check"]

  network_interface {
    network    = google_compute_network.carshub_vpc.id
    subnetwork = google_compute_subnetwork.carshub_subnet.id
    access_config {
      # add external ip to fetch packages
    }
  }
  disk {
    source_image = "ubuntu-os-cloud/ubuntu-2204-lts"
    auto_delete  = true
    boot         = true
  }

  metadata_startup_script = base64encode(templatefile("${path.module}/scripts/user_data_frontend.sh", {
    BASE_URL = "${google_compute_global_address.carshub_backend_lb_global_address.address}"
    CDN_URL  = "${google_compute_global_address.carshub_cdn_lb_global_address.address}"
  }))

  lifecycle {
    create_before_destroy = true
  }
}

# Frontend health check
resource "google_compute_health_check" "carshub-frontend-health-check" {
  name = "carshub-frontend-health-check"
  http_health_check {
    port_specification = "USE_SERVING_PORT"
  }
}
