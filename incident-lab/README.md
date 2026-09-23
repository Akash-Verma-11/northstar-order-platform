# Production Troubleshooting Lab

Do not memorize these incidents. Reproduce them, observe the symptoms, form a hypothesis, prove it, fix it, and document prevention.

## Incident 1 — CrashLoopBackOff
Symptom: API pods restart continuously.
Inject:
`kubectl -n northstar set env deployment/order-api DATABASE_URL=postgresql://bad:bad@postgres:5432/orders`
Commands:
`kubectl -n northstar get pods`
`kubectl -n northstar describe pod <pod>`
`kubectl -n northstar logs <pod> --previous`
`kubectl -n northstar get events --sort-by=.lastTimestamp`
Recovery:
`kubectl -n northstar rollout undo deployment/order-api`

## Incident 2 — 502 / unhealthy targets
Break the service targetPort or readiness path. Observe:
`kubectl -n northstar get endpoints`
`kubectl -n northstar describe ingress northstar`
`kubectl -n northstar logs deployment/order-api`
Then restore the Service/Deployment and verify ALB target health.

## Incident 3 — Database connection failure
Scale the API while blocking database connectivity with a NetworkPolicy in a lab namespace. Compare:
`kubectl -n northstar get pods`
`kubectl -n northstar get endpoints`
`kubectl -n northstar exec deploy/order-api -- python -c "..."`
Then remove the policy and verify readiness returns.

## Incident 4 — High CPU
Generate traffic with a load tool such as `hey` or `ab`. Watch:
`kubectl top pods -n northstar`
`kubectl get hpa -n northstar -w`
`rate(container_cpu_usage_seconds_total[5m])`
Explain why HPA needs resource requests and metrics-server.

## Incident 5 — Bad release / rollback
Deploy a deliberately invalid image tag:
`kubectl -n northstar set image deployment/order-api api=ghcr.io/example/northstar-api:does-not-exist`
Observe `ImagePullBackOff`, inspect events, then:
`kubectl -n northstar rollout undo deployment/order-api`
Finally perform the same workflow through Argo CD and inspect sync/health history.

## Incident 6 — Disk / inode pressure on Linux
On a disposable EC2 lab host:
`df -h`
`df -i`
`du -xhd1 /var | sort -h`
`journalctl --disk-usage`
Clean only after identifying the consumer. Verify the alert clears.

## Incident 7 — AWS cost spike
Use AWS Cost Explorer and CloudWatch to identify an intentionally oversized node group. Compare utilization, desired/min/max capacity, and monthly estimate. Document the change before applying it.

## Incident 8 — DNS / TLS
Trace:
`dig orders.example.com`
`nslookup orders.example.com`
Check Route 53 record, ALB listener, target health, certificate status and security groups. Do not guess; move layer by layer.

## Interview structure
For every incident answer:
1. Customer impact
2. Detection/alert
3. First 3 commands
4. Hypothesis
5. Evidence
6. Immediate mitigation
7. Permanent fix
8. Monitoring/alert added
9. Deployment/change-control lesson
