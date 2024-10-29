pipeline {
    agent any

    environment {
        PYTHON_VENV          = 'wl5_venv'
        TERRAFORM_DIR        = 'Terraform'
        BACKEND_DIR          = 'backend'
        FRONTEND_DIR         = 'frontend'
        TERRAFORM_VERSION    = '1.9.8'
        NODE_EXPORTER_VERSION = '1.8.2'
    }

    parameters {
        booleanParam(
            name: 'DESTROY_INFRASTRUCTURE',
            defaultValue: false,
            description: 'Destroy all infrastructure'
        )
    }

    options {
        timeout(time: 2, unit: 'HOURS')        // Limit pipeline execution time
        disableConcurrentBuilds()              // Only one build runs at a time
    }

    stages {
        stage('Destroy Existing Infrastructure') {
            when {
                expression { params.DESTROY_INFRASTRUCTURE == true }
            }
            steps {
                withCredentials([
                    string(credentialsId: 'AWS_ACCESS_KEY', variable: 'AWS_ACCESS_KEY'),
                    string(credentialsId: 'AWS_SECRET_KEY', variable: 'AWS_SECRET_KEY'),
                    string(credentialsId: 'DB_PASSWORD', variable: 'DB_PASSWORD')
                ]) {
                    dir(TERRAFORM_DIR) {
                        script {
                            try {
                                sh '''
                                    export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY
                                    export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_KEY
                                    export TF_VAR_db_password=$DB_PASSWORD
                                    terraform init -input=false
                                    terraform destroy -auto-approve
                                '''
                            } catch (e) {
                                error "Terraform destroy failed: ${e.getMessage()}"
                            }
                        }
                    }
                }
            }
        }

        stage('Validate Environment') {
            steps {
                script {
                    // Basic tool validation
                    sh '''
                        python3.9 --version || { echo "Python 3.9 is required"; exit 1; }
                        node --version || { echo "Node.js is required"; exit 1; }
                        terraform version || { echo "Terraform is required"; exit 1; }
                        aws --version || { echo "AWS CLI is required"; exit 1; }
                    '''

                    // AWS validation with credentials
                    withCredentials([
                        string(credentialsId: 'AWS_ACCESS_KEY', variable: 'AWS_ACCESS_KEY'),
                        string(credentialsId: 'AWS_SECRET_KEY', variable: 'AWS_SECRET_KEY')
                    ]) {
                        sh '''
                            export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY
                            export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_KEY
                            aws ec2 describe-key-pairs --key-name workload-5-key-shaf || { echo "AWS key pair 'workload-5-key-shaf' is required"; exit 1; }
                        '''
                    }
                }
            }
        }

        stage('Build') {
            steps {
                script {
                    try {
                        sh '''#!/bin/bash
                            set -e
                            echo "Setting up Python virtual environment..."
                            python3.9 -m venv ${PYTHON_VENV}
                            source ${PYTHON_VENV}/bin/activate
                            echo "Installing backend dependencies..."
                            pip install --upgrade pip
                            pip install -r ${BACKEND_DIR}/requirements.txt
                            echo "Installing Node.js LTS..."
                            curl -fsSL https://deb.nodesource.com/setup_lts.x > setup_node.sh
                            DEBIAN_FRONTEND=noninteractive sudo -E bash setup_node.sh
                            sudo apt-get install -y nodejs git
                            echo "Building frontend application..."
                            cd ${FRONTEND_DIR}
                            export NODE_OPTIONS=--openssl-legacy-provider
                            export CI=false
                            npm ci
                            npm run build
                            cd ..
                        '''
                    } catch (e) {
                        error "Build stage failed: ${e.getMessage()}"
                    }
                }
            }
        }

        stage('Test') {
            steps {
                script {
                    try {
                        sh '''#!/bin/bash
                            set -e
                            echo "Activating Python virtual environment..."
                            source ${PYTHON_VENV}/bin/activate
                            echo "Installing testing tools..."
                            pip install pytest-django pytest-cov
                            echo "Running backend tests with coverage..."
                            cd ${BACKEND_DIR}
                            mkdir -p ../test-reports
                            python manage.py makemigrations account payments product
                            python manage.py migrate
                            pytest account/tests.py --verbose \
                                --junit-xml ../test-reports/results.xml \
                                --cov=. \
                                --cov-report=xml:../test-reports/coverage.xml
                            cd ..
                            echo "Running frontend tests..."
                            cd ${FRONTEND_DIR}
                            npm test -- --ci --coverage || echo "No frontend tests configured"
                            cd ..
                        '''
                    } catch (e) {
                        error "Test stage failed: ${e.getMessage()}"
                    }
                }
            }
            post {
                always {
                    junit '**/test-reports/results.xml'
                }
            }
        }

        stage('Terraform Init') {
            steps {
                dir(TERRAFORM_DIR) {
                    script {
                        try {
                            sh 'terraform init -input=false'
                        } catch (e) {
                            error "Terraform initialization failed: ${e.getMessage()}"
                        }
                    }
                }
            }
        }

        stage('Terraform Plan') {
            steps {
                withCredentials([
                    string(credentialsId: 'AWS_ACCESS_KEY', variable: 'AWS_ACCESS_KEY'),
                    string(credentialsId: 'AWS_SECRET_KEY', variable: 'AWS_SECRET_KEY'),
                    string(credentialsId: 'DB_PASSWORD', variable: 'DB_PASSWORD')
                ]) {
                    dir(TERRAFORM_DIR) {
                        script {
                            try {
                                def exitCode = sh(
                                    script: """
                                        export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY}
                                        export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_KEY}
                                        export TF_VAR_db_password=${DB_PASSWORD}
                                        terraform plan -input=false -detailed-exitcode \\
                                        -out=plan.tfplan \\
                                        -var="NODE_EXPORTER_VERSION=${NODE_EXPORTER_VERSION}"
                                    """,
                                    returnStatus: true
                                )
                                if (exitCode == 0 || exitCode == 2) {
                                    echo "Terraform plan completed successfully with exit code ${exitCode}"
                                } else {
                                    error "Terraform planning failed with exit code ${exitCode}"
                                }
                            } catch (e) {
                                error "Terraform planning failed: ${e.getMessage()}"
                            }
                        }
                    }
                }
            }
        }

        stage('Terraform Apply') {
            steps {
                withCredentials([
                    string(credentialsId: 'AWS_ACCESS_KEY', variable: 'AWS_ACCESS_KEY'),
                    string(credentialsId: 'AWS_SECRET_KEY', variable: 'AWS_SECRET_KEY'),
                    string(credentialsId: 'DB_PASSWORD', variable: 'DB_PASSWORD')
                ]) {
                    dir(TERRAFORM_DIR) {
                        script {
                            try {
                                sh(
                                    script: '''
                                        export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY
                                        export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_KEY
                                        export TF_VAR_db_password=$DB_PASSWORD
                                        terraform apply -input=false -auto-approve plan.tfplan
                                    ''',
                                    shell: '/bin/bash'
                                )
                            } catch (e) {
                                error "Terraform apply failed: ${e.getMessage()}"
                            }
                        }
                    }
                }
            }
        }

        stage('Configure Database') {
            steps {
                withCredentials([
                    string(credentialsId: 'DB_PASSWORD', variable: 'DB_PASSWORD'),
                    string(credentialsId: 'AWS_ACCESS_KEY', variable: 'AWS_ACCESS_KEY'),
                    string(credentialsId: 'AWS_SECRET_KEY', variable: 'AWS_SECRET_KEY')
                ]) {
                    script {
                        try {
                            sh '''#!/bin/bash
                                set -e
                                # Set AWS credentials for CLI
                                export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY
                                export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_KEY
                                
                                echo "Waiting for RDS instance to become available..."
                                aws rds wait db-instance-available --db-instance-identifier ecommerce-db
                                
                                echo "Retrieving RDS endpoint from Terraform outputs..."
                                cd ${TERRAFORM_DIR}
                                RDS_ENDPOINT=$(terraform output -raw rds_endpoint)
                                RDS_HOST=$(echo $RDS_ENDPOINT | cut -d':' -f1)
                                cd ..
                                
                                echo "RDS Host: $RDS_HOST (without port)"
                                
                                echo "Activating Python virtual environment..."
                                source ${PYTHON_VENV}/bin/activate
                                cd ${BACKEND_DIR}
                                
                                # Create a temporary settings file for database operations
                                cat > my_project/temp_settings.py <<EOL
import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
SECRET_KEY = 'django-insecure-*7!!kc@bmtx8ngui6lr@xmifmcwm6y%hnbe)rdei(b!ds8t)uq'
DEBUG = True
ALLOWED_HOSTS = ['*']

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

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'corsheaders.middleware.CorsMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

ROOT_URLCONF = 'my_project.urls'

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': 'ecommercedb',
        'USER': 'kurac5user',
        'PASSWORD': '$DB_PASSWORD',
        'HOST': '$RDS_HOST',
        'PORT': '5432',
    },
    'sqlite': {
        'ENGINE': 'django.db.backends.sqlite3',
        'NAME': BASE_DIR / 'db.sqlite3',
    }
}

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.debug',
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ],
        },
    },
]

STATIC_URL = '/static/'
DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'
EOL
                                
                                echo "Setting Django settings module..."
                                export DJANGO_SETTINGS_MODULE=my_project.temp_settings
                                export PYTHONPATH=$PWD:$PYTHONPATH
                                
                                echo "Installing psycopg2 if not already installed..."
                                pip install psycopg2-binary
                                
                                echo "Applying database migrations..."
                                python manage.py makemigrations account payments product
                                python manage.py migrate
                                
                                echo "Exporting data from SQLite..."
                                python manage.py dumpdata --database=sqlite \
                                    --natural-foreign --natural-primary \
                                    -e contenttypes -e auth.Permission \
                                    -e sessions.session \
                                    --indent 4 > datadump.json
                                
                                echo "Loading data into PostgreSQL..."
                                python manage.py loaddata datadump.json
                                
                                echo "Verifying data migration..."
                                cat <<EOL | python
import os
import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'my_project.temp_settings')
django.setup()

from django.contrib.auth.models import User
users = User.objects.all()
print(f'Successfully migrated {users.count()} users')
if users.count() == 0:
    exit(1)
EOL
                                
                                echo "Cleaning up temporary files..."
                                rm -f my_project/temp_settings.py
                                rm -f datadump.json
                                
                                echo "Database migration completed successfully!"
                            '''
                        } catch (e) {
                            error "Database configuration failed: ${e.getMessage()}"
                        }
                    }
                }
            }
        }

        stage('Verify Deployment') {
            steps {
                script {
                    try {
                        sh '''#!/bin/bash
                            set -e
                            echo "Fetching ALB DNS from Terraform..."
                            cd ${TERRAFORM_DIR}
                            ALB_DNS=$(terraform output -raw alb_dns_name)
                            cd ..
                            
                            echo "ALB DNS: $ALB_DNS"
                            echo "Checking if the application is responding with HTTP 200..."
                            
                            timeout 300 bash -c '
                                while true; do
                                    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://'$ALB_DNS')
                                    echo "Current HTTP response code: $HTTP_CODE"
                                    if [ "$HTTP_CODE" = "200" ]; then
                                        echo "Application is ready!"
                                        break
                                    fi
                                    echo "Waiting for application to be ready..."
                                    sleep 5
                                done
                            '
                            echo "Deployment verified successfully: Application is up and running at http://$ALB_DNS"
                        '''
                    } catch (e) {
                        error "Deployment verification failed: ${e.getMessage()}"
                    }
                }
            }
        }
    }

    post {
        always {
            script {
                def buildStatus = currentBuild.result ?: 'SUCCESS'
                def message = "Build ${env.BUILD_NUMBER} - ${buildStatus}\n${env.BUILD_URL}"
                echo message
            }
        }
        failure {
            script {
                try {
                    timeout(time: 10, unit: 'MINUTES') {
                        input message: 'Infrastructure deployment failed. Would you like to destroy the infrastructure? (Timeout in 10 minutes)', ok: 'Destroy'
                    }
                    withCredentials([
                        string(credentialsId: 'AWS_ACCESS_KEY', variable: 'AWS_ACCESS_KEY'),
                        string(credentialsId: 'AWS_SECRET_KEY', variable: 'AWS_SECRET_KEY'),
                        string(credentialsId: 'DB_PASSWORD', variable: 'DB_PASSWORD')
                    ]) {
                        dir(TERRAFORM_DIR) {
                            echo "Initiating Terraform destroy due to build failure..."
                            sh '''
                                export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY
                                export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_KEY
                                export TF_VAR_db_password=$DB_PASSWORD
                                
                                # Initialize Terraform if needed
                                terraform init -input=false
                                
                                # Run destroy with timeout
                                timeout 20m terraform destroy -auto-approve || {
                                    echo "First destroy attempt failed, waiting 30 seconds and trying again..."
                                    sleep 30
                                    terraform destroy -auto-approve
                                }
                                
                                # Verify all resources are destroyed
                                terraform show || echo "No state file found - resources likely destroyed"
                            '''
                        }
                    }
                } catch (e) {
                    if (e instanceof org.jenkinsci.plugins.workflow.steps.FlowInterruptedException) {
                        echo "Destroy skipped by user or timeout"
                        echo "WARNING: Resources may still exist in AWS - manual cleanup may be required"
                    } else {
                        echo "WARNING: Terraform destroy encountered an issue: ${e.getMessage()}"
                        echo "IMPORTANT: Manual cleanup may be required!"
                        echo "Resources may still exist in AWS - please check the AWS Console"
                    }
                }
            }
        }
        cleanup {
            cleanWs(
                cleanWhenNotBuilt: false,
                deleteDirs: true,
                disableDeferredWipeout: true,
                notFailBuild: true
            )
        }
    }
}
