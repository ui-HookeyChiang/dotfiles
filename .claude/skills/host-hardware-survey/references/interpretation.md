# Reading the survey output

How to turn raw `hw-survey.sh` output into conclusions about a platform's
hardware layout — and, where relevant, its storage/network benchmark ceilings.

## Command → what it proves

| Command | Answers | Why not something else |
|---|---|---|
| `dmidecode -t system/baseboard/bios` | Chassis model, motherboard, BIOS version, serial | Only source for **physical/firmware** identity; `/proc` has none of it |
| `lscpu` / `numactl --hardware` | Cores, threads, L3 (CCD count), NUMA nodes (NPS) | `/proc/cpuinfo` lacks cache/NUMA topology |
| `dmidecode -t memory` | **Per-slot** DIMM: locator, size, rated vs configured speed | `free`/`/proc/meminfo` give only the total, never which channels are populated |
| `lspci -vv` → `LnkCap`/`LnkSta` | PCIe generation and lane width **negotiated** per device | `nvme list` shows the drive but not the link it trained to |
| `lspci -tv` | Root-complex → bridge → endpoint tree | Reveals switch vs direct-attach; a flat device list hides it |
| `nvme list` / `lsblk` | Drive model, capacity, sector size, transport | — |
| `zpool status -L` / `/proc/mdstat` | Existing pool/array vdev layout | Must know before any destructive test |

## PCIe link speed decode (`LnkSta: Speed … Width …`)

| Speed | Generation | ~GB/s per x4 (usable) |
|---|---|---|
| 2.5 GT/s | Gen1 | ~0.8 |
| 5 GT/s | Gen2 | ~1.6 |
| 8 GT/s | Gen3 | ~3.5 |
| 16 GT/s | Gen4 | ~7 |
| 32 GT/s | Gen5 | ~14 |
| 64 GT/s | Gen6 | ~28 |

- Compare **`LnkSta` (actual)** against **`LnkCap` (max)**. If `LnkSta` is slower/narrower than `LnkCap`, the link **down-trained** — a reseat, backplane, bifurcation-setting, or signal-integrity problem. Flag it; it caps that drive's throughput.
- `Width x4` is one NVMe drive's normal lane count; `x8`/`x16` are NICs/HBAs/GPUs.

## Direct-attach vs PCIe switch (why it matters for benchmarks)

Read `lspci -tv`:

- Endpoints hanging directly off CPU root-complex bridges (e.g. AMD "GPP Bridge", Intel "PCI Express Root Port") with **no third-party switch** in the path → **direct-attach**, each drive gets full non-shared bandwidth. Aggregate throughput scales with drive count.
- A Broadcom/PLX (PEX), Microchip/Microsemi, or PMC switch between the root port and several drives → the drives **share** the switch's upstream link. N drives behind an x16 upstream can be **oversubscribed**; aggregate is capped by the upstream, not the sum of the drives. Size expectations accordingly.

Multiple root complexes (e.g. domains `0000:00 / :40 / :80 / :c0` on AMD EPYC) map to the CPU's IO dies / quadrants. Which quadrant a drive or NIC sits in matters under NPS2/NPS4 (multi-NUMA); under NPS1 they all report as node0.

## Memory: population is the hidden benchmark ceiling

`dmidecode -t memory` per-DIMM read is the point. Checklist:

1. **Channels populated vs total.** Count DIMMs with a real `Size` against `Number Of Devices`. A 12-channel CPU (AMD EPYC Genoa/Bergamo SP5) or 8-channel (Intel SP) with only a few DIMMs filled runs at a **fraction of peak memory bandwidth**. This throttles page-cache/ARC-heavy storage tests and high-QD network paths — call it out explicitly.
2. **Rated vs `Configured Memory Speed`.** If configured < rated (e.g. DDR5-5600 module running 4800), the platform down-clocked it (population rules, mixed ranks, or BIOS). Real bandwidth follows the configured speed.
3. **One vs multiple sockets.** Cross-socket (remote NUMA) memory access is slower; pin benchmark threads to the NUMA node local to the drives/NIC under test (`numactl -N`).

## Interpreting NIC rows

`speed=-1Mb` or `state=down` = link not up (unplugged, no SFP, or admin-down) — normal for spare ports. For a storage server, match the **usable network egress** (sum of up 25G/100G ports) against the **aggregate drive throughput**; the smaller one bounds a remote (NFS/SMB/iSCSI) benchmark. Also check the NIC's own `LnkSta` — a 2×25G NIC starved on a Gen3 x8 slot can't reach line rate on both ports.

## SMBIOS present but `dmidecode` not installed

Common on minimal Debian/arm64 server images — e.g. **ENVR Core** (Ampere Altra,
ASRockRack board, AMI BIOS): `/sys/firmware/dmi/tables/` exists, but the
`dmidecode` package is absent. This is an **SMBIOS** platform (not Device Tree),
so the script takes the `smbios` branch. Three tiers of access, cheapest first:

1. **Kernel-parsed identity — zero install, no root.** The kernel already
   decodes the common DMI fields into `/sys/class/dmi/id/`:

   ```bash
   for f in sys_vendor product_name product_serial board_vendor board_name \
            bios_vendor bios_version bios_date chassis_type; do
     printf '%-14s %s\n' "$f" "$(cat /sys/class/dmi/id/$f 2>/dev/null)"
   done
   ```
   This covers vendor / board / BIOS identity without installing anything. Empty
   fields (e.g. `sys_vendor`, `product_serial`) just mean the OEM left that
   SMBIOS string blank.

2. **Per-DIMM memory — needs `dmidecode`.** `/sys/class/dmi/id/` does **not**
   expose SMBIOS type-17 (memory device) records, so DIMM locator / size / speed
   require `dmidecode` to parse `/sys/firmware/dmi/tables/DMI`. This is the only
   reason to install anything on an SMBIOS host.

3. **Install it (opt-in `--install-deps`).** The package is `dmidecode` on every
   distro; the script detects `apt`/`dnf`/`apk`/`opkg`/`zypper`/`pacman`. Keep it
   opt-in — auto-installing on a production box is a side-effect, not a read.

Rule of thumb: need only *what box is this?* → no install (`/sys/class/dmi/id`).
Need *how are the memory channels populated?* → `--install-deps`.

## When `dmidecode` returns nothing (arm64 / embedded)

`dmidecode` is **not** x86-only; it parses **SMBIOS/DMI tables**, which are a firmware feature, not a CPU-architecture one.

- **SBBR/SBSA arm64 servers** (Ampere Altra, AWS Graviton, Neoverse platforms) boot UEFI+ACPI and **do** expose SMBIOS → `dmidecode` works normally.
- **Embedded / SBC arm64** (most Ubiquiti devices, Raspberry Pi, generic SoC boards) boot U-Boot + **Device Tree** and expose **no** SMBIOS → `dmidecode` prints `No SMBIOS nor DMI entry point found`.

Presence test:

```bash
ls /sys/firmware/dmi/tables/ 2>/dev/null       # exists => SMBIOS present => dmidecode works
```

On a Device-Tree platform, identity comes from three places instead of SMBIOS:

| Source | SMBIOS equivalent | What it gives |
|---|---|---|
| **Device Tree** — `/proc/device-tree/*`, `/sys/firmware/devicetree/base/*` | machine model + memory + buses | `model`, `compatible` (SoC), `serial-number`, `memory@*/reg`, per-controller nodes |
| **`/sys` + `/proc`** | generic | CPU, RAM total, storage, NICs — identical to x86 |
| **Vendor board-info file** | system serial / asset tag | Ubiquiti: `/proc/ubnthal/system.info`; others: `/etc/board.info`, on-board EEPROM |

Concrete recipe (verified on a Ubiquiti ENAS, Marvell CN10K aarch64):

```bash
# 1) Device-Tree identity  (properties are NUL-terminated → pipe through tr)
cat /proc/device-tree/model; echo                     # e.g. ENAS-REV04
tr '\0' ' ' < /proc/device-tree/compatible; echo      # e.g. marvell,cn10kb   (SoC)
cat /proc/device-tree/serial-number 2>/dev/null; echo
ls /proc/device-tree/                                 # walk top-level nodes
tr '\0' ' ' < /proc/device-tree/cpus/cpu@0/compatible; echo   # per-CPU SoC id

# 2) Vendor board-info (Ubiquiti) — serial, MACs, board rev, SoC, ramsize
cat /proc/ubnthal/system.info
cat /usr/lib/version                                  # firmware version

# 3) Decode the DT memory region (arm64: #address-cells=2 #size-cells=2 →
#    16-byte big-endian <base><size>). No fdtget on most Ubiquiti images:
python3 -c 'import struct;d=open("/proc/device-tree/memory@0/reg","rb").read();b,s=struct.unpack(">QQ",d[:16]);print(f"base={b:#x} size={s/1024**3:.1f} GiB")'
# with device-tree-compiler installed instead:  fdtget -t x /proc/device-tree memory@0 reg
```

ARM CPU id decode (from `/proc/cpuinfo`): `CPU implementer 0x41` = ARM;
`CPU part 0xd49` = Neoverse N2, `0xd0c` = N1, `0xd42` = A78. Combine with the DT
`cpu@0/compatible` (e.g. `marvell,cn10670-cpu`) for the vendor's SoC name.

Gotchas specific to Device Tree:
- **String props end in `\0`** — `cat` then `echo` for a clean line; `compatible`
  is a `\0`-separated list, so `tr '\0' ' '`.
- **Binary props** (`reg`, cell counts) are **big-endian**; decode with `python3
  struct` or `fdtget`, never assume host byte order.
- **No per-DIMM memory** — soldered LPDDR has no SPD/locator; you get total +
  physical regions only.

Everything else in the survey (`lscpu`, `lsblk`, `nvme`, `lspci`, `/sys/class/net`) is architecture-independent and works on both. Some embedded SoCs have no PCIe controller so `lspci` is empty (expected) — but SoCs with an internal PCIe fabric (e.g. Marvell CN10K/OcteonTX) **do** populate `lspci` with on-die Cavium/ThunderX functions.

## Privilege

`dmidecode`, `nvme list`, `lspci -vv` link fields, and `zpool` need root. The script uses the least privilege that works: it runs direct as root, else `sudo -S` with `SUDO_PASS`, else passwordless `sudo -n`, else an unprivileged best-effort. Unprivileged runs still produce CPU/NUMA/lsblk/NIC sections; the privileged sections note the gap rather than failing the whole run.
