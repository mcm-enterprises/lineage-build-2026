#!/usr/bin/env python3
"""Catch absent vendor copy sources and Git LFS pointer files before compiling."""
import re
import sys
import hashlib
from pathlib import Path

def check(root, vendor_path="vendor/google/husky", makefile_name="husky-vendor.mk"):
    root = Path(root)
    vendor = root / vendor_path
    makefile = vendor / makefile_name
    blueprint = vendor / "Android.bp"
    if not makefile.is_file() or not blueprint.is_file():
        raise ValueError("Missing selected profile vendor build files. Run sync with the matching local manifest.")
    references = set(re.findall(re.escape(vendor_path) + r"/proprietary/[^\s:]+", makefile.read_text()))
    references.update(vendor_path + "/" + path for path in re.findall(
        r'"(proprietary/[^"*]+)"', blueprint.read_text()
    ))
    missing = sorted(path for path in references if not (root / path).exists())
    pointers = []
    for path in (vendor / "proprietary").rglob("*"):
        if path.is_file():
            with path.open("rb") as stream:
                if stream.read(128).startswith(b"version https://git-lfs.github.com/spec/v1"):
                    pointers.append(str(path.relative_to(root)))
    errors = []
    # Firmware lives outside proprietary/. Missing or unresolved LFS images here
    # otherwise surface during target-files/OTA packaging, late in the build.
    radio_makefile = vendor / 'Android.mk'
    if radio_makefile.is_file():
        radio = re.findall(r'\$\(call\s+add-radio-file-sha1-checked,\s*([^,\s]+)\s*,\s*([0-9a-fA-F]{40})\s*\)',
                           radio_makefile.read_text())
        for relative, expected in radio:
            image = vendor / relative
            if not image.is_file():
                errors.append(f'Missing OTA firmware image: {image.relative_to(root)}')
                continue
            with image.open('rb') as stream:
                digest = hashlib.sha1()
                for block in iter(lambda: stream.read(1024 * 1024), b''):
                    digest.update(block)
                actual = digest.hexdigest()
            if actual.lower() != expected.lower():
                errors.append(f'OTA firmware checksum mismatch (or unresolved LFS blob): {image.relative_to(root)}')
    if missing:
        errors.append("Missing vendor sources (first 10): " + ", ".join(missing[:10]))
    if pointers:
        errors.append("Undownloaded Git LFS blobs (first 10): " + ", ".join(pointers[:10]) +
                      f". Run git -C {vendor_path} lfs pull in the source tree.")
    if errors:
        raise ValueError("\n".join(errors))

if __name__ == "__main__":
    try:
        check(*sys.argv[1:])
    except (ValueError, OSError) as error:
        sys.exit(str(error))
