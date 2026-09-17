#!/usr/bin/env python3
"""Prepare a minimal private deployment bundle. Never print credential values."""

import os
import re
import shutil
import sys
from pathlib import Path

SERVICE = "crystalweb-webapp"
ROOT = Path(__file__).resolve().parents[1]


def required(name):
    value = os.environ.get(name, "")
    if not value:
        raise ValueError(f"{name} is required")
    return value


def match(name, pattern, default=None):
    value = os.environ.get(name) or default or required(name)
    if not re.fullmatch(pattern, value):
        raise ValueError(f"{name} has an invalid format")
    return value


def origin(name):
    value = match(name, r"https://[A-Za-z0-9.-]+(?::[0-9]+)?").rstrip("/")
    if ".invalid" in value or ".example" in value or "localhost" in value:
        raise ValueError(f"{name} must be the real deployment origin")
    return value


def prepare(destination):
    match("VERIFY_PUBLIC_DNS", r"true|false", "true")
    match("VPS_HOST", r"[A-Za-z0-9][A-Za-z0-9.:-]*")
    if match("VPS_USER", r"[a-z_][a-z0-9_-]*") == "root":
        raise ValueError("VPS_USER must be an unprivileged deployment account")
    match("GHCR_USER", r"[A-Za-z0-9_-]+")
    for name, default in (("VPS_PORT", "22"), ("SERVICE_PORT", "8081" if SERVICE.endswith("backend") else "3000")):
        value = int(match(name, r"[0-9]+", default))
        if not 1 <= value <= 65535:
            raise ValueError(f"{name} must be a TCP port")
    path = match("VPS_PATH", r"/[A-Za-z0-9_/-]+", f"/srv/{SERVICE}")
    if str(Path(path)) != path or len(Path(path).parts) < 3 or ".." in Path(path).parts:
        raise ValueError("VPS_PATH must be a canonical absolute service directory")
    revision = match("SOURCE_REVISION", r"[0-9a-f]{40}")
    match("DEPLOYMENT_ID", re.escape(revision) + r"-[0-9]+-[0-9]+")
    image = match("IMAGE", rf"ghcr\.io/microsaltinc/{SERVICE}@sha256:[0-9a-f]{{64}}")
    for name in ("VPS_SSH_KEY", "VPS_KNOWN_HOSTS", "GHCR_TOKEN"):
        required(name)
    values = {
        "DEPLOYMENT_ENVIRONMENT": match("DEPLOYMENT_ENVIRONMENT", r"development|production", "production"),
        "APP_ENV": "production", "LOCAL_AUTH_ENABLED": "false",
        "API_PUBLIC_URL": origin("API_PUBLIC_URL"),
        "WEBAPP_PUBLIC_URL": origin("WEBAPP_PUBLIC_URL"),
        "SOURCE_REVISION": revision,
    }
    destination.mkdir(mode=0o700, parents=True, exist_ok=True)
    destination.chmod(0o700)
    values.update({"WEB_IMAGE": image, "WEB_PORT": os.environ.get("SERVICE_PORT") or "3000"})
    (destination / "scripts").mkdir()
    shutil.copy2(ROOT / "scripts/activate-release.sh", destination / "scripts/activate-release.sh")
    shutil.copy2(ROOT / "scripts/rootless-docker.sh", destination / "scripts/rootless-docker.sh")
    for filename in ("compose.yaml", "compose.production.yaml"):
        shutil.copy2(ROOT / filename, destination / filename)
    # Values above are constrained to shell-safe/Compose-safe ASCII, never secret values.
    (destination / ".env").write_text("".join(f"{key}={value}\n" for key, value in values.items()))
    (destination / ".env").chmod(0o600)


if __name__ == "__main__":
    try:
        prepare(Path(sys.argv[1]))
    except (ValueError, IndexError) as exc:
        raise SystemExit(str(exc)) from exc
