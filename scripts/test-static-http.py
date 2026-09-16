#!/usr/bin/env python3
"""Check browser asset responses using the production nginx image/configuration."""

from __future__ import annotations

import re
import subprocess
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def docker(*args: str) -> str:
    return subprocess.check_output(["docker", *args], text=True).strip()


def main() -> None:
    image = re.findall(r"^FROM (nginxinc/\S+)$", (ROOT / "Dockerfile").read_text(), re.M)[0]
    modules = sorted(set(re.findall(r"/pdfjs/[^'\"\s]+\.mjs", (ROOT / "web/index.html").read_text())))
    assert len(modules) >= 2, "PDF.js runtime and worker must be tested"
    name = f"crystalweb-static-test-{uuid.uuid4().hex[:12]}"
    try:
        docker(
            "run", "--detach", "--rm", "--name", name,
            "--read-only", "--tmpfs", "/tmp", "--cap-drop", "ALL",
            "--security-opt", "no-new-privileges", "--publish", "127.0.0.1::8080",
            "--mount", f"type=bind,src={ROOT / 'docker/nginx.conf'},dst=/etc/nginx/conf.d/default.conf,readonly",
            "--mount", f"type=bind,src={ROOT / 'web'},dst=/usr/share/nginx/html,readonly",
            image,
        )
        address = docker("port", name, "8080/tcp").splitlines()[0]
        base = f"http://{address}"
        deadline = time.monotonic() + 15
        while True:
            try:
                with urllib.request.urlopen(f"{base}/healthz", timeout=1) as response:
                    assert response.read() == b"healthy\n"
                break
            except (urllib.error.URLError, TimeoutError):
                if time.monotonic() >= deadline:
                    raise
                time.sleep(0.2)

        for path, expected_type in [
            *((path, "application/javascript") for path in modules),
            ("/favicon.png", "image/png"),
            ("/manifest.json", "application/json"),
        ]:
            with urllib.request.urlopen(base + path, timeout=10) as response:
                actual = response.headers.get_content_type()
                assert actual == expected_type, f"{path}: expected {expected_type}, got {actual}"
                assert response.headers.get("X-Content-Type-Options") == "nosniff"
                assert response.read() == (ROOT / "web" / path.lstrip("/")).read_bytes()
                print(f"PASS {path}: {actual}, complete file, nosniff")

        try:
            urllib.request.urlopen(f"{base}/pdfjs/missing.mjs", timeout=5)
        except urllib.error.HTTPError as error:
            assert error.code == 404, f"Missing module returned {error.code}"
        else:
            raise AssertionError("Missing module incorrectly fell back to the HTML application")
        print("PASS missing module returns 404")
    finally:
        subprocess.run(["docker", "rm", "--force", name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


if __name__ == "__main__":
    main()
