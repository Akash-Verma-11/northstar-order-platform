# Northstar Order Platform — Real-World DevOps Architecture

## Runtime
Internet → Route 53 → ALB → EKS → React/Nginx frontend → Flask API → PostgreSQL RDS.
The worker processes newly-created orders from the same database in this training implementation.

## AWS
VPC spans 3 AZs. Public subnets host load-balancer-facing resources; private subnets host EKS nodes; isolated database subnets host RDS. NAT provides controlled outbound access. ECR stores images. S3 stores build/artifact data. IAM/IRSA provides least-privilege access. CloudWatch handles AWS metrics/logs.

## Delivery
Git push → tests → SonarQube → Trivy → Docker image → ECR → GitOps repo image tag → Argo CD → EKS rolling deployment.

## Observability
Prometheus scrapes `/metrics`; Grafana dashboards visualize traffic/latency/errors/resource metrics; Alertmanager handles alerts. Filebeat/Logstash/Elasticsearch demonstrates centralized logs. CloudWatch covers AWS infrastructure.

## Environments
local: Docker Compose
dev: kind/minikube
staging: EKS
prod: EKS + RDS + ALB + Route 53

This is a training project: secrets, certificates, DNS names and Git repositories must be replaced with real values before production use.
