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

cd /home/ubuntu
sudo mkdir nodeapp
# Checking out from Version Control
sudo git clone https://github.com/mmdcloud/carshub-gcp-managed-instance-groups
cd carshub-gcp-managed-instance-groups/frontend
sudo cp -r . /home/ubuntu/nodeapp/
cd /home/ubuntu/nodeapp/
# Setting up env variables
sudo cat > .env <<EOL
BASE_URL=${BASE_URL}
CDN_URL=${CDN_URL}
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