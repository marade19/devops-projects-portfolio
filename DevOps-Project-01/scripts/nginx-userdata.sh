#!/bin/bash
# nginx-userdata.sh
# Runs at boot on every frontend EC2 instance. Installs Nginx and configures
# it to reverse-proxy to the app tier via the INTERNAL Tomcat NLB — this is
# the exact pattern the original README specifies (see its "Nginx
# Configuration" section): upstream backend = internal NLB DNS name : 8080.
#
# Replace InternalTomcatNLB-49c5132eae8ab1e2.elb.us-east-1.amazonaws.com with
# your own internal NLB's DNS name if reproducing this (from 07-app-tier.sh).

apt-get update -y
apt-get install -y nginx

# Remove default nginx welcome config so it doesn't conflict
rm -f /etc/nginx/sites-enabled/default

# Drop in the reverse-proxy config pointing at the internal Tomcat NLB
cat > /etc/nginx/conf.d/app.conf <<'CONF'
upstream backend {
    server InternalTomcatNLB-49c5132eae8ab1e2.elb.us-east-1.amazonaws.com:8080;
}

server {
    listen 80;

    location / {
        proxy_pass http://backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
CONF

systemctl enable nginx
systemctl restart nginx
