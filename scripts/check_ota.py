#!/usr/bin/env python3
"""Validate OTA contents and device metadata before exporting a successful build."""
from pathlib import Path
import sys
import zipfile


def check(path, device):
    try:
        with zipfile.ZipFile(path) as ota:
            metadata = ota.read('META-INF/com/android/metadata').decode('utf-8')
            fields = dict(line.split('=', 1) for line in metadata.splitlines() if '=' in line)
            devices = fields.get('pre-device', '').split('|')
            if device not in devices:
                raise ValueError(f'OTA metadata targets {devices}, expected {device}: {path}')
            if ota.testzip() is not None:
                raise ValueError(f'OTA ZIP has a bad CRC: {path}')
    except (zipfile.BadZipFile, KeyError, UnicodeError, RuntimeError) as error:
        raise ValueError(f'Invalid OTA ZIP or missing Android metadata: {path}: {error}') from error
    print(f'OTA metadata and ZIP integrity passed: {Path(path).name}')

if __name__ == '__main__':
    try:
        for path in sys.argv[2:]:
            check(path, sys.argv[1])
    except (ValueError, OSError) as error:
        sys.exit(str(error))
