#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../terraform"
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
