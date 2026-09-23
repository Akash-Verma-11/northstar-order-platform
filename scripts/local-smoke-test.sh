#!/usr/bin/env bash
set -euo pipefail
curl -fsS http://localhost:3000 >/dev/null
echo "Frontend is reachable"
docker compose ps
