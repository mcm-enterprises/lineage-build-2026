#!/usr/bin/env python3
"""Probe the selected source directory without touching existing downloads."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def check(directory):
    with tempfile.TemporaryDirectory(prefix='.lineage-fs-check-', dir=directory) as temp:
        root = Path(temp)
        upper = root / 'CaseCheck'
        upper.write_text('test')
        if (root / 'casecheck').exists():
            raise ValueError('Source filesystem is case-insensitive. Use a case-sensitive Linux filesystem.')
        link = root / 'link'
        link.symlink_to(upper.name)
        if not link.is_symlink() or link.read_text() != 'test':
            raise ValueError('Source filesystem does not preserve symlinks.')
        executable = root / 'execute-check'
        executable.write_text('#!/bin/sh\nexit 0\n')
        executable.chmod(0o700)
        subprocess.run([str(executable)], check=True, capture_output=True)
    print('Source filesystem supports case-sensitive names, symlinks and execution.')

if __name__ == '__main__':
    try:
        check(sys.argv[1])
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        sys.exit(f'Source filesystem check failed: {error}. Check mount permissions/noexec and use a Linux filesystem.')
