#!/usr/bin/env python3
"""Resolve a hosted deployment target without reading or exporting credentials."""

import os
import re
import subprocess
from pathlib import Path

RELEASE_REF = re.compile(r"refs/tags/v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)")
PLACEHOLDER_API = "https://api.example.invalid"


def configuration(environ):
    if environ.get("GITHUB_EVENT_NAME") not in {"push", "workflow_dispatch"}:
        raise ValueError("Only push or manual runs may configure a deployment")
    ref = environ.get("GITHUB_REF", "")
    if ref == "refs/heads/main":
        target = "development"
    elif RELEASE_REF.fullmatch(ref):
        target = "production"
    else:
        raise ValueError("Deploy main to development or a vMAJOR.MINOR.PATCH tag to production")
    enabled = environ.get("DEPLOY_ENABLED") or "false"
    if enabled not in {"true", "false"}:
        raise ValueError("DEPLOY_ENABLED must be true or false")
    for name in ("API_PUBLIC_URL", "WEBAPP_PUBLIC_URL"):
        origin = environ.get(name, "")
        if origin and not re.fullmatch(r"https://[A-Za-z0-9.-]+(?::[0-9]+)?", origin):
            raise ValueError(f"{name} must be an HTTPS origin without a path")
        if enabled == "true" and (
            not origin or any(part in origin for part in (".invalid", ".example", "localhost"))
        ):
            raise ValueError(f"Set the real {name} in the {target} environment before enabling deployment")
    platforms = environ.get("DOCKER_PLATFORMS") or "linux/amd64"
    if any(platform not in {"linux/amd64", "linux/arm64"} for platform in platforms.split(",")):
        raise ValueError("DOCKER_PLATFORMS supports linux/amd64 and linux/arm64")
    return {
        "environment": target,
        "deploy_enabled": enabled,
        "api_public_url": environ.get("API_PUBLIC_URL") or PLACEHOLDER_API,
        "docker_platforms": platforms,
    }


def verify_release_commit():
    result = subprocess.run(
        ["git", "merge-base", "--is-ancestor", "HEAD", "refs/remotes/origin/main"],
        check=False, capture_output=True,
    )
    if result.returncode != 0:
        raise ValueError("The production tag must point to a commit on origin/main")


def main():
    values = configuration(os.environ)
    if values["environment"] == "production":
        verify_release_commit()
    # Only validated nonsecret build configuration crosses between jobs.
    with Path(os.environ["GITHUB_OUTPUT"]).open("a") as output:
        for name, value in values.items():
            output.write(f"{name}={value}\n")


if __name__ == "__main__":
    try:
        main()
    except ValueError as exc:
        raise SystemExit(str(exc)) from exc
