import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

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
        self.device = self.root / fixes.DEVICE_MK
        self.device.parent.mkdir(parents=True)
        self.device.write_text('PRODUCT_PACKAGES += ' + ' '.join(fixes.REQUIRED_PACKAGES) + '\n')
        self.contexts = self.root / fixes.USB_CONTEXTS
        self.contexts.parent.mkdir(parents=True)
        self.contexts.write_text('# Existing device labels\n')
        domain = self.root / fixes.USB_DOMAIN
        domain.parent.mkdir(parents=True)
        domain.write_text('type mtk_hal_usb_exec, exec_type, file_type, vendor_file_type;\ninit_daemon_domain(mtk_hal_usb)\n')

        policy = self.root / fixes.POLICY_DEVICE
        policy.parent.mkdir(parents=True, exist_ok=True)
        policy.write_text('type vendor_block_device, dev_type;\n' + fixes.DTBO_DECLARATION + '\n')
        platform = self.root / fixes.PLATFORM_DEVICE
        platform.parent.mkdir(parents=True)
        platform.write_text(fixes.DTBO_DECLARATION + '\n')
        (self.root / fixes.POLICY_FILE).write_text(fixes.ISO_DECLARATION + '\n')
        lineage = self.root / fixes.LINEAGE_FILE
        lineage.parent.mkdir(parents=True)
        lineage.write_text(fixes.ISO_PLATFORM_DECLARATION + '\n')
        (self.root / fixes.ISO_GENFS).write_text(fixes.ISO_GENFS_ENTRY + '\ngenfscon rawfs / u:object_r:rawfs:s0\n')
        lineage_genfs = self.root / fixes.LINEAGE_GENFS
        lineage_genfs.parent.mkdir(parents=True)
        lineage_genfs.write_text(fixes.ISO_GENFS_ENTRY + '\n')
        (self.root / fixes.CODEC2_POLICY).write_text(fixes.CODEC2_OLD + '\n')
        sf = self.root / fixes.SF_POLICY
        sf.parent.mkdir(parents=True)
        sf.write_text('# Existing service types\n')
        audio = self.root / fixes.AUDIO_CONTEXTS
        audio.parent.mkdir(parents=True)
        audio.write_text(fixes.AUDIO_OLD + '\n')
        platform_properties = self.root / fixes.PLATFORM_PROPERTIES
        platform_properties.parent.mkdir(parents=True)
        platform_properties.write_text(fixes.AUDIO_PLATFORM + '\n')
        (self.root / fixes.SF_CONTEXTS).write_text(fixes.SF_CONTEXT + ' u:object_r:mtk_hal_sf_service:s0\n')
        (self.root / 'system/sepolicy/public/hal_omx.te').write_text(
            fixes.CODEC2_NEW.replace('mtk_hal_c2', 'hal_omx_server') + '\n')

    def test_dtbo_uses_platform_type_and_preserves_other_vendor_types(self):
        fixes.apply(self.root, 'realme6')
        policy = (self.root / fixes.POLICY_DEVICE).read_text()
        self.assertNotIn(fixes.DTBO_DECLARATION, policy)
        self.assertNotIn(fixes.ISO_DECLARATION, (self.root / fixes.POLICY_FILE).read_text())
        self.assertIn('type vendor_block_device, dev_type;', policy)
        self.assertIn('-' + fixes.DTBO_DECLARATION, (self.root / fixes.PATCH).read_text())

    def test_usb_audio_property_uses_platform_definition(self):
        fixes.apply(self.root, 'realme6')
        self.assertNotIn(fixes.AUDIO_OLD, (self.root / fixes.AUDIO_CONTEXTS).read_text())
        self.assertEqual((self.root / fixes.PLATFORM_PROPERTIES).read_text(), fixes.AUDIO_PLATFORM + '\n')

    def test_iso_genfs_uses_lineage_label_and_preserves_other_filesystems(self):
        fixes.apply(self.root, 'realme6')
        vendor = (self.root / fixes.ISO_GENFS).read_text()
        self.assertNotIn(fixes.ISO_GENFS_ENTRY, vendor)
        self.assertIn('genfscon rawfs / u:object_r:rawfs:s0', vendor)
        self.assertEqual((self.root / fixes.LINEAGE_GENFS).read_text(), fixes.ISO_GENFS_ENTRY + '\n')

    def test_different_lineage_iso_genfs_label_rejects_all_changes(self):
        (self.root / fixes.LINEAGE_GENFS).write_text('genfscon iso9660 / u:object_r:unlabeled:s0\n')
        with self.assertRaisesRegex(ValueError, 'Expected platform iso9660-genfs'):
            fixes.apply(self.root, 'realme6')
        self.assertEqual(self.target.read_text(), self.original)
        self.assertIn(fixes.ISO_GENFS_ENTRY, (self.root / fixes.ISO_GENFS).read_text())

    def test_missing_platform_audio_property_rejects_changes(self):
        (self.root / fixes.PLATFORM_PROPERTIES).write_text('')
        with self.assertRaisesRegex(ValueError, 'Expected platform'):
            fixes.apply(self.root, 'realme6')
        self.assertEqual(self.target.read_text(), self.original)

    def test_sf_declaration_matches_existing_context_without_new_allow_rules(self):
        fixes.apply(self.root, 'realme6')
        self.assertEqual((self.root / fixes.SF_POLICY).read_text(),
                         '# Existing service types\n' + fixes.SF_DECLARATION + '\n')

    def test_conflicting_sf_declaration_rejects_all_changes(self):
        (self.root / fixes.SF_POLICY).write_text('type mtk_hal_sf_service, domain;\n')
        with self.assertRaisesRegex(ValueError, 'Unexpected MediaTek SurfaceFlinger'):
            fixes.apply(self.root, 'realme6')
        self.assertEqual(self.target.read_text(), self.original)

    def test_codec2_retains_network_restrictions_with_debug_only_exception(self):
        fixes.apply(self.root, 'realme6')
        self.assertEqual((self.root / fixes.CODEC2_POLICY).read_text(), fixes.CODEC2_NEW + '\n')
        self.assertIn('userdebug_or_eng', fixes.CODEC2_NEW)
        self.assertIn('domain:{ udp_socket rawip_socket } *;', fixes.CODEC2_NEW)

    def test_unexpected_codec2_policy_rejects_all_changes(self):
        (self.root / fixes.CODEC2_POLICY).write_text('unexpected policy')
        with self.assertRaisesRegex(ValueError, 'Unexpected MediaTek Codec2'):
            fixes.apply(self.root, 'realme6')
        self.assertEqual(self.target.read_text(), self.original)
        self.assertIn(fixes.DTBO_DECLARATION, (self.root / fixes.POLICY_DEVICE).read_text())

    def test_missing_lineage_iso_type_rejects_all_changes(self):
        (self.root / fixes.LINEAGE_FILE).write_text('')
        with self.assertRaisesRegex(ValueError, 'Expected platform iso9660'):
            fixes.apply(self.root, 'realme6')
        self.assertEqual(self.target.read_text(), self.original)
        self.assertIn(fixes.DTBO_DECLARATION, (self.root / fixes.POLICY_DEVICE).read_text())

    def test_missing_platform_dtbo_type_rejects_all_changes(self):
        (self.root / fixes.PLATFORM_DEVICE).write_text('')
        with self.assertRaisesRegex(ValueError, 'Expected platform'):
            fixes.apply(self.root, 'realme6')
        self.assertEqual(self.target.read_text(), self.original)
        self.assertFalse((self.root / fixes.RECORD).exists())

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

    def test_missing_hardware_is_added_without_removing_device_packages(self):
        original_device = self.device.read_bytes()
        fixes.apply(self.root, 'realme6')
        self.assertEqual(self.device.read_bytes(), original_device)
        wrapper = self.root / 'hardware/mediatek/libwifi-hal-wrapper'
        self.assertIn('libwifi-hal-mtk.so', (wrapper / 'libwifi-hal.cpp').read_text())
        self.assertIn('/vendor/lib64/libwifi-hal-wrapper.so', (wrapper / 'libwifi-hal-wrapper.xml').read_text())
        usb = self.root / 'hardware/mediatek/aidl/usb-legacy/Android.bp'
        self.assertIn('name: "android.hardware.usb-service.mediatek-legacy"', usb.read_text())
        record = json.loads((self.root / fixes.RECORD).read_text())['fixes'][1]
        self.assertEqual(record['revision'], 'd3b422e37e83d09301efcdfc7beca4c3c9344155')
        self.assertEqual(len(record['files']), 11)
        matrix = self.root / 'hardware/mediatek/vintf/mediatek_framework_compatibility_matrix.xml'
        self.assertEqual(ET.parse(matrix).getroot().attrib['type'], 'framework')
        self.assertIn(fixes.USB_CONTEXT_LINE, self.contexts.read_text())

    def test_conflicting_hardware_source_is_not_overwritten_or_partially_applied(self):
        usb = self.root / 'hardware/mediatek/aidl/usb-legacy/Android.bp'
        usb.parent.mkdir(parents=True)
        usb.write_text('existing user implementation')
        with self.assertRaisesRegex(ValueError, 'differs from the pinned overlay'):
            fixes.apply(self.root, 'realme6')
        self.assertEqual(usb.read_text(), 'existing user implementation')
        self.assertEqual(self.target.read_text(), self.original)
        self.assertFalse((self.root / fixes.RECORD).exists())

    def test_removed_wifi_package_is_rejected(self):
        self.device.write_text('PRODUCT_PACKAGES += android.hardware.usb-service.mediatek-legacy\n')
        with self.assertRaisesRegex(ValueError, 'must retain both'):
            fixes.apply(self.root, 'realme6')
        self.assertEqual(self.target.read_text(), self.original)

    def test_conflicting_usb_label_is_not_silently_replaced(self):
        original = fixes.USB_CONTEXT_LINE.replace(fixes.USB_EXEC_CONTEXT, 'u:object_r:vendor_file:s0') + '\n'
        self.contexts.write_text(original)
        with self.assertRaisesRegex(ValueError, 'different SELinux label'):
            fixes.apply(self.root, 'realme6')
        self.assertEqual(self.contexts.read_text(), original)
        self.assertEqual(self.target.read_text(), self.original)
