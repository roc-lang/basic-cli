#!/usr/bin/env python3
"""Render docs/releases/<version>.md, filling in values only known at release time.

Placeholders:
  {{PLATFORM_URL}}  URL of the published platform bundle
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


PLACEHOLDER_RE = re.compile(r"\{\{[A-Z_]+\}\}")


def platform_url(repo: str, version: str, bundles_path: Path) -> str:
    bundles = json.loads(bundles_path.read_text(encoding="utf-8"))
    if len(bundles) != 1:
        raise SystemExit(f"expected exactly one release bundle, found {len(bundles)}")
    return f"https://github.com/{repo}/releases/download/{version}/{bundles[0]['artifact_file']}"


def render(template: str, values: dict[str, str]) -> str:
    rendered = template
    for name, value in values.items():
        rendered = rendered.replace("{{" + name + "}}", value)

    unknown = sorted(set(PLACEHOLDER_RE.findall(rendered)))
    if unknown:
        raise SystemExit(f"unknown release notes placeholders: {', '.join(unknown)}")
    return rendered


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("template", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--bundles", type=Path, required=True)
    args = parser.parse_args()

    values = {"PLATFORM_URL": platform_url(args.repo, args.version, args.bundles)}
    args.output.write_text(render(args.template.read_text(encoding="utf-8"), values), encoding="utf-8")


if __name__ == "__main__":
    main()
