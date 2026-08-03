#!/usr/bin/env bash
# hw-survey.sh — read-only hardware layout survey for a Linux host.
#
# Dumps CPU topology, memory DIMM population, PCIe lanes/link speed, NVMe
# device layout, NIC speeds, and existing RAID/ZFS/filesystem config in one
# sectioned report. Use it to understand/inventory a platform's hardware layout,
# as a portable machine fingerprint for cross-host comparison, or as pre-flight
# before a storage/network benchmark.
#
# Read-only by default: never writes to the target, never touches block devices.
# The ONLY exception is the opt-in --install-deps flag (see below).
#
# Usage:
#   bash hw-survey.sh                      # survey the local host
#   bash hw-survey.sh --remote ui@10.0.0.5 # survey a remote host (pipes self over ssh)
#   bash hw-survey.sh --remote HOST --password ui        # ssh login password (lab devices)
#   bash hw-survey.sh --remote HOST --sudo-pass PASS      # sudo password if != login
#   bash hw-survey.sh --install-deps       # install dmidecode if SMBIOS present but tool missing
#   SUDO_PASS=xxx bash hw-survey.sh        # local, non-interactive privileged reads
#
# Privileged reads (dmidecode, nvme, lspci -vv, zpool) degrade gracefully when
# no privilege is available — the section prints what it can and notes the gap.
#
# On an SMBIOS host with no dmidecode, identity still comes for free from the
# kernel's /sys/class/dmi/id/*. dmidecode is only needed for per-DIMM memory
# detail; pass --install-deps to install it (apt/dnf/apk/opkg/zypper/pacman).

set -u

# ---------------------------------------------------------------------------
# arg parse
# ---------------------------------------------------------------------------
REMOTE=""
SSH_PASS=""
SUDO_PASS_ARG="${SUDO_PASS:-}"
INSTALL_DEPS=0

usage() {
  sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --remote)       REMOTE="${2:-}"; shift 2 ;;
    --password)     SSH_PASS="${2:-}"; shift 2 ;;
    --sudo-pass)    SUDO_PASS_ARG="${2:-}"; shift 2 ;;
    --install-deps) INSTALL_DEPS=1; shift ;;
    --local)        shift ;;              # internal: forced local mode over ssh
    -h|--help)      usage 0 ;;
    *) echo "unknown argument: $1" >&2; usage 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# remote mode: re-exec this same script on the target via ssh (pipe self)
# ---------------------------------------------------------------------------
if [ -n "$REMOTE" ]; then
  ssh_prefix=()
  if [ -n "$SSH_PASS" ]; then
    command -v sshpass >/dev/null 2>&1 || { echo "sshpass required for --password" >&2; exit 3; }
    ssh_prefix=(sshpass -p "$SSH_PASS")
  fi
  remote_sudo="${SUDO_PASS_ARG:-$SSH_PASS}"
  remote_flags="--local"
  [ "$INSTALL_DEPS" = 1 ] && remote_flags="$remote_flags --install-deps"
  "${ssh_prefix[@]}" ssh \
    -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
    "$REMOTE" "SUDO_PASS='${remote_sudo}' bash -s -- ${remote_flags}" < "$0"
  exit $?
fi

# ---------------------------------------------------------------------------
# helpers (local mode)
# ---------------------------------------------------------------------------
SUDO_PASS="$SUDO_PASS_ARG"

# run_priv CMD...  — run a command with the least privilege that works.
run_priv() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif [ -n "$SUDO_PASS" ]; then
    printf '%s\n' "$SUDO_PASS" | sudo -S -p '' "$@" 2>/dev/null
  elif sudo -n true 2>/dev/null; then
    sudo "$@"
  else
    "$@" 2>/dev/null
  fi
}

have() { command -v "$1" >/dev/null 2>&1; }

section() { printf '\n==== %s ====\n' "$1"; }

# dt_str PATH — print a device-tree string property (NUL-separated → spaces).
dt_str() { tr '\0' ' ' < "$1" 2>/dev/null; }

# decode_dt_mem — decode /proc/device-tree/memory*/reg (arm64 standard
# #address-cells=2 #size-cells=2 → 16-byte big-endian <base size> pairs).
decode_dt_mem() {
  local reg found=0
  for reg in /proc/device-tree/memory@*/reg /proc/device-tree/memory/reg; do
    [ -r "$reg" ] || continue
    found=1
    if have python3; then
      python3 - "$reg" <<'PY'
import struct, sys
p = sys.argv[1]
d = open(p, "rb").read()
for i in range(0, len(d) - 15, 16):
    b, s = struct.unpack(">QQ", d[i:i+16])
    print(f"  {p}: base={b:#x} size={s/1024**3:.2f} GiB")
PY
    elif have fdtget; then
      echo "  $reg: $(fdtget -t x "${reg%/reg}" reg 2>/dev/null)"
    else
      echo "  $reg: raw $(wc -c < "$reg" 2>/dev/null) bytes (install python3 or device-tree-compiler to decode)"
    fi
  done
  [ "$found" = 1 ] || echo "  (no /proc/device-tree/memory node)"
}

# install_pkg PKG — best-effort install via the host's package manager (opt-in).
install_pkg() {
  local pkg="$1" mgr=""
  for m in apt-get dnf yum apk opkg zypper pacman; do have "$m" && { mgr="$m"; break; }; done
  [ -n "$mgr" ] || { echo "  (no known package manager — cannot install $pkg)"; return 1; }
  echo "  installing $pkg via $mgr ..."
  case "$mgr" in
    apt-get) run_priv apt-get update -qq >/dev/null 2>&1; run_priv apt-get install -y "$pkg" >/dev/null 2>&1 ;;
    dnf|yum) run_priv "$mgr" install -y "$pkg" >/dev/null 2>&1 ;;
    zypper)  run_priv zypper --non-interactive install "$pkg" >/dev/null 2>&1 ;;
    apk)     run_priv apk add "$pkg" >/dev/null 2>&1 ;;
    opkg)    run_priv opkg update >/dev/null 2>&1; run_priv opkg install "$pkg" >/dev/null 2>&1 ;;
    pacman)  run_priv pacman -Sy --noconfirm "$pkg" >/dev/null 2>&1 ;;
  esac
  if have "$pkg"; then echo "  $pkg installed"; else echo "  $pkg install failed"; return 1; fi
}

# platform info source: SMBIOS (x86 + SBBR/SBSA arm64) vs Device Tree (embedded).
# SMBIOS presence = kernel DMI tables OR a working dmidecode — NOT dmidecode
# alone (SBBR arm64 boxes like ENVR Core ship SMBIOS but no dmidecode).
if [ -d /sys/firmware/dmi/tables ] || [ -r /sys/firmware/dmi/tables/DMI ] \
   || { have dmidecode && run_priv dmidecode -t system >/dev/null 2>&1; }; then
  PLATFORM=smbios
else
  PLATFORM=devicetree
fi

# opt-in dependency install (the only non-read-only action; default off)
if [ "$INSTALL_DEPS" = 1 ] && [ "$PLATFORM" = smbios ] && ! have dmidecode; then
  echo "# --install-deps: dmidecode missing on an SMBIOS host — installing" >&2
  install_pkg dmidecode >&2 || true
fi

# ---------------------------------------------------------------------------
# report
# ---------------------------------------------------------------------------
printf '# hardware survey — %s — %s\n' "$(hostname 2>/dev/null)" "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)"
printf '# platform-info-source: %s\n' "$PLATFORM"

section "SYSTEM / BOARD / FIRMWARE"
if [ "$PLATFORM" = smbios ]; then
  dmi_out=""
  have dmidecode && dmi_out=$(run_priv dmidecode -t system -t baseboard -t bios 2>/dev/null \
    | grep -E "Manufacturer:|Product Name:|Version:|Serial Number:|Vendor:|Release Date:|BIOS Revision:" \
    | grep -v "To Be Filled")
  if [ -n "$dmi_out" ]; then
    printf '%s\n' "$dmi_out"
  else
    # dmidecode absent OR unprivileged (empty) — the kernel already exposes the
    # common DMI fields at /sys/class/dmi/id, readable without root.
    echo "(dmidecode unavailable/unprivileged — identity from kernel /sys/class/dmi/id; per-DIMM memory needs dmidecode + root, see --install-deps)"
    for f in sys_vendor product_name product_version product_serial \
             board_vendor board_name bios_vendor bios_version bios_date; do
      v=$(cat "/sys/class/dmi/id/$f" 2>/dev/null)
      [ -n "$v" ] && printf '  %-16s %s\n' "$f" "$v"
    done
  fi
else
  echo "(no SMBIOS — Device-Tree platform; identity from /proc/device-tree + vendor board-info)"
  printf 'model:      %s\n' "$(dt_str /proc/device-tree/model)"
  printf 'compatible: %s\n' "$(dt_str /proc/device-tree/compatible)"
  printf 'serial:     %s\n' "$(dt_str /proc/device-tree/serial-number)"
  for bi in /proc/ubnthal/system.info /etc/board.info; do
    [ -r "$bi" ] && { echo "--- $bi (vendor board-info) ---"; cat "$bi"; }
  done
  for v in /usr/lib/version /etc/version; do
    [ -r "$v" ] && printf 'firmware (%s): %s\n' "$v" "$(cat "$v")"
  done
  echo "--- /proc/device-tree top-level nodes ---"
  ls /proc/device-tree/ 2>/dev/null | tr '\n' ' '; echo
fi

section "CPU"
if have lscpu; then
  lscpu | grep -E "^Architecture|^Model name|^BIOS Model name|^CPU\(s\):|Thread\(s\) per core|Core\(s\) per socket|^Socket\(s\)|NUMA node\(s\)|NUMA node[0-9]|L3 cache|CPU max MHz|Vendor ID"
else
  grep -E "model name|processor" /proc/cpuinfo | sort -u
fi
if [ "$PLATFORM" = devicetree ]; then
  printf 'SoC (cpu@0 compatible): %s\n' "$(dt_str /proc/device-tree/cpus/cpu@0/compatible)"
  grep -E "CPU implementer|CPU part|CPU architecture" /proc/cpuinfo | head -n 3
fi
have numactl && { section "NUMA"; numactl --hardware 2>/dev/null; }

section "MEMORY"
echo "Total: $(awk '/MemTotal/{printf "%.0f GiB\n", $2/1024/1024}' /proc/meminfo 2>/dev/null)"
if [ "$PLATFORM" = smbios ] && ! have dmidecode; then
  echo "(per-DIMM population needs dmidecode — not installed; rerun with --install-deps)"
elif [ "$PLATFORM" = smbios ]; then
  mem_out=$(run_priv dmidecode -t memory 2>/dev/null | awk '
    /Maximum Capacity:/   { print "Max capacity:" $0 }
    /Number Of Devices:/  { print $0 }
    /^Memory Device/      { loc=""; sz=""; sp=""; cs="" }
    /\tSize:/             { sz=$2 " " $3 }
    /\tLocator:/          { loc=$2 }
    /Configured Memory Speed:/ { cs=$4 " " $5 }
    /\tSpeed:/            { sp=$2 " " $3 }
    /Rank:/               { if (loc!="") printf "  %-14s %-12s rated=%-10s configured=%s\n", loc, sz, sp, cs }
  ')
  if [ -n "$mem_out" ]; then
    echo "-- per-DIMM population (locator | size | rated | configured) --"
    printf '%s\n' "$mem_out"
  else
    echo "(per-DIMM population needs dmidecode + root — no privileged output; run as root or with SUDO_PASS)"
  fi
else
  echo "(Device-Tree platform — RAM is typically soldered LPDDR, no per-slot data)"
  echo "-- physical regions from /proc/device-tree/memory*/reg --"
  decode_dt_mem
fi

section "PCIe — NVMe link speed/width (cap vs actual)"
# sysfs link attrs (current/max_link_speed, *_link_width) are readable WITHOUT
# root — unlike `lspci -vv` LnkCap/LnkSta which need privilege for config space.
nvme_found=0
for d in /sys/class/nvme/nvme*; do
  [ -e "$d" ] || continue
  nvme_found=1
  name=$(basename "$d")
  pcidir=$(readlink -f "$d/device" 2>/dev/null)
  pciaddr=$(basename "$pcidir" 2>/dev/null)
  [ -n "$pciaddr" ] || continue
  mdl=$(tr -s ' ' < "$d/model" 2>/dev/null)
  cur_sp=$(cat "$pcidir/current_link_speed" 2>/dev/null)
  max_sp=$(cat "$pcidir/max_link_speed" 2>/dev/null)
  cur_w=$(cat "$pcidir/current_link_width" 2>/dev/null)
  max_w=$(cat "$pcidir/max_link_width" 2>/dev/null)
  printf '  %-8s %-13s %s\n' "$name" "$pciaddr" "$mdl"
  printf '      cap: %s x%s    actual: %s x%s\n' "${max_sp:-?}" "${max_w:-?}" "${cur_sp:-?}" "${cur_w:-?}"
  if { [ -n "$cur_sp" ] && [ "$cur_sp" != "$max_sp" ]; } || \
     { [ -n "$cur_w" ] && [ "$cur_w" != "$max_w" ]; }; then
    echo "      ^ DOWN-TRAINED — actual link below cap (reseat / bifurcation / signal integrity)"
  fi
done
[ "$nvme_found" = 1 ] || echo "  (no NVMe devices found)"

section "PCIe — topology (switch vs direct-attach)"
if have lspci; then
  echo "-- PCIe switches/bridges (non-CPU) --"
  lspci 2>/dev/null | grep -Ei "switch|PLX|Broadcom.*PEX|Microchip|PMC-Sierra" | grep -vi "host bridge" || echo "  none found (drives likely direct-attached to CPU root ports)"
  echo "-- tree (root complexes → bridges → endpoints) --"
  lspci -tv 2>/dev/null
fi

section "NVMe devices"
have nvme && run_priv nvme list 2>/dev/null
echo "-- lsblk --"
have lsblk && lsblk -d -o NAME,SIZE,MODEL,SERIAL,TRAN,ROTA 2>/dev/null | grep -Ev "^loop|^ram"

section "NETWORK interfaces"
for i in /sys/class/net/*; do
  n=$(basename "$i")
  [ "$n" = "lo" ] && continue
  printf '  %-16s state=%s speed=%sMb mac=%s\n' \
    "$n" "$(cat "$i/operstate" 2>/dev/null)" "$(cat "$i/speed" 2>/dev/null)" "$(cat "$i/address" 2>/dev/null)"
done

section "STORAGE config (existing RAID / ZFS / mounts)"
echo "-- mdadm --"; cat /proc/mdstat 2>/dev/null | grep -v "^unused" || true
if have zpool; then
  echo "-- zpool --"; run_priv zpool list 2>/dev/null; run_priv zpool status -L 2>/dev/null
  run_priv awk '/c_max|c_min|^size/{print "arc " $1 " = " $NF}' /proc/spl/kstat/zfs/arcstats 2>/dev/null
fi
echo "-- filesystems --"; df -h -x tmpfs -x devtmpfs -x overlay 2>/dev/null | grep -Ev "/snap|loop"

section "TOOLING present"
for t in fio nvme smartctl numactl iperf3 zpool mdadm lvs; do
  printf '  %-10s %s\n' "$t:" "$(command -v "$t" 2>/dev/null || echo MISSING)"
done

printf '\n# end of survey\n'
