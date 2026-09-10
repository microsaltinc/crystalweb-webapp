#!/usr/bin/env bash
# Runs on a GitHub runner. All secret transport is over authenticated SSH stdin.
# shellcheck disable=SC2029 # Validated operands intentionally expand before SSH.
set -euo pipefail
: "${VPS_HOST:?VPS_HOST is required}"
cd "$(dirname "$0")/.."
SERVICE=crystalweb-webapp
VPS_PATH=${VPS_PATH:-/srv/$SERVICE}
VPS_PORT=${VPS_PORT:-22}
export VPS_PATH VPS_PORT
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
chmod 700 "$temporary"
python3 scripts/prepare-deploy.py "$temporary/bundle"
printf '%s\n' "$VPS_SSH_KEY" > "$temporary/key"
printf '%s\n' "$VPS_KNOWN_HOSTS" > "$temporary/known_hosts"
chmod 600 "$temporary/key" "$temporary/known_hosts"
ssh_options=(-i "$temporary/key" -p "$VPS_PORT" -o BatchMode=yes -o IdentitiesOnly=yes
  -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$temporary/known_hosts")
destination="$VPS_USER@$VPS_HOST"
release="$VPS_PATH/releases/$DEPLOYMENT_ID"
# Paths, user, host, revision and registry username were validated before interpolation.
tar -C "$temporary/bundle" -czf "$temporary/bundle.tar.gz" .
ssh "${ssh_options[@]}" "$destination" \
  "set -eu; umask 077; mkdir -p '$VPS_PATH/releases'; mkdir '$release'; chmod 700 '$VPS_PATH' '$release'; tar -xzf - -C '$release'" \
  < "$temporary/bundle.tar.gz"
printf '%s' "$GHCR_TOKEN" | ssh "${ssh_options[@]}" "$destination" \
  "bash '$release/scripts/activate-release.sh' '$VPS_PATH' '$GHCR_USER'"
curl --fail --silent --show-error --retry 5 --retry-delay 3 \
  "${WEBAPP_PUBLIC_URL}/healthz" > /dev/null
printf '%s\n' "$SERVICE deployed at revision $SOURCE_REVISION"
