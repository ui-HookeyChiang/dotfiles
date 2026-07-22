---
name: ubiquiti-debbox-fw-build
description: >-
  Build firmware .bin images using the debbox build system (NOT debfactory .deb packages).
  Use this skill whenever the task involves: building firmware images or .bin files for any
  Ubiquiti device; setting up or troubleshooting debbox Docker build containers
  (extra/docker-util/debbox setup/enter/clean); creating git worktrees for firmware builds;
  configuring or modifying kernel configs (menuconfig, target/kernel/configs/); customizing
  package lists or HAS_* feature flags (conf/package/package.list); understanding debbox
  configuration hierarchy (conf/arch, conf/platform, conf/product-base, conf/product);
  firmware signing with AWS Lambda (uicli, firmware-prod profile, ubnt-mkfwimage);
  validating firmware before deploy (MD5 checksum);
  deploying firmware to devices (see ubiquiti-debbox-fw-deploy); targeting any platform
  or SoC (rtd1619, alpine, ipq5322, ipq9574, ipq5018, cn10k, cn9670, qcs8550, apq8053,
  cascadelake, mt7622, ampere); building for any product (UNAS, UNAS4, UNAS Pro, ENAS,
  UNVR, UNVR Pro, UNVR AI, UDW, UDW Pro, UDM, UDM Pro, UDM Beast, UXG, UXG Pro, UXG Lite,
  UCG, UCG Industrial, UCK, UCK AI, UDR, UEX, ENVR); running make targets like
  target-kernel, target-image, bootstrap, reprepro-repository; troubleshooting bootstrap
  dependency failures, stale rootfs, expired AWS STS credentials, or container issues;
  understanding the build flow (kernel compile, rootfs bootstrap, squashfs, boot image,
  image-layout, firmware packing and signing); building multiple products in parallel
  (concurrent builds, parallel-build.sh, --share-dl, --seed-from, dl/ race avoidance,
  hardlink-seed mode, multi-worktree builds); or working with the debbox repository
  (github.com/ubiquiti/debbox) in any capacity.
argument-hint: "<product> [--worktree|--docker] | parallel-build.sh [--share-dl|--seed-from <dir>|--no-seed] [--bypass-aws] <product>:<wt>..."
test-devices: local
landing-group: build
---

# Building Firmware with debbox

debbox assembles Debian packages (from debfactory), kernel, root filesystem, bootloader, and updater into signed firmware images (.bin) for Ubiquiti devices.

**Repository:** https://github.com/ubiquiti/debbox

## Path Resolution

**Prerequisite:** Run `ubiquiti-path-resolution` to detect and register repo paths.

```bash
DEBBOX_DIR=$(ubiquiti-path-resolution/scripts/resolve-path.sh debbox)
```

## Quick Start

**Always use a git worktree** for builds to keep the main checkout clean and enable
concurrent builds for different products/versions.

```bash
# 0. Find the correct container name. The Debian distro it runs MUST match
#    the requirement in conf/arch/debian-arm64 (BuildHost/Debian/require,N,arm64
#    — N=11 bullseye / 12 bookworm / 13 trixie). master tracks the latest dist;
#    a stale container yields `Build host requires Debian X.x arm64. Stop.`
REQUIRED_VER=$(grep -oE 'BuildHost/Debian/require,[0-9]+' conf/arch/debian-arm64 | grep -oE '[0-9]+$')
case "$REQUIRED_VER" in 11) DIST=bullseye;; 12) DIST=bookworm;; 13) DIST=trixie;; esac
CONTAINER=$(docker ps --filter "name=$(whoami)-debbox-builder" --format "{{.Names}}" \
    | grep -E -- "${DIST}-arm64-debbox$" | head -1)
echo "Using container: $CONTAINER (Debian $REQUIRED_VER / $DIST)"
# If empty, start one: extra/docker-util/debbox setup arch=arm64 dist=$DIST

# 0. Verify AWS credentials BEFORE starting (avoid mid-build failure)
docker exec -u $(id -u):$(id -g) $CONTAINER \
    bash -lc "aws --profile firmware-prod lambda invoke --function-name signer --invocation-type DryRun /dev/null"
# Expected: {"StatusCode": 204}
# If expired: run uicli authorize + uicli aws -a firmware-prod save (see AWS Signing Setup)

# 1. Set up Docker build container (one-time)
extra/docker-util/debbox setup

# 2. Create a worktree for the build
mkdir -p .worktrees
git worktree add .worktrees/<name> <tag-or-branch>

# 2a. Single-build mode: each worktree gets its own dl/ (no sharing). Safe by default.
#     For parallel builds across worktrees, see "Concurrent Builds" below — sharing
#     dl/ via symlink is UNSAFE while builds run in parallel (md5 race, see references/parallel-build.md).

# 3. Build inside the Docker container, pointing to the worktree
docker exec -u $(id -u):$(id -g) -w $(pwd)/.worktrees/<name> $CONTAINER \
    bash -lc "make PRODUCT=<product> all"
```

**Output:** `.worktrees/<name>/build/target-<product>/dist/<FW_VERSION>.bin`

### Example: Build UNAS from stable/5.0

```bash
# Find container
CONTAINER=$(docker ps --filter "name=debbox-builder" --format "{{.Names}}" | grep arm64 | head -1)

# Create worktree from stable branch
mkdir -p .worktrees
git worktree add .worktrees/unas-stable-5.0 origin/stable/5.0

# Build
docker exec -u $(id -u):$(id -g) -w $(pwd)/.worktrees/unas-stable-5.0 $CONTAINER \
    bash -lc "make PRODUCT=unas.rtd1619 all"

# Deploy to device — see ubiquiti-debbox-fw-deploy for full deploy + verify flow

# Cleanup when done
git worktree remove .worktrees/unas-stable-5.0
```

### Concurrent Builds

> ⚠️ **dl/ race condition**: debbox download primitives (`include/utils.mk` —
> `File/download/md5check`, `Files/git/clonecache`) have **no flock protection**.
> Two parallel `make` runs targeting the same `dl/` will both `wget -O <same-file>`,
> truncate each other's output, fail md5 verification (`exit 9`, file deleted),
> and loop forever. **Symlinking dl/ across worktrees is unsafe during parallel builds.**

Two safe modes — pick one:

**Mode 1 — Independent dl/ per worktree (simplest, safe by default)**
Each worktree downloads its own copy. Disk cost: ~150MB kernel tarball + ~500MB
package debs **per worktree**, but zero contention.

```bash
# Build UNAS and UNVR in parallel — separate dl/ per worktree
mkdir -p .worktrees
git worktree add .worktrees/unas-stable-5.0 origin/stable/5.0
git worktree add .worktrees/unvr-stable-5.0 origin/stable/5.0
# Do NOT symlink dl/ — let each worktree own its cache.

docker exec -u $(id -u):$(id -g) -w $(pwd)/.worktrees/unas-stable-5.0 $CONTAINER \
    bash -lc "make PRODUCT=unas.rtd1619 all" &
docker exec -u $(id -u):$(id -g) -w $(pwd)/.worktrees/unvr-stable-5.0 $CONTAINER \
    bash -lc "make PRODUCT=unvr4.alpine all" &
wait
```

**Mode 2 — Shared dl/ with serial prefetch (disk-efficient)**
Run one worktree's download phase first to warm the shared `dl/`, *then* fork
parallel `make all` runs. The downloads are idempotent once the file exists +
md5 matches, so subsequent builds skip the wget entirely (no race).

```bash
mkdir -p dl
git worktree add .worktrees/unas-stable-5.0 origin/stable/5.0
git worktree add .worktrees/unvr-stable-5.0 origin/stable/5.0
ln -sfn $(pwd)/dl .worktrees/unas-stable-5.0/dl
ln -sfn $(pwd)/dl .worktrees/unvr-stable-5.0/dl

# Phase 1 — Serial prefetch (each product warms shared dl/ in turn).
# Run BOTH products serially so every kernel tarball + tool tarball + package
# .deb is in dl/ before any parallel make runs. The target list below covers
# kernel/tool downloads but not target-image's DEB_DLPKGS — for that, run a
# full `make all` for the *first* product serially before forking the rest.
docker exec -u $(id -u):$(id -g) -w $(pwd)/.worktrees/unas-stable-5.0 $CONTAINER \
    bash -lc "make PRODUCT=unas.rtd1619 host-tools target-kernel target-tools target-updater"
docker exec -u $(id -u):$(id -g) -w $(pwd)/.worktrees/unvr-stable-5.0 $CONTAINER \
    bash -lc "make PRODUCT=unvr4.alpine host-tools target-kernel target-tools target-updater"

# Phase 2a — Build first product to completion serially (populates package debs in dl/)
docker exec -u $(id -u):$(id -g) -w $(pwd)/.worktrees/unas-stable-5.0 $CONTAINER \
    bash -lc "make PRODUCT=unas.rtd1619 all"

# Phase 2b — Now dl/ is fully hot; remaining products run in parallel safely
docker exec -u $(id -u):$(id -g) -w $(pwd)/.worktrees/unvr-stable-5.0 $CONTAINER \
    bash -lc "make PRODUCT=unvr4.alpine all" &
wait
```

**Mode 3 — Hardlink-seed from existing dl/ (fastest, recommended)**
If you already have a populated `dl/` from prior single-product builds (typical
debbox dev setup: 10-15 GB cache), pre-populate each parallel worktree's `dl/`
via hardlink. Zero copy, zero extra disk, zero race (hardlinks share the same
inode so `[ -f X ]` is always true → utils.mk:21 skips the wget entirely).

```bash
# Worktrees use independent dl/ paths but hardlinks point at the same bytes
# as the main dl/. utils.mk's md5 check passes because the file already exists.
# NOTE: this minimal teaching form uses bash glob `dl/*`, which (by default)
# skips dotfiles — that's how `.mark.prepared` (a Makefile build sentinel,
# NOT a download artifact) stays out of the worktree by accident. The
# wrapper `scripts/parallel-build.sh` makes the exclusion explicit via
# `find -maxdepth 1 -type f ! -name '.mark.*'` for robustness.
mkdir -p dl
git worktree add .worktrees/unas-stable-5.1 origin/stable/5.1
git worktree add .worktrees/unaspro-stable-5.1 origin/stable/5.1
mkdir -p .worktrees/unas-stable-5.1/dl .worktrees/unaspro-stable-5.1/dl
for wt in unas-stable-5.1 unaspro-stable-5.1; do
    for f in dl/*; do
        [[ -f "$f" ]] && [[ ! -e ".worktrees/$wt/dl/$(basename $f)" ]] \
            && ln "$f" ".worktrees/$wt/dl/$(basename $f)"
    done
done

# Now build in parallel — most downloads hit hardlinked cache, only stale debs re-fetch
docker exec ... -w .worktrees/unas-stable-5.1 ... "make PRODUCT=unas.rtd1619 all" &
docker exec ... -w .worktrees/unaspro-stable-5.1 ... "make PRODUCT=unas-pro.alpine all" &
wait
```

**Wrapper script** (`scripts/parallel-build.sh`) automates all three modes:
- Mode 1 (default): per-worktree dl/, race-free, disk-heavy
- Mode 2 (`--share-dl`): symlink + serial prefetch + serial first build
- Mode 3 (`--seed-from <dir>`): hardlink-seed from main dl/, fastest
- Mode 1 (explicit): `--no-seed` forces empty dl/ per worktree (cold-cache builds, smoke tests)
- AWS-less: `--bypass-aws` skips DryRun pre-flight + exports BYPASS_AWS=y (signing still attempted)

See [references/parallel-build.md](references/parallel-build.md) for the
race analysis, recovery procedure, and trade-offs between modes.

## Version Management

`PRODUCT_VERSION` is a **privileged variable** defined in `conf/arch/version` and managed
by release branches/tags. Do NOT override it on the command line.

- **Stable branches** follow the pattern `stable/<major.minor>` (e.g., `stable/5.0`)
- **Release tags** follow the pattern `<product-family>/v<version>` (e.g., `unifi-nas/v5.0.12`)
- The version in `conf/arch/version` on that branch/tag is already set correctly
- **Prefer building from stable branch head** over old tags — old tags may have
  dependency conflicts with current external apt repositories

### Tag Naming by Product Family

| Product Family | Tag Prefix | Example |
|----------------|------------|---------|
| UNAS, UNAS4 | `unifi-nas/` | `unifi-nas/v5.0.12` |
| UNAS Pro | `unifi-naspro4/` | `unifi-naspro4/v5.0.12` |
| Enterprise NAS | `enterprise-nas/` | `enterprise-nas/v5.0.12` |
| UNVR, UNVR Pro | `unifi-nvr/` | `unifi-nvr/v5.0.12` |
| UDM, UDM Pro | `unifi-dream/` | `unifi-dream/v5.0.12` |
| UCK | `unifi-cloudkey/` | `unifi-cloudkey/v5.0.12` |

To discover tags for a version: `git tag -l "*<version>*"`

## AWS Signing Setup

The build requires AWS credentials to sign firmware via a Lambda function.
The Docker container sets `ENV AWS_PROFILE firmware-prod`.

### Setup with uicli (required)

```bash
# 1. Get JWT token from https://home.uidev.tools (browser login)

# 2. Authorize uicli inside the build container
docker exec -u $(id -u):$(id -g) <container> \
    bash -lc 'uicli authorize --token="<JWT>"'

# 3. Save AWS credentials (creates firmware-prod profile in ~/.aws/credentials)
docker exec -u $(id -u):$(id -g) <container> \
    bash -lc "uicli aws -a firmware-prod save"

# 4. Verify signer access
docker exec -u $(id -u):$(id -g) <container> \
    bash -lc "aws --profile firmware-prod lambda invoke --function-name signer --invocation-type DryRun /dev/null"
# Expected: {"StatusCode": 204}
```

**Note:** uicli stores the JWT in `~/.config/@ui-devops/uicli/config.json` (plain text, 0600).
AWS STS credentials are written to `~/.aws/credentials` under the `[firmware-prod]` section.
STS credentials are temporary and may need refreshing via `uicli aws -a firmware-prod save`.

### How Signing Works

The `ubnt-mkfwimage` tool handles signing during image assembly:

1. Computes SHA1 hash of the firmware image
2. Invokes AWS Lambda (`signer` function) with the hash and product signing key
3. Lambda returns RSA signature which is embedded in the firmware binary

Each product defines its signing key in its config (e.g., `FWIMAGE_SIGNING_PRIVATE_KEY=nas_al324`).

## Docker Build Container

The build runs inside a Docker container. The container mounts the home directory,
so it can access any worktree under the debbox tree.

### Container Commands

```bash
extra/docker-util/debbox setup                    # Create/start container
extra/docker-util/debbox setup arch=arm64 dist=bullseye  # Specific arch/dist
extra/docker-util/debbox setup qemu=yes            # QEMU emulation mode
extra/docker-util/debbox setup host=arm64 arch=arm64     # Native build
extra/docker-util/debbox setup force=yes           # Force rebuild
extra/docker-util/debbox setup registry=my-reg.com # Custom registry
extra/docker-util/debbox enter                     # Shell into container
extra/docker-util/debbox clean                     # Remove container+image
extra/docker-util/debbox dry                       # Print Dockerfile
```

Container naming: `<user>-debbox-builder-{native|cross|qemu}-{dist}-{arch}[-suffix]`
Registry: `registry.corp.ubnt.com`

## Interactive Build (shell inside container)

When building interactively inside the container (via `extra/docker/debbox enter` or
`extra/docker-util/debbox enter`), **do NOT run `sudo make` from scratch**. The `sudo`
drops SSH agent (can't git clone), AWS credentials (can't sign), and creates root-owned
files in `build/` that break subsequent non-sudo builds.

**Correct two-phase approach (produces signed firmware):**

```bash
# Phase 1: As regular user (has SSH key + AWS creds)
make PRODUCT=<product> host-tools       # clone + build host tools
make PRODUCT=<product> target-kernel    # clone + compile kernel
make PRODUCT=<product> target-tools     # download + build packages
make PRODUCT=<product> reprepro-repository  # create local APT repo

# Phase 2: As sudo (needed for debootstrap/chroot in bootstrap)
# sudo -E preserves user's env including AWS_PROFILE + HOME (so ~/.aws/credentials works)
sudo -E make PRODUCT=<product>          # builds remaining steps (bootstrap + image)
# .mark.* files ensure Phase 1 steps are skipped
```

**Note:** `sudo -E` makes the version string show `+root` (e.g., `v5.1.4+root.32169`)
because `whoami` returns root. This is cosmetic only — the firmware is still properly signed.
For a clean version, use `docker exec` builds instead of interactive shell.

**Pre-flight checks before Phase 1:**
```bash
# 1. Verify DNS resolves leaf.corp.ubnt.com (package downloads)
getent hosts leaf.corp.ubnt.com || echo "FIX DNS: ask root to add corporate nameserver to /etc/resolv.conf"

# 2. Verify SSH key works (kernel/tool source downloads)
ssh -T git@github.com 2>&1 | grep -q "successfully" && echo "SSH OK" || echo "FIX: check SSH agent"

# 3. Verify no stale root-owned files in build/
find build/ -not -user $(id -u) 2>/dev/null | head -5 && echo "FIX: sudo chown -R $(id -u):$(id -g) build/"
```

## Build Flow

```
make PRODUCT=<product> all
  1. product-info        Show build configuration
  2. build.prepare       Create build directories
  3. host-tools          Build mkfwimage, uboot-tools, dosfstools
  4. target-kernel       Compile kernel -> .deb
  5. target-tools        Build target-specific utilities
  6. target-updater      Download firmware updater package
  7. target-image        Assemble firmware image
     a. Build local packages (dpkg-buildpackage)
     b. Download external packages from debfactory/leaf
     c. Create reprepro APT repository (all .debs combined)
     d. Bootstrap rootfs (multistrap + overlay hooks)
     e. Create squashfs rootfs.img (zstd/gzip)
     f. Create boot image (mkimage FIT or mkbootimg)
     g. Generate image-layout.txt (partition table)
     h. Pack + sign with ubnt-mkfwimage (AWS Lambda)
```

## Make Targets

```bash
make PRODUCT=<product> all              # Full build
make PRODUCT=<product> product-info     # Show config summary
make PRODUCT=<product> target-kernel    # Kernel only
make PRODUCT=<product> target-kernel.menuconfig  # Kernel menuconfig
make PRODUCT=<product> target-image     # Image only (after kernel)
make PRODUCT=<product> bootstrap        # Rootfs only
make PRODUCT=<product> reprepro-repository  # Package repo only

# Clean targets
make PRODUCT=<product> target-kernel.clean
make PRODUCT=<product> target-image.clean
make PRODUCT=<product> bootstrap.clean

# Useful variables
make PRODUCT=<product> V=1 all                # Verbose
make PRODUCT=<product> RELEASE_BUILD=true all  # Release build
```

## Deploying Firmware

After building, deploy using the `ubiquiti-debbox-fw-deploy` skill. It covers:
- Firmware upgrade for all platforms
- HTTP+tmux for UART-connected devices
- Alpine SoC manual rootfs/kernel update
- Post-deploy verification and recovery

## Configuration Hierarchy

debbox uses 4-level Makefile-based configuration (not Kconfig):

```
conf/<product>                    e.g., unas.rtd1619
  includes conf/product-base/<base>    e.g., debian-arm64-unas.rtd1619
    includes conf/platform/<platform>  e.g., debian-arm64.rtd1619
      includes conf/arch/<arch>        e.g., debian-arm64
```

### Key Config Variables

| Variable | Level | Example |
|----------|-------|---------|
| `PRODUCT_NAME` | product | `unas.rtd1619` |
| `PRODUCT_SHORTNAME` | product | `UNAS` |
| `PRODUCT_VERSION` | arch (privileged, branch-managed) | `5.1.0` |
| `BUILD_IMAGES` | product-base | `unas-image` |
| `BUILD_KERNEL` | product-base | `linux-realtek-5.10.216` |
| `BUILD_KERNEL_CONFIG` | product-base | `linux-rtd1619-unas-5.10.216.config` |
| `DEBIAN_TARGET_ARCH` | arch | `arm64` |
| `BOOTSTRAP_MAIN_PACKAGES` | arch/platform | Base Debian packages |
| `BOOTSTRAP_LOCAL_PACKAGES` | product | Locally-built packages |
| `FWIMAGE_SIGNING_PRIVATE_KEY` | product | AWS signing key name |

### Feature Flags

Products enable features via `HAS_*` flags in `conf/package/package.list`:

| Flag | Adds |
|------|------|
| `HAS_UNIFI_OS` | unifi-core, ulcmd |
| `HAS_UNIFI_NETWORK` | unifi-network-server |
| `HAS_UNIFI_PROTECT` | unifi-protect |
| `HAS_UNIFI_DRIVE` | unifi-drive-config |
| `HAS_UDAPI` | udapi-server, udapi-bridge |
| `HAS_WIFI` | WiFi subsystem |
| `HAS_ZFS` | ZFS kernel modules + tools |
| `HAS_NVME` | NVMe support |
| `HAS_LCM` | LCD display |
| `HAS_LED` | LED control |

## Product Catalog

See [references/products.md](references/products.md) for all 48+ products.

### Common Products

| Product Config | Short | Platform | Image Builder |
|----------------|-------|----------|---------------|
| `unas.rtd1619` | UNAS | rtd1619 | unas-image |
| `unas4.rtd1619` | UNAS4 | rtd1619 | unas-image |
| `unas-pro.alpine` | UNAS Pro | alpine | unas-image |
| `enterprise-nas.cn10k` | ENAS | cn10k | enterprise-nas-image |
| `unvr4.alpine` | UNVR | alpine | unvr-image |
| `unvr-pro.alpine` | UNVR Pro | alpine | unvr-image |
| `unvr-ai.qcs8550` | UNVR AI | qcs8550 | qcs8550-image |
| `udw.alpine` | UDW | alpine | dream-wall-image |
| `udw-pro.alpine` | UDW Pro | alpine | dream-wall-image |
| `udm-pro.alpine` | UDM Pro | alpine | dream-image |
| `udm-beast.cn10k` | UDM Beast | cn10k | dream-image |
| `uxg.ipq5322` | UXG | ipq5322 | qcom-ipq5322-image |
| `uxg-pro.alpine` | UXG Pro | alpine | dream-image |
| `ucg-industrial.ipq9574` | UCG Ind. | ipq9574 | qcom-ipq9574-image |
| `uck-ai.qcs8550` | UCK AI | qcs8550 | qcs8550-image |
| `udr7.ipq5322` | UDR 7 | ipq5322 | qcom-ipq5322-image |

### Platforms (SoC Families)

| Platform | Arch | SoC | Products |
|----------|------|-----|----------|
| `alpine` | arm64 | Annapurna Alpine | UDM, UNAS Pro, UNVR, UDW, UXG Pro |
| `rtd1619` | arm64 | Realtek RTD1619 | UNAS, UNAS4, UNVR-INS |
| `ipq5322` | arm64 | Qualcomm IPQ5322 | UXG, UDR7, UCG-Max |
| `ipq9574` | arm64 | Qualcomm IPQ9574 | UCG-Fiber, UCG-Industrial |
| `ipq5018` | arm64 | Qualcomm IPQ5018 | UXG-Lite, UEX |
| `cn10k` | arm64 | Marvell CN10k | UDM-Beast, ENAS |
| `cn9670` | arm64 | Marvell CN9670 | UDM-Enterprise, UXG-Enterprise |
| `qcs8550` | arm64 | Qualcomm QCS8550 | UCK-AI, UNVR-AI |
| `apq8053` | arm64 | Qualcomm APQ8053 | UCK-G2, UCK-G3-Plus |
| `cascadelake` | amd64 | Intel Xeon | UCK-Enterprise |
| `mt7622` | arm64 | MediaTek MT7622 | UDR |
| `ampere` | arm64 | Ampere | ENVR-Core |

## Directory Structure

```
debbox/
├── Makefile                     # Root orchestrator
├── conf/                        # Configuration hierarchy
│   ├── arch/                    #   debian-arm64, debian-amd64
│   ├── platform/                #   SoC-specific (debian-arm64.rtd1619, etc.)
│   ├── product-base/            #   Product templates
│   ├── package/package.list     #   HAS_* flag -> package mapping
│   └── <product>                #   Product configs
├── target/
│   ├── kernel/configs/          #   Kernel .config files (47+)
│   ├── image/<image-name>/      #   Image builders + layout files
│   ├── packages/src/            #   Local packages (debian/)
│   ├── packages/download/       #   External .deb download specs
│   ├── bootstrap/overlay/       #   Rootfs file overlays
│   ├── bootstrap/hooks/         #   Pre/post-config hook scripts
│   └── bootloader/              #   Bootloader download specs
├── tools/                       #   Host tool build specs
├── scripts/                     #   bootstrap, reprepro-setup, image-layout-gen
├── extra/docker-util/           #   Docker container management
├── build/                       #   Build output (generated)
│   ├── target-<product>/dist/   #   Final .bin firmware
│   └── target-<dist>-<arch>/apt/#   Reprepro repository
└── dl/                          #   Download cache
```

## Kernel Config Changes

The build system enforces **config consistency** (`include/target-kernel.mk` lines 31-34):
it copies the checked-in config to `.config`, runs `make oldconfig`, and diffs against the
original — if they differ, the build **fails**. This means committed kconfig files must be
**fully pre-resolved** with all derived options included.

**Do NOT** commit only the top-level symbol change (e.g., `CONFIG_KASAN=y`). `make oldconfig`
will generate additional derived options, and the diff check will fail.

### Kconfig Change Workflow

1. **Edit the top-level symbol** in `target/kernel/configs/<config>.config`
   (e.g., change `# CONFIG_KASAN is not set` to `CONFIG_KASAN=y`)

2. **Resolve all derived options** — choose one method:
   ```bash
   # Option A: Interactive menuconfig (recommended for complex changes)
   docker exec -it $CONTAINER \
       bash -lc "make PRODUCT=<product> target-kernel-menuconfig"

   # Option B: Non-interactive oldconfig (for simple toggles)
   # Copy config to kernel source .config, run make oldconfig, copy back
   ```

3. **Copy the resolved config back** to `target/kernel/configs/<config>.config`

4. **Commit the fully-resolved config** — includes all derived options

**Warnings:**
- Do NOT hand-edit derived kconfig symbols — let `make oldconfig` generate them
- `detect-header-impact.sh` correctly detects ALL toggled configs (including derived ones) from the git diff

## Kernel Header Updates (Tie-Shoe-Knot)

For kernel header updates that require the debbox → debfactory → debbox round-trip
(tie-fw-knot), see **`ubiquiti-flow` (tie-fw-knot)**. This includes auto-detection
(`detect-header-impact.sh`), local path, CI path (Phases A/B/C), and leaf URL handoff.

## Standalone CI Path

For independent firmware builds that don't involve the kernel header roundtrip
(e.g., kconfig-only changes, package list updates, defconfig tweaks), use the
single-command CI poller:

```bash
_shared/ci/ci-poll.lua --repo ubiquiti/debbox --pr <number>
# → prints artifact URL on success
```

**What it does under the hood (4-step pipeline):**

1. **Poll GH checks** — runs `poll-gh-checks.lua` until all CI checks pass or fail
2. **Get PR HEAD SHA** — fetches the current commit SHA via `gh pr view`
3. **Poll leaf URL** — runs `poll-leaf-url.lua` to find the build artifact matching that SHA
4. **Verify freshness** — runs `verify-artifact-freshness.lua` to confirm the artifact
   isn't stale; if stale, retries the whole pipeline (up to 3 times)

**Options:**

| Flag | Default | Description |
|------|---------|-------------|
| `--repo` | (required) | GitHub repository (`owner/repo`) |
| `--pr` | (required) | Pull request number |
| `--check-interval` | 360 | Seconds between GH check polls |
| `--leaf-interval` | 60 | Seconds between leaf URL polls |
| `--timeout` | 86400 | Per-step timeout in seconds |

**Exit codes:** 0 = success (artifact URL printed), 1 = CI failed/timeout/stale, 2 = usage error.

## Troubleshooting

For Docker TTY workaround and container troubleshooting common to debfactory builds, see also `ubiquiti-debfactory-build/references/troubleshooting.md`.

| Problem | Solution |
|---------|----------|
| `firmware-prod` profile not found | Run `uicli authorize --token=<JWT>` then `uicli aws -a firmware-prod save` inside the container |
| AWS STS credentials expired | Re-run `uicli aws -a firmware-prod save` inside the container |
| Signer AccessDeniedException | The IAM user lacks `lambda:InvokeFunction`. Use uicli to get STS credentials with proper role permissions |
| Bootstrap `unmet dependencies` | Old tags may conflict with current apt repos. Build from the stable branch head instead |
| Container not found | `extra/docker-util/debbox setup force=yes` |
| Parallel build fails: md5 mismatch / `Invalid <file> checksum` / wget truncated | dl/ race — two builds wrote the same file. Recover: `rm -f dl/<corrupted-file>` then rerun. Long-term: switch to Mode 1 (independent dl/) or Mode 2 (serial prefetch + parallel build), see [Concurrent Builds](#concurrent-builds) and [references/parallel-build.md](references/parallel-build.md) |
| Parallel build hangs on `git fetch` of kernel | `Files/git/clonecache` race — two builds writing `dl/<repo>-<hash>.tar.gz`. Same fix as md5 mismatch above. |
| Worktree exists but `git worktree remove` fails with `Permission denied` | Bootstrap (multistrap) created root-owned files in `bootstrap/root/`. Clean from inside the container: `docker exec --user root:root <container> rm -rf .worktrees/<name>` then `git worktree prune`. |
| `parallel-build.sh` dies with `Please define PRODUCT` | Worktree dir exists but isn't in `git worktree list` (orphan from prior failed run). Wrapper now refuses to proceed and prints the cleanup command — follow its instructions. |
| Multistrap fails with `Failed to fetch ... pdx-artifacts.rad.ubnt.com` | This is a network reachability issue, NOT a parallel-build bug. Verify with `timeout 5 bash -c 'echo > /dev/tcp/pdx-artifacts.rad.ubnt.com/443' && echo OK \|\| echo BLOCKED`. If BLOCKED, contact IT — likely VPN/route/firewall to PDX (10.53.x.x) datacenter. |
| Build dies seconds in with `conf/arch/debian-arm64:17: *** Build host requires Debian X.x arm64. Stop.` | Container Debian distro doesn't match `BuildHost/Debian/require,N,arm64` in the tree. master tracks the latest distro (was bullseye→trixie May 2026). Start the matching container: `extra/docker-util/debbox setup arch=arm64 dist=trixie` (or `bullseye`/`bookworm`). The wrapper `parallel-build.sh` auto-detects + picks the right container; manual `docker exec` builds must select it themselves. |
| `parallel-build.sh` warns `tree needs Debian X but selected container is Y` | The required `*-debbox` variant isn't running. Either start it (`extra/docker-util/debbox setup arch=arm64 dist=<required>`) or accept the warning if you intentionally cross-build. |
| Docker container Exited after host reboot | `docker start $(docker ps -a --filter "name=debbox-builder" --format "{{.Names}}")` |
| Bootstrap fails or stale rootfs | `make PRODUCT=<p> bootstrap.clean && make PRODUCT=<p> bootstrap` |
| Kernel build fails after config change | `make PRODUCT=<p> target-kernel.clean && make PRODUCT=<p> target-kernel` |
| List available products | `ls conf/ \| grep '\.'` |
| Permission errors in container | Ensure `extra/docker-util/debbox setup` ran successfully |
| Download 404 for kmod package (no product variant on leaf) | Some kmod packages (e.g., kmod-st7735fb) don't have variants for all products. Add the missing `<PRODUCT>_MD5` using a compatible variant's deb (e.g., UNAS for UNASPRO) |
| Upgrade failed on any platform | See `ubiquiti-debbox-fw-deploy` — covers all platforms including Alpine SoC (`/dev/boot*`) |
| `leaf.corp.ubnt.com` resolution fails inside Docker container | First check how the host resolves it: `getent hosts leaf.corp.ubnt.com` (works?) vs `dig +short leaf.corp.ubnt.com` (works?). **If getent works but dig fails** → host uses `/etc/hosts`; copy the entry: `LEAF_IP=$(getent hosts leaf.corp.ubnt.com \| awk '{print $1}') && docker exec --user root:root <container> bash -c "echo '$LEAF_IP leaf.corp.ubnt.com' >> /etc/hosts"`. **If dig works** → container DNS is wrong; find your DNS with `dig leaf.corp.ubnt.com \| grep SERVER`, then: `docker exec --user root:root <container> bash -c "echo 'nameserver <YOUR_DNS_IP>' > /etc/resolv.conf && echo 'nameserver 8.8.8.8' >> /etc/resolv.conf"` (note: `sed -i` fails on Docker-mounted `/etc/resolv.conf` with "Device or resource busy" — use `echo >` instead) |
| APT 404 for `bullseye-backports` or `buster` repos | Debian has archived these suites. Fix inside container: (1) `sed -i 's\|deb.debian.org/debian bullseye-backports\|archive.debian.org/debian bullseye-backports\|g' /etc/apt/sources.list.d/*.list`, (2) remove buster sources: `rm /etc/apt/sources.list.d/buster-main.list`, (3) `echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-check-valid-until`, (4) `apt-get update` |
