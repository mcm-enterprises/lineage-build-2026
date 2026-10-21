#!/usr/bin/env python3
"""Apply narrow, recorded compatibility fixes to the pinned Realme community tree."""
import difflib
import hashlib
import json
from pathlib import Path
import sys

THERMAL = 'hardware/mediatek/aidl/thermal/Android.bp'
PIXELSTATS = 'hardware/google/pixel/pixelstats/Android.bp'
OLD = 'android.frameworks.stats-V1-ndk'
NEW = 'android.frameworks.stats-V2-ndk'
RECORD = '.lineage-source-fixes.json'
PATCH = '.lineage-source-fixes.patch'


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
    # Canonical before/after retain a complete diff on repeated builds, including
    # a sync that restored the original pinned Android.bp.
    before = updated.replace(NEW, OLD)
    patch = ''.join(difflib.unified_diff(before.splitlines(True), updated.splitlines(True),
                                        fromfile='a/' + THERMAL, tofile='b/' + THERMAL))
    record = dict(profile=profile, fixes=[dict(
        name='mediatek-thermal-stats-v2', path=THERMAL,
        reason='Match libpixelstats and libpixelstatsatoms stats AIDL V2 dependencies.',
        before_sha256=hashlib.sha256(before.encode()).hexdigest(),
        after_sha256=hashlib.sha256(updated.encode()).hexdigest())])
    if updated != original:
        # Same filesystem atomic replacement avoids a half-written blueprint.
        temporary = target.with_suffix('.bp.lineage-tmp')
        temporary.write_text(updated)
        temporary.chmod(target.stat().st_mode & 0o777)
        temporary.replace(target)
    (root / PATCH).write_text(patch)
    (root / RECORD).write_text(json.dumps(record, indent=2) + '\n')
    print('Source compatibility: MediaTek thermal stats dependencies aligned with libpixelstats (V2).')
    print(f'Source modification record: {root / RECORD}')


if __name__ == '__main__':
    try:
        apply(*sys.argv[1:])
    except (OSError, ValueError) as error:
        sys.exit(f'Cannot apply source compatibility fix: {error}')
