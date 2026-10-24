#!/usr/bin/env python3
"""Apply narrow, recorded compatibility fixes to the pinned Realme community tree."""
import difflib
import hashlib
import json
from pathlib import Path
import re
import sys

THERMAL = 'hardware/mediatek/aidl/thermal/Android.bp'
PIXELSTATS = 'hardware/google/pixel/pixelstats/Android.bp'
OLD = 'android.frameworks.stats-V1-ndk'
NEW = 'android.frameworks.stats-V2-ndk'
RECORD = '.lineage-source-fixes.json'
PATCH = '.lineage-source-fixes.patch'
OVERLAY_DIR = Path(__file__).resolve().parent / 'source_overlays' / 'realme6'
DEVICE_MK = 'device/realme/RM6785-common/RM6785.mk'
REQUIRED_PACKAGES = ('android.hardware.usb-service.mediatek-legacy', 'libwifi-hal-wrapper')
USB_CONTEXTS = 'device/realme/RM6785-common/sepolicy/vendor/file_contexts'
USB_DOMAIN = 'device/mediatek/sepolicy_vndr/basic/non_plat/mtk_hal_usb.te'
USB_EXEC = '/vendor/bin/hw/android.hardware.usb-service.mediatek-legacy'
USB_EXEC_CONTEXT = 'u:object_r:mtk_hal_usb_exec:s0'
USB_CONTEXT_LINE = r'/(vendor|system/vendor)/bin/hw/android\.hardware\.usb-service\.mediatek-legacy ' + USB_EXEC_CONTEXT


POLICY_DEVICE = 'device/mediatek/sepolicy_vndr/basic/non_plat/device.te'
PLATFORM_DEVICE = 'system/sepolicy/public/device.te'
DTBO_DECLARATION = 'type dtbo_block_device, dev_type;'
DTBO_COMMENT = '# dtbo_block_device is declared by the Android platform public policy.'


POLICY_FILE = 'device/mediatek/sepolicy_vndr/basic/non_plat/file.te'
LINEAGE_FILE = 'device/lineage/sepolicy/common/public/file.te'
ISO_DECLARATION = 'type iso9660, fs_type;'
ISO_PLATFORM_DECLARATION = 'type iso9660, sdcard_type, fs_type, mlstrustedobject;'
ISO_COMMENT = '# iso9660 is declared by the LineageOS public policy.'
ISO_GENFS = 'device/mediatek/sepolicy_vndr/basic/non_plat/genfs_contexts'
LINEAGE_GENFS = 'device/lineage/sepolicy/common/private/genfs_contexts'
ISO_GENFS_ENTRY = 'genfscon iso9660 / u:object_r:iso9660:s0'
ISO_GENFS_COMMENT = '# iso9660 filesystem labeling is supplied by the LineageOS policy.'
AUDIO_CONTEXTS = 'device/mediatek/sepolicy_vndr/basic/plat_private/property_contexts'
PLATFORM_PROPERTIES = 'system/sepolicy/private/property_contexts'
AUDIO_OLD = 'ro.audio.usb.period_us u:object_r:exported_default_prop:s0 exact int'
AUDIO_PLATFORM = 'ro.audio.usb.period_us u:object_r:audio_config_prop:s0 exact int'
AUDIO_COMMENT = '# ro.audio.usb.period_us uses the platform audio_config_prop label.'



def prepare_platform_policy(root, vendor_path, platform_path, declaration,
                            platform_declaration, comment, name,
                            reason='Use the public policy type instead of redeclaring it in vendor policy.'):
    target = root / vendor_path
    original = target.read_text()
    if (root / platform_path).read_text().splitlines().count(platform_declaration) != 1:
        raise ValueError(f'Expected platform {name} declaration; source left unchanged.')
    lines = original.splitlines()
    if lines.count(declaration) == 1 and comment not in lines:
        updated = original.replace(declaration, comment)
    elif lines.count(comment) == 1 and declaration not in lines:
        updated = original
    else:
        raise ValueError(f'Unexpected MediaTek {name} declaration layout; source left unchanged.')
    before = updated.replace(comment, declaration)
    patch = ''.join(difflib.unified_diff(before.splitlines(True), updated.splitlines(True),
                                        fromfile='a/' + vendor_path, tofile='b/' + vendor_path))
    record = dict(name='mediatek-platform-' + name + '-type', path=vendor_path,
                  reason=reason,
                  before_sha256=hashlib.sha256(before.encode()).hexdigest(),
                  after_sha256=hashlib.sha256(updated.encode()).hexdigest())
    return target, original, updated, patch, record


CODEC2_POLICY = 'device/mediatek/sepolicy_vndr/basic/non_plat/mtk_hal_c2.te'
CODEC2_OLD = 'neverallow mtk_hal_c2 domain:{ tcp_socket udp_socket rawip_socket } *;'
CODEC2_NEW = ("neverallow mtk_hal_c2 domain:{ udp_socket rawip_socket } *;\n"
              "neverallow mtk_hal_c2 { domain userdebug_or_eng(`-su') }:tcp_socket *;")


def prepare_codec2_policy(root):
    # Match the platform media HAL restriction, including its debug-only su exception.
    platform = (root / 'system/sepolicy/public/hal_omx.te').read_text()
    if CODEC2_NEW.replace('mtk_hal_c2', 'hal_omx_server') not in platform:
        raise ValueError('Expected platform media HAL network restriction; source left unchanged.')
    target = root / CODEC2_POLICY
    original = target.read_text()
    if original.count(CODEC2_OLD) == 1 and CODEC2_NEW not in original:
        updated = original.replace(CODEC2_OLD, CODEC2_NEW)
    elif CODEC2_OLD not in original and original.count(CODEC2_NEW) == 1:
        updated = original
    else:
        raise ValueError('Unexpected MediaTek Codec2 network restriction; source left unchanged.')
    before = updated.replace(CODEC2_NEW, CODEC2_OLD)
    patch = ''.join(difflib.unified_diff(before.splitlines(True), updated.splitlines(True),
                                        fromfile='a/' + CODEC2_POLICY, tofile='b/' + CODEC2_POLICY))
    record = dict(name='mediatek-codec2-debug-socket', path=CODEC2_POLICY,
                  reason='Match the platform media HAL debug-only su TCP exception; retain production network restrictions.',
                  before_sha256=hashlib.sha256(before.encode()).hexdigest(),
                  after_sha256=hashlib.sha256(updated.encode()).hexdigest())
    return target, original, updated, patch, record


SF_POLICY = 'device/mediatek/sepolicy_vndr/bsp/plat_private/service.te'
SF_CONTEXTS = 'device/mediatek/sepolicy_vndr/bsp/plat_private/service_contexts'
SF_DECLARATION = 'type mtk_hal_sf_service, service_manager_type;'
SF_CONTEXT = 'vendor.mediatek.framework.mtksf_ext.IMtkSF_ext/default'


def prepare_sf_policy(root):
    contexts = [line.split() for line in (root / SF_CONTEXTS).read_text().splitlines()]
    if [SF_CONTEXT, 'u:object_r:mtk_hal_sf_service:s0'] not in contexts:
        raise ValueError('Expected MediaTek SurfaceFlinger service context; source left unchanged.')
    target = root / SF_POLICY
    original = target.read_text()
    declarations = re.findall(r'^type mtk_hal_sf_service[^;]*;', original, re.M)
    if not declarations:
        if not original.endswith('\n'):
            raise ValueError('Expected newline-terminated MediaTek service policy; source left unchanged.')
        updated = original + SF_DECLARATION + '\n'
    elif declarations == [SF_DECLARATION] and original.endswith(SF_DECLARATION + '\n'):
        updated = original
    else:
        raise ValueError('Unexpected MediaTek SurfaceFlinger service declaration; source left unchanged.')
    before = updated.removesuffix(SF_DECLARATION + '\n')
    patch = ''.join(difflib.unified_diff(before.splitlines(True), updated.splitlines(True),
                                        fromfile='a/' + SF_POLICY, tofile='b/' + SF_POLICY))
    record = dict(name='mediatek-surfaceflinger-service-type', path=SF_POLICY,
                  reason='Restore the upstream type for the existing MediaTek SurfaceFlinger service label.',
                  upstream='https://github.com/LineageOS/android_device_mediatek_sepolicy_vndr',
                  revision='9d3404ed69414981622155625b06a58ba544f798',
                  before_sha256=hashlib.sha256(before.encode()).hexdigest(),
                  after_sha256=hashlib.sha256(updated.encode()).hexdigest())
    return target, original, updated, patch, record


def prepare_usb_policy(root):
    domain = (root / USB_DOMAIN).read_text()
    if 'type mtk_hal_usb_exec,' not in domain or 'init_daemon_domain(mtk_hal_usb)' not in domain:
        raise ValueError('Expected existing MediaTek USB execution domain; refusing to guess SELinux policy.')
    target = root / USB_CONTEXTS
    original = target.read_text()
    block = '\n# Legacy MediaTek USB AIDL service\n' + USB_CONTEXT_LINE + '\n'
    if original.count(block) > 1:
        raise ValueError('Duplicate legacy USB execution labels; source left unchanged.')
    matches = []
    for line in original.splitlines():
        fields = line.split('#', 1)[0].split()
        if len(fields) >= 2 and re.fullmatch(fields[0], USB_EXEC):
            matches.append(fields[-1])
    if any(context != USB_EXEC_CONTEXT for context in matches):
        raise ValueError('Legacy USB executable already has a different SELinux label; source left unchanged.')
    before = original.replace(block, '', 1)
    updated = original if matches else original + block
    patch = ''.join(difflib.unified_diff(before.splitlines(True), updated.splitlines(True),
                                        fromfile='a/' + USB_CONTEXTS, tofile='b/' + USB_CONTEXTS))
    record = dict(name='mediatek-usb-execution-label', path=USB_CONTEXTS,
                  reason='Run the restored legacy USB service in the existing MediaTek USB domain.',
                  upstream='https://github.com/LineageOS/android_device_mediatek_sepolicy_vndr',
                  revision='9d3404ed69414981622155625b06a58ba544f798',
                  before_sha256=hashlib.sha256(before.encode()).hexdigest(),
                  after_sha256=hashlib.sha256(updated.encode()).hexdigest())
    return target, original, updated, patch, record


def prepare_hardware_overlay(root):
    """Validate all bundled modules and existing files before modifying the tree."""
    packages = (root / DEVICE_MK).read_text().split()
    if any(name not in packages for name in REQUIRED_PACKAGES):
        raise ValueError('RM6785 must retain both the legacy USB service and Wi-Fi wrapper in PRODUCT_PACKAGES.')
    metadata = json.loads((OVERLAY_DIR / 'manifest.json').read_text())
    files = []
    patches = []
    for relative, expected_hash in sorted(metadata['files'].items()):
        content = (OVERLAY_DIR / relative).read_bytes()
        if hashlib.sha256(content).hexdigest() != expected_hash:
            raise ValueError(f'Bundled hardware source checksum mismatch: {relative}')
        target = root / relative
        if target.exists() and target.read_bytes() != content:
            raise ValueError(f'Existing hardware source differs from the pinned overlay: {relative}. Source left unchanged.')
        files.append((target, content))
        patches.append(''.join(difflib.unified_diff(
            [], content.decode().splitlines(True), fromfile='/dev/null', tofile='b/' + relative)))
    record = dict(name='mediatek-usb-wifi-implementations',
                  reason='Supply the required USB service, Wi-Fi wrapper and MediaTek compatibility matrix without removing packages.',
                  upstream=metadata['upstream'], revision=metadata['revision'], files=metadata['files'])
    return files, ''.join(patches), record


def apply(directory, profile):
    if profile == 'pixel':
        return
    if profile != 'realme6':
        raise ValueError(f'Unknown source-fix profile: {profile}')
    root = Path(directory)
    target = root / THERMAL
    original = target.read_text()
    pixelstats = (root / PIXELSTATS).read_text()
    if ('name: "android.hardware.thermal-service.mediatek"' not in original or
            '"libpixelstats"' not in original):
        raise ValueError('Unexpected MediaTek thermal module; refusing to modify source.')
    if (NEW not in pixelstats or OLD in pixelstats or
            not (root / 'frameworks/hardware/interfaces/stats/aidl/aidl_api/android.frameworks.stats/2').is_dir()):
        raise ValueError('Expected Pixel stats V2 dependencies and frozen stats V2 API; refusing to guess an interface version.')
    if original.count(OLD) == 2 and NEW not in original:
        updated = original.replace(OLD, NEW)
    elif OLD not in original and original.count(NEW) == 2:
        updated = original
    else:
        raise ValueError('Unexpected MediaTek thermal stats dependencies; expected exactly two V1 or two V2 references. Source left unchanged.')
    overlay_files, overlay_patch, overlay_record = prepare_hardware_overlay(root)
    policy_target, policy_original, policy_updated, policy_patch, policy_record = prepare_usb_policy(root)
    policy_fixes = [
        prepare_platform_policy(root, POLICY_DEVICE, PLATFORM_DEVICE, DTBO_DECLARATION,
                                DTBO_DECLARATION, DTBO_COMMENT, 'dtbo'),
        prepare_platform_policy(root, POLICY_FILE, LINEAGE_FILE, ISO_DECLARATION,
                                ISO_PLATFORM_DECLARATION, ISO_COMMENT, 'iso9660'),
        prepare_platform_policy(root, ISO_GENFS, LINEAGE_GENFS, ISO_GENFS_ENTRY,
                                ISO_GENFS_ENTRY, ISO_GENFS_COMMENT, 'iso9660-genfs',
                                reason='Use the identical LineageOS filesystem label without a duplicate vendor genfs entry.'),
        prepare_codec2_policy(root),
        prepare_sf_policy(root),
        prepare_platform_policy(root, AUDIO_CONTEXTS, PLATFORM_PROPERTIES, AUDIO_OLD,
                                AUDIO_PLATFORM, AUDIO_COMMENT, 'usb-audio-period'),
    ]
    # Canonical before/after retain a complete diff on repeated builds, including
    # a sync that restored the original pinned Android.bp.
    before = updated.replace(NEW, OLD)
    patch = ''.join(difflib.unified_diff(before.splitlines(True), updated.splitlines(True),
                                        fromfile='a/' + THERMAL, tofile='b/' + THERMAL)) + overlay_patch + policy_patch + ''.join(item[3] for item in policy_fixes)
    record = dict(profile=profile, fixes=[dict(
        name='mediatek-thermal-stats-v2', path=THERMAL,
        reason='Match libpixelstats and libpixelstatsatoms stats AIDL V2 dependencies.',
        before_sha256=hashlib.sha256(before.encode()).hexdigest(),
        after_sha256=hashlib.sha256(updated.encode()).hexdigest())])
    record['fixes'].append(overlay_record)
    record['fixes'].append(policy_record)
    record['fixes'].extend(item[4] for item in policy_fixes)
    if updated != original:
        # Same filesystem atomic replacement avoids a half-written blueprint.
        temporary = target.with_suffix('.bp.lineage-tmp')
        temporary.write_text(updated)
        temporary.chmod(target.stat().st_mode & 0o777)
        temporary.replace(target)
    for destination, content in overlay_files:
        if not destination.exists():
            destination.parent.mkdir(parents=True, exist_ok=True)
            temporary = destination.with_name(destination.name + '.lineage-tmp')
            temporary.write_bytes(content)
            temporary.replace(destination)
    if policy_updated != policy_original:
        temporary = policy_target.with_name(policy_target.name + '.lineage-tmp')
        temporary.write_text(policy_updated)
        temporary.chmod(policy_target.stat().st_mode & 0o777)
        temporary.replace(policy_target)
    for policy_file, policy_before, policy_after, _, _ in policy_fixes:
        if policy_after != policy_before:
            temporary = policy_file.with_name(policy_file.name + '.lineage-tmp')
            temporary.write_text(policy_after)
            temporary.chmod(policy_file.stat().st_mode & 0o777)
            temporary.replace(policy_file)
    (root / PATCH).write_text(patch)
    (root / RECORD).write_text(json.dumps(record, indent=2) + '\n')
    print('Source compatibility: MediaTek thermal stats dependencies aligned with libpixelstats (V2).')
    print('Source compatibility: pinned USB legacy service and Wi-Fi wrapper verified; device packages preserved.')
    print('Source compatibility: legacy USB executable mapped to the existing MediaTek USB SELinux domain.')
    print('Source compatibility: redundant MediaTek DTBO and iso9660 types replaced by public policy declarations.')
    print('Source compatibility: duplicate MediaTek iso9660 filesystem label replaced by the identical LineageOS definition.')
    print('Source compatibility: Codec2 network restriction aligned with the platform debug-only su socket exception.')
    print('Source compatibility: missing upstream MediaTek SurfaceFlinger service type restored.')
    print('Source compatibility: duplicate USB audio property label replaced by the platform definition.')
    print(f'Source modification record: {root / RECORD}')


if __name__ == '__main__':
    try:
        apply(*sys.argv[1:])
    except (OSError, ValueError) as error:
        sys.exit(f'Cannot apply source compatibility fix: {error}')
