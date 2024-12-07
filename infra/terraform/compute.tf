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
    source_image = "debian-cloud/debian-12"
    auto_delete  = true
    boot         = true
  }

  metadata_startup_script = 

  # install nginx and nodejs with application
  metadata = {
    startup-script = <<-EOF1
        #!/bin/bash
	sudo apt-get update
	sudo apt-get install -y nginx
	sudo apt update
	curl -sL https://deb.nodesource.com/setup_18.x -o nodesource_setup.sh
	sudo bash nodesource_setup.sh
	sudo apt install nodejs -y
	cd /home/deapoolandwolverine
	git clone https://github.com/mmdcloud/gcp-autoscaling-with-managed-instance-groups
	cd gcp-autoscaling-with-managed-instance-groups
	sudo cp scripts/nodejs_nginx.config /etc/nginx/sites-available/default
	sudo service nginx restart
	sudo npm i
	sudo npm i -g pm2
	pm2 start server.mjs
    EOF1
  }
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
    source_image = "debian-cloud/debian-12"
    auto_delete  = true
    boot         = true
  }

  # install nginx and nodejs with application
  metadata = {
    startup-script = <<-EOF1
        #!/bin/bash
	sudo apt-get update
	sudo apt-get install -y nginx
	sudo apt update
	curl -sL https://deb.nodesource.com/setup_18.x -o nodesource_setup.sh
	sudo bash nodesource_setup.sh
	sudo apt install nodejs -y
	cd /home/deapoolandwolverine
	git clone https://github.com/mmdcloud/gcp-autoscaling-with-managed-instance-groups
	cd gcp-autoscaling-with-managed-instance-groups
	sudo cp scripts/nodejs_nginx.config /etc/nginx/sites-available/default
	sudo service nginx restart
	sudo npm i
	sudo npm i -g pm2
	pm2 start server.mjs
    EOF1
  }
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
