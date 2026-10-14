# Build analysis

Reviewed main at d832042ffcad37aeec4d3e746981e689d96d6bfa (commit), October 14, 2026.

| Finding | Consequence | Implemented change |
| --- | --- | --- |
| Docker writes `.repo/local_manifests` before checking whether `.repo` exists | A fresh run always skips `repo init` | Run idempotent init before installing the manifest; test a partial `.repo` directory |
| README calls a root-level script that only exists in `archive/` | Documented native command cannot run | Document and share `build-lineage.sh` across host and Docker |
| Docker selects 23.0; native/manifest select 22.1 | Source, device and blobs can come from incompatible releases | Support one verified 22.1 configuration; reject other branches/old manifests |
| Local manifest splits husky/shiba into separate device repos | Does not match upstream 22.1's shusky device layout | Follow shusky → zuma → gs101 → gs-common dependencies and shusky kernel remote |
| Docker requests an unavailable TheMuppets zuma repository/branch | Sync retries cannot repair a bad repository definition | Use only the matching husky vendor project |
| Native script mounts hardcoded images, ignores mount errors and copies blobs by basename | Can select wrong partitions/versions, miss hashed entries and leave incomplete vendor output | Remove rescue logic; validate matched vendor build files, copy sources and LFS downloads |
| Native script lacks fail-fast handling for breakfast | Build can continue with an invalid configuration | Propagate failed init, sync, breakfast, compilation and artifact export |
| Retry loop deletes every `.lock` and force-syncs 100 times | Can disrupt active Git operations and obscure permanent failures | Source-directory flock, bounded retries, no force-sync/lock deletion |
| Docker chowns source/home but not ZIP output; UID/GID fallbacks assume group name builder | Unprivileged build may fail to export results | Host-created writable mounts and build-time numeric UID/GID mapping |
| ZIP move errors are ignored | Container can report success without usable artifacts | Require new/changed ZIP, copy artifacts, export checksum and pinned manifest |
| All CPU threads used; Docker fixed at 24 GiB; ccache configured inconsistently | RAM pressure and unpredictable cache behavior | Conservative memory-aware jobs, no arbitrary cap, cache disabled consistently |
| Host setup fetches legacy DEBs over HTTP and globally trusts every Git directory | Fragile package installation and unnecessary global configuration | Ubuntu 22.04 packages or Docker; fail-aware HTTPS repo download; no global safe.directory wildcard |
| Native script fakes date and globally disables AppArmor user namespace restriction | Hides source/host mismatch and changes host policy | Use branch defaults; keep host policy intact; document specific sandbox troubleshooting |
| Redirected logs directory may not exist; reset docs target 23.0 and broadly kill Python | Launch can fail before the script starts; recovery affects unrelated tasks | Correct log creation, stage-based resume, scoped Docker stop, no automatic deletion |

Upstream checks through GitHub confirmed LineageOS 22.1 shusky dependencies, product
makefile and Python extraction entry point, plus TheMuppets husky's 22.1 branch/vendor
makefile. TheMuppets zuma 22.1 returned 404. The manifest kernel remote/revision comes
from LineageOS `snippets/pixel.xml`; that Googlesource repository was not downloaded here.

Validation here uses offline integration tests, Bash syntax, XML parsing and Compose
configuration validation. The environment has about 30 GiB free disk, 10 GiB RAM, no
swap, an unreachable shell HTTP proxy, and an inaccessible Docker daemon socket.
Consequently neither the Ubuntu image build nor a full source sync/Android compilation
was run here. CI adds an actual Docker image build and tool smoke check. A full compile
and device boot test remain necessary before treating any generated image as usable.

## Separate Pixel reference and Realme 6 builds

The workflow now selects `pixel` (husky / lineage-22.1) or `realme6`
(RMX2001L1 / lineage-21.0). Profile configuration controls target, manifest and
vendor layout. Native sources/logs/outputs and Docker projects/volumes are isolated;
a source profile marker rejects reuse across devices. Manifest validation accepts
only the exact selected profile manifest. Artifact matching checks the target
suffix so a ZIP from another device cannot be reported as the selected build.

Realme dependencies were inspected and pinned from the community lineage-21 source
set, including device/common configuration, kernel defconfig, vendor build files,
MediaTek hardware and policy. See REALME6.md for revisions and firmware limitations.
Offline tests verify both targets and default path isolation; CI validates both
Compose configurations and Docker entry points. Neither full Android compilation
nor Realme phone testing has been completed in this environment.

Sync now probes small remote refs before the large download, saves one log per
attempt, prints error lines and retries serially after the first failure. Partial
downloads remain reusable. `check-network` skips the fresh-tree disk budget so
connectivity can be diagnosed on a small machine. CI tests actual repo init for
both bases as well as remote availability; full repo sync remains untested.

## Docker Desktop on macOS / M4 with 16 GB RAM

Sources now live in separate Linux named volumes rather than macOS bind mounts.
The image seeds source-directory ownership for the host's numeric UID/GID; CI tests
a macOS-style 501:20 user and an actual named-volume filesystem probe. Compose fixes
the platform to linux/amd64 for the Android prebuilts. macOS launches default to
sync with two workers; explicit actions allow staged network checks and builds.
Docker Desktop VM disk/RAM allocations are distinct from host capacity. Apple
Silicon emulation and full ROM compilation on 16 GB physical RAM remain unverified.
