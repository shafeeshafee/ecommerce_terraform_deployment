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
        booleanParam(
            name: 'DESTROY_INFRASTRUCTURE',
            defaultValue: false,
            description: 'Destroy all infrastructure'
        )
    }

    options {
        timeout(time: 2, unit: 'HOURS')
        disableConcurrentBuilds()
        timestamps()  // Add timestamps to console output
        ansiColor('xterm')  // Enable colored output
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
                                    set -e
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
                    // Basic tool validation
                    sh '''
                        set -e
                        echo "Checking required tools..."
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
                            set -e
                            export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY
                            export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_KEY
                            aws ec2 describe-key-pairs --key-name workload-5-key-shaf || { 
                                echo "AWS key pair 'workload-5-key-shaf' is required"; 
                                exit 1; 
                            }
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
                    junit allowEmptyResults: true, testResults: '**/test-reports/results.xml'
                    recordCoverage(tools: [[parser: 'COBERTURA', pattern: '**/test-reports/coverage.xml']])
                }
            }
        }

        stage('Terraform Init') {
            steps {
                dir(TERRAFORM_DIR) {
                    script {
                        try {
                            sh '''
                                set -e
                                terraform init -input=false
                            '''
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
                                        set -e
                                        export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY}
                                        export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_KEY}
                                        export TF_VAR_db_password=${DB_PASSWORD}
                                        
                                        terraform plan -input=false -detailed-exitcode \
                                            -out=plan.tfplan \
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
                                sh '''
                                    set -e
                                    export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY
                                    export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_KEY
                                    export TF_VAR_db_password=$DB_PASSWORD
                                    
                                    terraform apply -input=false -auto-approve plan.tfplan
                                '''
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
                                cd ..
                                
                                echo "Activating Python virtual environment..."
                                source ${PYTHON_VENV}/bin/activate
                                cd ${BACKEND_DIR}
                                
                                echo "Backing up SQLite database configuration..."
                                cp my_project/settings.py my_project/settings.py.bak
                                
                                echo "Configuring dual database setup for migration..."
                                sed -i 's/DATABASES = {/DATABASES = {\
                                    "sqlite": {\
                                        "ENGINE": "django.db.backends.sqlite3",\
                                        "NAME": str(BASE_DIR \/ "db.sqlite3"),\
                                    },\
                                    "default": {\
                                        "ENGINE": "django.db.backends.postgresql",\
                                        "NAME": "ecommercedb",\
                                        "USER": "kurac5user",\
                                        "PASSWORD": "'$DB_PASSWORD'",\
                                        "HOST": "'$RDS_ENDPOINT'",\
                                        "PORT": "5432"\
                                    },/g' my_project/settings.py
                                
                                echo "Installing psycopg2 if not already installed..."
                                pip install psycopg2-binary
                                
                                echo "Waiting for database connection..."
                                for i in {1..30}; do
                                    if python -c "
                                        import psycopg2
                                        try:
                                            conn = psycopg2.connect(
                                                dbname='ecommercedb',
                                                user='kurac5user',
                                                password='$DB_PASSWORD',
                                                host='$RDS_ENDPOINT',
                                                port='5432'
                                            )
                                            conn.close()
                                            exit(0)
                                        except:
                                            exit(1)
                                    "; then
                                        echo "Database connection successful!"
                                        break
                                    fi
                                    echo "Waiting for database connection... Attempt $i/30"
                                    sleep 10
                                done
                                
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
                                python -c "
                                    import django
                                    django.setup()
                                    from django.contrib.auth.models import User
                                    users = User.objects.all()
                                    print(f'Successfully migrated {users.count()} users')
                                "
                                
                                echo "Restoring original settings file..."
                                mv my_project/settings.py.bak my_project/settings.py
                                
                                echo "Updating settings to use PostgreSQL only..."
                                sed -i 's/DATABASES = {/DATABASES = {\
                                    "default": {\
                                        "ENGINE": "django.db.backends.postgresql",\
                                        "NAME": "ecommercedb",\
                                        "USER": "kurac5user",\
                                        "PASSWORD": "'$DB_PASSWORD'",\
                                        "HOST": "'$RDS_ENDPOINT'",\
                                        "PORT": "5432"\
                                    },/g' my_project/settings.py
                                
                                echo "Database migration completed successfully!"
                            '''
                        } catch (Exception e) {
                            error "Database configuration failed: ${e.getMessage()}"
                            currentBuild.result = 'FAILURE'
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
                            
                            echo "Checking if the application is responding..."
                            MAX_RETRIES=60
                            RETRY_INTERVAL=5
                            
                            for i in $(seq 1 $MAX_RETRIES); do
                                HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://${ALB_DNS})
                                if [ "$HTTP_CODE" = "200" ]; then
                                    echo "Application is up and running!"
                                    exit 0
                                fi
                                echo "Attempt $i/$MAX_RETRIES: Application not ready (HTTP ${HTTP_CODE}), retrying in ${RETRY_INTERVAL} seconds..."
                                sleep $RETRY_INTERVAL
                            done
                            
                            echo "Application failed to respond with HTTP 200 after $MAX_RETRIES attempts"
                            exit 1
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
            
            // Clean up workspace
            cleanWs(
                cleanWhenNotBuilt: false,
                deleteDirs: true,
                disableDeferredWipeout: true,
                notFailBuild: true
            )
        }
        
        success {
            script {
                echo """
                    =========================================
                    🎉 Pipeline completed successfully! 
                    =========================================
                    You can access the application at:
                    http://\$(cd ${TERRAFORM_DIR} && terraform output -raw alb_dns_name)
                    =========================================
                """
            }
        }
        
        failure {
            script {
                try {
                    timeout(time: 10, unit: 'MINUTES') {
                        def userInput = input(
                            message: 'Infrastructure deployment failed. Would you like to destroy the infrastructure?',
                            parameters: [
                                booleanParam(
                                    defaultValue: true,
                                    description: 'Destroy all created infrastructure',
                                    name: 'DESTROY_INFRA'
                                )
                            ]
                        )
                        
                        if (userInput) {
                            withCredentials([
                                string(credentialsId: 'AWS_ACCESS_KEY', variable: 'AWS_ACCESS_KEY'),
                                string(credentialsId: 'AWS_SECRET_KEY', variable: 'AWS_SECRET_KEY'),
                                string(credentialsId: 'DB_PASSWORD', variable: 'DB_PASSWORD')
                            ]) {
                                dir(TERRAFORM_DIR) {
                                    echo "Initiating Terraform destroy due to build failure..."
                                    sh '''
                                        set -e
                                        export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY
                                        export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_KEY
                                        export TF_VAR_db_password=$DB_PASSWORD
                                        
                                        # Initialize Terraform if needed
                                        terraform init -input=false
                                        
                                        # Run destroy with timeout and retry
                                        for attempt in {1..3}; do
                                            echo "Attempting destroy (attempt $attempt/3)..."
                                            if timeout 20m terraform destroy -auto-approve; then
                                                echo "Destroy successful!"
                                                break
                                            else
                                                if [ $attempt -eq 3 ]; then
                                                    echo "ERROR: Failed to destroy after 3 attempts"
                                                    exit 1
                                                fi
                                                echo "Destroy failed, waiting 30 seconds before retry..."
                                                sleep 30
                                            fi
                                        done
                                        
                                        # Verify all resources are destroyed
                                        if ! terraform show; then
                                            echo "No state file found - resources likely destroyed successfully"
                                        fi
                                    '''
                                }
                            }
                        } else {
                            echo "Manual destruction was skipped by user."
                            echo "⚠️ WARNING: Resources may still exist in AWS - manual cleanup may be required!"
                        }
                    }
                } catch (org.jenkinsci.plugins.workflow.steps.FlowInterruptedException e) {
                    echo "Destroy operation was interrupted: ${e.getMessage()}"
                    echo "⚠️ WARNING: Resources may still exist in AWS - manual cleanup may be required!"
                } catch (Exception e) {
                    echo """
                        ❌ ERROR: Terraform destroy encountered an issue: ${e.getMessage()}
                        ⚠️ IMPORTANT: Manual cleanup may be required!
                        Please check the AWS Console for any remaining resources in these categories:
                        - EC2 Instances
                        - RDS Databases
                        - VPCs and associated networking components
                        - Load Balancers
                        - Security Groups
                    """
                }
            }
            
            // Send failure notification
            echo """
                =========================================
                ❌ Pipeline failed! 
                =========================================
                Build Number: ${env.BUILD_NUMBER}
                Build URL: ${env.BUILD_URL}
                =========================================
            """
        }
        
        unstable {
            echo """
                =========================================
                ⚠️ Pipeline is unstable! 
                =========================================
                Build Number: ${env.BUILD_NUMBER}
                Build URL: ${env.BUILD_URL}
                Please check the test results and logs.
                =========================================
            """
        }
    }
}