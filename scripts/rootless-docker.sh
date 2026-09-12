#!/bin/sh
# Source before production Docker commands, including with a temporary DOCKER_CONFIG.
crystalweb_require_rootless_docker() {
  deployment_uid=$(id -u)
  if [ "$deployment_uid" = 0 ]; then
    echo "Production deployment must run as an unprivileged service account" >&2
    return 1
  fi
  case " $(id -nG) " in
    *" docker "*)
      echo "Remove the deployment account from the privileged docker group" >&2
      return 1
      ;;
  esac
  # Temporary registry credentials must not lose the user's rootless context or
  # fall back to the host daemon. Each service account has its own fixed socket.
  unset DOCKER_CONTEXT DOCKER_TLS_VERIFY DOCKER_CERT_PATH
  DOCKER_HOST="unix:///run/user/$deployment_uid/docker.sock"
  export DOCKER_HOST
  security_options=$(docker info --format '{{json .SecurityOptions}}') || {
    echo "Cannot connect to the service account rootless Docker daemon" >&2
    return 1
  }
  printf '%s\n' "$security_options" | python3 -c '
import json
import sys
try:
    options = json.load(sys.stdin)
except (ValueError, OSError):
    raise SystemExit("Cannot verify the service account rootless Docker daemon") from None
if not isinstance(options, list) or "name=rootless" not in options:
    raise SystemExit("Production requires rootless Docker; refusing a privileged daemon")
'
}
