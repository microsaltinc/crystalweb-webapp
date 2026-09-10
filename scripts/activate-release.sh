#!/usr/bin/env bash
# Runs on the VPS under its deployment account; stdin is an ephemeral GHCR token.
set -euo pipefail
SERVICE=crystalweb-webapp
release=$(cd "$(dirname "$0")/.." && pwd)
root=${1:?service root required}
registry_user=${2:?registry user required}
cd "$release"
set -a
# shellcheck disable=SC1091
source .env
set +a
exec 9> "$root/.deploy.lock"
flock -w 900 9
registry_config=$(mktemp -d)
export DOCKER_CONFIG="$registry_config"
cleanup() { rm -rf "$registry_config" "$release/.secrets"; }
trap cleanup EXIT
docker login ghcr.io --username "$registry_user" --password-stdin > /dev/null
compose=(docker compose --project-name "$SERVICE" --env-file "$release/.env"
  -f "$release/compose.yaml" -f "$release/compose.production.yaml")

"${compose[@]}" config --quiet
"${compose[@]}" pull
observed_origin=$(docker image inspect --format '{{index .Config.Labels "org.crystalweb.api-url"}}' "$WEB_IMAGE")
[[ "$observed_origin" == "$API_PUBLIC_URL" ]] || { echo "Web image API origin mismatch" >&2; exit 1; }
"${compose[@]}" up --detach --wait --wait-timeout 120 webapp
curl --fail --silent --show-error "http://127.0.0.1:${WEB_PORT}/healthz" > /dev/null
if [[ -L "$root/current" ]]; then
  readlink "$root/current" > "$root/previous-release"
fi
ln -sfn "$release" "$root/current.next"
mv -Tf "$root/current.next" "$root/current"
printf '%s\n' "$SERVICE is healthy; previous release retained for manual rollback."
