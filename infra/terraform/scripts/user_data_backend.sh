#! /bin/bash
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
cd /home/admin_mohitcloud_xyz
sudo mkdir nodeapp
# Checking out from Version Control
sudo git clone https://github.com/mmdcloud/carshub-gcp-managed-instance-groups
cd carshub-gcp-managed-instance-groups/src/backend/api
sudo cp -r . ../../../../nodeapp/
cd ../../../../nodeapp/
# Copying Nginx config
sudo cp scripts/default /etc/nginx/sites-available/
# Installing dependencies
sudo npm i

sudo cat > .env <<EOL
DB_PATH=${DB_PATH}
UN=${UN}
CREDS=${CREDS}
EOL
# Building the project
sudo npm run build
# Starting PM2 app
sudo pm2 start dist/main.js
sudo service nginx restart