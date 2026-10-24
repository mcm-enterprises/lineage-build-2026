# Realme 6 missing hardware implementations

These eleven files are copied unchanged from
https://github.com/LineageOS/android_hardware_mediatek at `lineage-21` revision
`d3b422e37e83d09301efcdfc7beca4c3c9344155`:

- `aidl/usb-legacy/`: the exact legacy USB service required by RM6785-common.
- `libwifi-hal-wrapper/`: the adapter used by Android's Wi-Fi service to load the
  vendor `libwifi-hal-mtk.so` and translate its older function table.
- `vintf/mediatek_framework_compatibility_matrix.xml`: the matrix already required
  by the device board configuration, retaining VINTF compatibility validation.

`manifest.json` records each file's SHA-256 hash and upstream revision. The
source-fix script verifies the bundle, preserves both device package entries,
and adds these files to the existing MediaTek hardware namespace. The pinned
community hardware project and its other implementations remain in use.

Upstream copyright and Apache-2.0 license notices are retained. The workflow
exports the complete local patch and source hashes with the
build artifacts.
