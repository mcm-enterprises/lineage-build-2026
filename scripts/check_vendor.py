#!/usr/bin/env python3
"""Catch absent vendor copy sources and Git LFS pointer files before compiling."""
import re
import sys
from pathlib import Path

def check(root):
    root = Path(root)
    vendor = root / "vendor/google/husky"
    makefile = vendor / "husky-vendor.mk"
    blueprint = vendor / "Android.bp"
    if not makefile.is_file() or not blueprint.is_file():
        raise ValueError("Missing husky vendor build files. Run sync with the matching local manifest.")
    references = set(re.findall(r"vendor/google/husky/proprietary/[^\s:]+", makefile.read_text()))
    references.update("vendor/google/husky/" + path for path in re.findall(
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
    if missing:
        errors.append("Missing vendor sources (first 10): " + ", ".join(missing[:10]))
    if pointers:
        errors.append("Undownloaded Git LFS blobs (first 10): " + ", ".join(pointers[:10]) +
                      ". Run git -C vendor/google/husky lfs pull in the source tree.")
    if errors:
        raise ValueError("\n".join(errors))

if __name__ == "__main__":
    try:
        check(sys.argv[1])
    except (ValueError, OSError) as error:
        sys.exit(str(error))
