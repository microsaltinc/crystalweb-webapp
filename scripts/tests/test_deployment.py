"""Validate deploy bundles without connecting to GitHub or a VPS."""

import importlib.util
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("prepare_deploy", ROOT / "scripts/prepare-deploy.py")
deploy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deploy)


class DeploymentBundleTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.destination = Path(self.temporary.name) / "bundle"
        self.values = {
            "VPS_HOST": "192.0.2.10", "VPS_USER": "deploy", "GHCR_USER": "microsaltinc",
            "VPS_SSH_KEY": "test-only-ssh-key", "VPS_KNOWN_HOSTS": "test-only-known-host",
            "GHCR_TOKEN": "test-only-registry-token", "SOURCE_REVISION": "a" * 40,
            "DEPLOYMENT_ID": "a" * 40 + "-1-1",
            "IMAGE": f"ghcr.io/microsaltinc/{deploy.SERVICE}@sha256:" + "b" * 64,
            "API_PUBLIC_URL": "https://api.microsalt.in",
            "WEBAPP_PUBLIC_URL": "https://crystals.microsalt.in",
            "DB_PASSWORD": "test-database-password-only",
            "APP_SECRET_KEY": "test-application-signing-key-only-123456",
        }

    def test_bundle_has_no_source_tree_and_no_inline_runtime_secrets(self):
        with patch.dict(os.environ, self.values, clear=True):
            deploy.prepare(self.destination)
        config = (self.destination / ".env").read_text()
        self.assertIn("LOCAL_AUTH_ENABLED=false", config)
        self.assertIn("APP_ENV=production", config)
        self.assertNotIn(self.values["DB_PASSWORD"], config)
        self.assertNotIn(self.values["APP_SECRET_KEY"], config)
        for name in ("api", "core", "lib", ".git", "tests", ".venv"):
            self.assertFalse((self.destination / name).exists())
        self.assertEqual(self.destination.stat().st_mode & 0o777, 0o700)
        self.assertTrue((self.destination / "scripts/rootless-docker.sh").is_file())
        if deploy.SERVICE.endswith("backend"):
            self.assertEqual((self.destination / ".secrets/db_password").stat().st_mode & 0o777, 0o600)
            self.assertTrue((self.destination / "scripts/backup.sh").is_file())
        else:
            self.assertFalse((self.destination / ".secrets").exists())

    def test_hosted_development_preserves_production_security_settings(self):
        with patch.dict(os.environ, self.values | {"DEPLOYMENT_ENVIRONMENT": "development"}, clear=True):
            deploy.prepare(self.destination)
        config = (self.destination / ".env").read_text()
        self.assertIn("DEPLOYMENT_ENVIRONMENT=development", config)
        self.assertIn("APP_ENV=production", config)
        self.assertIn("LOCAL_AUTH_ENABLED=false", config)
        if deploy.SERVICE.endswith("backend"):
            self.assertIn("ENVIRONMENT=production", config)
            self.assertIn("DB_SSLMODE=verify-full", config)

    def test_ssh_transfer_preserves_container_readable_files_and_private_secrets(self):
        import subprocess

        binaries = Path(self.temporary.name) / "bin"
        binaries.mkdir()
        ssh = binaries / "ssh"
        ssh.write_text(
            '#!/usr/bin/env python3\n'
            'import subprocess, sys\n'
            'command = sys.argv[-1]\n'
            'if "activate-release.sh" in command:\n'
            '    sys.stdin.buffer.read()  # Do not activate services in this transport test.\n'
            'else:\n'
            '    sys.exit(subprocess.run(["bash", "-c", command], stdin=sys.stdin).returncode)\n'
        )
        ssh.chmod(0o755)
        curl = binaries / "curl"
        curl.write_text("#!/bin/sh\nexit 0\n")
        curl.chmod(0o755)
        service_root = Path(self.temporary.name) / "service"
        env = os.environ | self.values | {
            "VPS_PATH": str(service_root),
            "PATH": f"{binaries}:{os.environ['PATH']}",
        }
        result = subprocess.run(
            ["bash", str(ROOT / "scripts/deploy-vps.sh")],
            env=env, capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        release = service_root / "releases" / self.values["DEPLOYMENT_ID"]
        self.assertEqual(release.stat().st_mode & 0o777, 0o700)
        self.assertEqual((release / ".env").stat().st_mode & 0o777, 0o600)
        self.assertEqual((release / "scripts/rootless-docker.sh").stat().st_mode & 0o777, 0o755)
        if deploy.SERVICE.endswith("backend"):
            self.assertEqual((release / "docker/nginx.conf").stat().st_mode & 0o777, 0o644)
            self.assertEqual((release / "scripts/runtime_manifest.py").stat().st_mode & 0o444, 0o444)
            self.assertEqual((release / ".secrets").stat().st_mode & 0o777, 0o700)
            self.assertEqual((release / ".secrets/db_password").stat().st_mode & 0o777, 0o600)

    def test_rejects_shell_injection_and_invalid_public_configuration(self):
        for name, value in (
            ("VERIFY_PUBLIC_DNS", "yes"),
            ("DEPLOYMENT_ENVIRONMENT", "local"),
            ("VPS_PATH", "/srv/app;touch /tmp/injected"),
            ("VPS_PATH", "/"),
            ("VPS_HOST", "host;command"),
            ("VPS_USER", "root$(id)"),
            ("VPS_USER", "root"),
            ("SOURCE_REVISION", "main"),
            ("DEPLOYMENT_ID", "main"),
            ("IMAGE", f"ghcr.io/microsaltinc/{deploy.SERVICE}:latest"),
            ("VPS_PORT", "0"),
            ("SERVICE_PORT", "99999"),
            ("API_PUBLIC_URL", "http://api.microsalt.in"),
            ("WEBAPP_PUBLIC_URL", "https://crystals.microsalt.in?token=secret"),
        ):
            with self.subTest(name=name, value=value), patch.dict(os.environ, self.values | {name: value}, clear=True):
                with self.assertRaises(ValueError):
                    deploy.prepare(self.destination)

    def test_compose_does_not_require_sibling_repository(self):
        compose = (ROOT / "compose.yaml").read_text()
        self.assertNotIn("../", compose)
        self.assertNotIn("external: true", compose)
        if deploy.SERVICE.endswith("webapp"):
            self.assertNotIn("depends_on", compose)
            self.assertNotIn("proxy_pass", (ROOT / "docker/nginx.conf").read_text())


if __name__ == "__main__":
    unittest.main()
