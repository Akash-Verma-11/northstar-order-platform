pipeline {
  agent { label 'custom-agent' }

  environment {
    REPO_OWNER   = 'akash-verma-11'
    SONAR_TOKEN  = credentials('sonar-token')
  }

  stages {
    stage('Checkout') {
      steps { checkout scm }
    }

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
        sh 'which trivy || (curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin)'
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

    stage('Push to GHCR') {
      when { branch 'main' }
      steps {
        withCredentials([usernamePassword(credentialsId: 'ghcr-token', usernameVariable: 'GHCR_USER', passwordVariable: 'GHCR_PASS')]) {
          sh 'echo $GHCR_PASS | docker login ghcr.io -u $GHCR_USER --password-stdin'
          sh '''
            for svc in api worker frontend; do
              docker tag northstar-$svc:$BUILD_NUMBER ghcr.io/${REPO_OWNER}/northstar-$svc:$BUILD_NUMBER
              docker push ghcr.io/${REPO_OWNER}/northstar-$svc:$BUILD_NUMBER
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
            which yq || (sudo curl -sL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/local/bin/yq && sudo chmod +x /usr/local/bin/yq)

            yq -i '.api.tag = "'"$BUILD_NUMBER"'"' helm/northstar/values.yaml
            yq -i '.worker.tag = "'"$BUILD_NUMBER"'"' helm/northstar/values.yaml
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
      sh 'docker logout ghcr.io || true'
    }
  }
}