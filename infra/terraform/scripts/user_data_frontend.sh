#!/bin/bash
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive
cd /

apt-get update -y
apt-get upgrade -y

# Nginx
apt-get install -y nginx git curl

# Node.js 20
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs
node -v && npm -v && which node

# PM2
npm i -g pm2

# Fetch code (idempotent for reboots)
rm -rf /tmp/repo /nodeapp
git clone https://github.com/mmdcloud/carshub-gcp-managed-instance-groups /tmp/repo
mkdir -p /nodeapp
cp -r /tmp/repo/src/frontend/. /nodeapp/
cd /nodeapp

# Env variables
tee .env > /dev/null <<EOL
BASE_URL=${BASE_URL}
CDN_URL=${CDN_URL}
EOL

# Nginx config
cp scripts/default /etc/nginx/sites-available/default
ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
nginx -t

# Build
npm ci || npm i
npm run build

# Start app with PM2
pm2 delete all || true
pm2 start ecosystem.config.js
pm2 save
pm2 startup systemd -u root --hp /root || true

systemctl restart nginx