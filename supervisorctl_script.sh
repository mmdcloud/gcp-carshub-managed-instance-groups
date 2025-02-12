
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
BASE_URL="${module.backend_lb.address}"
CDN_URL="${module.cdn_lb.address}"
EOL

# Installing dependencies
npm i

# Building the project
npm run build

# Run the app
npm start

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
supervisorctl reload

service nginx reload
service nginx restart