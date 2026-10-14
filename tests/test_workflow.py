"""Offline integration tests: exercise workflow order and failures using tiny tool stubs."""
import importlib.util
import os
import shutil
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
                        JOBS='2', TRACE=str(self.base / 'trace'), BUILD_PROFILE='pixel')
        self.tool('git', '''#!/bin/bash
case "$*" in
  *ls-remote*)
    if [[ "${TEST_REMOTE_FAIL:-0}" == 1 ]]; then echo 'fatal: network unavailable' >&2; exit 128; fi
    printf '1234567890abcdef refs/heads/mock\n'; exit 0 ;;
  *lfs*|*GIT_AUTHOR_IDENT*) exit 0 ;;
  *branch.default.merge*) if [[ "$BUILD_PROFILE" == realme6 ]]; then default_branch=refs/heads/lineage-21.0; else default_branch=refs/heads/lineage-22.1; fi
    echo "${TEST_EXISTING_BRANCH:-$default_branch}" ;;
esac
''')
        self.tool('repo', '''#!/bin/bash
set -e
printf '%s\n' "$*" >> "$TRACE"
case "$1" in
init) mkdir -p .repo/manifests/.git ;;
sync)
  test -d .repo/manifests/.git
  if [[ "$BUILD_PROFILE" == realme6 ]]; then
    manifest=realme6.xml; vendor=vendor/realme/RM6785-common; makefile=RM6785-common-vendor.mk
  else
    manifest=husky.xml; vendor=vendor/google/husky; makefile=husky-vendor.mk
  fi
  test -f ".repo/local_manifests/$manifest"
  if [[ "${TEST_SYNC_FAIL:-0}" == 1 ]]; then exit 7; fi
  mkdir -p build "$vendor/proprietary"
  printf '# mock vendor\n' > "$vendor/$makefile"
  printf '// mock vendor\n' > "$vendor/Android.bp"
  cat > build/envsetup.sh <<'ENVSETUP'
breakfast() { echo "breakfast $*" >> "$TRACE"; return "${TEST_BREAKFAST_EXIT:-0}"; }
m() {
    echo "m $*" >> "$TRACE"
    [[ "${TEST_BUILD_FAIL:-0}" == 0 ]] || return 9
    [[ "${TEST_NO_ZIP:-0}" == 0 ]] || return 0
    mkdir -p out/target/product/$DEVICE
    printf 'test zip\n' > out/target/product/$DEVICE/lineage-test-$DEVICE.zip
    printf 'test boot\n' > out/target/product/$DEVICE/boot.img
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
        self.assertEqual((self.base / 'zips/lineage-test-husky.zip').read_text(), 'test zip\n')
        self.assertTrue((self.base / 'zips/boot.img').exists())
        self.assertTrue((self.base / 'zips/source-manifest.xml').exists())
        subprocess.run(['sha256sum', '-c', 'SHA256SUMS'], cwd=self.base / 'zips', check=True,
                       stdout=subprocess.PIPE)

    def test_realme_profile_uses_matching_manifest_branch_target_and_vendor(self):
        result = self.run_workflow(BUILD_PROFILE='realme6')
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn('-b lineage-21.0', self.trace())
        self.assertIn('breakfast RMX2001L1 userdebug', self.trace())
        self.assertTrue((self.source / '.repo/local_manifests/realme6.xml').exists())
        self.assertTrue((self.base / 'zips/lineage-test-RMX2001L1.zip').exists())
        self.assertFalse((self.base / 'zips/lineage-test-husky.zip').exists())

    def test_profile_marker_prevents_reusing_pixel_tree_for_realme(self):
        self.assertEqual(self.run_workflow('sync').returncode, 0)
        trace = self.trace()
        result = self.run_workflow('sync', BUILD_PROFILE='realme6')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('another profile', result.stdout)
        self.assertEqual(self.trace(), trace)

    def test_default_paths_keep_both_builds_and_artifacts_separate(self):
        checkout = self.base / 'checkout'
        checkout.mkdir()
        shutil.copy2(ROOT / 'build-lineage.sh', checkout)
        for directory in ('profiles', 'scripts', 'local_manifests'):
            shutil.copytree(ROOT / directory, checkout / directory)
        env = dict(self.env)
        for variable in ('BUILD_DIR', 'OUTPUT_DIR', 'LOG_DIR'):
            env.pop(variable)
        for profile, branch, device in (('pixel', 'lineage-22.1', 'husky'),
                                        ('realme6', 'lineage-21.0', 'RMX2001L1')):
            result = subprocess.run(['bash', str(checkout / 'build-lineage.sh'),
                                     '--profile', profile, 'all'], env=env, text=True,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20)
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertTrue((checkout / 'android_source' / profile / branch / '.lineage-profile').exists())
            self.assertTrue((checkout / 'zips' / profile / branch / f'lineage-test-{device}.zip').exists())
            self.assertTrue(list((checkout / 'logs' / profile / branch).glob('*.log')))

    def test_unknown_profile_fails_before_touching_sources(self):
        result = self.run_workflow(BUILD_PROFILE='unknown')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.source.exists())

    def test_remote_failure_stops_before_init_or_download(self):
        result = self.run_workflow('sync', TEST_REMOTE_FAIL='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Remote checks failed before source download', result.stdout)
        self.assertEqual(self.trace(), '')

    def test_network_check_does_not_need_fresh_tree_disk_budget(self):
        result = self.run_workflow('check-network', MIN_FREE_GB='99999')
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.trace(), '')

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
        self.assertIn('sync -c -j1', self.trace())
        self.assertEqual(len(list((self.base / 'logs').glob('*attempt-*.log'))), 2)
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
        zipfile = product / 'lineage-old-husky.zip'
        zipfile.write_text('stale')
        os.utime(zipfile, (1, 1))
        result = self.run_workflow(TEST_NO_ZIP='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('no new lineage ZIP', result.stdout)
        self.assertFalse((self.base / 'zips/lineage-old-husky.zip').exists())

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

    def test_realme_vendor_sources_are_checked(self):
        checker = load_script('check_vendor')
        with tempfile.TemporaryDirectory() as directory:
            vendor = Path(directory) / 'vendor/realme/RM6785-common'
            (vendor / 'proprietary').mkdir(parents=True)
            (vendor / 'RM6785-common-vendor.mk').write_text(
                'vendor/realme/RM6785-common/proprietary/config.xml:vendor/etc/config.xml')
            (vendor / 'Android.bp').write_text('// fixture')
            with self.assertRaisesRegex(ValueError, 'Missing vendor sources'):
                checker.check(directory, 'vendor/realme/RM6785-common', 'RM6785-common-vendor.mk')
            (vendor / 'proprietary/config.xml').write_text('<config/>')
            checker.check(directory, 'vendor/realme/RM6785-common', 'RM6785-common-vendor.mk')

class DockerConfigurationTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('docker'), 'Compose CLI is unavailable')
    def test_profiles_use_isolated_linux_sources_and_amd64(self):
        import json
        volumes = []
        for profile in ('pixel', 'realme6'):
            env = dict(os.environ, BUILD_PROFILE=profile, BUILD_ACTION='sync')
            env.pop('COMPOSE_PROJECT_NAME', None)
            config = json.loads(subprocess.check_output(
                ['docker', 'compose', '-f', str(ROOT / 'docker_env/docker-compose.yml'),
                 'config', '--format', 'json'], env=env, text=True))
            service = config['services']['lineage-builder']
            self.assertEqual(service['platform'], 'linux/amd64')
            self.assertEqual(service['command'], ['sync'])
            self.assertEqual(config['name'], 'lineage-' + profile)
            source = next(v for v in service['volumes'] if v['target'] == '/android/lineage')
            self.assertEqual(source['type'], 'volume')
            volumes.append(config['volumes'][source['source']]['name'])
            for volume in service['volumes']:
                if volume['type'] == 'bind':
                    self.assertIn('/docker_source/' + profile + '/', volume['source'])
        self.assertEqual(len(set(volumes)), 2)

    def test_mac_launcher_defaults_to_sync_and_two_workers(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            shutil.copy2(ROOT / 'bootstrap_docker.sh', base)
            bin_dir = base / 'bin'
            bin_dir.mkdir()
            uname = bin_dir / 'uname'
            uname.write_text('#!/bin/sh\nif [ "$1" = -s ]; then echo Darwin; else echo arm64; fi\n')
            uname.chmod(0o755)
            docker = bin_dir / 'docker'
            docker.write_text('#!/bin/sh\nprintf "%s %s %s %s\\n" "$*" "$BUILD_ACTION" "$BUILD_PROFILE" "$SYNC_JOBS" >> "$TRACE"\n')
            docker.chmod(0o755)
            env = dict(os.environ, PATH=str(bin_dir) + ':' + os.environ['PATH'], TRACE=str(base / 'trace'))
            for key in ('BUILD_ACTION', 'SYNC_JOBS', 'BUILD_PROFILE'):
                env.pop(key, None)
            result = subprocess.run(['bash', str(base / 'bootstrap_docker.sh'), '--profile', 'realme6'],
                                    env=env, text=True, capture_output=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('Apple Silicon', result.stdout)
            trace = (base / 'trace').read_text()
            self.assertIn('sync realme6 2', trace)
            self.assertTrue((base / 'docker_source/realme6/logs').is_dir())
            self.assertFalse((base / 'docker_source/realme6/lineage').exists())

class FilesystemTests(unittest.TestCase):
    def test_probe_cleans_up_and_preserves_existing_files(self):
        checker = load_script('check_filesystem')
        with tempfile.TemporaryDirectory() as directory:
            existing = Path(directory) / 'existing-download'
            existing.write_text('keep')
            checker.check(directory)
            self.assertEqual(list(Path(directory).iterdir()), [existing])
            self.assertEqual(existing.read_text(), 'keep')

if __name__ == '__main__':
    unittest.main()
