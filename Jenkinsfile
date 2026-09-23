pipeline {
  agent any
  stages {
    stage('Checkout') { steps { checkout scm } }
    stage('Test') { steps { sh 'python3 -m pip install -r backend/requirements.txt pytest && PYTHONPATH=backend pytest -q backend/tests' } }
    stage('SonarQube') { steps { echo 'Run SonarQube scanner configured by Jenkins global tools' } }
    stage('Build') { steps {
      sh 'docker build -t northstar-api:$BUILD_NUMBER backend'
      sh 'docker build -t northstar-worker:$BUILD_NUMBER worker'
      sh 'docker build -t northstar-frontend:$BUILD_NUMBER frontend'
    }}
    stage('Trivy') { steps { sh 'trivy image --severity HIGH,CRITICAL --exit-code 1 northstar-api:$BUILD_NUMBER' } }
    stage('Push ECR') { when { branch 'main' } steps { echo 'Authenticate to ECR using AWS credentials and push immutable image tags' } }
    stage('GitOps') { when { branch 'main' } steps { echo 'Update image tag in the GitOps repository; Argo CD syncs EKS' } }
  }
}
