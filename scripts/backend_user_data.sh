#!/bin/bash

# Enable error handling and logging
set -e
exec 1> >(tee -a /var/log/ecommerce/backend-setup.log) 2>&1

# Create log directory
sudo mkdir -p /var/log/ecommerce
sudo chown ubuntu:ubuntu /var/log/ecommerce

echo "Starting backend server setup at $(date)"

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

# Function to wait for database
wait_for_database() {
    echo "Waiting for database to be ready..."
    for i in {1..30}; do
        if pg_isready -h "${rds_endpoint}" -U "${db_username}"; then
            echo "Database is ready!"
            return 0
        fi
        echo "Database not ready, waiting... ($i/30)"
        sleep 10
    done
    echo "Database connection timeout"
    return 1
}

# Update packages with retry
echo "Updating system packages..."
retry_command sudo apt update -y
sudo apt install -y wget postgresql-client

# Install Python and dependencies
echo "Installing Python and dependencies..."
retry_command sudo apt install -y python3.9 python3.9-venv python3.9-dev git

# Install Node Exporter for monitoring
echo "Installing Node Exporter..."
cd /home/ubuntu
NODE_EXPORTER_VERSION="${NODE_EXPORTER_VERSION}"  # Use the injected variable
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
cd ecommerce_terraform_deployment/backend

# Create and activate virtual environment
echo "Setting up Python virtual environment..."
python3.9 -m venv venv
source venv/bin/activate

# Install dependencies with retry
echo "Installing Python dependencies..."
retry_command pip install -r requirements.txt
pip install psycopg2-binary

# Modify settings.py
echo "Configuring Django settings..."
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

# Validate required variables
if [ -z "${db_name}" ] || [ -z "${db_username}" ] || [ -z "${db_password}" ] || [ -z "${rds_endpoint}" ]; then
    echo "Error: Database configuration variables are not set"
    exit 1
fi

# Create a temporary settings file for migration
cat > my_project/temp_settings.py <<EOF
import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
SECRET_KEY = 'django-insecure-*7!!kc@bmtx8ngui6lr@xmifmcwm6y%hnbe)rdei(b!ds8t)uq'
DEBUG = True
ALLOWED_HOSTS = ['$PRIVATE_IP']

INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    'rest_framework',
    'corsheaders',
    'product',
    'payments',
    'account',
]

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': '${db_name}',
        'USER': '${db_username}',
        'PASSWORD': '${db_password}',
        'HOST': '${rds_endpoint}',
        'PORT': '5432',
    },
    'sqlite': {
        'ENGINE': 'django.db.backends.sqlite3',
        'NAME': BASE_DIR / 'db.sqlite3',
    }
}
EOF

# Set the Django settings module to our temporary settings
export DJANGO_SETTINGS_MODULE=my_project.temp_settings

# Wait for database to be ready
wait_for_database

# Database setup with retry
echo "Setting up database..."
retry_command python manage.py makemigrations account
retry_command python manage.py makemigrations payments
retry_command python manage.py makemigrations product
retry_command python manage.py migrate

# Migrate data with error handling
echo "Migrating data..."
if python manage.py dumpdata --database=sqlite \
    --natural-foreign --natural-primary \
    -e contenttypes -e auth.Permission \
    -e sessions.session \
    --indent 4 > datadump.json; then
    retry_command python manage.py loaddata datadump.json
else
    echo "Error: Failed to dump data from SQLite"
    exit 1
fi

# Verify the migration
echo "Verifying migration..."
python manage.py shell <<EOF
from django.contrib.auth.models import User
user_count = User.objects.count()
print(f"Successfully migrated {user_count} users")
if user_count == 0:
    exit(1)
EOF

# Update the actual settings.py file
echo "Updating final Django settings..."
sed -i "s/ALLOWED_HOSTS = \[\]/ALLOWED_HOSTS = \['$PRIVATE_IP'\]/" my_project/settings.py
sed -i "s|'ENGINE': 'django.db.backends.sqlite3'|'ENGINE': 'django.db.backends.postgresql'|" my_project/settings.py
sed -i "s|'NAME': BASE_DIR / 'db.sqlite3',|'NAME': '${db_name}', 'USER': '${db_username}', 'PASSWORD': '${db_password}', 'HOST': '${rds_endpoint}', 'PORT': '5432',|" my_project/settings.py

# Create Django service with proper logging
sudo tee /etc/systemd/system/django.service <<EOF
[Unit]
Description=Django Application Server
After=network.target

[Service]
User=ubuntu
WorkingDirectory=/home/ubuntu/ecommerce_terraform_deployment/backend
Environment="PATH=/home/ubuntu/ecommerce_terraform_deployment/backend/venv/bin"
Environment="DJANGO_SETTINGS_MODULE=my_project.settings"
ExecStart=/home/ubuntu/ecommerce_terraform_deployment/backend/venv/bin/python manage.py runserver 0.0.0.0:8000
StandardOutput=append:/var/log/ecommerce/django.log
StandardError=append:/var/log/ecommerce/django.log
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Start services
echo "Starting services..."
sudo systemctl daemon-reload
sudo systemctl enable node_exporter
sudo systemctl start node_exporter
sudo systemctl enable django
sudo systemctl start django

echo "Backend setup completed successfully at $(date)"