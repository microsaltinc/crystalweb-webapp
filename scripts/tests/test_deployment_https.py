"""Keep staged deployments tied to the new VPS without weakening HTTPS."""

import importlib.util
import subprocess
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("deployment_https", ROOT / "scripts/verify-deployment-https.py")
https = importlib.util.module_from_spec(spec)
spec.loader.exec_module(https)


class DeploymentHttpsTests(unittest.TestCase):
    url = "https://crystal.microsalt.in/healthz"
    env = {"VPS_HOST": "192.0.2.10"}

    def test_default_checks_deployed_vps_before_public_dns_with_tls_validation(self):
        with patch.object(https.subprocess, "run") as run:
            https.verify(self.url, self.env)
        self.assertEqual(run.call_count, 2)
        direct, public = [call.args[0] for call in run.call_args_list]
        self.assertIn("crystal.microsalt.in:443:192.0.2.10:443", direct)
        self.assertNotIn("--connect-to", public)
        for command in (direct, public):
            self.assertEqual(command[-1], self.url)
            self.assertNotIn("--insecure", command)
            self.assertNotIn("-k", command)
        for call in run.call_args_list:
            self.assertTrue(call.kwargs["check"])

    def test_staging_still_checks_target_vps_with_production_hostname(self):
        with patch.object(https.subprocess, "run") as run:
            https.verify(self.url, self.env | {"VERIFY_PUBLIC_DNS": "false"})
        run.assert_called_once()
        self.assertIn("crystal.microsalt.in:443:192.0.2.10:443", run.call_args.args[0])
        self.assertEqual(run.call_args.args[0][-1], self.url)

    def test_failed_direct_check_cannot_pass_using_old_public_host(self):
        with patch.object(https.subprocess, "run", side_effect=subprocess.CalledProcessError(60, "curl")) as run:
            with self.assertRaises(subprocess.CalledProcessError):
                https.verify(self.url, self.env)
        run.assert_called_once()

    def test_public_route_failure_is_not_ignored(self):
        with patch.object(https.subprocess, "run", side_effect=[None, subprocess.CalledProcessError(22, "curl")]):
            with self.assertRaises(subprocess.CalledProcessError):
                https.verify(self.url, self.env)

    def test_explicit_tls_port_and_ipv6_vps(self):
        with patch.object(https.subprocess, "run") as run:
            https.verify("https://crystal.microsalt.in:8443/healthz", {
                "VPS_HOST": "2001:db8::1", "VERIFY_PUBLIC_DNS": "false",
            })
        self.assertIn("crystal.microsalt.in:8443:[2001:db8::1]:8443", run.call_args.args[0])

    def test_invalid_configuration_fails_before_network(self):
        for url, values in (
            (self.url, self.env | {"VERIFY_PUBLIC_DNS": "yes"}),
            (self.url, {"VPS_HOST": "host;command"}),
            (self.url, {}),
            ("http://crystal.microsalt.in/healthz", self.env),
            ("https://user:secret@crystal.microsalt.in/healthz", self.env),
            ("https://crystal.microsalt.in/healthz?token=secret", self.env),
        ):
            with self.subTest(url=url, values=values), patch.object(https.subprocess, "run") as run:
                with self.assertRaises(ValueError):
                    https.verify(url, values)
                run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
