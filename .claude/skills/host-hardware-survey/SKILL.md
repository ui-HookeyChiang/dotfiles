---
name: host-hardware-survey
description: Use when you need to understand, inventory, or fingerprint a Linux host's hardware layout over SSH (or locally) — CPU, per-DIMM memory, PCIe link speed, NVMe, NIC, and existing RAID/ZFS — including arm64 devices with no dmidecode (auto-detects SMBIOS vs Device Tree). Read-only. NOT for running benchmarks, provisioning storage, or firmware/BIOS updates.
argument-hint: "--remote user@host [--password PASS] [--install-deps]"
disable-model-invocation: true
test-devices: local
landing-group: test
---

# Host Hardware Survey

Read-only hardware inventory for a Linux host: CPU + NUMA topology, **per-slot**
memory population, PCIe generation/width per device, NVMe layout, NIC speeds, and
any existing RAID/ZFS/filesystem config. One script, one sectioned report — use
it to understand a platform, fingerprint it for comparison, or as pre-flight
before a benchmark.

**Dual-platform, auto-detected** (the `platform-info-source` line in the report
says which path ran):
- **SMBIOS** — x86, and SBBR/SBSA arm64 servers (Ampere, Graviton). Identity +
  per-DIMM memory via `dmidecode`.
- **Device Tree** — embedded arm64 with no SMBIOS (most Ubiquiti devices,
  Marvell CN10K, generic SoC boards, Raspberry Pi). Identity from
  `/proc/device-tree` + vendor board-info (`/proc/ubnthal/system.info`,
  `/etc/board.info`); memory regions decoded from the DT `memory` node.

## When to use

- Just **understanding / inventorying** a platform — what's in the box and how
  it's wired (a new machine, an unfamiliar lab box, an audit).
- Answering "what CPU / how much memory / which PCIe gen / how many NVMe and how
  are they wired (direct-attach vs switch)".
- Capturing a portable **fingerprint** of a box to compare against another.
- **Pre-flight before a benchmark** — knowing the ceilings (PCIe gen, memory
  channels, NIC speed) before you interpret storage/network numbers.
- Pulling hardware identity from an **embedded arm64** device (Ubiquiti ENAS/UNAS,
  Marvell/SoC board) where `dmidecode` fails with `No SMBIOS … entry point found`.

**Not this skill:**
- Running the benchmark → `ubiquiti-nas-perf-test` / `ubiquiti-nas-perf-matrix`.
- Provisioning or nuking storage → `ubiquiti-deploy-storage`.
- Analyzing a device **support archive** (offline `.tar.zst`) → `ubiquiti-support-debug`.
- Adding a device to SSH config / registry → `ubiquiti-add-device`.

## Contract

- **Read-only by default.** No writes to the target, no block-device access.
  Safe on a production or already-populated box. The **only** exception is the
  opt-in `--install-deps` flag (installs `dmidecode`; off unless you pass it).
- **Input:** a reachable Linux host (local, or `user@host` over SSH).
- **Output:** a sectioned text report on stdout — `SYSTEM`, `CPU`, `NUMA`,
  `MEMORY`, `PCIe link`, `PCIe topology`, `NVMe`, `NETWORK`, `STORAGE config`,
  `TOOLING`. Redirect to a file to keep a per-host fingerprint.
- **Privilege:** `dmidecode`, `nvme list`, `lspci -vv` link fields, and `zpool`
  need root. The script uses the least privilege that works (root → `sudo -S`
  with `SUDO_PASS` → `sudo -n` → unprivileged best-effort); privileged sections
  note the gap instead of aborting the whole run.

## Run it

```bash
SKILL_DIR=~/.claude/skills/host-hardware-survey

# local host
bash "$SKILL_DIR/scripts/hw-survey.sh"

# remote host (pipes the script over ssh; nothing is installed on the target)
bash "$SKILL_DIR/scripts/hw-survey.sh" --remote ui@10.59.1.194 --password ui

# save a fingerprint for later comparison
bash "$SKILL_DIR/scripts/hw-survey.sh" --remote ui@HOST --password ui > host-HOST.txt

# SMBIOS host missing dmidecode (e.g. ENVR Core, an SBBR arm64 box): opt in to
# installing it so the MEMORY section can show per-DIMM population
bash "$SKILL_DIR/scripts/hw-survey.sh" --remote envr-core --install-deps
```

- `--password` uses `sshpass` for the SSH login (lab devices with a known
  password); omit it when key-based SSH works.
- SUDO password defaults to the SSH password; override with `--sudo-pass` when
  they differ, or set `SUDO_PASS=…` for a local privileged run.
- **`--install-deps`** (opt-in, the only non-read-only action): if the host has
  SMBIOS but no `dmidecode`, install it via the detected package manager
  (`apt`/`dnf`/`apk`/`opkg`/`zypper`/`pacman`). **Without it**, identity still
  comes for free from the kernel's `/sys/class/dmi/id/*`; only **per-DIMM
  memory** detail is skipped (that is the one thing sysfs can't provide).

## Reading the output

`references/interpretation.md` is the SSOT for turning raw output into
conclusions. Load it when interpreting. Key levers:

- **PCIe cap vs actual link** — 32 GT/s = Gen5, 16 = Gen4, 8 = Gen3. Read from
  sysfs (`max_link_speed` vs `current_link_speed`, no root needed); the script
  auto-flags `DOWN-TRAINED` when actual is below cap (that caps the drive).
- **Direct-attach vs switch** — read `lspci -tv`. No third-party PLX/Broadcom/
  Microchip switch in the path = each drive gets full bandwidth; behind a switch
  = drives **share** the upstream (possible oversubscription).
- **Memory population is the hidden ceiling** — count populated DIMMs against the
  channel count (EPYC SP5 = 12, Intel SP = 8). A partly-filled box runs at a
  fraction of peak bandwidth and throttles cache/ARC-heavy tests. Also compare
  rated vs `Configured Memory Speed`.
- **NIC vs drive aggregate** — for a remote (NFS/SMB/iSCSI) benchmark, the
  smaller of (summed up-NIC egress) and (summed drive throughput) bounds it.

## Preconditions / caveats

- Target needs standard tools: `dmidecode`, `lscpu`, `lspci` (pciutils),
  `nvme` (nvme-cli), `lsblk`. Missing tools degrade that section, not the run.
- `--password` needs `sshpass` on the **caller**.
- **arm64 / embedded**: `dmidecode` is a **SMBIOS** feature, not an x86 one.
  SBBR/SBSA arm64 servers (Ampere, Graviton) have it; U-Boot + Device-Tree
  boards (most Ubiquiti devices, Pi) do not — the script auto-detects this and
  runs the Device-Tree branch instead (`/proc/device-tree` + vendor board-info
  + DT `memory` decode). No per-DIMM data there (RAM is soldered LPDDR). To
  decode DT binary props the target needs `python3` or `device-tree-compiler`
  (`fdtget`); without either, `memory/reg` prints as raw bytes. Detail + manual
  commands: `references/interpretation.md`.

## Pointers

- `scripts/hw-survey.sh` — the collector (local + `--remote` self-pipe).
- `references/interpretation.md` — command→proof table, PCIe/memory/NIC
  interpretation, arm64 Device-Tree fallback.
