#!/bin/bash

#############################
### ADD WORKLOAD SSH KEY ###
#############################
# Ensure the .ssh directory exists and has correct permissions
mkdir -p /home/ubuntu/.ssh
chmod 700 /home/ubuntu/.ssh

# Add your public SSH key to authorized_keys
echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDSkMc19m28614Rb3sGEXQUN+hk4xGiufU9NYbVXWGVrF1bq6dEnAD/VtwM6kDc8DnmYD7GJQVvXlDzvlWxdpBaJEzKziJ+PPzNVMPgPhd01cBWPv82+/Wu6MNKWZmi74TpgV3kktvfBecMl+jpSUMnwApdA8Tgy8eB0qELElFBu6cRz+f6Bo06GURXP6eAUbxjteaq3Jy8mV25AMnIrNziSyQ7JOUJ/CEvvOYkLFMWCF6eas8bCQ5SpF6wHoYo/iavMP4ChZaXF754OJ5jEIwhuMetBFXfnHmwkrEIInaF3APIBBCQWL5RC4sJA36yljZCGtzOi5Y2jq81GbnBXN3Dsjvo5h9ZblG4uWfEzA2Uyn0OQNDcrecH3liIpowtGAoq8NUQf89gGwuOvRzzILkeXQ8DKHtWBee5Oi/z7j9DGfv7hTjDBQkh28LbSu9RdtPRwcCweHwTLp4X3CYLwqsxrIP8tlGmrVoZZDhMfyy/bGslZp5Bod2wnOMlvGktkHs=" >> /home/ubuntu/.ssh/authorized_keys

# Set permissions and ownership
chmod 600 /home/ubuntu/.ssh/authorized_keys
chown -R ubuntu:ubuntu /home/ubuntu/.ssh

#############################
### UPDATE AND INSTALL DEPENDENCIES ###
#############################
sudo apt update
sudo apt install -y wget git nginx

#############################
### NODE EXPORTER SETUP ###
#############################
NODE_EXPORTER_VERSION="${NODE_EXPORTER_VERSION}"

# Download and install Node Exporter
wget https://github.com/prometheus/node_exporter/releases/download/v$NODE_EXPORTER_VERSION/node_exporter-$NODE_EXPORTER_VERSION.linux-amd64.tar.gz
tar xvfz node_exporter-$NODE_EXPORTER_VERSION.linux-amd64.tar.gz
sudo mv node_exporter-$NODE_EXPORTER_VERSION.linux-amd64/node_exporter /usr/local/bin/
rm -rf node_exporter-$NODE_EXPORTER_VERSION.linux-amd64*

# Create Node Exporter user
sudo useradd --no-create-home --shell /bin/false node_exporter

# Create Node Exporter service
cat << EOF | sudo tee /etc/systemd/system/node_exporter.service
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF

# Start and enable Node Exporter service
sudo systemctl daemon-reload
sudo systemctl start node_exporter
sudo systemctl enable node_exporter

#############################
### NODE.JS SETUP ###
#############################
# Install Node.js LTS (v18.x)
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs

#############################
### REACT SETUP ###
#############################
# Clone repository and set ownership
git clone https://github.com/shafeeshafee/ecommerce_terraform_deployment.git /home/ubuntu/ecommerce_terraform_deployment
chown -R ubuntu:ubuntu /home/ubuntu/ecommerce_terraform_deployment

# Navigate to frontend directory
cd /home/ubuntu/ecommerce_terraform_deployment/frontend

# Remove backend URL replacement (since we'll use relative URLs)
# sed -i "s|http://.*:8000/api/|http://${backend_private_ip}:8000/api/|g" src/constants/index.js

# Install dependencies and build as ubuntu user
sudo -u ubuntu bash << 'EOF'
cd /home/ubuntu/ecommerce_terraform_deployment/frontend
export NODE_OPTIONS=--openssl-legacy-provider
npm install
npm run build
EOF

# Create directory for Nginx logs
sudo mkdir -p /var/log/nginx/react
sudo chown -R www-data:adm /var/log/nginx/react

#############################
### NGINX CONFIGURATION ###
#############################
# Remove default Nginx site
sudo rm -f /etc/nginx/sites-enabled/default

# Create Nginx server block for React app
cat << EOF | sudo tee /etc/nginx/sites-available/react_app
server {
    listen 3000;
    server_name localhost;

    # Logging configuration
    access_log /var/log/nginx/react_access.log;
    error_log /var/log/nginx/react_error.log debug;

    root /home/ubuntu/ecommerce_terraform_deployment/frontend/build;
    index index.html;

    # Add proper mime types
    include /etc/nginx/mime.types;

    location / {
        try_files \$uri \$uri/ /index.html =404;
        add_header 'Access-Control-Allow-Origin' '*';
        add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
        add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
    }

    location /api/ {
        proxy_pass http://${backend_private_ip}:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }

    # Handle static files
    location /static/ {
        expires 1y;
        add_header Cache-Control "public, no-transform";
    }

    # Handle the main index.html
    location = /index.html {
        add_header Cache-Control "no-cache";
        expires 0;
    }
}
EOF

# Enable the new site
sudo ln -s /etc/nginx/sites-available/react_app /etc/nginx/sites-enabled/

# Set correct permissions for the entire path
sudo chmod 755 /home/ubuntu
sudo chmod 755 /home/ubuntu/ecommerce_terraform_deployment
sudo chmod 755 /home/ubuntu/ecommerce_terraform_deployment/frontend
sudo chmod -R 755 /home/ubuntu/ecommerce_terraform_deployment/frontend/build
sudo chown -R www-data:www-data /home/ubuntu/ecommerce_terraform_deployment/frontend/build

# Verify Nginx configuration
sudo nginx -t

# Restart and enable Nginx service
sudo systemctl restart nginx
sudo systemctl enable nginx
