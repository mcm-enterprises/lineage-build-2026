"""Monitor must finish even when Docker's log follower remains attached."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class MonitorTests(unittest.TestCase):
    def test_stopped_success_failure_and_missing_container(self):
        with tempfile.TemporaryDirectory() as temporary:
            docker = Path(temporary) / 'docker'
            docker.write_text('''#!/bin/bash
case "$1" in
compose) printf '%s' "${TEST_CONTAINER:-}" ;;
logs)
    if [[ "$2" == --follow ]]; then exec sleep 30; fi
    echo 'Workflow final output' ;;
wait) echo "$TEST_EXIT" ;;
*) exit 99 ;;
esac
''')
            docker.chmod(0o755)
            for container, code in [('container123', 0), ('container123', 9), ('', 1)]:
                with self.subTest(container=container, code=code):
                    result = subprocess.run(
                        ['bash', str(ROOT / 'monitor_docker.sh'), '--profile', 'realme6'],
                        env=dict(os.environ, PATH=temporary + ':' + os.environ['PATH'],
                                 TEST_CONTAINER=container, TEST_EXIT=str(code)),
                        capture_output=True, text=True, timeout=5)
                    self.assertEqual(result.returncode, code, result.stdout + result.stderr)
                    if container:
                        self.assertIn('Workflow final output', result.stdout)
                        self.assertIn('SUCCESS:' if code == 0 else 'FAILED:',
                                      result.stdout + result.stderr)
                    else:
                        self.assertIn('No workflow container found', result.stderr)
