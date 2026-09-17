#!/usr/bin/env python3
"""Verify the deployed host over HTTPS, then check public routing after cutover."""

import ipaddress
import os
import re
import subprocess
import sys
from urllib.parse import urlsplit


def verify(url, environ):
    public = environ.get("VERIFY_PUBLIC_DNS") or "true"
    if public not in {"true", "false"}:
        raise ValueError("VERIFY_PUBLIC_DNS must be true or false")
    host = environ.get("VPS_HOST", "")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.:-]*", host):
        raise ValueError("VPS_HOST must be a hostname or IP address")
    if ":" in host:
        host = f"[{ipaddress.IPv6Address(host)}]"
    origin = urlsplit(url)
    if (origin.scheme != "https" or not origin.hostname or origin.username
            or origin.password or origin.query or origin.fragment
            or not re.fullmatch(r"[A-Za-z0-9.-]+", origin.hostname)):
        raise ValueError("Health check requires an HTTPS URL without credentials or query parameters")
    port = origin.port or 443
    command = [
        "curl", "--fail", "--silent", "--show-error", "--retry", "5",
        "--retry-delay", "3", "--connect-timeout", "10", "--max-time", "30",
        "--noproxy", "*", "--proto", "=https",
    ]
    # Preserve the original Host header, TLS SNI and certificate validation while
    # connecting to the exact VPS that received this release, before DNS cutover.
    subprocess.run(command + [
        "--connect-to", f"{origin.hostname}:{port}:{host}:{port}", url,
    ], check=True, stdout=subprocess.DEVNULL)
    print("Deployed VPS HTTPS readiness verified.")
    if public == "true":
        subprocess.run(command + [url], check=True, stdout=subprocess.DEVNULL)
        print("Public DNS HTTPS readiness verified.")
    else:
        print("Public DNS check deferred; enable VERIFY_PUBLIC_DNS after DNS cutover.")


if __name__ == "__main__":
    try:
        verify(sys.argv[1], os.environ)
    except (ValueError, IndexError) as exc:
        raise SystemExit(str(exc)) from exc
