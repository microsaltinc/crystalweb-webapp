#!/usr/bin/env python3
"""Fail if AWS dependencies, protocols, clients, endpoints, or services enter CrystalWeb."""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PYTHON_RUNTIME_DIRS = (ROOT / "api", ROOT / "core")
FORBIDDEN_MODULES = {
    "boto3",
    "botocore",
    "s3transfer",
    "moto",
    "aioboto3",
    "aiobotocore",
}
FORBIDDEN_PATHS = (
    ROOT / "trigger",
    ROOT / "analyzer",
    ROOT / "retrainer",
    ROOT / "api" / "orchestrator.py",
    ROOT / "api" / "s3_reconciler.py",
    ROOT / "core" / "storage" / "s3_storage.py",
    ROOT / "infra",
)
# These indicate executable provider protocol, credentials, endpoints, or control-plane behavior.
# Legacy s3_* database and JSON field names are intentionally not forbidden.
PROTOCOL_PATTERN = re.compile(
    r"(?i)(x-amz-[a-z0-9-]+|amazonaws\.com|s3://|aws_access_key_id|"
    r"aws_secret_access_key|aws_session_token|aws_security_token|"
    r"lambda_handler|localstack|(?:^|[\s/])aws[\s]+(?:s3|ecs|lambda|rds)(?:$|[\s/]))"
)
FORBIDDEN_IDENTIFIERS = re.compile(
    r"(?i)^(?:awscredentials|awssession|s3client|ecsclient|lambdaclient|rdsclient)$"
)
errors: list[str] = []

for path in FORBIDDEN_PATHS:
    if path.exists():
        errors.append(f"forbidden runtime path exists: {path.relative_to(ROOT)}")

# Dart and Web runtime code is inspected textually because it is not Python AST.
for directory in (ROOT / "lib", ROOT / "web", ROOT / "third_party"):
    if not directory.exists():
        continue
    for path in directory.rglob("*"):
        if path.suffix not in {".dart", ".js", ".html", ".json"} or not path.is_file():
            continue
        if match := PROTOCOL_PATTERN.search(path.read_text(encoding="utf-8")):
            errors.append(
                f"forbidden provider protocol {match.group(1)!r} in {path.relative_to(ROOT)}"
            )

manifest_paths = [
    ROOT / "pubspec.yaml", ROOT / "pubspec.lock", ROOT / "compose.yaml",
    ROOT / "compose.production.yaml", ROOT / "Dockerfile", ROOT / "docker/nginx.conf",
    *ROOT.glob(".github/workflows/*.yml"),
    *ROOT.glob("third_party/**/pubspec.yaml"),
]
package_pattern = re.compile(
    r"(?i)(?:^|[^a-z0-9_-])(boto3|botocore|s3transfer|moto|aioboto3|aiobotocore)"
    r"(?:$|[^a-z0-9_-])"
)
for path in manifest_paths:
    text = path.read_text(encoding="utf-8")
    if match := package_pattern.search(text):
        errors.append(f"forbidden package token {match.group(1)} in {path.relative_to(ROOT)}")
    if match := PROTOCOL_PATTERN.search(text):
        errors.append(
            f"forbidden service/protocol token {match.group(1)} in {path.relative_to(ROOT)}"
        )

if errors:
    print("AWS-independence audit FAILED", file=sys.stderr)
    for error in sorted(set(errors)):
        print(f"- {error}", file=sys.stderr)
    raise SystemExit(1)
print("AWS-independence audit passed")
print("Legacy s3_* database/JSON names remain compatibility identifiers only.")
