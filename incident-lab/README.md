Northstar Order Platform

A cloud-native order processing platform built to demonstrate production-style Kubernetes, GitOps, and CI/CD practices — deployed locally on Minikube with an architecture designed to port directly to AWS EKS.

📄 Incident & Hardening Log — 12+ documented incidents debugged during this build, from cluster recovery and autoscaling feedback loops to secret hygiene, CVE triage, and observability setup. Written in symptom → investigation → root cause → fix → verification format.

🧪 Production Troubleshooting Lab — a separate set of reproducible failure scenarios (CrashLoopBackOff, 502s, DB connectivity, HPA under load, bad releases, disk pressure, cost spikes, DNS/TLS) for practicing the diagnostic workflow itself, independent of this project's own incident history. See the full scenario list at the bottom of this README.

Architecture
                        ┌─────────────┐
                        │   GitHub     │
                        │  (source)    │
                        └──────┬───────┘
                               │ push
                        ┌──────▼───────────────────────────┐
                        │        GitHub Actions CI          │
                        │  tests → SonarQube → Quality Gate │
                        │  → Trivy (fs) → build → Trivy     │
                        │  (image) → push to GHCR →         │
                        │  bump Helm values → commit         │
                        └──────┬───────────────────────────┘
                               │ commit (Helm values updated)
                        ┌──────▼───────┐
                        │    ArgoCD     │  ← auto-sync, GitOps
                        └──────┬───────┘
                               │ apply
                ┌──────────────▼──────────────┐
                │         Kubernetes            │
                │  frontend · order-api (HPA)   │
                │  order-worker · postgres       │
                │  NetworkPolicy · Secrets       │
                └──────────────┬─────────────────┘
                               │ scraped by
                        ┌──────▼───────────────┐
                        │  Prometheus + Grafana  │
                        │  + Alertmanager         │
                        └────────────────────────┘

Flow: push to main → CI tests, scans, and gates the code → builds and scans container images → pushes to GHCR → bumps image tags in the Helm chart and commits back to Git → ArgoCD detects the change and syncs it to the cluster automatically → Prometheus continuously scrapes order-api and cluster health, visualized in Grafana. No manual deploy step, no manual observability setup after initial install.

Stack
Layer	Tooling
Orchestration	Kubernetes (Minikube locally, EKS-targeted)
Packaging	Helm
GitOps / CD	ArgoCD
CI	GitHub Actions
Static analysis	SonarQube Cloud (enforced Quality Gate)
Vulnerability scanning	Trivy (filesystem + per-image)
Registry	GitHub Container Registry (GHCR)
Observability	Prometheus, Grafana, Alertmanager (kube-prometheus-stack)
App services	Flask API (order-api), background worker, static frontend
Database	PostgreSQL (in-cluster, PVC-backed)
Autoscaling	HorizontalPodAutoscaler (CPU-based, bounded)
IaC (next phase)	Terraform (VPC, EKS, RDS, ECR — scaffolded in /terraform)
Services
order-api — Flask REST API, Gunicorn, /api/health and /api/ready endpoints, Prometheus metrics exposed on /metrics, scraped via a ServiceMonitor.
order-worker — background job processor, consumes from the same Postgres instance.
frontend — static asset server, exposed via ingress-nginx.
postgres — single-instance Postgres 17-alpine, PVC-backed, credentials sourced from a Kubernetes Secret (never committed to Git).
CI/CD pipeline

Every push to main and every PR runs:

Backend tests — pytest
SonarQube scan + Quality Gate — static analysis, enforced (not just reported — the gate actually fails the build)
Trivy filesystem scan — fails on CRITICAL/HIGH
Image builds — API, worker, frontend
Trivy image scans — per service, same enforced threshold, CVEs triaged and tracked via .trivyignore with justification
Push to GHCR
Helm values.yaml auto-bump — pipeline commits the new image tags back to main, which ArgoCD then syncs
Observability

Prometheus + Grafana + Alertmanager run via kube-prometheus-stack, installed separately from the application's Helm release (infra tooling, not synced through ArgoCD).

order-api is scraped directly via a ServiceMonitor (monitoring/servicemonitor.yaml) — confirmed live in Prometheus's own /targets page (2/2 up).
Alert rules (monitoring/prometheus-rules.yaml) cover API downtime and elevated pod restart rate.
Grafana is provisioned with a non-default admin credential sourced from a Kubernetes Secret, and every component (Prometheus, Grafana, the operator, kube-state-metrics, node-exporter, Alertmanager) has explicit resource requests/limits — no BestEffort pods in the monitoring stack, after earlier rounds showed exactly what happens when they are.
Known gap: three Minikube control-plane ServiceMonitor targets (kube-controller-manager, kube-etcd, kube-scheduler) show down — a Minikube bind-address characteristic, not a project bug. Documented in the incident log rather than worked around.
bash
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
Key engineering decisions
HPA is explicitly bounded (maxReplicas: 3, scaleUp stabilization window) after an observed feedback loop where cold-start CPU was misread as traffic demand. See Incident 3 — and re-fixed a second time after the Helm chart silently drifted from this fix post-GitOps migration (Incident 8).
Every service has a tuned startupProbe, including Postgres — the single dependency every other service waits on — after cascading probe-kill restarts traced to default 1-second timeouts (Incident 2). A second, distinct probe-kill mode showed up later in Grafana, where a healthy process simply took longer to finish booting than the probe window allowed (Incident 12) — same symptom, different root cause.
No secret values are committed to Git. Kubernetes Secrets (database credentials, Grafana admin password) are created out-of-band and referenced via secretKeyRef; argocd.argoproj.io/sync-options=Prune=false prevents GitOps reconciliation from deleting what it doesn't manage (Incident 9).
NetworkPolicy restricts database access to order-api/order-worker only. Deployed and tracked via GitOps now; enforcement is a CNI-level capability Minikube's default kindnet doesn't provide, validated properly once this ships to EKS (Incident 10).
Single source of truth per resource. Early on, a duplicate Helm release and manual kubectl apply manifests coexisted in the same namespace, causing silent config drift (including an HPA fix being "undone" by an unsynced chart). Resolved by consolidating on the Helm chart as the only deployment path, synced exclusively through ArgoCD.
Memory pressure was measured with the wrong tool for a while. kubectl top nodes and docker stats disagreed on the cluster's real memory usage by ~40 points; traced to how each calculates its percentage against the node's reported vs. actual cgroup capacity, and standardized on the one that matched observed symptoms (Incident 11).
Local setup
bash
minikube start --driver=docker --cpus=4 --memory=5120

kubectl create namespace northstar
kubectl create secret generic order-db-secret -n northstar \
  --from-literal=password='<your-password>' \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl annotate secret order-db-secret -n northstar \
  argocd.argoproj.io/sync-options=Prune=false

helm install northstar ./helm/northstar -n northstar --create-namespace
kubectl get pods -n northstar -w

kubectl create namespace monitoring
kubectl create secret generic grafana-admin-secret -n monitoring \
  --from-literal=admin-user=admin \
  --from-literal=admin-password='<your-password>' \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl annotate secret grafana-admin-secret -n monitoring \
  argocd.argoproj.io/sync-options=Prune=false

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring -f monitoring/kube-prometheus-stack-values.yaml
kubectl apply -f monitoring/servicemonitor.yaml
kubectl apply -f monitoring/prometheus-rules.yaml
kubectl get pods -n monitoring -w
Roadmap
 Local Kubernetes deployment (Minikube)
 Helm chart packaging
 GitOps deployment via ArgoCD
 CI/CD with enforced quality and security gates
 Production hardening pass (autoscaling, probes, secrets, network policy)
 Observability — Prometheus, Grafana, Alertmanager, verified end-to-end
 Terraform-provisioned AWS EKS (scaffolded, not yet applied)
 RDS for Postgres (replacing in-cluster database)
 AWS Load Balancer Controller + ALB ingress
 External Secrets Operator + AWS Secrets Manager
Production Troubleshooting Lab (practice scenarios)

A separate exercise set for practicing the diagnostic workflow itself — these are reproducible scenarios to break and fix on purpose, distinct from the project's own incident history above. Full detail also lives in incident-lab/README.md.

Do not memorize these incidents. Reproduce them, observe the symptoms, form a hypothesis, prove it, fix it, and document prevention.

Incident 1 — CrashLoopBackOff Symptom: API pods restart continuously. Inject: kubectl -n northstar set env deployment/order-api DATABASE_URL=postgresql://bad:bad@postgres:5432/orders Commands: kubectl -n northstar get pods · kubectl -n northstar describe pod <pod> · kubectl -n northstar logs <pod> --previous · kubectl -n northstar get events --sort-by=.lastTimestamp Recovery: kubectl -n northstar rollout undo deployment/order-api

Incident 2 — 502 / unhealthy targets Break the service targetPort or readiness path. Observe: kubectl -n northstar get endpoints · kubectl -n northstar describe ingress northstar · kubectl -n northstar logs deployment/order-api Then restore the Service/Deployment and verify ALB target health.

Incident 3 — Database connection failure Scale the API while blocking database connectivity with a NetworkPolicy in a lab namespace. Compare: kubectl -n northstar get pods · kubectl -n northstar get endpoints · kubectl -n northstar exec deploy/order-api -- python -c "..." Then remove the policy and verify readiness returns.

Incident 4 — High CPU Generate traffic with a load tool such as hey or ab. Watch: kubectl top pods -n northstar · kubectl get hpa -n northstar -w · rate(container_cpu_usage_seconds_total[5m]) Explain why HPA needs resource requests and metrics-server.

Incident 5 — Bad release / rollback Deploy a deliberately invalid image tag: kubectl -n northstar set image deployment/order-api api=ghcr.io/example/northstar-api:does-not-exist Observe ImagePullBackOff, inspect events, then: kubectl -n northstar rollout undo deployment/order-api Finally perform the same workflow through Argo CD and inspect sync/health history.

Incident 6 — Disk / inode pressure on Linux On a disposable EC2 lab host: df -h · df -i · du -xhd1 /var | sort -h · journalctl --disk-usage Clean only after identifying the consumer. Verify the alert clears.

Incident 7 — AWS cost spike Use AWS Cost Explorer and CloudWatch to identify an intentionally oversized node group. Compare utilization, desired/min/max capacity, and monthly estimate. Document the change before applying it.

Incident 8 — DNS / TLS Trace: dig orders.example.com · nslookup orders.example.com Check Route 53 record, ALB listener, target health, certificate status and security groups. Do not guess; move layer by layer.

Interview structure — for every incident above, answer:

Customer impact
Detection/alert
First 3 commands
Hypothesis
Evidence
Immediate mitigation
Permanent fix
Monitoring/alert added
Deployment/change-control lesson