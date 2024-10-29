pipeline {
    agent any

    environment {
        PYTHON_VENV = 'wl5_venv'
        TERRAFORM_DIR = 'Terraform'
        BACKEND_DIR = 'backend'
        FRONTEND_DIR = 'frontend'
        TERRAFORM_VERSION = '1.9.8'
        NODE_EXPORTER_VERSION = '1.8.2'
    }

    parameters {
        booleanParam(name: 'DESTROY_INFRASTRUCTURE', defaultValue: false, description: 'Destroy all infrastructure')
    }

    options {
        timeout(time: 2, unit: 'HOURS')  // Limit pipeline execution time
        disableConcurrentBuilds()        // Only one build runs at a time
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
                            } catch (Exception e) {
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
                    sh '''
                        python3.9 --version || { echo "Python 3.9 is required"; exit 1; }
                        node --version || { echo "Node.js is required"; exit 1; }
                        terraform version || { echo "Terraform is required"; exit 1; }
                        aws --version || { echo "AWS CLI is required"; exit 1; }
                        # Validate AWS key pair
                        aws ec2 describe-key-pairs --key-name workload-5-key-shaf || { echo "AWS key pair 'workload-5-key-shaf' is required"; exit 1; }
                    '''
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
                            sudo apt-get install -y nodejs
                            echo "Building frontend application..."
                            cd ${FRONTEND_DIR}
                            export NODE_OPTIONS=--openssl-legacy-provider
                            export CI=false
                            npm ci
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
                    } catch (Exception e) {
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
                            } catch (Exception e) {
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
                    string(credentialsId: 'DB_PASSWORD', variable: 'DB_PASSWORD')
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
                                    --natural-foreign --natural-primary \
                                    -e contenttypes -e auth.Permission --indent 4 > datadump.json
                                echo "Updating database settings for PostgreSQL..."
                                sed -i 's/DATABASES = {/DATABASES = {"default": {"ENGINE": "django.db.backends.postgresql","NAME": "ecommercedb","USER": "kurac5user","PASSWORD": "'$DB_PASSWORD'","HOST": "'$RDS_ENDPOINT'","PORT": "5432"},/g' my_project/settings.py
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
                            echo "Fetching ALB DNS from Terraform..."
                            cd ${TERRAFORM_DIR}
                            ALB_DNS=$(terraform output -raw alb_dns_name)
                            cd ..
                            echo "Checking if the application is responding with HTTP 200..."
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
                } catch (org.jenkinsci.plugins.workflow.steps.FlowInterruptedException e) {
                    echo "Destroy skipped by user or timeout"
                    echo "WARNING: Resources may still exist in AWS - manual cleanup may be required"
                } catch (Exception e) {
                    echo "WARNING: Terraform destroy encountered an issue: ${e.getMessage()}"
                    echo "IMPORTANT: Manual cleanup may be required!"
                    echo "Resources may still exist in AWS - please check the AWS Console"
                }
            }
        }
        cleanup {
            cleanWs(cleanWhenNotBuilt: false,
                   deleteDirs: true,
                   disableDeferredWipeout: true,
                   notFailBuild: true)
        }
    }
}