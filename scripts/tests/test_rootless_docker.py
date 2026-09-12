"""Exercise production daemon selection and refusal of privileged execution."""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class RootlessDockerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.observed = self.directory / "observed"
        for name, script in {
            "id": '#!/bin/sh\ncase "$1" in -u) echo "$TEST_UID";; -nG) echo "$TEST_GROUPS";; *) exit 1;; esac\n',
            "docker": (
                '#!/bin/sh\n'
                'printf "%s\\n" "$DOCKER_HOST" "${DOCKER_CONTEXT-unset}" "$DOCKER_CONFIG" > "$TEST_OBSERVED"\n'
                'printf "%s\\n" "$TEST_SECURITY"\n'
                'exit "$TEST_DOCKER_STATUS"\n'
            ),
        }.items():
            path = self.directory / name
            path.write_text(script)
            path.chmod(0o755)
        self.env = os.environ | {
            "PATH": f"{self.directory}:{os.environ['PATH']}",
            "TEST_UID": "1002", "TEST_GROUPS": "cicd-user",
            "TEST_SECURITY": '["name=seccomp,profile=builtin", "name=rootless"]',
            "TEST_DOCKER_STATUS": "0", "TEST_OBSERVED": str(self.observed),
            "DOCKER_HOST": "unix:///var/run/docker.sock", "DOCKER_CONTEXT": "default",
            "DOCKER_CONFIG": str(self.directory / "temporary-registry-credentials"),
        }

    def run_check(self, **changes):
        return subprocess.run(
            ["sh", "-c", '. "$1"; crystalweb_require_rootless_docker', "sh", str(ROOT / "scripts/rootless-docker.sh")],
            env=self.env | changes, capture_output=True, text=True,
        )

    def test_temporary_credentials_still_use_only_the_service_account_socket(self):
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.observed.read_text().splitlines(), [
            "unix:///run/user/1002/docker.sock", "unset", self.env["DOCKER_CONFIG"],
        ])

    def test_root_and_docker_group_are_rejected_before_contacting_docker(self):
        for changes in ({"TEST_UID": "0"}, {"TEST_GROUPS": "cicd-user docker"}):
            with self.subTest(changes=changes):
                result = self.run_check(**changes)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.observed.exists())

    def test_rootful_missing_or_invalid_daemon_fails_closed(self):
        for changes in (
            {"TEST_SECURITY": '["name=seccomp,profile=builtin"]'},
            {"TEST_SECURITY": "invalid json"},
            {"TEST_SECURITY": '{"name=rootless": true}'},
            {"TEST_DOCKER_STATUS": "1"},
        ):
            with self.subTest(changes=changes):
                self.assertNotEqual(self.run_check(**changes).returncode, 0)


if __name__ == "__main__":
    unittest.main()
