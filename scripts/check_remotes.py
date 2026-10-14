#!/usr/bin/env python3
"""Check small remote refs before starting the large Android source download."""
import concurrent.futures
import os
from pathlib import Path
import subprocess
import sys
import xml.etree.ElementTree as ET


def targets(manifest, branch):
    root = ET.parse(manifest).getroot()
    remotes = {r.get('name'): r.get('fetch') for r in root.findall('remote')}
    remotes.update(github='https://github.com', **{'aosp-shusky': 'https://android.googlesource.com'})
    checks = [('Android manifest', 'https://github.com/LineageOS/android.git', f'refs/heads/{branch}')]
    for project in root.findall('project'):
        remote = project.get('remote')
        fetch = remotes[remote].rstrip('/')
        revision = project.get('upstream') or project.get('revision') or 'refs/tags/android-15.0.0_r14'
        ref = revision if revision.startswith('refs/') else 'refs/heads/' + revision
        checks.append((project.get('path'), fetch + '/' + project.get('name'), ref))
    return checks


def probe(target):
    label, url, ref = target
    env = dict(os.environ, GIT_TERMINAL_PROMPT='0')
    try:
        result = subprocess.run(['git', 'ls-remote', '--exit-code', url, ref], env=env,
                                capture_output=True, text=True, timeout=30)
        if result.returncode or not result.stdout.strip():
            return f'{label}: cannot resolve {ref} at {url}\n{result.stderr.strip()[:1500]}'
    except subprocess.TimeoutExpired:
        return f'{label}: remote ref check timed out after 30s: {url}'
    return None


def check(manifest, branch):
    failures = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
        pending = {executor.submit(probe, target): target[0] for target in targets(manifest, branch)}
        for future in concurrent.futures.as_completed(pending):
            error = future.result()
            print(('FAIL: ' + error) if error else ('Remote OK: ' + pending[future]), flush=True)
            if error:
                failures.append(error)
    if failures:
        raise ValueError('Remote checks failed before source download. Resolve the errors above and rerun check-network or sync.')
    print('Remote refs are reachable. This checks the manifest/device repositories; full Android sync also contacts other upstream projects.', flush=True)

if __name__ == '__main__':
    try:
        check(sys.argv[1], sys.argv[2])
    except (ValueError, OSError, ET.ParseError, KeyError) as error:
        sys.exit(str(error))
