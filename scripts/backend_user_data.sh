#!/bin/bash

# Enable error handling
set -e
exec 1> >(logger -s -t $(basename $0)) 2>&1

# Create log directory
sudo mkdir -p /var/log/ecommerce
sudo chown ubuntu:ubuntu /var/log/ecommerce

echo "Starting backend server setup..."

# Update packages
sudo apt update -y
sudo apt install -y python3.9 python3.9-venv python3.9-dev git

# Install Node Exporter for monitoring
echo "Installing Node Exporter..."
cd /home/ubuntu
wget https://github.com/prometheus/node_exporter/releases/download/v1.6.1/node_exporter-1.6.1.linux-amd64.tar.gz
tar xvfz node_exporter-1.6.1.linux-amd64.tar.gz
cd node_exporter-1.6.1.linux-amd64

# Create Node Exporter service
sudo tee /etc/systemd/system/node_exporter.service <<EOF
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=ubuntu
ExecStart=/home/ubuntu/node_exporter-1.6.1.linux-amd64/node_exporter
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
cd ecommerce_terraform_deployment/backend

# Create and activate virtual environment
python3.9 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Modify settings.py
echo "Configuring Django settings..."
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
sed -i "s/ALLOWED_HOSTS = \[\]/ALLOWED_HOSTS = \['$PRIVATE_IP'\]/" my_project/settings.py
sed -i "s|'ENGINE': 'django.db.backends.sqlite3'|'ENGINE': 'django.db.backends.postgresql'|" my_project/settings.py
sed -i "s|'NAME': BASE_DIR / 'db.sqlite3',|'NAME': '${db_name}', 'USER': '${db_username}', 'PASSWORD': '${db_password}', 'HOST': '${rds_endpoint}', 'PORT': '5432',|" my_project/settings.py

# Create Django service
sudo tee /etc/systemd/system/django.service <<EOF
[Unit]
Description=Django Application Server
After=network.target

[Service]
User=ubuntu
WorkingDirectory=/home/ubuntu/ecommerce_terraform_deployment/backend
Environment="PATH=/home/ubuntu/ecommerce_terraform_deployment/backend/venv/bin"
ExecStart=/home/ubuntu/ecommerce_terraform_deployment/backend/venv/bin/python manage.py runserver 0.0.0.0:8000
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Database setup
echo "Setting up database..."
python manage.py makemigrations account
python manage.py makemigrations payments
python manage.py makemigrations product
python manage.py migrate

# Migrate data
python manage.py dumpdata --database=sqlite --natural-foreign --natural-primary -e contenttypes -e auth.Permission --indent 4 > datadump.json
python manage.py loaddata datadump.json

# Start Django service
sudo systemctl daemon-reload
sudo systemctl enable django
sudo systemctl start django

echo "Backend setup completed successfully!"