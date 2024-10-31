#!/bin/bash

# Extract variables passed from Terraform
allowed_hosts="${allowed_hosts}"

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
sudo apt install -y wget git python3-pip python3-venv build-essential \
libjpeg-dev zlib1g-dev libpng-dev libfreetype6-dev liblcms2-dev \
libtiff5-dev libwebp-dev tcl8.6-dev tk8.6-dev python3-tk

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
### DJANGO SETUP ###
#############################
# Clone repository
git clone https://github.com/shafeeshafee/ecommerce_terraform_deployment.git /home/ubuntu/ecommerce_terraform_deployment
chown -R ubuntu:ubuntu /home/ubuntu/ecommerce_terraform_deployment

# Setup virtual environment and install dependencies as ubuntu user
sudo -u ubuntu bash << EOF
cd /home/ubuntu/ecommerce_terraform_deployment
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip setuptools wheel
pip install gunicorn
pip install -r backend/requirements.txt
deactivate
EOF

# Update ALLOWED_HOSTS in Django settings
backend_private_ip=$(hostname -I | awk '{print $1}')
sed -i "s/ALLOWED_HOSTS = \[\]/ALLOWED_HOSTS = ['$backend_private_ip', '${allowed_hosts}']/" /home/ubuntu/ecommerce_terraform_deployment/backend/my_project/settings.py


# Update settings.py to use PostgreSQL
cd /home/ubuntu/ecommerce_terraform_deployment/backend/
sed -i "s/# 'ENGINE': 'django.db.backends.postgresql'/'ENGINE': 'django.db.backends.postgresql'/" my_project/settings.py
sed -i "s/# 'NAME': 'your_db_name'/'NAME': '${db_name}'/" my_project/settings.py
sed -i "s/# 'USER': 'your_username'/'USER': '${db_username}'/" my_project/settings.py
sed -i "s/# 'PASSWORD': 'your_password'/'PASSWORD': '${db_password}'/" my_project/settings.py
sed -i "s/# 'HOST': 'your-rds-endpoint.amazonaws.com'/'HOST': '${rds_endpoint}'/" my_project/settings.py
sed -i "s/# 'PORT': '5432'/'PORT': '5432'/" my_project/settings.py
sed -i "s/#\},/},/" my_project/settings.py
sed -i "s/# 'sqlite': {/'sqlite': {/" my_project/settings.py

# Set STATIC_ROOT in settings.py
echo "STATIC_ROOT = os.path.join(BASE_DIR, 'staticfiles')" >> my_project/settings.py

# Run Django commands as ubuntu user
sudo -u ubuntu bash << EOF
cd /home/ubuntu/ecommerce_terraform_deployment/backend
source ../venv/bin/activate
python manage.py makemigrations
python manage.py migrate
python manage.py collectstatic --noinput
echo "from django.contrib.auth import get_user_model; User = get_user_model(); User.objects.create_superuser('admin', 'admin@example.com', 'password')" | python manage.py shell
deactivate
EOF

#############################
### GUNICORN SETUP ###
#############################
# Create Gunicorn service file
cat << EOF | sudo tee /etc/systemd/system/gunicorn.service
[Unit]
Description=Gunicorn instance to serve Django app
After=network.target

[Service]
User=ubuntu
Group=www-data
WorkingDirectory=/home/ubuntu/ecommerce_terraform_deployment/backend
Environment="PATH=/home/ubuntu/ecommerce_terraform_deployment/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=/home/ubuntu/ecommerce_terraform_deployment/venv/bin/gunicorn \
          --workers 3 \
          --bind 0.0.0.0:8000 \
          --error-logfile /var/log/gunicorn/error.log \
          --access-logfile /var/log/gunicorn/access.log \
          my_project.wsgi:application

[Install]
WantedBy=multi-user.target
EOF

# Create log directory for Gunicorn
sudo mkdir -p /var/log/gunicorn
sudo chown -R ubuntu:ubuntu /var/log/gunicorn

# Start and enable Gunicorn service
sudo systemctl daemon-reload
sudo systemctl start gunicorn
sudo systemctl enable gunicorn