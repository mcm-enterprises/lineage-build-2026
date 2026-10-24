# Realme 6 RMX2001 community build profile

Select `--profile realme6` for a LineageOS 21.0 (Android 14) build targeting
`RMX2001L1`. That product name is defined by the community device tree; it is not
a replacement for the phone's model number, RMX2001.

The local manifest pins the following `lineage-21` snapshots, inspected on
October 14, 2026. Pinning keeps dependencies from silently changing between syncs.

| Source | Checkout path | Verified revision |
| --- | --- | --- |
| [Device](https://github.com/realme-mt6785-devs/android_device_realme_RMX2001L1) | device/realme/RMX2001L1 | e409983a594e7ed13295682c0e8077a5db343702 |
| [Shared configuration](https://github.com/realme-mt6785-devs/android_device_realme_RM6785-common) | device/realme/RM6785-common | 1877f586573c3bf9e05e8e0123224c4326a43541 |
| [Kernel](https://github.com/realme-mt6785-devs/android_kernel_realme_mt6785) | kernel/realme/mt6785 | 1c7f84704726fc608340abd1647adc4d837b19c6 |
| [Vendor blobs](https://github.com/realme-mt6785-devs/proprietary_vendor_realme_RM6785-common) | vendor/realme/RM6785-common | 3259c12a0542ccbcd1701e1f8b47980ea0846f35 |
| [MediaTek hardware](https://github.com/realme-mt6785-devs/android_hardware_mediatek-old) | hardware/mediatek | d4f2080e8761d92c76706c2512e67eda91bf7c80 |
| [MediaTek SELinux policy](https://github.com/realme-mt6785-devs/android_device_mediatek_sepolicy_vndr-old) | device/mediatek/sepolicy_vndr | b2e91057424be1cc8e87aee1dadc9ffd80bdf330 |

The product inherits RM6785-common, whose board configuration specifies the mt6785
kernel and `RM6785_defconfig` (confirmed present). Its device makefile imports the
common vendor makefile and MediaTek hardware namespaces; its board configuration
imports the MediaTek SELinux policy. Those dependencies are included explicitly,
because this community tree does not provide a `lineage.dependencies` file.

The community source branch is `lineage-21`, while the official Android manifest
branch is `lineage-21.0`. The build profile uses the latter for repo init and the
pinned community revisions for the device dependencies. It does not pair old
Realme device files with the Pixel profile's Android 15 base.

This is an unofficial candidate build configuration. Source inspection and mocked
workflow tests do not establish compile success or working camera, modem, encryption,
recovery or boot. Firmware baseline and regional compatibility are not established:
the device product overrides reference RMX2002 Android 11 firmware, and the common
board configuration declares vendor security patch 2022-05-05. Follow the original
maintainer's device/firmware requirements before testing on an RMX2001. No firmware
installation or phone flashing is performed by these scripts.

If extracting your own blobs instead of using the pinned vendor project, use the
matched device/common extraction scripts and the firmware they expect. Do not copy
similarly named blobs from another phone or from the Pixel reference output.

## Commands

Before compilation, `scripts/source_fixes.py` aligns the MediaTek thermal
service's two `android.frameworks.stats-V1-ndk` references with V2, which the
LineageOS 21 Pixel stats libraries use. It checks the expected thermal dependency
layout, Pixel stats version and frozen V2 API before changing the file. The fix
is idempotent and leaves the thermal HAL's own V1 interface unchanged.

The pinned community hardware tree lacks two implementations and a compatibility
matrix required by its device configuration. The workflow adds the legacy USB
service, Wi-Fi HAL wrapper and MediaTek framework compatibility matrix
from LineageOS's `lineage-21` hardware revision
`d3b422e37e83d09301efcdfc7beca4c3c9344155`. Their source files are bundled under
`scripts/source_overlays/realme6/` with provenance and SHA-256 hashes. The Wi-Fi
wrapper loads the existing vendor `libwifi-hal-mtk.so`; both original USB and
Wi-Fi package entries are required and preserved. Conflicting existing module
sources cause a clear failure instead of being overwritten.

The legacy USB executable is also labelled for the existing `mtk_hal_usb` SELinux
domain, matching LineageOS 21 MediaTek policy revision
`9d3404ed69414981622155625b06a58ba544f798`. This adds the missing executable label
without changing allow rules or making SELinux permissive. The Wi-Fi policy
already matches the upstream implementation.

The compatibility script also removes the redundant `dtbo_block_device`
and `iso9660` types from the MediaTek vendor policy. Android 14 declares the
DTBO type and LineageOS declares the ISO filesystem type in public policy;
retaining both declarations stops `checkpolicy` during compilation. The fix
checks that the public declarations exist and preserves the vendor allow rules.
It also removes the duplicate MediaTek `iso9660` filesystem label after verifying
that LineageOS supplies the identical `genfscon` entry. This lets recovery policy
compile while preserving the filesystem's SELinux context.

The Codec2 network restriction is also aligned with the platform OMX policy:
UDP/raw sockets stay forbidden, and TCP stays forbidden except for `su` on
userdebug/eng builds. This resolves the conflict with the platform's debug-only
Binder socket permission without adding allow rules or bypassing neverallow checks.

The missing `mtk_hal_sf_service` declaration is restored from LineageOS policy
revision `9d3404ed69414981622155625b06a58ba544f798`, matching its existing
SurfaceFlinger extension service context. This adds only the service type.

The duplicate `ro.audio.usb.period_us` property context is removed from the
MediaTek system extension policy so Android's `audio_config_prop` label applies.
The script verifies that the platform's exact integer property definition exists.

The pinned source manifest describes upstream commits. Local compatibility changes
are recorded separately in `.lineage-source-fixes.json` and
`.lineage-source-fixes.patch` inside the source tree. Successful builds export
these as `source-fixes.json` and `source-fixes.patch` alongside the ROM and source
manifest so the modified sources can be reproduced. An unexpected dependency
layout fails before compilation instead of applying a broad version replacement.

```bash
./build-lineage.sh --profile realme6 check
./build-lineage.sh --profile realme6 sync
./build-lineage.sh --profile realme6 build
# Or run the complete workflow in Docker:
./bootstrap_docker.sh --profile realme6 --action all
```

Native outputs are under `zips/realme6/lineage-21.0/`; Docker outputs are under
`docker_source/realme6/zips/`. A successful workflow requires a new or updated
`lineage-*-RMX2001L1.zip`; it will not export a Pixel ZIP as a Realme result.
