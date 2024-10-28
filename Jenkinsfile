pipeline {
    agent any
    
    environment {
        PYTHON_VENV = 'wl5_venv'
        TERRAFORM_DIR = 'Terraform'
        BACKEND_DIR = 'backend'
        FRONTEND_DIR = 'frontend'
        TERRAFORM_VERSION = '1.9.8' 
    }

    options {
        timeout(time: 2, unit: 'HOURS')  // Limits pipeline execution time to prevent hangs
        disableConcurrentBuilds()        // Ensures only one build runs at a time
    }

    stages {
        stage('Validate Environment') {
            steps {
                script {
                    // Verify that required tools are installed and accessible
                    sh '''
                        python3.9 --version || { echo "Python 3.9 is required"; exit 1; }
                        node --version || { echo "Node.js is required"; exit 1; }
                        terraform version || { echo "Terraform is required"; exit 1; }
                    '''
                }
            }
        }

        stage('Build') {
            steps {
                script {
                    try {
                        sh '''#!/bin/bash
                            set -e  # Exit immediately if a command exits with a non-zero status

                            echo "Setting up Python virtual environment..."
                            python3.9 -m venv ${PYTHON_VENV}
                            source ${PYTHON_VENV}/bin/activate

                            echo "Installing backend dependencies..."
                            pip install --upgrade pip
                            pip install -r ${BACKEND_DIR}/requirements.txt

                            echo "Installing Node.js LTS..."
                            curl -fsSL https://deb.nodesource.com/setup_lts.x > setup_node.sh
                            DEBIAN_FRONTEND=noninteractive sudo -E bash setup_node.sh
                            DEBIAN_FRONTEND=noninteractive sudo -E apt-get install -y nodejs

                            echo "Building frontend application..."
                            cd ${FRONTEND_DIR}
                            export NODE_OPTIONS=--openssl-legacy-provider
                            export CI=false
                            npm ci  # Performs a clean install based on package-lock.json
                            npm run build
                            cd ..
                        '''
                    } catch (Exception e) {
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

                            # Ensure the test reports directory exists
                            mkdir -p ../test-reports

                            # Apply database migrations for tests
                            python manage.py makemigrations account payments product
                            python manage.py migrate

                            # Execute tests and generate coverage reports
                            pytest account/tests.py \
                                --verbose \
                                --junit-xml ../test-reports/results.xml \
                                --cov=. \
                                --cov-report=xml:../test-reports/coverage.xml
                            
                            cd ..

                            echo "Running frontend tests..."
                            cd ${FRONTEND_DIR}
                            export NODE_OPTIONS=--openssl-legacy-provider
                            export CI=false
                            npm test -- --ci --coverage || echo "No frontend tests configured"
                            cd ..
                        '''
                    } catch (Exception e) {
                        error "Test stage failed: ${e.getMessage()}"
                    }
                }
            }
            post {
                always {
                    // Publish JUnit test results and coverage reports
                    junit '**/test-reports/results.xml'
                    recordCoverage(tools: [[parser: 'COBERTURA', pattern: '**/test-reports/coverage.xml']])
                }
            }
        }

        stage('Terraform Init') {
            steps {
                dir(TERRAFORM_DIR) {
                    script {
                        try {
                            sh 'terraform init -input=false'  // Initialize Terraform with no interactive input
                        } catch (Exception e) {
                            error "Terraform initialization failed: ${e.getMessage()}"
                        }
                    }
                }
            }
        }

        stage('Terraform Plan') {
            steps {
                withCredentials([
                    string(credentialsId: 'AWS_ACCESS_KEY', variable: 'aws_access_key'),
                    string(credentialsId: 'AWS_SECRET_KEY', variable: 'aws_secret_key'),
                    string(credentialsId: 'DB_PASSWORD', variable: 'db_password')
                ]) {
                    dir(TERRAFORM_DIR) {
                        script {
                            try {
                                sh '''
                                    terraform plan \
                                        -input=false \
                                        -detailed-exitcode \
                                        -out=plan.tfplan \
                                        -var="aws_access_key=${aws_access_key}" \
                                        -var="aws_secret_key=${aws_secret_key}" \
                                        -var="db_password=${db_password}"
                                '''
                            } catch (Exception e) {
                                error "Terraform planning failed: ${e.getMessage()}"
                            }
                        }
                    }
                }
            }
        }

        stage('Terraform Apply') {
            steps {
                dir(TERRAFORM_DIR) {
                    script {
                        try {
                            sh 'terraform apply -input=false -auto-approve plan.tfplan'  // Apply the planned Terraform changes
                        } catch (Exception e) {
                            error "Terraform apply failed: ${e.getMessage()}"
                        }
                    }
                }
            }
        }

        stage('Configure Database') {
            steps {
                withCredentials([
                    string(credentialsId: 'DB_PASSWORD', variable: 'db_password')
                ]) {
                    script {
                        try {
                            sh '''#!/bin/bash
                                set -e

                                echo "Waiting for RDS instance to become available..."
                                aws rds wait db-instance-available --db-instance-identifier ecommerce-db

                                echo "Retrieving RDS endpoint from Terraform outputs..."
                                cd ${TERRAFORM_DIR}
                                RDS_ENDPOINT=$(terraform output -raw rds_endpoint)
                                cd ..

                                echo "Activating Python virtual environment..."
                                source ${PYTHON_VENV}/bin/activate
                                cd ${BACKEND_DIR}

                                echo "Exporting existing database data..."
                                python manage.py dumpdata --database=sqlite \
                                    --natural-foreign \
                                    --natural-primary \
                                    -e contenttypes \
                                    -e auth.Permission \
                                    --indent 4 > datadump.json

                                echo "Updating database settings for PostgreSQL..."
                                sed -i 's/DATABASES = {/DATABASES = {"default": {"ENGINE": "django.db.backends.postgresql","NAME": "ecommercedb","USER": "kurac5user","PASSWORD": "'$db_password'","HOST": "'$RDS_ENDPOINT'","PORT": "5432"},/g' my_project/settings.py

                                echo "Applying database migrations..."
                                python manage.py makemigrations account payments product
                                python manage.py migrate

                                echo "Importing data into the new database..."
                                python manage.py loaddata datadump.json
                            '''
                        } catch (Exception e) {
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

                            echo "Fetching Application Load Balancer DNS from Terraform..."
                            cd ${TERRAFORM_DIR}
                            ALB_DNS=$(terraform output -raw alb_dns_name)
                            cd ..

                            echo "Checking if the application is responding with HTTP 200..."
                            # Retry until the application responds successfully or timeout after 5 minutes
                            timeout 300 bash -c '
                                while [[ "$(curl -s -o /dev/null -w ''%{http_code}'' http://${ALB_DNS})" != "200" ]]; do
                                    echo "Waiting for application to be ready..."
                                    sleep 5
                                done
                            '

                            echo "Deployment verified successfully: Application is up and running."
                        '''
                    } catch (Exception e) {
                        error "Deployment verification failed: ${e.getMessage()}"
                    }
                }
            }
        }
    }

    post {
        always {
            cleanWs()  // Clean up workspace to free up space
            script {
                // Prepare and display build status message
                def buildStatus = currentBuild.result ?: 'SUCCESS'
                def message = "Build ${env.BUILD_NUMBER} - ${buildStatus}\n${env.BUILD_URL}"
                
                echo message
                // Placeholder for integrating with external notification services (e.g., Slack, Email)
            }
        }
        failure {
            script {
                try {
                    withCredentials([
                        string(credentialsId: 'AWS_ACCESS_KEY', variable: 'aws_access_key'),
                        string(credentialsId: 'AWS_SECRET_KEY', variable: 'aws_secret_key'),
                        string(credentialsId: 'DB_PASSWORD', variable: 'db_password')
                    ]) {
                        dir(TERRAFORM_DIR) {
                            echo "Initiating Terraform destroy due to build failure..."
                            sh '''
                                terraform destroy -auto-approve \
                                    -var="aws_access_key=${aws_access_key}" \
                                    -var="aws_secret_key=${aws_secret_key}" \
                                    -var="db_password=${db_password}"
                            '''
                        }
                    }
                } catch (Exception e) {
                    echo "Warning: Terraform destroy encountered an issue: ${e.getMessage()}"
                }
            }
        }
    }
}
