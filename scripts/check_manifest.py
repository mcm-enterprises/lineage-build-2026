#!/usr/bin/env python3
"""Reject incompatible local manifests without modifying a user's source tree."""
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

def check(directory):
    for path in sorted(Path(directory).glob("*.xml")):
        if path.name == "husky.xml":
            expected = Path(__file__).resolve().parents[1] / "local_manifests/husky.xml"
            if path.read_bytes() == expected.read_bytes():
                continue
            raise ValueError(f"{path} differs from the supported manifest. Back it up and remove it before syncing.")
        root = ET.parse(path).getroot()
        for project in root.findall("project"):
            name = project.get("name", "")
            target = project.get("path", "")
            revision = project.get("revision", "")
            if target.startswith(("device/google/", "vendor/google/")) or (
                revision and revision != "lineage-22.1"
            ) or any(word in name for word in ("google_husky", "google_shiba", "google_zuma", "google_shusky")):
                raise ValueError(f"Conflicting local manifest: {path}. Back it up and remove it, or use a fresh BUILD_DIR.")

if __name__ == "__main__":
    try:
        check(sys.argv[1])
    except (ValueError, ET.ParseError) as error:
        sys.exit(str(error))
