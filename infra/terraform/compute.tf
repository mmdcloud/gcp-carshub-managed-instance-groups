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

  metadata_startup_script = <<EOF
#!/bin/bash
sudo apt-get update -y
sudo apt-get upgrade -y
# Installing Nginx
sudo apt-get install -y nginx
# Installing Node.js
curl -sL https://deb.nodesource.com/setup_20.x -o nodesource_setup.sh
sudo bash nodesource_setup.sh
sudo apt install nodejs -y
# Installing PM2
sudo npm i -g pm2
# Installing Nest CLI
sudo npm install -g @nestjs/cli
cd /home/susmitashiyekar
sudo mkdir nodeapp
# Checking out from Version Control
git clone https://github.com/mmdcloud/carshub-gcp-managed-instance-groups
cd carshub-gcp-managed-instance-groups/backend/api
cp -r . /home/susmitashiyekar/nodeapp/
cd /home/susmitashiyekar/nodeapp/
# Copying Nginx config
sudo cp scripts/default /etc/nginx/sites-available/
# Installing dependencies
sudo npm i

# Copying DB crendetials 
cat > .env <<EOL
DB_PATH="${google_sql_database_instance.carshub_db_instance.first_ip_address}"
UN="mohit"
CREDS="${google_secret_manager_secret_version.carshub_db_secret_version_data.secret_data}"
EOL
# Building the project
sudo npm run build
# Starting PM2 app
pm2 start dist/main.js
sudo service nginx restart
  EOF 
  # base64encode(templatefile("${path.module}/scripts/user_data_backend.sh", {
  #   DB_PATH  = "${google_sql_database_instance.carshub_db_instance.first_ip_address}"
  #   USERNAME = "admin"
  #   PASSWORD = "${google_secret_manager_secret_version.carshub_db_secret_version_data.secret_data}"
  # }))

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

  metadata_startup_script = <<EOF
#!/bin/bash
sudo apt-get update -y
sudo apt-get upgrade -y
# Installing Nginx
sudo apt-get install -y nginx
# Installing Node.js
curl -sL https://deb.nodesource.com/setup_20.x -o nodesource_setup.sh
sudo bash nodesource_setup.sh
sudo apt install nodejs -y
# Installing PM2
sudo npm i -g pm2

cd /home/susmitashiyekar
mkdir nodeapp
# Checking out from Version Control
git clone https://github.com/mmdcloud/carshub-gcp-managed-instance-groups
cd carshub-gcp-managed-instance-groups/frontend
cp -r . /home/susmitashiyekar/nodeapp/
cd /home/susmitashiyekar/nodeapp/

# Setting up env variables
cat > .env <<EOL
CDN_URL="${google_compute_global_address.carshub_cdn_lb_global_address.address}"
BASE_URL="${google_compute_global_address.carshub_backend_lb_global_address.address}"
EOL

# Copying Nginx config
sudo cp scripts/default /etc/nginx/sites-available/
# Installing dependencies
sudo npm i

# Building the project
sudo npm run build
# Starting PM2 app
pm2 start ecosystem.config.js
sudo service nginx restart
  EOF 
  # base64encode(templatefile("${path.module}/scripts/user_data_frontend.sh", {
  #   BASE_URL = "${google_compute_global_address.carshub_backend_lb_global_address.address}"
  #   CDN_URL  = "${google_compute_global_address.carshub_cdn_lb_global_address.address}"
  # }))

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
