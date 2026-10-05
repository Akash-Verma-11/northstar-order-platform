pipeline {
  agent { label 'custom-agent' }

  environment {
    AWS_REGION     = 'ap-south-1'
    AWS_ACCOUNT_ID = credentials('aws-account-id')     // Secret text
    ECR_REGISTRY   = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    SONAR_TOKEN    = credentials('sonar-token')
    GIT_REPO_URL   = 'https://github.com/akash-verma-11/northstar-order-platform.git'
  }

  stages {

    stage('Test') {
      steps {
        sh '''
          python3 -m venv .venv
          . .venv/bin/activate
          pip install -r backend/requirements.txt pytest
          PYTHONPATH=backend pytest -q backend/tests
        '''
      }
    }

    stage('SonarQube') {
      steps {
        withSonarQubeEnv('SonarCloud') {
          sh "${tool 'SonarScanner'}/bin/sonar-scanner"
        }
      }
    }

    stage('Quality Gate Check') {
      steps {
        script {
          def taskFile = readFile('.scannerwork/report-task.txt')
          def ceTaskUrl = (taskFile =~ /ceTaskUrl=(.*)/)[0][1]

          timeout(time: 5, unit: 'MINUTES') {
            waitUntil {
              def response = sh(script: "curl -s -u ${SONAR_TOKEN}: '${ceTaskUrl}'", returnStdout: true)
              def status = (response =~ /"status":"(\w+)"/)[0][1]
              echo "SonarQube analysis status: ${status}"
              return status == 'SUCCESS'
            }
          }

          def analysisId = sh(script: "curl -s -u ${SONAR_TOKEN}: '${ceTaskUrl}' | grep -oP '\"analysisId\":\"\\K[^\"]+'", returnStdout: true).trim()
          def gateResponse = sh(script: "curl -s -u ${SONAR_TOKEN}: 'https://sonarcloud.io/api/qualitygates/project_status?analysisId=${analysisId}'", returnStdout: true)
          def gateStatus = (gateResponse =~ /"status":"(\w+)"/)[0][1]
          echo "Quality Gate status: ${gateStatus}"
          if (gateStatus != 'OK') {
            error "Quality Gate failed: ${gateStatus}"
          }
        }
      }
    }

    stage('Trivy FS Scan') {
      steps {
        sh 'trivy fs --severity HIGH,CRITICAL --exit-code 1 .'
      }
    }

    stage('Build Images') {
      steps {
        sh 'docker build -t northstar-api:$BUILD_NUMBER backend'
        sh 'docker build -t northstar-worker:$BUILD_NUMBER worker'
        sh 'docker build -t northstar-frontend:$BUILD_NUMBER frontend'
      }
    }

    stage('Trivy Image Scans') {
      steps {
        sh 'trivy image --severity HIGH,CRITICAL --exit-code 1 --ignorefile .trivyignore northstar-api:$BUILD_NUMBER'
        sh 'trivy image --severity HIGH,CRITICAL --exit-code 1 northstar-worker:$BUILD_NUMBER'
        sh 'trivy image --severity HIGH,CRITICAL --exit-code 1 northstar-frontend:$BUILD_NUMBER'
      }
    }

    stage('Push to ECR') {
      when { branch 'main' }
      steps {
        withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-creds']]) {
          sh '''
            aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY

            for svc in api worker frontend; do
              aws ecr describe-repositories --repository-names northstar/$svc --region $AWS_REGION || \
                aws ecr create-repository --repository-name northstar/$svc --region $AWS_REGION --image-scanning-configuration scanOnPush=true

              docker tag northstar-$svc:$BUILD_NUMBER $ECR_REGISTRY/northstar/$svc:$BUILD_NUMBER
              docker push $ECR_REGISTRY/northstar/$svc:$BUILD_NUMBER
            done
          '''
        }
      }
    }

    stage('GitOps — Bump Helm Values') {
      when { branch 'main' }
      steps {
        withCredentials([usernamePassword(credentialsId: 'github-creds', usernameVariable: 'GIT_USER', passwordVariable: 'GIT_PASS')]) {
          sh '''
            yq -i '.api.image = "'"$ECR_REGISTRY"'/northstar/api"' helm/northstar/values.yaml
            yq -i '.api.tag = "'"$BUILD_NUMBER"'"' helm/northstar/values.yaml
            yq -i '.worker.image = "'"$ECR_REGISTRY"'/northstar/worker"' helm/northstar/values.yaml
            yq -i '.worker.tag = "'"$BUILD_NUMBER"'"' helm/northstar/values.yaml
            yq -i '.frontend.image = "'"$ECR_REGISTRY"'/northstar/frontend"' helm/northstar/values.yaml
            yq -i '.frontend.tag = "'"$BUILD_NUMBER"'"' helm/northstar/values.yaml

            git config user.name "jenkins-bot"
            git config user.email "jenkins-bot@users.noreply.github.com"
            git add helm/northstar/values.yaml
            git commit -m "chore: bump image tags to build $BUILD_NUMBER [jenkins]" || echo "No changes to commit"
            git push https://${GIT_USER}:${GIT_PASS}@github.com/akash-verma-11/northstar-order-platform.git HEAD:main
          '''
        }
      }
    }
  }

  post {
    always {
      sh 'docker logout $ECR_REGISTRY || true'
    }
  }
}