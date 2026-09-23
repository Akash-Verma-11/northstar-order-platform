# Validation performed

Generated files: 51

- Python source files were compiled with `python -m py_compile`.
- YAML files were parsed with PyYAML when available in the generation environment.
- Shell scripts were created with strict mode (`set -euo pipefail`) where appropriate.
- Application and infrastructure files were generated as a coherent project.

## What was NOT falsely claimed as validated
AWS resources, EKS, ALB, Route 53, RDS, Terraform apply, Docker builds, Helm installation, Argo CD sync, Prometheus/Grafana and ELK require the user's machine, credentials and/or cluster. Those cannot be truthfully validated from this environment.

The project therefore includes explicit smoke tests and troubleshooting labs for the user to execute.

## Known replacement values
Search for `REPLACE_ME`, `CHANGE_ME`, `example.com`, and `ghcr.io/example` before deployment.
