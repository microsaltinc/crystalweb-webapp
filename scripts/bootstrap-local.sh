#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if [ ! -f .env ]; then cp .env.example .env; fi
python3 scripts/audit-no-aws.py
docker compose config --quiet
docker compose up --build --detach --wait --wait-timeout 600
printf '%s\n' "Webapp ready on http://localhost:${WEB_PORT:-3000}; API is configured separately."
