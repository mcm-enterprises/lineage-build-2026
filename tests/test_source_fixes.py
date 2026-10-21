import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('source_fixes', ROOT / 'scripts/source_fixes.py')
fixes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixes)


class SourceFixTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.target = self.root / fixes.THERMAL
        self.target.parent.mkdir(parents=True)
        self.original = ('cc_binary {\n name: "android.hardware.thermal-service.mediatek",\n'
            ' static_libs: ["libpixelstats"],\n'
            ' shared_libs: ["android.frameworks.stats-V1-ndk", "android.hardware.thermal-V1-ndk"],\n'
            ' export_shared_lib_headers: ["android.frameworks.stats-V1-ndk"],\n}\n')
        self.target.write_text(self.original)
        pixel = self.root / fixes.PIXELSTATS
        pixel.parent.mkdir(parents=True)
        pixel.write_text('cc_library { name: "libpixelstats", shared_libs: ["android.frameworks.stats-V2-ndk"] }')
        (self.root / 'frameworks/hardware/interfaces/stats/aidl/aidl_api/android.frameworks.stats/2').mkdir(parents=True)

    def test_fix_is_narrow_idempotent_and_records_reproducible_diff(self):
        fixes.apply(self.root, 'realme6')
        updated = self.target.read_text()
        self.assertEqual(updated, self.original.replace(fixes.OLD, fixes.NEW))
        self.assertIn('android.hardware.thermal-V1-ndk', updated)
        record = (self.root / fixes.RECORD).read_text()
        patch = (self.root / fixes.PATCH).read_text()
        self.assertIn('-' + ' shared_libs:', patch)
        self.assertEqual(json.loads(record)['fixes'][0]['name'], 'mediatek-thermal-stats-v2')
        fixes.apply(self.root, 'realme6')
        self.assertEqual(self.target.read_text(), updated)
        self.assertEqual((self.root / fixes.RECORD).read_text(), record)
        self.assertEqual((self.root / fixes.PATCH).read_text(), patch)

    def test_incompatible_pixelstats_and_unexpected_thermal_are_left_unchanged(self):
        for content in (self.original.replace('"libpixelstats"', '"unrelated"'),
                        self.original.replace(fixes.OLD, fixes.NEW, 1)):
            self.target.write_text(content)
            with self.assertRaises(ValueError):
                fixes.apply(self.root, 'realme6')
            self.assertEqual(self.target.read_text(), content)
        self.target.write_text(self.original)
        (self.root / fixes.PIXELSTATS).write_text(fixes.OLD)
        with self.assertRaises(ValueError):
            fixes.apply(self.root, 'realme6')
        self.assertEqual(self.target.read_text(), self.original)

    def test_pixel_profile_never_modifies_sources(self):
        fixes.apply(self.root, 'pixel')
        self.assertEqual(self.target.read_text(), self.original)
        self.assertFalse((self.root / fixes.RECORD).exists())
