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
  # ${google_sql_database_instance.carshub_db_instance.ip_address[0].ip_address}
  metadata = {
    startup-script = <<-EOT
#! /bin/bash
apt-get update -y
apt-get upgrade -y
# Installing Nginx
apt-get install -y nginx
# Installing Node.js
curl -sL https://deb.nodesource.com/setup_20.x -o nodesource_setup.sh
bash nodesource_setup.sh
apt install nodejs -y
# Installing PM2
npm i -g pm2
# Installing Nest CLI
npm install -g @nestjs/cli
mkdir nodeapp
# Checking out from Version Control
git clone https://github.com/mmdcloud/carshub-gcp-managed-instance-groups
cd carshub-gcp-managed-instance-groups/backend/api
cp -r . ../nodeapp/
cd ../nodeapp/
# Copying Nginx config
cp scripts/default /etc/nginx/sites-available/
# Installing dependencies
npm i

cat > .env <<EOL
DB_PATH=""
UN="mohit"
CREDS="${google_secret_manager_secret_version.carshub_db_secret_version_data.secret_data}"
EOL
# Building the project
npm run build
# Starting PM2 app
pm2 start dist/main.js
service nginx restart
    EOT
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
    source_image = "ubuntu-os-cloud/ubuntu-2204-lts"
    auto_delete  = true
    boot         = true
  }

  metadata = {
    startup-script = <<-EOT
#! /bin/bash
apt-get update -y
apt-get upgrade -y
apt-get install -y nginx
# Installing Node.js
curl -sL https://deb.nodesource.com/setup_20.x -o nodesource_setup.sh
bash nodesource_setup.sh
apt install nodejs -y
apt-get install -yq ca-certificates git build-essential supervisor

# Checking out from Version Control
git clone https://github.com/mmdcloud/carshub-gcp-managed-instance-groups  /opt/app/new-repo
cd /opt/app/new-repo/frontend
cp scripts/default /etc/nginx/sites-available/
cat > .env <<EOL
CDN_URL="${google_compute_global_address.carshub_cdn_lb_global_address.address}"
BASE_URL="${google_compute_global_address.carshub_backend_lb_global_address.address}"
EOL

# Installing dependencies
npm i

# Building the project
npm run build

useradd -m -d /home/nodeapp nodeapp
chown -R nodeapp:nodeapp /opt/app

# Configure supervisor to run the node app.
cat >/etc/supervisor/conf.d/node-app.conf << EOF
[program:nodeapp]
directory=/opt/app/new-repo/frontend
command=npm start
autostart=true
autorestart=true
user=nodeapp
environment=HOME="/home/nodeapp",USER="nodeapp",NODE_ENV="production"
stdout_logfile=syslog
stderr_logfile=syslog
EOF
supervisorctl reread
supervisorctl update
service nginx reload
service nginx restart
    EOT
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
