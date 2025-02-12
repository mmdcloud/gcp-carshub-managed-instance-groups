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

cd /home/milinddixit1967_gmail_com
mkdir nodeapp
# Checking out from Version Control
git clone https://github.com/mmdcloud/carshub-gcp-managed-instance-groups
cd carshub-gcp-managed-instance-groups/frontend
cp -r . /home/milinddixit1967_gmail_com/nodeapp/
cd /home/milinddixit1967_gmail_com/nodeapp/

# Setting up env variables
cat > .env <<EOL
CDN_URL=$1
BASE_URL=$2
EOL

# Copying Nginx config
cp scripts/default /etc/nginx/sites-available/
# Installing dependencies
npm i

# Building the project
npm run build
# Starting PM2 app
pm2 start ecosystem.config.js
service nginx restart