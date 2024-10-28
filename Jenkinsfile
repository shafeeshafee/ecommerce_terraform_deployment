pipeline {
    agent any
    
    environment {
        // Define environment variables
        PYTHON_VENV = 'wl5_venv'
        TERRAFORM_DIR = 'Terraform'
        BACKEND_DIR = 'backend'
        FRONTEND_DIR = 'frontend'
    }

    stages {
        stage('Build') {
            steps {
                sh '''#!/bin/bash
                    # Install Python dependencies
                    python3.9 -m venv ${PYTHON_VENV}
                    source ${PYTHON_VENV}/bin/activate
                    pip install -r backend/requirements.txt
                    
                    # Install Node.js and build frontend
                    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
                    sudo apt install -y nodejs
                    
                    cd frontend
                    npm install
                    npm run build
                    cd ..
                '''
            }
        }

        stage('Test') {
            steps {
                sh '''#!/bin/bash
                    # Activate virtual environment
                    source ${PYTHON_VENV}/bin/activate
                    
                    # Install test dependencies
                    pip install pytest-django
                    
                    # Run migrations
                    cd backend
                    python manage.py makemigrations account
                    python manage.py makemigrations payments
                    python manage.py makemigrations product
                    python manage.py migrate
                    
                    # Run tests
                    pytest account/tests.py --verbose --junit-xml ../test-reports/results.xml
                    cd ..
                '''
            }
            post {
                always {
                    junit '**/test-reports/results.xml'
                }
            }
        }

        stage('Init') {
            steps {
                dir('Terraform') {
                    sh 'terraform init'
                }
            }
        }

        stage('Plan') {
            steps {
                withCredentials([
                    string(credentialsId: 'AWS_ACCESS_KEY', variable: 'aws_access_key'),
                    string(credentialsId: 'AWS_SECRET_KEY', variable: 'aws_secret_key'),
                    string(credentialsId: 'DB_PASSWORD', variable: 'db_password')
                ]) {
                    dir('Terraform') {
                        sh '''
                            terraform plan -out plan.tfplan \
                            -var="aws_access_key=${aws_access_key}" \
                            -var="aws_secret_key=${aws_secret_key}" \
                            -var="db_password=${db_password}"
                        '''
                    }
                }
            }
        }

        stage('Apply') {
            steps {
                dir('Terraform') {
                    sh 'terraform apply plan.tfplan'
                }
            }
        }

        stage('Configure Database') {
            steps {
                withCredentials([
                    string(credentialsId: 'DB_PASSWORD', variable: 'db_password')
                ]) {
                    sh '''#!/bin/bash
                        # Wait for backend instances to be ready
                        sleep 180
                        
                        # Get RDS endpoint from Terraform output
                        cd Terraform
                        RDS_ENDPOINT=$(terraform output -raw rds_endpoint)
                        cd ..
                        
                        # Activate virtual environment
                        source ${PYTHON_VENV}/bin/activate
                        cd backend
                        
                        # Dump data from SQLite to JSON
                        python manage.py dumpdata --database=sqlite --natural-foreign --natural-primary -e contenttypes -e auth.Permission --indent 4 > datadump.json
                        
                        # Configure database settings
                        sed -i 's/DATABASES = {/DATABASES = {\\"default\\": {\\"ENGINE\\": \\"django.db.backends.postgresql\\",\\"NAME\\": \\"ecommercedb\\",\\"USER\\": \\"kurac5user\\",\\"PASSWORD\\": \\"'$db_password'\\",\\"HOST\\": \\"'$RDS_ENDPOINT'\\",\\"PORT\\": \\"5432\\"},/g' my_project/settings.py
                        
                        # Run migrations and load data
                        python manage.py makemigrations account
                        python manage.py makemigrations payments
                        python manage.py makemigrations product
                        python manage.py migrate
                        python manage.py loaddata datadump.json
                    '''
                }
            }
        }
    }

    post {
        always {
            cleanWs()
        }
        failure {
            sh '''
                cd Terraform
                terraform destroy -auto-approve \
                -var="aws_access_key=${aws_access_key}" \
                -var="aws_secret_key=${aws_secret_key}" \
                -var="db_password=${db_password}"
            '''
        }
    }
}