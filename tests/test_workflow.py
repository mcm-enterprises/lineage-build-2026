"""Offline integration tests: exercise workflow order and failures using tiny tool stubs."""
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import fcntl

ROOT = Path(__file__).resolve().parents[1]

def load_script(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'scripts' / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

class WorkflowTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='lineage test ')
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.source = self.base / 'source'
        self.bin = self.base / 'bin'
        self.bin.mkdir()
        self.env = dict(os.environ, PATH=str(self.bin) + ':' + os.environ['PATH'],
                        BUILD_DIR=str(self.source), OUTPUT_DIR=str(self.base / 'zips'),
                        LOG_DIR=str(self.base / 'logs'), MIN_FREE_GB='1', SYNC_RETRY_DELAY='0',
                        JOBS='2', TRACE=str(self.base / 'trace'), BRANCH='lineage-22.1')
        self.tool('git', '''#!/bin/bash
case "$*" in
  *lfs*|*GIT_AUTHOR_IDENT*) exit 0 ;;
  *branch.default.merge*) echo "${TEST_EXISTING_BRANCH:-refs/heads/lineage-22.1}" ;;
esac
''')
        self.tool('repo', '''#!/bin/bash
set -e
printf '%s\n' "$*" >> "$TRACE"
case "$1" in
init) mkdir -p .repo/manifests/.git ;;
sync)
  test -d .repo/manifests/.git
  test -f .repo/local_manifests/husky.xml
  if [[ "${TEST_SYNC_FAIL:-0}" == 1 ]]; then exit 7; fi
  mkdir -p build vendor/google/husky/proprietary
  printf '# mock vendor\n' > vendor/google/husky/husky-vendor.mk
  printf '// mock vendor\n' > vendor/google/husky/Android.bp
  cat > build/envsetup.sh <<'ENVSETUP'
breakfast() { echo "breakfast $*" >> "$TRACE"; return "${TEST_BREAKFAST_EXIT:-0}"; }
m() {
    echo "m $*" >> "$TRACE"
    [[ "${TEST_BUILD_FAIL:-0}" == 0 ]] || return 9
    [[ "${TEST_NO_ZIP:-0}" == 0 ]] || return 0
    mkdir -p out/target/product/husky
    printf 'test zip\n' > out/target/product/husky/lineage-test.zip
    printf 'test boot\n' > out/target/product/husky/boot.img
}
ENVSETUP
  ;;
manifest) printf '<manifest/>\n' > "$4" ;;
esac
''')
        self.tool('rsync', '''#!/usr/bin/env python3
import shutil, sys
from pathlib import Path
for path in sys.argv[2:-1]:
    shutil.copy2(path, Path(sys.argv[-1]) / Path(path).name)
''')

    def tool(self, name, content):
        path = self.bin / name
        path.write_text(content)
        path.chmod(0o755)

    def run_workflow(self, action='all', **env):
        result = subprocess.run(['bash', str(ROOT / 'build-lineage.sh'), action],
                                env=dict(self.env, **env), text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20)
        return result

    def trace(self):
        return (self.base / 'trace').read_text() if (self.base / 'trace').exists() else ''

    def test_fresh_build_initializes_before_sync_and_exports(self):
        result = self.run_workflow()
        self.assertEqual(result.returncode, 0, result.stdout)
        lines = self.trace().splitlines()
        self.assertTrue(lines[0].startswith('init '))
        self.assertTrue(lines[1].startswith('sync '))
        self.assertIn('m bacon -j2', lines)
        self.assertEqual((self.base / 'zips/lineage-test.zip').read_text(), 'test zip\n')
        self.assertTrue((self.base / 'zips/boot.img').exists())
        self.assertTrue((self.base / 'zips/source-manifest.xml').exists())
        subprocess.run(['sha256sum', '-c', 'SHA256SUMS'], cwd=self.base / 'zips', check=True,
                       stdout=subprocess.PIPE)

    def test_partial_repo_directory_does_not_skip_init(self):
        (self.source / '.repo/local_manifests').mkdir(parents=True)
        result = self.run_workflow('sync')
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertTrue(self.trace().startswith('init '))

    def test_preflight_never_downloads(self):
        result = self.run_workflow('check')
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.trace(), '')

    def test_sync_failure_is_bounded_and_keeps_locks(self):
        (self.source / '.repo').mkdir(parents=True)
        lock = self.source / '.repo/test.lock'
        lock.write_text('preserve')
        result = self.run_workflow(TEST_SYNC_FAIL='1', SYNC_RETRIES='2')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.trace().count('sync -c'), 2)
        self.assertNotIn('breakfast', self.trace())
        self.assertTrue(lock.exists())

    def test_build_and_breakfast_failures_propagate(self):
        for failure in ({'TEST_BUILD_FAIL': '1'}, {'TEST_BREAKFAST_EXIT': '8'}):
            with self.subTest(failure=failure):
                result = self.run_workflow(**failure)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('Build complete.', result.stdout)

    def test_stale_zip_is_not_success(self):
        product = self.source / 'out/target/product/husky'
        product.mkdir(parents=True)
        zipfile = product / 'lineage-old.zip'
        zipfile.write_text('stale')
        os.utime(zipfile, (1, 1))
        result = self.run_workflow(TEST_NO_ZIP='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('no new lineage ZIP', result.stdout)
        self.assertFalse((self.base / 'zips/lineage-old.zip').exists())

    def test_conflicting_manifest_is_not_overwritten(self):
        manifest = self.source / '.repo/local_manifests/muppets.xml'
        manifest.parent.mkdir(parents=True)
        content = '<manifest><project name="wrong" path="vendor/google/zuma"/></manifest>'
        manifest.write_text(content)
        result = self.run_workflow('sync')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(manifest.read_text(), content)
        self.assertEqual(self.trace(), '')

    def test_existing_wrong_branch_is_rejected(self):
        (self.source / '.repo/manifests/.git').mkdir(parents=True)
        result = self.run_workflow('sync', TEST_EXISTING_BRANCH='refs/heads/lineage-23.0')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.trace(), '')

    def test_concurrent_workflow_is_rejected(self):
        self.source.mkdir()
        with (self.source / '.lineage-build.lock').open('w') as handle:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = self.run_workflow('check')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Another workflow', result.stdout)

    def test_invalid_settings_are_rejected(self):
        for config in ({'JOBS': '0'}, {'BRANCH': 'lineage-23.0'}, {'SYNC_RETRIES': '-1'}):
            with self.subTest(config=config):
                self.assertNotEqual(self.run_workflow('check', **config).returncode, 0)

    def test_build_without_sources_fails(self):
        result = self.run_workflow('build')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Run sync first', result.stdout)

class VendorTests(unittest.TestCase):
    def test_missing_copy_source_and_lfs_pointer(self):
        checker = load_script('check_vendor')
        with tempfile.TemporaryDirectory() as directory:
            vendor = Path(directory) / 'vendor/google/husky'
            (vendor / 'proprietary').mkdir(parents=True)
            (vendor / 'husky-vendor.mk').write_text('vendor/google/husky/proprietary/missing.xml:system/etc/foo')
            (vendor / 'Android.bp').write_text('srcs: ["proprietary/library.so"]')
            (vendor / 'proprietary/library.so').write_text('version https://git-lfs.github.com/spec/v1\n')
            with self.assertRaisesRegex(ValueError, 'Missing vendor sources'):
                checker.check(directory)
            (vendor / 'proprietary/missing.xml').write_text('<xml/>')
            with self.assertRaisesRegex(ValueError, 'Git LFS'):
                checker.check(directory)
            (vendor / 'proprietary/library.so').write_bytes(b'\x7fELF')
            checker.check(directory)

if __name__ == '__main__':
    unittest.main()
