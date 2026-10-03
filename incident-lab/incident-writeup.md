Northstar Order Platform — Incident & Hardening Log

A record of production-style incidents debugged and fixes applied while building out this Kubernetes + Helm + ArgoCD + CI/CD project on a local Minikube cluster. Each entry follows: Symptom → Investigation → Root Cause → Fix → Verification.

Stack: Minikube (Docker driver, WSL2) · Kubernetes · Helm · ArgoCD · GitHub Actions · SonarQube Cloud · Trivy · GHCR.

Incident 1 — Cluster unreachable after host restart

Symptom

kubectl get nodes
The connection to the server 127.0.0.1:58594 was refused

minikube status showed apiserver: Stopped, kubeconfig: Misconfigured.

Investigation docker ps showed the minikube container was running and recently restarted. minikube status flagged a kubeconfig endpoint mismatch: kubeconfig pointed at 58594, the container was actually exposing 51066.

Root cause Docker/WSL restarted. With the Docker driver, Minikube's whole cluster runs inside one container; on restart, Docker reassigns the host-side port mapping for the API server, but kubelet/apiserver processes inside the container don't auto-restart, and the kubeconfig still points at the old port.

Fix

bash
minikube start        # restarts kubelet/apiserver inside the existing container,
                       # rewrites kubeconfig with the new port
minikube update-context  # fallback if kubectl context still stale

Verification

bash
kubectl get nodes          # Ready
kubectl get pods -A        # all core components Running
Incident 2 — Probe-kill loop (Prometheus Operator stuck at 0/1)

Symptom monitoring-kube-prometheus-operator pod Running but 0/1 Ready, 8+ restarts, repeating Liveness probe failed: context deadline exceeded.

Investigation

bash
kubectl describe pod -n monitoring -l app=kube-prometheus-stack-operator
kubectl logs -n monitoring deploy/monitoring-kube-prometheus-operator -f

describe showed three different failure signatures: connection refused (not listening yet), context deadline exceeded (too slow to answer), and connection reset by peer (died mid-request). The live log showed the operator starting cleanly, syncing caches, reconciling successfully — then receiving SIGTERM and shutting down gracefully. This was a probe kill, not a crash.

Root cause Liveness/readiness probes used Kubernetes defaults: timeoutSeconds: 1, failureThreshold: 3. On a CPU-starved node (docker stats showed the Minikube container at 277–528% of a 400% CPU budget), the operator's /healthz endpoint couldn't respond within 1 second even though the process was healthy. Kubelet killed it on every probe window.

Fix No fix applied to the monitoring chart directly (later uninstalled to free resources — see Incident 4). For all first-party services (order-api, worker, postgres), added real probe timeouts going forward:

yaml
readinessProbe: {periodSeconds: 10, timeoutSeconds: 3, failureThreshold: 3}
livenessProbe:  {periodSeconds: 15, timeoutSeconds: 5, failureThreshold: 4}
startupProbe:   {periodSeconds: 5,  failureThreshold: 30}   # absorbs slow boots

Verification Post-fix, order-api/postgres/worker pods stayed 1/1 Ready through a full minikube stop && minikube start cycle with zero probe-kill restarts.

Incident 3 — HPA feedback loop (CPU storm, 528% node CPU)

Symptom docker stats showed the Minikube container at 528% CPU (of 400% available). kubectl get hpa showed order-api HPA at REPLICAS 8 (max), with only 1/8 pods actually Ready.

Investigation

bash
docker exec minikube sudo crictl stats

Showed 7 api containers each consuming 20–31% CPU (~200–300m) — all still booting, none serving traffic. One settled api pod was at 1.8% CPU. kubectl get hpa -n northstar showed cpu: 98%/65%, MAXPODS: 8.

Root cause A feedback loop: cold start → 8 order-api pods boot simultaneously → each consumes real CPU just starting up → node CPU spikes → HPA reads this as demand → holds at maxReplicas: 8 → more competition for CPU → readiness probes fail → pods restart → loop continues. The HPA's CPU request baseline (100m) was also too low relative to actual startup cost (~250m), skewing the percentage calculation.

Fix

yaml
autoscaling:
  minReplicas: 2
  maxReplicas: 3              # bounded to what the node can actually carry
  targetCPUUtilizationPercentage: 80

Added behavior.scaleUp to prevent instant jumps to max:

yaml
behavior:
  scaleUp:
    stabilizationWindowSeconds: 120
    policies: [{type: Pods, value: 1, periodSeconds: 60}]
  scaleDown:
    stabilizationWindowSeconds: 300

Raised the API's CPU request from 100m to 200m to match observed startup cost.

Verification

bash
minikube stop && minikube start
kubectl get pods -n northstar -w

Full stop/start cycle completed with flat restart counts, no climbing, node CPU settled under 70% within minutes instead of taking the better part of an hour.

Incident 4 — Duplicate deployment paths (Helm release vs. manual kubectl apply)

Symptom kubectl get all -A showed two parallel sets of resources in northstar: order-api/frontend (from manual kubectl apply -f k8s/) alongside northstar-northstar-api/northstar-northstar-frontend (Helm-fullname-pattern names). HPA showed the old unbounded config (maxReplicas: 8) despite the chart having been edited. helm uninstall northstar -n northstar failed with release: not found.

Investigation

bash
helm list -A

revealed the release was registered in namespace default, not northstar — helm install northstar ./helm/northstar had been run without -n northstar, so Helm defaulted to the then-current kubectl context namespace for its own bookkeeping, while the chart's templates (which hardcode namespace: northstar in some files) still created resources in northstar. Two sources of truth were live in the same namespace simultaneously.

Root cause A Helm release's registered namespace (where its metadata lives) and the namespace its resources actually land in can diverge if -n isn't passed explicitly at install time. Combined with pre-existing manual manifests in the same namespace, this produced duplicate Services/Deployments with mismatched label selectors (app: frontend vs app: northstar-frontend), silently breaking Service routing.

Fix

bash
helm uninstall northstar -n default     # correct namespace, from `helm list -A`
kubectl delete namespace argocd         # also found installed but unconfigured —
                                         # no Application resources, pure overhead

Going forward, helm install/upgrade always pinned explicitly with -n northstar.

Verification

bash
kubectl get deploy -n northstar

Showed only the intended single set of resources, no northstar-northstar-* duplicates.

Incident 5 — GHCR push failing: uppercase repository name

Symptom

Error parsing reference: "ghcr.io/Akash-Verma-11/northstar-api:<sha>" is not a
valid repository/tag: invalid reference format: repository name must be lowercase

Investigation Traced to the Tag and push images step using ${{ github.repository_owner }} directly in the image reference — this resolves to the GitHub username/org exactly as cased (Akash-Verma-11).

Root cause OCI/Docker registry paths require all-lowercase repository names. GitHub usernames and org names may contain mixed case. github.repository_owner does not normalize this.

Fix

yaml
- name: Set lowercase repo owner
  run: echo "REPO_OWNER=$(echo '${{ github.repository_owner }}' | tr '[:upper:]' '[:lower:]')" >> $GITHUB_ENV

All subsequent ghcr.io/... references switched from ${{ github.repository_owner }} to ${{ env.REPO_OWNER }}.

Verification Tag and push images and Update Helm values with new image tags steps both passed on the next run; images visible in GHCR under ghcr.io/akash-verma-11/....

Incident 6 — Silently non-blocking quality gate

Symptom No incident per se — caught during review. The SonarQube step in CI had:

yaml
continue-on-error: true

meaning the job stayed green even if the Sonar scan failed outright or a quality gate failed, with no separate gate-check step enforcing anything.

Root cause continue-on-error: true applied to a security/quality step converts an intended gate into a cosmetic report — failures are swallowed silently.

Fix Removed continue-on-error. Added an explicit gate-check step matching the pattern already used for the Trivy steps (exit-code: "1"):

yaml
- name: SonarQube Quality Gate
  uses: SonarSource/sonarqube-quality-gate-action@v1
  timeout-minutes: 5
  env: {SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}}

Verification Pipeline run showed SonarQube Quality Gate as its own job step, explicitly ✓ Quality Gate has PASSED, and the step is now capable of failing the job.

Incident 7 — Base image CVEs (54 → 47 → triaged to zero actionable)

Symptom Trivy image scan: Total: 54 (HIGH: 54, CRITICAL: 0), all in Debian OS packages, zero in Python application dependencies.

Investigation

bash
trivy image northstar-api:test --severity CRITICAL,HIGH

Status column distinguished fixed (patch available upstream) from affected/ fix_deferred (no patch exists yet). Base image was already python:3.12-slim.

Root cause apt-get install without a following upgrade pins whatever package versions were current in the base image layer at build time — patches released after that layer was cached are never picked up.

Fix

dockerfile
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends postgresql-client && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

Rebuilt with --no-cache to force a fresh layer. Result: 54 → 47 HIGH (the 7 fixed-status CVEs — openssl, libssl3t64, libpcre2-8-0 — resolved). Remaining 47 are all affected/fix_deferred (no upstream patch exists) in util-linux/perl/systemd packages not exercised by the application (non-root container, no privileged mode, no mount/systemd-homed usage). Documented and suppressed via .trivyignore with justification per CVE rather than lowering the severity threshold.

Verification

bash
trivy image northstar-api:test --severity CRITICAL,HIGH --ignorefile .trivyignore

Clean pass; same .trivyignore committed so CI enforces the same baseline.

Incident 8 — HPA regression after GitOps migration

Symptom Weeks after Incident 3's fix, kubectl get hpa -n northstar showed MAXPODS: 8 again on northstar-northstar-api.

Root cause The earlier fix had been applied to k8s/api.yaml (manual manifests). Once ArgoCD took over deployment from the Helm chart (helm/northstar/templates/), the chart's own hpa.yaml — never updated — silently reintroduced the original unbounded config. Same root issue as Incident 4: more than one manifest source for the same resource, drifting independently.

Fix Re-applied the Incident 3 fix directly to helm/northstar/templates/hpa.yaml and helm/northstar/values.yaml (the files ArgoCD actually syncs from), this time verifying with helm template before pushing:

bash
helm template northstar ./helm/northstar | grep -A5 "kind: HorizontalPodAutoscaler"

Verification

bash
kubectl get hpa -n northstar -w

MAXPODS confirmed at 3 after ArgoCD sync, holding since.

Incident 9 — Plaintext DB password in Git despite existing Secret

Symptom A Kubernetes Secret (order-db-secret) existed and was correctly referenced via secretKeyRef in postgres.yaml — but api.yaml/worker.yaml built DATABASE_URL by interpolating {{ .Values.postgres.password }} directly, rendering the plaintext password into the Deployment manifest itself (kubectl get deploy -o yaml showed postgresql://app:app@postgres:5432/orders in full).

Root cause Having a Secret object exist doesn't automatically mean every consumer uses it — api/worker templates were still reading the raw value from values.yaml, which was itself committed to Git with the real password in plain text.

Fix

yaml
env:
- {name: DB_PASSWORD, valueFrom: {secretKeyRef: {name: order-db-secret, key: password}}}
- {name: DATABASE_URL, value: "postgresql+psycopg://$(DB_USER):$(DB_PASSWORD)@postgres:5432/$(DB_NAME)"}

Removed postgres.password from values.yaml entirely and the Secret block from the chart's postgres.yaml. Created the Secret once, out-of-band:

bash
kubectl create secret generic order-db-secret -n northstar \
  --from-literal=password='...' --dry-run=client -o yaml | kubectl apply -f -
kubectl annotate secret order-db-secret -n northstar \
  argocd.argoproj.io/sync-options=Prune=false

The Prune=false annotation stops ArgoCD from deleting a resource it no longer defines in Git — without it, auto-sync with pruning enabled would delete the Secret on the next reconcile since Git no longer declares it.

Verification

bash
grep -ri "password" helm/northstar/**/*.yaml   # no literal value anywhere
kubectl logs -n northstar deploy/northstar-northstar-api --tail=10

Logs confirmed successful DB connection (Database is ready) using the Secret-sourced credential; kubectl get secret order-db-secret showed it survived the Git-side removal with Prune=false in place.

Incident 10 — NetworkPolicy deployed but silently unenforced

Symptom After adding a NetworkPolicy restricting Postgres ingress to order-api/ worker pods only, a curl from frontend to postgres:5432 still showed Established connection — the policy had no observable effect.

Investigation

bash
kubectl get pods -n kube-system -l app=kindnet

Confirmed the cluster's CNI is kindnet, Minikube's default for the Docker driver.

Root cause kindnet does not implement NetworkPolicy enforcement. The policy object applies to the API server without error and is fully valid — but nothing actually reads or enforces it at the network layer on this CNI.

Fix None applicable locally — this is a platform constraint, not a config error. Policy was committed and deployed via the Helm chart/ArgoCD regardless, since the manifest is correct and will enforce properly on a policy-capable CNI (Calico, Cilium, or AWS VPC CNI on EKS).

Verification

bash
kubectl get networkpolicy -n northstar   # object exists, tracked by ArgoCD

Enforcement validation deferred to the EKS migration phase, where the VPC CNI (or Calico overlay) will actually block the frontend → postgres path this policy targets.

Summary table
#	Incident	Category	Status
1	Stale kubeconfig after restart	Cluster/networking	Resolved
2	Probe-kill loop (1s timeout defaults)	Health checks	Resolved
3	HPA feedback loop (CPU storm)	Autoscaling	Resolved
4	Duplicate Helm release / manual manifests	GitOps hygiene	Resolved
5	GHCR uppercase repo name	CI/CD	Resolved
6	Non-blocking quality gate	CI/CD	Resolved
7	Base image CVEs	Security	Triaged & documented
8	HPA regression post-GitOps-migration	Autoscaling / GitOps hygiene	Resolved
9	Plaintext DB password in Git	Security	Resolved
10	NetworkPolicy unenforced on local CNI	Security / platform limitation	Documented, deferred to EKS

Recurring theme across 1, 2, 3, 8: every one of these traced back to either default timeouts/thresholds not being revisited for actual node capacity, or more than one manifest source for the same Kubernetes resource drifting independently. The fix pattern was consistent — identify the single source of truth, fix it there, verify via the actual sync/deploy path (not just the file on disk).


Incident 11 — Memory ceiling masked by inconsistent reporting tools

Symptom During a monitoring stack reinstall, kubectl top nodes consistently reported ~54% memory usage while docker stats on the same Minikube container showed 89–91%. Pod-level kubectl top pods summed to roughly 1.4GB across both monitoring and northstar namespaces — nowhere near either percentage, despite the node staying visibly under pressure (flat high memory, rising cumulative Block I/O, Grafana stuck in CreateContainerConfigError then later timing out on its startup probe).

Investigation Compared the two reporting tools directly against the Minikube container's actual cgroup limit:

bash
kubectl top nodes
docker stats --no-stream minikube
kubectl top pods -n monitoring --sort-by=memory
kubectl top pods -n northstar --sort-by=memory

Root cause kubectl top nodes calculates its percentage against the memory capacity the Node object reports to the scheduler, which on Minikube's Docker driver can reflect the host/WSL VM's visible memory rather than the container's actual cgroup cap. docker stats enforces and reports against the real limit. The ~2.3–2.9GB gap between the sum of workload pods (kubectl top pods) and the real ceiling (docker stats) was the Kubernetes control plane itself (etcd, apiserver, controller-manager, scheduler, kubelet, containerd) plus ArgoCD's six pods plus ingress-nginx — none of which per-namespace kubectl top pods queries surface, since they live in kube-system/argocd.

Fix Standardized on docker stats as the authoritative memory signal for this cluster going forward, since it was the only one of the three that stayed consistent with observed symptoms (slow boots, probe timeouts) throughout. Trimmed Prometheus retention (15d → 6h, retentionSize: 500MB) and disabled the Grafana dashboard-provisioning sidecar (sidecar.dashboards.enabled: false, not in use yet) to reduce real memory draw. When trimming alone wasn't sufficient, rebuilt the cluster with a larger ceiling:

bash
minikube delete
minikube start --driver=docker --cpus=4 --memory=5120

Verification Post-rebuild, docker stats showed memory settling at 79% with ~1GB of real headroom, versus 91% with ~350MB headroom pre-rebuild — a stable, repeatable improvement rather than a transient reading.

Incident 12 — Grafana startup probe killed a healthy-but-slow boot

Symptom Grafana pod stuck 0/2 through multiple reinstall attempts, event log showing:

Warning  Unhealthy  (x25 over 5m1s)  Startup probe failed: connection refused
Normal   Killing                     Container grafana failed startup probe, will be restarted

The container never once responded on port 3000 during its startupProbe window before being killed — a different failure signature from every other probe-kill incident in this project (Incident 2), where the process was healthy but slow to respond. Here it was healthy but hadn't started listening at all yet.

Investigation

bash
kubectl logs -n monitoring <grafana-pod> -c grafana

The log showed no errors — clean progression through config load, SQLite migrations, encryption setup — but a revealing pace: 4 seconds between "Loading plugins..." and the first plugin registering, then ~15 seconds for that single plugin alone. Grafana's distroless image bundles a large set of built-in plugins registered sequentially at startup.

Root cause At that pace, full plugin registration for all bundled plugins would exceed the configured startupProbe window (failureThreshold: 30 × periodSeconds: 5 = 150s, later 30 × 10s = 300s). This was compounded by the whole stack cold-booting simultaneously (confirmed by a 4x jump in cumulative Block I/O during the same window) — disk contention slowed an already disk-bound plugin-loading phase. Kubelet killed a process that was working correctly, just more slowly than the probe allowed for.

Fix Raised startupProbe.failureThreshold to 60 at periodSeconds: 10 (10 minutes total tolerance), and restored Grafana's memory limit from an over-aggressive trim (256Mi → 384Mi) since the node now had real headroom to spend on a faster boot rather than starving it further:

yaml
grafana:
  startupProbe:
    httpGet: {path: /api/health, port: 3000}
    failureThreshold: 60
    periodSeconds: 10
  resources:
    limits: {cpu: 300m, memory: 384Mi}

Verification Next reinstall reached 2/2 Running, Ready: True within the extended window, 0 restarts after settling. Confirmed Grafana was genuinely using the Secret-based admin credentials (Incident 9's pattern) rather than a stale chart-generated Secret:

bash
kubectl get secret grafana-admin-secret -n monitoring
Known limitation — three control-plane ServiceMonitor targets unreachable

Symptom Prometheus /targets shows kube-controller-manager, kube-etcd, and kube-scheduler as down, each with connect: connection refused against 192.168.49.2 on their respective ports.

Root cause These control-plane components bind to 127.0.0.1 by default in Minikube's static pod configuration, not the node's externally-reachable IP that the default kube-prometheus-stack ServiceMonitors target. This is a Minikube packaging characteristic, not a configuration error in this project.

Decision Not fixed. Editing Minikube's static pod manifests to change bind addresses is fragile and non-portable, and on EKS these are AWS-managed control-plane components not scraped directly in the same way. Documented as a known, accepted gap rather than chased — order-api, the actual application, scrapes successfully (2/2 up), which is the metric that matters for this project.