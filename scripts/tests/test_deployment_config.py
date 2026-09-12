"""Exercise release routing and reject unsafe cross-environment configuration."""

import importlib.util
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("deployment_config", ROOT / "scripts/deployment-config.py")
config = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(config)


class DeploymentConfigurationTests(unittest.TestCase):
    def test_main_uses_development_and_defaults_to_no_deployment(self):
        for event in ("push", "workflow_dispatch"):
            values = config.configuration({"GITHUB_EVENT_NAME": event, "GITHUB_REF": "refs/heads/main"})
            self.assertEqual(values["environment"], "development")
            self.assertEqual(values["deploy_enabled"], "false")

    def test_release_tags_use_production(self):
        for event in ("push", "workflow_dispatch"):
            values = config.configuration({"GITHUB_EVENT_NAME": event, "GITHUB_REF": "refs/tags/v1.2.3"})
            self.assertEqual(values["environment"], "production")

    def test_pull_requests_feature_branches_and_invalid_tags_cannot_deploy(self):
        for event, ref in (
            ("pull_request", "refs/heads/main"),
            ("workflow_dispatch", "refs/heads/feature"),
            ("push", "refs/tags/v1.2"),
            ("push", "refs/tags/v1.2.3-rc1"),
            ("push", "refs/tags/v01.2.3"),
            ("push", "refs/tags/production"),
        ):
            with self.subTest(event=event, ref=ref), self.assertRaises(ValueError):
                config.configuration({"GITHUB_EVENT_NAME": event, "GITHUB_REF": ref})

    def test_enabled_deployment_requires_both_real_https_origins(self):
        values = {
            "GITHUB_EVENT_NAME": "push", "GITHUB_REF": "refs/heads/main", "DEPLOY_ENABLED": "true",
            "API_PUBLIC_URL": "https://api-dev.microsalt.in", "WEBAPP_PUBLIC_URL": "https://dev.microsalt.in",
        }
        self.assertEqual(config.configuration(values)["deploy_enabled"], "true")
        for name in ("API_PUBLIC_URL", "WEBAPP_PUBLIC_URL"):
            for value in ("", "http://dev.microsalt.in", "https://api.example.invalid", "https://localhost"):
                with self.subTest(name=name, value=value), self.assertRaises(ValueError):
                    config.configuration(values | {name: value})

    def test_invalid_switch_architecture_and_output_injection_are_rejected(self):
        values = {"GITHUB_EVENT_NAME": "push", "GITHUB_REF": "refs/heads/main"}
        for name, value in (
            ("DEPLOY_ENABLED", "yes"), ("DOCKER_PLATFORMS", "linux/unknown"),
            ("API_PUBLIC_URL", "https://dev.microsalt.in\nenvironment=production"),
        ):
            with self.subTest(name=name), self.assertRaises(ValueError):
                config.configuration(values | {name: value})

    def test_only_nonsecret_configuration_is_exported(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "output"
            values = {
                "GITHUB_EVENT_NAME": "push", "GITHUB_REF": "refs/heads/main", "GITHUB_OUTPUT": str(output),
                "DB_PASSWORD": "test-only-do-not-export", "VPS_SSH_KEY": "test-only-private-key",
                "API_PUBLIC_URL": "https://api-dev.microsalt.in",
            }
            with patch.dict(os.environ, values, clear=True):
                config.main()
            written = dict(line.split("=", 1) for line in output.read_text().splitlines())
            self.assertEqual(set(written), {"environment", "deploy_enabled", "api_public_url", "docker_platforms"})
            self.assertEqual(written["api_public_url"], values["API_PUBLIC_URL"])

    def test_production_tag_requires_a_commit_on_main(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)

            def git(*args):
                return subprocess.run(
                    ["git", "-C", str(root), *args], check=True, capture_output=True, text=True,
                ).stdout.strip()

            git("init", "--initial-branch=main")
            git("-c", "user.name=Deployment Test", "-c", "user.email=deployment@example.test",
                "commit", "--allow-empty", "-m", "Main commit")
            git("update-ref", "refs/remotes/origin/main", "HEAD")
            env = os.environ | {"GITHUB_EVENT_NAME": "push", "GITHUB_REF": "refs/tags/v1.2.3",
                                "GITHUB_OUTPUT": str(root / "output"), "DEPLOY_ENABLED": "false"}
            result = subprocess.run(["python3", str(ROOT / "scripts/deployment-config.py")],
                                    cwd=root, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            git("checkout", "-b", "unmerged")
            git("-c", "user.name=Deployment Test", "-c", "user.email=deployment@example.test",
                "commit", "--allow-empty", "-m", "Unmerged commit")
            (root / "output").unlink()
            result = subprocess.run(["python3", str(ROOT / "scripts/deployment-config.py")],
                                    cwd=root, env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("must point to a commit on origin/main", result.stderr)
            self.assertFalse((root / "output").exists())


if __name__ == "__main__":
    unittest.main()
