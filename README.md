# Northstar Order Platform — 3 -4 Years DevOps Engineer Production Lab

This is intentionally designed as a realistic operations project rather than a collection of disconnected tool demos.

## Business scenario
Northstar is a retail company. Customers place orders through a web portal. The API persists orders, a worker processes new orders, and operations teams monitor the service. The platform has dev/staging/prod environments and a GitOps production deployment model.

## Skills demonstrated
AWS: EC2, S3, VPC, IAM, EKS, RDS, Route 53, Auto Scaling, ALB, CloudWatch
CI/CD: Git, GitHub, Jenkins, GitHub Actions, GitLab CI/CD, Argo CD
Containers: Docker, Kubernetes, EKS, Helm
IaC/automation: Terraform, Ansible
DevSecOps: SonarQube, Trivy
Observability: Prometheus, Grafana, CloudWatch, ELK
Scripting/config: Python, Bash, YAML
OS: Linux

## 1. Local validation
Prerequisites: Docker Desktop, Git, Python 3.12.

`docker compose up --build`

Open http://localhost:3000.

Test:
`docker compose ps`
`curl http://localhost:3000`
`docker compose logs order-api`
`docker compose down`

Backend unit tests:
`python -m pip install -r backend/requirements.txt pytest`
`PYTHONPATH=backend pytest -q backend/tests`

## 2. Kubernetes lab
Use kind or minikube. Build the three images and load them into the cluster, then replace the placeholder image names in k8s/api.yaml, frontend.yaml and worker.yaml.

Apply:
`kubectl apply -f k8s/namespace.yaml`
`kubectl apply -f k8s/configmap.yaml`
`kubectl apply -f k8s/postgres.yaml`
`kubectl apply -f k8s/api.yaml`
`kubectl apply -f k8s/frontend.yaml`
`kubectl apply -f k8s/worker.yaml`

Troubleshoot:
`kubectl get pods -n northstar`
`kubectl get svc -n northstar`
`kubectl describe pod -n northstar <pod>`
`kubectl logs -n northstar deploy/order-api`
`kubectl get events -n northstar --sort-by=.lastTimestamp`

## 3. AWS build
Configure AWS credentials and choose ap-south-1 or another region.

`cd terraform`
`terraform init`
`terraform fmt -recursive`
`terraform validate`
`terraform plan -var-file=terraform.tfvars`
`terraform apply -var-file=terraform.tfvars`

Never commit tfvars containing secrets. For a serious production account, store Terraform state remotely in S3 with locking/versioning and protect it with IAM/KMS.

## 4. EKS operations
After cluster creation:
`aws eks update-kubeconfig --region ap-south-1 --name northstar-prod`
`kubectl get nodes`

Install AWS Load Balancer Controller using the official AWS documentation and an IAM role for service accounts. Then deploy the Helm release.

## 5. Helm
`helm lint helm/northstar`
`helm template northstar helm/northstar`
`helm upgrade --install northstar helm/northstar -n northstar --create-namespace`

## 6. Argo CD
Install Argo CD in the cluster, edit `argocd/application.yaml` with your repository, then apply it. Argo CD should become the deployment controller for staging/prod. Do not mix manual kubectl changes with GitOps in production except during an incident.

## 7. Monitoring
Install kube-prometheus-stack:
`helm repo add prometheus-community https://prometheus-community.github.io/helm-charts`
`helm upgrade --install monitoring prometheus-community/kube-prometheus-stack -n monitoring --create-namespace -f monitoring/kube-prometheus-stack-values.yaml`

Create the ServiceMonitor and PrometheusRule after confirming the Service port is named `http`.

## 8. Production troubleshooting
Use `incident-lab/README.md`. Reproduce each failure on a disposable environment. Record the timeline, customer impact, detection, evidence, mitigation, root cause, permanent fix and prevention.

## 9. Production hardening checklist
- Secrets in AWS Secrets Manager or Kubernetes External Secrets, not Git
- RDS Multi-AZ and deletion protection for production
- Remote Terraform state with locking/versioning
- KMS encryption
- Private EKS endpoint where appropriate
- IAM least privilege and IRSA
- NetworkPolicies
- PodDisruptionBudgets
- Resource requests/limits
- Image tags by Git SHA, not `latest`
- ECR lifecycle policies
- TLS certificates with ACM
- Route 53 health checks where appropriate
- ALB access logs
- CloudWatch log retention
- Prometheus alert routing
- Backup restore drills
- Disaster recovery runbook
- Change management and rollback procedure

