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
cd /home/ubuntu
mkdir nodeapp
# Checking out from Version Control
git clone https://github.com/mmdcloud/carshub-gcp-managed-instance-groups
cd carshub-gcp-managed-instance-groups/backend/api
cp -r . /home/ubuntu/nodeapp/
cd /home/ubuntu/nodeapp/
# Copying Nginx config
cp scripts/default /etc/nginx/sites-available/
# Installing dependencies
sudo npm i

# Copying DB crendetials 
cat > .env << EOL
DB_PATH=$1
USERNAME=$2
PASSWORD=$3
EOL
# Building the project
sudo npm run build
# Starting PM2 app
pm2 start dist/main.js
sudo service nginx restart