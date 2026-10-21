#!/usr/bin/env python3
"""Accept only the selected profile's manifest in a managed source tree."""
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

def check(directory, expected):
    expected = Path(expected)
    ET.parse(expected)
    for path in sorted(Path(directory).glob("*.xml")):
        if path.name == expected.name and path.read_bytes() == expected.read_bytes():
            continue
        raise ValueError(f"Conflicting local manifest: {path}. Back it up outside local_manifests and remove it, or use a fresh BUILD_DIR.")

if __name__ == "__main__":
    try:
        check(sys.argv[1], sys.argv[2])
    except (ValueError, OSError, ET.ParseError) as error:
        sys.exit(str(error))
