#!/bin/bash

# Enable error handling
set -e
exec 1> >(logger -s -t $(basename $0)) 2>&1

# Create log directory
sudo mkdir -p /var/log/ecommerce
sudo chown ubuntu:ubuntu /var/log/ecommerce

echo "Starting frontend server setup..."

# Update packages
sudo apt update -y

# Install Node.js and npm
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt install -y nodejs git

# Install Node Exporter for monitoring
echo "Installing Node Exporter..."
cd /home/ubuntu
wget https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-amd64.tar.gz
tar xvfz node_exporter-1.8.2.linux-amd64.tar.gz
cd node_exporter-1.8.2.linux-amd64

# Create Node Exporter service
sudo tee /etc/systemd/system/node_exporter.service <<EOF
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=ubuntu
ExecStart=/home/ubuntu/node_exporter-1.8.2.linux-amd64/node_exporter
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable node_exporter
sudo systemctl start node_exporter

# Clone the repository
echo "Cloning repository..."
cd /home/ubuntu
git clone https://github.com/shafeeshafee/ecommerce_terraform_deployment.git
cd ecommerce_terraform_deployment/frontend

# Update package.json proxy
sed -i 's|"proxy": "http://localhost:8000"|"proxy": "http://${backend_private_ip}:8000"|' package.json

# Install dependencies
npm install

# Create React service
sudo tee /etc/systemd/system/react.service <<EOF
[Unit]
Description=React Frontend Application
After=network.target

[Service]
User=ubuntu
WorkingDirectory=/home/ubuntu/ecommerce_terraform_deployment/frontend
Environment=NODE_OPTIONS=--openssl-legacy-provider
ExecStart=/usr/bin/npm start
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Start React service
sudo systemctl daemon-reload
sudo systemctl enable react
sudo systemctl start react

echo "Frontend setup completed successfully!"
