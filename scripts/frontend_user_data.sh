#!/bin/bash

# Enable error handling and logging
set -e
exec 1> >(tee -a /var/log/ecommerce/frontend-setup.log) 2>&1

# Create log directory
sudo mkdir -p /var/log/ecommerce
sudo chown ubuntu:ubuntu /var/log/ecommerce

echo "Starting frontend server setup at $(date)"

# Function to retry commands
retry_command() {
    local retries=5
    local count=1
    until "$@"; do
        count=$((count + 1))
        if [ $count -gt "$retries" ]; then
            return 1
        fi
        echo "Failed, retrying... ($count/$retries)"
        sleep 15
    done
    return 0
}

# Update packages with retry
echo "Updating system packages..."
retry_command sudo apt update -y
sudo apt install -y wget

# Install Node.js and npm
echo "Installing Node.js and npm..."
retry_command "curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -"
retry_command sudo apt install -y nodejs git

# Install Node Exporter for monitoring
echo "Installing Node Exporter..."
cd /home/ubuntu
NODE_EXPORTER_VERSION="1.6.1"
wget https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
tar xvfz node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
cd node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64

# Create Node Exporter service with proper logging
sudo tee /etc/systemd/system/node_exporter.service <<EOF
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=ubuntu
ExecStart=/home/ubuntu/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter
StandardOutput=append:/var/log/ecommerce/node_exporter.log
StandardError=append:/var/log/ecommerce/node_exporter.log
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Clone the repository with retry
echo "Cloning repository..."
cd /home/ubuntu
retry_command git clone https://github.com/shafeeshafee/ecommerce_terraform_deployment.git
cd ecommerce_terraform_deployment/frontend

# Update package.json proxy with validation
echo "Updating package.json proxy configuration..."
if [ -z "${backend_private_ip}" ]; then
    echo "Error: backend_private_ip is not set"
    exit 1
fi
sed -i 's|"proxy": "http://localhost:8000"|"proxy": "http://'${backend_private_ip}':8000"|' package.json

# Install dependencies with retry
echo "Installing npm dependencies..."
retry_command npm install

# Create React service with proper logging
sudo tee /etc/systemd/system/react.service <<EOF
[Unit]
Description=React Frontend Application
After=network.target

[Service]
User=ubuntu
WorkingDirectory=/home/ubuntu/ecommerce_terraform_deployment/frontend
Environment=NODE_OPTIONS=--openssl-legacy-provider
ExecStart=/usr/bin/npm start
StandardOutput=append:/var/log/ecommerce/react.log
StandardError=append:/var/log/ecommerce/react.log
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Start services
echo "Starting services..."
sudo systemctl daemon-reload
sudo systemctl enable node_exporter
sudo systemctl start node_exporter
sudo systemctl enable react
sudo systemctl start react

echo "Frontend setup completed successfully at $(date)"
