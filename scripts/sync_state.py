#!/usr/bin/env python3
"""Record full-sync completion atomically; reject interrupted or mismatched trees."""
import hashlib
import json
from pathlib import Path
import sys
from datetime import datetime, timezone


def identity(profile, branch, manifest):
    return dict(profile=profile, branch=branch,
                manifest_sha256=hashlib.sha256(Path(manifest).read_bytes()).hexdigest())


def write(path, status, profile, branch, manifest):
    path = Path(path)
    record = dict(identity(profile, branch, manifest), status=status,
                  updated_at=datetime.now(timezone.utc).isoformat())
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(record, indent=2) + '\n')
    temporary.replace(path)


def check(path, profile, branch, manifest):
    try:
        record = json.loads(Path(path).read_text())
    except (OSError, ValueError) as error:
        raise ValueError('No valid completed-sync checkpoint. Run sync before build.') from error
    if record.get('status') != 'complete' or any(
        record.get(key) != value for key, value in identity(profile, branch, manifest).items()
    ):
        raise ValueError('Last sync is incomplete or uses a different manifest/profile. Rerun sync before build; downloads are preserved.')

if __name__ == '__main__':
    try:
        if sys.argv[1] == 'check':
            check(*sys.argv[2:])
        else:
            write(*sys.argv[2:])
    except (ValueError, OSError) as error:
        sys.exit(str(error))
