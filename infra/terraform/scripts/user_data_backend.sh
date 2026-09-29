#!/bin/bash
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive
cd /

apt-get update -y
apt-get upgrade -y

# Nginx + tools
apt-get install -y nginx git curl

# Node.js 20
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs
node -v && npm -v && which node

# PM2 + Nest CLI
npm i -g pm2 @nestjs/cli

# Fetch code (idempotent for reboots)
rm -rf /tmp/repo /nodeapp
git clone https://github.com/mmdcloud/carshub-gcp-managed-instance-groups /tmp/repo
mkdir -p /nodeapp
cp -r /tmp/repo/src/backend/api/. /nodeapp/
cd /nodeapp

# Env variables (contains secrets, so lock down permissions)
umask 077
tee .env > /dev/null <<EOL
DB_PATH=${DB_PATH}
UN=${UN}
CREDS=${CREDS}
EOL
chmod 600 .env
umask 022

# Nginx config
cp scripts/default /etc/nginx/sites-available/default
ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
nginx -t

# Install and build
npm ci || npm i
npm run build
test -f dist/main.js

# Start app with PM2 (cwd is /nodeapp, so .env is found)
pm2 delete all || true
pm2 start dist/main.js --name carshub-backend
pm2 save
pm2 startup systemd -u root --hp /root || true

systemctl restart nginx