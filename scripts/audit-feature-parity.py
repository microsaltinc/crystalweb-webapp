#!/usr/bin/env python3
"""Detect unreviewed CrystalApp feature drift without copying upstream runtime code.

Reads committed source with Git, so a stale/dirty neighboring checkout is harmless.
Reviewed adaptations are pinned on both sides in feature-parity.json. This is a
source comparison guard, not a substitute for API, PostgreSQL and browser tests.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE_PREFIX = 'frontend/'
SOURCE_PATHS = ('frontend/lib', 'frontend/web', 'frontend/assets', 'frontend/pubspec.yaml')


def blob_id(path: Path) -> str | None:
    if not path.is_file():
        return None
    data = path.read_bytes()
    return hashlib.sha1(f"blob {len(data)}\0".encode() + data).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT.parent.parent / "crystalApp")
    parser.add_argument("--ref", default="refs/remotes/origin/main")
    args = parser.parse_args()
    manifest = json.loads((ROOT / "scripts/feature-parity.json").read_text())
    reviewed = manifest["adaptations"]

    def git(*arguments: str) -> str:
        return subprocess.check_output(
            ["git", "-C", str(args.source), *arguments], text=True
        ).strip()

    revision = git("rev-parse", "--verify", f"{args.ref}^{{commit}}")
    entries = {}
    for line in git("ls-tree", "-r", revision, "--", *SOURCE_PATHS).splitlines():
        metadata, name = line.split("\t", 1)
        mode, kind, oid = metadata.split()
        if kind != "blob" or mode not in {"100644", "100755"}:
            raise ValueError(f"Unsupported source entry: {name}")
        entries[name] = oid
    if not entries:
        raise ValueError("Source ref contains no application files")

    errors = []
    identical = adapted = omitted = 0
    for name, source_blob in entries.items():
        rule = reviewed.get(name)
        target = rule["target"] if rule else name.removeprefix(SOURCE_PREFIX)
        target_blob = blob_id(ROOT / target) if target else None
        if rule:
            if target is None and (ROOT / name.removeprefix(SOURCE_PREFIX)).exists():
                errors.append(f"Intentionally omitted file was reintroduced: {name}")
            elif source_blob != rule["source_blob"] or target_blob != rule["target_blob"]:
                errors.append(f"Changed since review: {name}")
            elif not rule.get("reason"):
                errors.append(f"Missing adaptation rationale: {name}")
            elif target is None:
                omitted += 1
            else:
                adapted += 1
        elif source_blob == target_blob:
            identical += 1
        else:
            errors.append(f"Unreviewed difference or missing feature file: {name}")
    for name in reviewed.keys() - entries.keys():
        errors.append(f"Reviewed source file was removed: {name}")

    print(f"CrystalApp source: {revision}")
    print(f"Reviewed baseline: {manifest['source_revision']}")
    print(f"{identical} identical, {adapted} adapted, {omitted} intentionally omitted")
    if errors:
        for error in errors:
            print(f"- {error}")
        print("Feature parity audit FAILED; review changes and update code/tests before the manifest.")
        return 1
    print("Feature parity source audit passed; see docs/feature-parity.md for scope and validation.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
