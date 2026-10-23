"""Exercise real command groups: silence, useful work, disk exhaustion and stops."""
import importlib.util
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'scripts/supervise.py'
spec = importlib.util.spec_from_file_location('supervise', SCRIPT)
supervisor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(supervisor)


class ActivityTests(unittest.TestCase):
    def test_cpu_io_and_process_turnover_count_but_small_noise_does_not(self):
        before = {('1', '10'): (100, 100)}
        self.assertFalse(supervisor.made_progress(before, {('1', '10'): (101, 101)}, 100))
        self.assertTrue(supervisor.made_progress(before, {('1', '10'): (130, 100)}, 100))
        self.assertTrue(supervisor.made_progress(before, {('1', '10'): (100, 5000)}, 100))
        self.assertTrue(supervisor.made_progress(before, {('1', '11'): (0, 0)}, 100))


@unittest.skipUnless(Path('/proc/self/stat').exists(), 'Linux /proc is required')
class SupervisorTests(unittest.TestCase):
    def run_command(self, code, *options):
        return subprocess.run([sys.executable, str(SCRIPT), '--interval', '0.1',
                               '--idle-timeout', '0.5', '--max-seconds', '5',
                               '--stop-grace', '0.1', '--reserve-gb', '0', *options,
                               '--', sys.executable, '-c', code],
                              capture_output=True, text=True, timeout=8)

    def test_success_failure_and_final_log_are_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / 'attempt.log'
            result = self.run_command('print("final output"); raise SystemExit(9)', '--log', str(log))
            self.assertEqual(result.returncode, 9, result.stdout + result.stderr)
            self.assertIn('final output', log.read_text())
        self.assertEqual(self.run_command('print("done")').returncode, 0)

    def test_silent_hang_is_bounded_and_children_are_killed(self):
        with tempfile.TemporaryDirectory() as directory:
            pidfile = Path(directory) / 'pid'
            result = self.run_command(
                'import subprocess,sys,time; from pathlib import Path; '
                'p=subprocess.Popen([sys.executable,"-c",'
                '"import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); time.sleep(60)"]); '
                f'Path({str(pidfile)!r}).write_text(str(p.pid)); time.sleep(60)')
            self.assertEqual(result.returncode, 124, result.stdout + result.stderr)
            self.assertIn('TIMEOUT', result.stdout)
            pid = int(pidfile.read_text())
            stat = Path(f'/proc/{pid}/stat')
            if stat.exists():
                self.assertEqual(stat.read_text().rsplit(')', 1)[1].split()[0], 'Z')

    def test_quiet_cpu_work_is_not_mistaken_for_a_stall(self):
        result = self.run_command('import time; end=time.monotonic()+1.5\nwhile time.monotonic()<end: pass')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('[watchdog] running', result.stdout)

    def test_hard_deadline_bounds_even_active_commands(self):
        result = self.run_command('while True: pass', '--max-seconds', '0.7')
        self.assertEqual(result.returncode, 124, result.stdout + result.stderr)

    def test_exited_parent_with_child_holding_pipe_is_still_bounded(self):
        result = self.run_command('import subprocess,sys; subprocess.Popen([sys.executable,"-c","import time; time.sleep(60)"])')
        self.assertEqual(result.returncode, 124, result.stdout + result.stderr)

    def test_log_chatter_does_not_disable_hard_deadline(self):
        result = self.run_command('import time\nwhile True: print("waiting",flush=True); time.sleep(.05)',
                                  '--max-seconds', '0.7')
        self.assertEqual(result.returncode, 124, result.stdout + result.stderr)

    def test_low_disk_stops_before_starting_command(self):
        result = self.run_command('print("must not start")', '--reserve-gb', '99999999')
        self.assertEqual(result.returncode, 75, result.stdout + result.stderr)
        self.assertNotIn('must not start', result.stdout)

    def test_disk_drop_during_command_stops_without_retry_code(self):
        args = type('Args', (), dict(path=['.'], log=None, reserve_gb=5,
                    command=[sys.executable, '-c', 'import time; time.sleep(60)'],
                    interval=.1, idle_timeout=5, max_seconds=10, stop_grace=.1))()
        enough = type('Usage', (), {'free': 10 * 1024**3})()
        low = type('Usage', (), {'free': 1024**3})()
        with mock.patch.object(supervisor.shutil, 'disk_usage', side_effect=[enough, low]):
            self.assertEqual(supervisor.supervise(args), 75)

    def test_sigterm_cleans_up_instead_of_retrying(self):
        with tempfile.TemporaryDirectory() as directory:
            ready = Path(directory) / 'ready'
            process = subprocess.Popen([sys.executable, str(SCRIPT), '--interval', '.1',
                '--stop-grace', '.1', '--reserve-gb', '0', '--', sys.executable, '-c',
                f'import os,time; from pathlib import Path; Path({str(ready)!r}).write_text(str(os.getpid())); time.sleep(60)'],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            try:
                deadline = time.monotonic() + 5
                while not ready.exists() and time.monotonic() < deadline:
                    time.sleep(.02)
                self.assertTrue(ready.exists())
                process.send_signal(signal.SIGTERM)
                output = process.communicate(timeout=5)[0]
                self.assertEqual(process.returncode, 143, output)
                self.assertFalse(Path(f'/proc/{ready.read_text()}/stat').exists())
            finally:
                if process.poll() is None:
                    process.kill()
                    process.communicate()
