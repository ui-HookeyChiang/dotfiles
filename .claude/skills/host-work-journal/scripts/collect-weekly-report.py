#!/usr/bin/env python3
"""Collect work activity data from a host into structured JSON.

Gathers data from git repos, shell history, Claude Code sessions,
OpenCode sessions, test artifacts, and SSH config. Outputs JSON for
report composition.

Usage:
    python3 collect-weekly-report.py [OPTIONS]
    python3 collect-weekly-report.py --start-date 2026-02-01 --end-date 2026-02-26 --detailed -v
"""

import argparse
import json
import logging
import os
import re
import socket
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

log = logging.getLogger("collect-weekly-report")

# ── Constants ────────────────────────────────────────────────────────────────

CLAUDE_DIR = Path.home() / ".claude"
HISTORY_JSONL = CLAUDE_DIR / "history.jsonl"
STATS_CACHE = CLAUDE_DIR / "stats-cache.json"
PROJECTS_DIR = CLAUDE_DIR / "projects"
OPENCODE_DB = Path.home() / ".local" / "share" / "opencode" / "opencode.db"
SSH_CONFIG = Path.home() / ".ssh" / "config"
TEST_RESULTS_DIR = Path.home() / "ubiquiti-test-results"
ZSH_HISTORY = Path.home() / ".zsh_history"
BASH_HISTORY = Path.home() / ".bash_history"
# Default journal paths; overridden by --journal-root at runtime.
_JOURNAL_ROOT_DEFAULT = Path.home() / "Awesome-CV" / "journal"
JOURNAL_RAW = _JOURNAL_ROOT_DEFAULT / "raw"
JOURNAL_INTEGRATED = _JOURNAL_ROOT_DEFAULT / "integrated"

# Directories to skip when scanning for git repos
GIT_SCAN_EXCLUDES = {
    ".cache", ".local", ".cargo", "node_modules", ".npm",
    ".rustup", ".gradle", ".m2", "go", ".vscode-server",
}

# Shell command categories
COMMAND_CATEGORIES = {
    "git": {"git", "gh", "tig"},
    "code_search": {"rg", "grep", "ag", "fd", "find", "ast-grep"},
    "editing": {"vim", "nvim", "vi", "nano", "code", "claude"},
    "build": {"make", "cargo", "npm", "yarn", "pip", "dpkg-buildpackage",
              "debuild", "cmake", "gcc", "g++", "python3", "python"},
    "file_transfer": {"scp", "rsync", "curl", "wget"},
    "remote": {"ssh", "mosh"},
    "package": {"dpkg", "apt", "apt-get", "brew"},
    "containers": {"docker", "podman"},
    "network": {"iperf3", "ping", "traceroute", "netstat", "ss", "ip", "nmap"},
    "storage": {"fio", "mdadm", "lvs", "lsblk", "mount", "umount", "blkdiscard",
                "smartctl", "hdparm", "dmsetup"},
    "system": {"systemctl", "journalctl", "dmesg", "top", "htop", "ps", "kill",
               "sudo", "su"},
    "file_ops": {"ls", "cat", "head", "tail", "cp", "mv", "rm", "mkdir",
                 "chmod", "chown", "ln", "tar", "gzip", "unzip", "zip"},
}

# Reverse lookup: command -> category
CMD_TO_CATEGORY = {}
for cat, cmds in COMMAND_CATEGORIES.items():
    for cmd in cmds:
        CMD_TO_CATEGORY[cmd] = cat

# Claude prompt topic keywords
TOPIC_KEYWORDS = {
    "storage/raid": ["raid", "mdadm", "lvm", "lvs", "btrfs", "zfs", "storage",
                     "disk", "nvme", "ssd", "cache", "nuke", "deploy"],
    "networking": ["network", "iperf", "smb", "nfs", "samba", "mount", "share",
                   "tcp", "udp", "vlan", "bond", "nic"],
    "performance": ["fio", "benchmark", "perf", "throughput", "iops", "latency",
                    "test", "testing"],
    "build/packaging": ["build", "debian", "deb", "dpkg", "debfactory", "package",
                        "compile", "cython"],
    "scripting": ["script", "bash", "python", "awk", "sed", "regex", "parse"],
    "firmware/deploy": ["firmware", "deploy", "flash", "install", "dpkg -i",
                        "systemctl"],
    "debugging": ["debug", "fix", "error", "bug", "issue", "crash", "traceback",
                  "log", "journal"],
    "documentation": ["doc", "readme", "report", "skill", "memory", "note"],
    "git/pr": ["commit", "pr", "pull request", "merge", "branch", "rebase",
               "cherry-pick"],
    "device_management": ["ssh", "device", "unas", "unvr", "enas", "discover",
                          "reboot"],
}

# SSH host device type prefixes
DEVICE_PREFIXES = [
    ("UNASPro", "UNAS Pro"),
    ("UNAS", "UNAS"),
    ("ENASPro", "ENAS Pro"),
    ("ENAS", "ENAS"),
    ("UNVRPro", "UNVR Pro"),
    ("UNVR", "UNVR"),
    ("UXG", "UXG"),
    ("UDM", "UDM"),
]

# SAR-focused git collection: loaded from _shared/categories.md (single source of truth)
def _load_categories():
    """Load SAR categories and target repos from _shared/categories.md.

    Falls back to built-in defaults if the file is missing (e.g., running
    the script outside the repo).
    """
    categories_file = Path(__file__).resolve().parent.parent.parent / "_shared" / "categories.md"
    cats = {}
    repos = set()

    if categories_file.exists():
        text = categories_file.read_text()
        # Parse SAR Categories table: | `category` | keyword1, keyword2, ... |
        in_sar = False
        for line in text.splitlines():
            if "## SAR Categories" in line:
                in_sar = True
                continue
            if in_sar and line.startswith("## "):
                in_sar = False
                continue
            if in_sar and line.startswith("| `"):
                m = re.match(r"\|\s*`([^`]+)`\s*\|\s*(.+?)\s*\|", line)
                if m:
                    cat_name = m.group(1)
                    keywords = [k.strip() for k in m.group(2).split(",")]
                    cats[cat_name] = keywords

        # Parse SAR Target Repos: comma-separated list in code block
        in_repos = False
        for line in text.splitlines():
            if "## SAR Target Repos" in line:
                in_repos = True
                continue
            if in_repos and line.startswith("## "):
                break
            if in_repos and line.strip() and not line.startswith("```") and not line.startswith("Used by"):
                repos.update(r.strip() for r in line.split(",") if r.strip())

    if not cats:
        log.warning("Could not load _shared/categories.md — using built-in defaults")
        cats = {
            "kernel-upgrade": ["kernel", "btrfs checksum", "alpine sdk", "driver", "phy", "pca9575", "kconfig", "kasan", "menuconfig", "btf", "ebpf"],
            "samba-perf": ["samba", "smb", "irq", "tcp tuning", "network tuning", "throughput", "async", "zero-copy", "pause frame", "rx-usecs", "qdisc", "nfsd", "sunrpc", "cpu affinity"],
            "zfs-backend": ["zfs", "dataset", "zpool", "snapshot", "quota", "refquota", "ustgcore", "dfree"],
            "nas-stability": ["stability", "stress", "xfstest", "fio stress", "sqa", "slab", "fio", "benchmark", "perf test", "preflight", "iperf"],
            "system-perf": ["memory", "oom", "socket buffer", "64kb page", "cgroup", "memhigh", "min_free_kbytes", "vm.", "sk_mem", "swap", "resource limit", "idle.slice"],
            "grpc-streamer": ["grpc", "protobuf", "event stream", "poller", "ustated", "ustate", "ustd", "gnet", "streaming"],
            "btrfs-backend": ["btrfs", "subvolume", "qgroup", "ecryptfs", "scrub", "balance", "trashcan", "worm", "snapshot prun"],
            "cloud-perf": ["async gc", "deadlock", "download state", "readdirplus", "one-shot delete", "readdir", "dir listing", "metadata", "cache invalidat", "vfs cache", "db optim", "sqlite", "page fault"],
            "cloud-cache": ["cache pin", "predownload", "autoupdate", "partial download", "cache gc", "watermark", "smart sync", "cache entry", "cache state", "bitmap"],
            "cloud-encrypt": ["client.side.encrypt", "enc.dir", "enc.unlock", "encryption"],
            "fuse-arch": ["fuse", "qrpc", "libev", "socket.handling", "daemon", "ipc", "fuse3", "meson", "autotools", "pjdfstest", "filebench"],
            "ai-skill": ["skill", "claude", "prompt", "ai", "agent", "mcp", "worktree"],
            "debian-trixie": ["trixie", "bullseye", "porting", "pyzfs", "migration"],
            "build-system": ["debfactory", "debbox", "deb package", "backport", "firmware", "build", "bootstrap", "reprepro", "package bump"],
        }
    if not repos:
        repos = {
            "unifi-drive-config", "debbox", "debfactory", "prompt-hub",
            "debbox-kernel", "debbox-base-files", "ustd", "ustate-exporter",
            "unifi-protobufs", "hybridmount",
        }
    return cats, repos

SAR_CATEGORIES, SAR_REPOS = _load_categories()


# ── Helpers ──────────────────────────────────────────────────────────────────


def date_str(dt):
    """Format datetime as YYYY-MM-DD string."""
    return dt.strftime("%Y-%m-%d")


def ts_ms_to_datetime(ts_ms):
    """Convert unix-millisecond timestamp to datetime."""
    return datetime.fromtimestamp(ts_ms / 1000, tz=timezone.utc)


def iso_to_datetime(iso_str):
    """Convert ISO 8601 string to timezone-aware UTC datetime, second precision.

    Accepts the formats Claude session files emit, e.g.
    '2026-02-26T05:54:18.845Z' or '2026-02-26T05:54:18+00:00'. Sub-second
    fractions are preserved by fromisoformat where possible; callers that
    need second-only comparison can `.replace(microsecond=0)`.
    Returns None when the input is empty or unparseable.
    """
    if not iso_str:
        return None
    s = str(iso_str).strip()
    if not s:
        return None
    # Python <3.11 fromisoformat doesn't accept trailing 'Z'
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    try:
        dt = datetime.fromisoformat(s)
    except ValueError:
        # Last-chance fallback: try date-only
        try:
            dt = datetime.strptime(s[:10], "%Y-%m-%d")
        except ValueError:
            return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    else:
        dt = dt.astimezone(timezone.utc)
    return dt


def datetime_to_iso(dt):
    """Format a datetime as ISO 8601 (UTC, second precision)."""
    if dt is None:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    else:
        dt = dt.astimezone(timezone.utc)
    return dt.replace(microsecond=0).isoformat()


def in_range(date_str_val, start, end):
    """Check if a YYYY-MM-DD date string falls within [start, end]."""
    return start <= date_str_val <= end


def in_range_dt(dt, start_dt, end_dt):
    """Check if a timezone-aware datetime falls within [start_dt, end_dt].

    Boundaries are inclusive. None datetimes are treated as out-of-range.
    """
    if dt is None or start_dt is None or end_dt is None:
        return False
    return start_dt <= dt <= end_dt


def parse_range_bounds(start_str, end_str):
    """Parse CLI --start-date/--end-date into (start_dt, end_dt) UTC datetimes.

    Accepts:
      - YYYY-MM-DD (date-only): expands start to 00:00:00, end to 23:59:59.999999
      - ISO 8601 with time: used as-is, assumes UTC if no tz

    Returns (start_dt, end_dt). Both are timezone-aware UTC datetimes.
    Raises ValueError on unparseable input.
    """
    def _parse(s, is_end):
        if not s:
            raise ValueError("empty date string")
        s = s.strip()
        # Date-only: YYYY-MM-DD with nothing else
        if re.fullmatch(r"\d{4}-\d{2}-\d{2}", s):
            base = datetime.strptime(s, "%Y-%m-%d").replace(tzinfo=timezone.utc)
            if is_end:
                return base.replace(hour=23, minute=59, second=59, microsecond=999999)
            return base
        # Otherwise treat as ISO 8601 (with time component)
        dt = iso_to_datetime(s)
        if dt is None:
            raise ValueError(f"unparseable date/time: {s!r}")
        return dt

    return _parse(start_str, is_end=False), _parse(end_str, is_end=True)


def cap_end_to_yesterday(end_dt, now=None):
    """Cap end_dt to end-of-yesterday if it covers today or the future.

    Why: collector runs that include "today" produce reports claiming the
    full day is covered. Re-running tomorrow with --skip-covered would
    then skip today entirely, losing every event after the original run
    time. Aligning with the day-granular dedup model, we instead trim
    the report so it ends at yesterday 23:59:59.999999 UTC, leaving
    today free for a future run.

    Returns the (possibly trimmed) end_dt. If the original end_dt was
    strictly before today (UTC), it is returned unchanged.
    """
    if now is None:
        now = datetime.now(timezone.utc)
    today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    if end_dt < today_start:
        return end_dt
    yesterday_end = today_start - timedelta(microseconds=1)
    return yesterday_end


def parse_report_date(date_part):
    """Parse date from report filename part. Handles YYYY-MM-DD and YYYY-MM formats."""
    if re.match(r'^\d{4}-\d{2}-\d{2}$', date_part):
        return datetime.strptime(date_part, "%Y-%m-%d").date()
    elif re.match(r'^\d{4}-\d{2}$', date_part):
        return datetime.strptime(date_part, "%Y-%m").date()
    return None


def scan_covered_dates(hostname):
    """Scan journal dirs for existing work-report date ranges.

    Returns a sorted list of (start_date, end_date) as date objects.
    """
    covered = []
    pattern = re.compile(r'work-report_(.+?)_(.+?)-to-(.+?)\.md$')

    for d in [JOURNAL_RAW, JOURNAL_INTEGRATED]:
        if not d.exists():
            continue
        for f in d.iterdir():
            m = pattern.match(f.name)
            if not m:
                continue
            host, start_s, end_s = m.groups()
            # Only match reports from the same host
            if host != hostname:
                continue
            start = parse_report_date(start_s)
            end = parse_report_date(end_s)
            if start and end:
                covered.append((start, end))

    covered.sort()
    return covered


def compute_gaps(start_date_str, end_date_str, covered_ranges):
    """Compute uncovered date gaps in [start, end] given covered ranges.

    Args:
        start_date_str: YYYY-MM-DD
        end_date_str: YYYY-MM-DD
        covered_ranges: sorted list of (date, date) tuples

    Returns list of (start_str, end_str) for uncovered gaps.
    """
    start = datetime.strptime(start_date_str, "%Y-%m-%d").date()
    end = datetime.strptime(end_date_str, "%Y-%m-%d").date()

    # Build a set of covered days
    covered_days = set()
    for cs, ce in covered_ranges:
        day = max(cs, start)
        last = min(ce, end)
        while day <= last:
            covered_days.add(day)
            day += timedelta(days=1)

    # Walk the range and find contiguous uncovered spans
    gaps = []
    current_gap_start = None
    day = start
    while day <= end:
        if day not in covered_days:
            if current_gap_start is None:
                current_gap_start = day
        else:
            if current_gap_start is not None:
                gaps.append((current_gap_start.strftime("%Y-%m-%d"),
                            (day - timedelta(days=1)).strftime("%Y-%m-%d")))
                current_gap_start = None
        day += timedelta(days=1)

    if current_gap_start is not None:
        gaps.append((current_gap_start.strftime("%Y-%m-%d"),
                    end.strftime("%Y-%m-%d")))

    return gaps


def run_cmd(cmd, timeout=5, cwd=None):
    """Run a shell command and return stdout, or None on failure."""
    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True, timeout=timeout, cwd=cwd
        )
        if result.returncode == 0:
            return result.stdout.strip()
        return None
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError) as e:
        log.debug("Command failed: %s (%s)", cmd, e)
        return None


def get_git_authors():
    """Get all git author names (local config + GitHub)."""
    authors = set()
    # Local git config
    name = run_cmd(["git", "config", "user.name"])
    if name:
        authors.add(name)
    # GitHub display name (may differ from git config)
    gh_name = run_cmd(["gh", "api", "user", "--jq", ".name"])
    if gh_name and gh_name != name:
        authors.add(gh_name)
    return sorted(authors) if authors else ["unknown"]


def classify_topic(text):
    """Classify a prompt/display text into a topic category."""
    text_lower = text.lower()
    for topic, keywords in TOPIC_KEYWORDS.items():
        for kw in keywords:
            if kw in text_lower:
                return topic
    return "other"


def classify_device(hostname):
    """Classify an SSH hostname into a device type."""
    for prefix, label in DEVICE_PREFIXES:
        if hostname.startswith(prefix):
            return label
    return "other"


def safe_json_load(path):
    """Load a JSON file, returning None on any error."""
    try:
        with open(path, "r") as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError, ValueError) as e:
        log.warning("Failed to load %s: %s", path, e)
        return None


def find_git_repos():
    """Find git repositories under $HOME using subprocess find.

    Uses find with -prune for efficiency — avoids traversing large build/cache
    directories that would cause multi-minute scans.
    """
    home = str(Path.home())
    # Build prune expressions for heavy dirs
    prune_dirs = [
        ".cache", ".local", ".cargo", "node_modules", ".npm",
        ".rustup", ".gradle", ".m2", "go", ".vscode-server",
        # Build output dirs that are huge
        "extra", "output", "ccache", ".ccache",
        # Kernel/large source trees — only want their top-level .git
        # (handled by maxdepth + source/ special case)
    ]
    # Strategy: check depth 1 (~/repo/.git) and depth 2 (~/parent/repo/.git)
    # separately for speed, rather than one deep find
    repos = set()

    # Depth 1: ~/repo/.git
    for entry in Path(home).iterdir():
        if entry.name.startswith(".") and entry.name in GIT_SCAN_EXCLUDES:
            continue
        git_dir = entry / ".git"
        if git_dir.exists():
            repos.add(str(entry))

    # Depth 2: ~/parent/repo/.git
    # Scan known parent dirs that contain sub-repos
    DEPTH2_PARENTS = {"projects", "source", "repos"}
    DEPTH2_SUBDIRS = {"source", "packages", "plugins", "repos", "projects"}

    for entry in Path(home).iterdir():
        if not entry.is_dir() or entry.name.startswith("."):
            continue
        if entry.name in GIT_SCAN_EXCLUDES:
            continue

        # If this is a known parent dir (e.g. ~/projects/), scan direct children
        if entry.name in DEPTH2_PARENTS:
            try:
                for sub_entry in entry.iterdir():
                    if sub_entry.is_dir() and (sub_entry / ".git").exists():
                        repos.add(str(sub_entry))
            except OSError:
                pass
            continue

        # Otherwise check select subdirs (e.g. ~/debfactory/source/ustd)
        for subdir_name in DEPTH2_SUBDIRS:
            subdir = entry / subdir_name
            if not subdir.is_dir():
                continue
            try:
                for sub_entry in subdir.iterdir():
                    if sub_entry.is_dir() and (sub_entry / ".git").exists():
                        repos.add(str(sub_entry))
            except OSError:
                pass

    return sorted(repos)


# ── Collectors ───────────────────────────────────────────────────────────────


def collect_infrastructure():
    """Parse SSH config for managed devices."""
    log.info("Collecting infrastructure from SSH config...")
    result = {
        "managed_devices": 0,
        "by_type": [],
        "hosts": [],
    }

    if not SSH_CONFIG.exists():
        log.warning("SSH config not found: %s", SSH_CONFIG)
        result["error"] = "SSH config not found"
        return result

    try:
        text = SSH_CONFIG.read_text()
    except OSError as e:
        result["error"] = str(e)
        return result

    # Parse Host lines (skip wildcards and patterns)
    host_re = re.compile(r"^Host\s+(\S+)\s*$", re.MULTILINE)
    hosts = []
    for m in host_re.finditer(text):
        name = m.group(1)
        if "*" in name or "?" in name:
            continue
        hosts.append(name)

    # Classify by device type
    type_counts = {}
    device_hosts = []
    for h in hosts:
        dtype = classify_device(h)
        if dtype != "other":
            type_counts[dtype] = type_counts.get(dtype, 0) + 1
            device_hosts.append({"name": h, "type": dtype})

    result["managed_devices"] = len(device_hosts)
    result["by_type"] = [
        {"type": t, "count": c}
        for t, c in sorted(type_counts.items(), key=lambda x: -x[1])
    ]
    result["hosts"] = device_hosts
    result["total_ssh_hosts"] = len(hosts)

    log.info("Found %d managed devices (%d total SSH hosts)",
             len(device_hosts), len(hosts))
    return result


def collect_shell_history(start_date, end_date):
    """Parse shell history for command usage within date range.

    Filtering is done at second precision: zsh timestamps are unix epoch
    integers, compared against the parsed range bounds (CLI may pass either
    date-only or full ISO 8601).
    """
    log.info("Collecting shell history...")
    result = {
        "total_commands": 0,
        "by_category": [],
        "ssh_targets": [],
        "scp_transfers": 0,
        "top_commands": [],
    }

    start_dt, end_dt = parse_range_bounds(start_date, end_date)

    commands = []  # (date_str, full_command)
    zsh_re = re.compile(r"^: (\d+):\d+;(.+)")

    # Parse zsh history
    if ZSH_HISTORY.exists():
        try:
            raw = ZSH_HISTORY.read_bytes()
            text = raw.decode("utf-8", errors="replace")
            cont_date = None
            cont_cmd = None
            for line in text.splitlines():
                if cont_cmd is not None:
                    # Multi-line command continuation
                    if line.endswith("\\"):
                        cont_cmd += " " + line[:-1]
                        continue
                    else:
                        cont_cmd += " " + line
                        commands.append((cont_date, cont_cmd))
                        cont_date = None
                        cont_cmd = None
                        continue

                m = zsh_re.match(line)
                if m:
                    ts = int(m.group(1))
                    cmd = m.group(2)
                    cmd_dt = datetime.fromtimestamp(ts, tz=timezone.utc)
                    if in_range_dt(cmd_dt, start_dt, end_dt):
                        cmd_date = cmd_dt.strftime("%Y-%m-%d")
                        if cmd.endswith("\\"):
                            cont_date = cmd_date
                            cont_cmd = cmd[:-1]
                            continue
                        commands.append((cmd_date, cmd))
        except OSError as e:
            log.warning("Failed to read zsh history: %s", e)

    # Parse bash history (no timestamps, include all)
    if BASH_HISTORY.exists():
        try:
            text = BASH_HISTORY.read_text(errors="replace")
            for line in text.splitlines():
                line = line.strip()
                if line and not line.startswith("#"):
                    # No date info in bash history, include if in range
                    commands.append(("unknown", line))
        except OSError as e:
            log.warning("Failed to read bash history: %s", e)

    result["total_commands"] = len(commands)

    # Categorize commands
    cat_counts = {}
    cmd_counts = {}
    ssh_targets = {}

    for date_str_val, cmd in commands:
        # Get first word (the command name)
        parts = cmd.split()
        if not parts:
            continue
        first_word = parts[0]
        # Strip leading sudo
        if first_word == "sudo" and len(parts) > 1:
            first_word = parts[1]

        # Categorize
        cat = CMD_TO_CATEGORY.get(first_word, "other")
        cat_counts[cat] = cat_counts.get(cat, 0) + 1
        cmd_counts[first_word] = cmd_counts.get(first_word, 0) + 1

        # Track SSH targets
        if first_word == "ssh" and len(parts) > 1:
            target = parts[-1]  # last arg is usually the host
            if not target.startswith("-"):
                ssh_targets[target] = ssh_targets.get(target, 0) + 1

        # Count SCP transfers
        if first_word == "scp":
            result["scp_transfers"] += 1

    result["by_category"] = [
        {"category": cat, "count": cnt}
        for cat, cnt in sorted(cat_counts.items(), key=lambda x: -x[1])
    ]
    result["ssh_targets"] = [
        {"target": t, "count": c}
        for t, c in sorted(ssh_targets.items(), key=lambda x: -x[1])
    ]
    result["top_commands"] = [
        {"command": cmd, "count": cnt}
        for cmd, cnt in sorted(cmd_counts.items(), key=lambda x: -x[1])[:30]
    ]

    log.info("Found %d commands in date range", len(commands))
    return result


def collect_git(start_date, end_date, authors, no_fetch=False):
    """Collect git commit data from all repos under $HOME."""
    log.info("Collecting git data (authors=%s, no_fetch=%s)...", authors, no_fetch)
    result = {
        "total_commits": 0,
        "total_prs": 0,
        "total_insertions": 0,
        "total_deletions": 0,
        "by_repo": [],
    }

    repos = find_git_repos()
    log.info("Found %d git repos to scan", len(repos))

    pr_re = re.compile(r"\(#(\d+)\)")
    stat_re = re.compile(
        r"(\d+) files? changed(?:, (\d+) insertions?\(\+\))?(?:, (\d+) deletions?\(-\))?"
    )

    for repo_path in repos:
        repo_name = str(Path(repo_path).relative_to(Path.home()))

        # Fetch latest refs from origin (unless --no-fetch)
        if not no_fetch:
            run_cmd(["git", "-C", repo_path, "fetch", "--quiet", "origin"], timeout=15)

        # Get commits in range for all authors (dedup by SHA)
        all_commits_by_sha = {}
        for author in authors:
            log_output = run_cmd(
                ["git", "-C", repo_path, "log", "--all",
                 "--author=" + author,
                 "--after=" + start_date,
                 "--before=" + end_date + "T23:59:59",
                 "--format=%H|%ad|%s", "--date=short"],
                timeout=10,
            )
            if log_output:
                for line in log_output.splitlines():
                    line = line.strip()
                    if not line:
                        continue
                    parts = line.split("|", 2)
                    if len(parts) < 3:
                        continue
                    sha, date, subject = parts
                    all_commits_by_sha[sha] = {"sha": sha[:8], "date": date, "subject": subject}

        if not all_commits_by_sha:
            continue

        commits = sorted(all_commits_by_sha.values(), key=lambda c: c["date"], reverse=True)
        prs = sum(1 for c in commits if pr_re.search(c["subject"]))

        # Get line stats for all authors (dedup by combining)
        insertions = 0
        deletions = 0
        stat_shas = set()
        for author in authors:
            stat_output = run_cmd(
                ["git", "-C", repo_path, "log", "--all",
                 "--author=" + author,
                 "--after=" + start_date,
                 "--before=" + end_date + "T23:59:59",
                 "--format=%H", "--shortstat"],
                timeout=10,
            )
            if stat_output:
                current_sha = None
                for line in stat_output.splitlines():
                    line = line.strip()
                    if not line:
                        continue
                    # Lines alternate: SHA then stat line
                    if len(line) == 40 and all(c in "0123456789abcdef" for c in line):
                        current_sha = line
                        continue
                    m = stat_re.search(line)
                    if m and current_sha and current_sha not in stat_shas:
                        stat_shas.add(current_sha)
                        insertions += int(m.group(2) or 0)
                        deletions += int(m.group(3) or 0)
                    current_sha = None

        # Get accurate PR count from GitHub API for github.com repos
        remote_url = run_cmd(["git", "-C", repo_path, "remote", "get-url", "origin"], timeout=5)
        if remote_url and "github.com" in remote_url:
            gh_match = re.search(r"github\.com[:/](.+?)(?:\.git)?$", remote_url)
            if gh_match:
                gh_repo = gh_match.group(1)
                gh_prs = run_cmd(
                    ["gh", "pr", "list", "--repo", gh_repo,
                     "--state", "merged", "--author", "@me", "--limit", "500",
                     "--json", "number,mergedAt",
                     "--jq", f'[.[] | select(.mergedAt >= "{start_date}" and .mergedAt < "{end_date}T23:59:59")] | length'],
                    timeout=30,
                )
                if gh_prs and gh_prs.isdigit():
                    prs = int(gh_prs)
                    log.info("GitHub API: %s has %d merged PRs", gh_repo, prs)

        repo_data = {
            "repo": repo_name,
            "commits": len(commits),
            "prs": prs,
            "insertions": insertions,
            "deletions": deletions,
            "recent_commits": commits,
        }
        result["by_repo"].append(repo_data)
        result["total_commits"] += len(commits)
        result["total_prs"] += prs
        result["total_insertions"] += insertions
        result["total_deletions"] += deletions

    # Sort repos by commit count descending
    result["by_repo"].sort(key=lambda r: -r["commits"])
    log.info("Found %d commits across %d repos",
             result["total_commits"], len(result["by_repo"]))
    return result


_STOP_WORDS = {
    "a", "an", "the", "to", "in", "of", "for", "and", "from",
    "is", "it", "on", "at", "by", "with",
}
_TOKEN_STRIP_RE = re.compile(r"[#()\[\]{}:,'\"]")


def _tokenize_subject(subject):
    """Lowercase, strip punctuation, split on whitespace, drop stop words."""
    cleaned = _TOKEN_STRIP_RE.sub("", subject.lower())
    return {
        word for word in cleaned.split()
        if word and word not in _STOP_WORDS
    }


def _jaccard(a, b):
    if not a or not b:
        return 0.0
    return len(a & b) / len(a | b)


def compute_initiatives(git_data):
    """Group commits into cross-repo/clustered initiatives.

    Deduplicates commits that share a SHA across worktree-branch repos, then
    single-linkage groups the remaining commits by subject-token Jaccard
    similarity (>= 0.5). Deterministic — no LLM calls, no network.
    """
    total_raw = 0
    by_sha = {}  # sha -> {sha, date, subject, repos: [repo, ...]}

    for repo_entry in git_data.get("by_repo", []):
        repo_name = repo_entry["repo"]
        for commit in repo_entry.get("recent_commits", []):
            total_raw += 1
            sha = commit["sha"]
            if sha in by_sha:
                if repo_name not in by_sha[sha]["repos"]:
                    by_sha[sha]["repos"].append(repo_name)
            else:
                by_sha[sha] = {
                    "sha": sha,
                    "date": commit["date"],
                    "subject": commit["subject"],
                    "repos": [repo_name],
                }

    unique_commits = list(by_sha.values())
    for commit in unique_commits:
        commit["tokens"] = _tokenize_subject(commit["subject"])

    # Single-linkage grouping by Jaccard similarity on subject tokens.
    groups = []  # list of list of commit dicts
    for commit in unique_commits:
        target_group = None
        for group in groups:
            if any(_jaccard(commit["tokens"], other["tokens"]) >= 0.5
                   for other in group):
                target_group = group
                break
        if target_group is not None:
            target_group.append(commit)
        else:
            groups.append([commit])

    cross_repo = []
    for group in groups:
        repos = sorted({repo for c in group for repo in c["repos"]})
        commit_count = len(group)
        if len(repos) < 2 and commit_count < 3:
            continue
        label = min((c["subject"] for c in group), key=len)
        shas = [c["sha"] for c in group]
        dates = sorted({c["date"] for c in group})
        cross_repo.append({
            "label": label,
            "repos": repos,
            "commits": commit_count,
            "shas": shas,
            "dates": dates,
        })

    cross_repo.sort(key=lambda g: -g["commits"])

    unique_shas = len(unique_commits)
    duplicates_removed = total_raw - unique_shas
    log.info("Initiatives: %d cross-repo groups, %d→%d SHA dedup",
             len(cross_repo), total_raw, unique_shas)

    return {
        "cross_repo": cross_repo,
        "sha_dedup_stats": {
            "total_raw": total_raw,
            "unique_shas": unique_shas,
            "duplicates_removed": duplicates_removed,
        },
    }


def _categorize_commit(subject, body, files):
    """Match a commit to SAR categories by keyword search in subject+body+files."""
    text = (subject + " " + body + " " + files).lower()
    categories = []
    for cat, keywords in SAR_CATEGORIES.items():
        for kw in keywords:
            if kw.lower() in text:
                categories.append(cat)
                break
    return categories if categories else ["other"]


def collect_git_sar(start_date, end_date, authors):
    """Collect detailed, categorized git commits from SAR target repos.

    Returns dict with commits grouped by category, each with subject, body
    (first 3 lines), and file stats. This supplements the regular collect_git()
    data for SAR case study extraction.
    """
    log.info("Collecting SAR git data from %d target repos...", len(SAR_REPOS))

    repos = find_git_repos()
    # Filter to SAR target repos only
    sar_repo_paths = []
    for repo_path in repos:
        repo_basename = Path(repo_path).name
        if repo_basename in SAR_REPOS:
            sar_repo_paths.append(repo_path)

    log.info("Found %d SAR repos to scan: %s",
             len(sar_repo_paths),
             [Path(p).name for p in sar_repo_paths])

    # Collect detailed commits from each SAR repo
    all_commits = []  # list of (repo_name, commit_dict)

    for repo_path in sar_repo_paths:
        repo_name = Path(repo_path).name

        for author in authors:
            # Get subject + body + stat in one call using a delimiter
            # Format: SHA|date|subject then body lines then --stat output
            # We use a unique separator to split commits
            log_output = run_cmd(
                ["git", "-C", repo_path, "log", "--all",
                 "--author=" + author,
                 "--after=" + start_date,
                 "--before=" + end_date + "T23:59:59",
                 "--format=__COMMIT__%H|%ad|%s%n%b__END_BODY__",
                 "--date=short", "--stat"],
                timeout=30,
            )
            if not log_output:
                continue

            # Parse the output: split by __COMMIT__ delimiter
            raw_commits = log_output.split("__COMMIT__")
            for raw in raw_commits:
                raw = raw.strip()
                if not raw:
                    continue

                # Split header from body+stat
                lines = raw.split("\n", 1)
                if not lines:
                    continue

                header = lines[0].strip()
                parts = header.split("|", 2)
                if len(parts) < 3:
                    continue

                sha, date, subject = parts[0][:8], parts[1], parts[2]

                # Extract body (between subject line and __END_BODY__)
                body = ""
                files_text = ""
                if len(lines) > 1:
                    rest = lines[1]
                    if "__END_BODY__" in rest:
                        body_part, stat_part = rest.split("__END_BODY__", 1)
                        # Body: first 3 non-empty lines
                        body_lines = [l.strip() for l in body_part.strip().splitlines()
                                      if l.strip()][:3]
                        body = "\n".join(body_lines)
                        # File stats from --stat output
                        stat_lines = [l.strip() for l in stat_part.strip().splitlines()
                                      if l.strip() and "|" in l]
                        files_text = "\n".join(stat_lines)

                categories = _categorize_commit(subject, body, files_text)

                commit_data = {
                    "sha": sha,
                    "date": date,
                    "subject": subject,
                    "body": body,
                    "files": files_text,
                    "repo": repo_name,
                    "categories": categories,
                }
                all_commits.append(commit_data)

    # Deduplicate by SHA (same commit may appear from multiple authors)
    seen_shas = set()
    unique_commits = []
    for c in all_commits:
        if c["sha"] not in seen_shas:
            seen_shas.add(c["sha"])
            unique_commits.append(c)

    # Group by category
    by_category = {}
    for c in unique_commits:
        for cat in c["categories"]:
            by_category.setdefault(cat, []).append(c)

    # Sort each category by date descending
    for cat in by_category:
        by_category[cat].sort(key=lambda c: c["date"], reverse=True)

    # Build summary
    summary = {}
    for cat, commits in by_category.items():
        repos_in_cat = sorted(set(c["repo"] for c in commits))
        summary[cat] = {
            "commits": len(commits),
            "repos": repos_in_cat,
        }

    log.info("SAR collection: %d unique commits across %d categories",
             len(unique_commits), len(by_category))

    return {
        "total_commits": len(unique_commits),
        "summary": summary,
        "by_category": {cat: commits for cat, commits in
                        sorted(by_category.items(),
                               key=lambda x: -len(x[1]))},
    }


def collect_test_artifacts(start_date, end_date):
    """Scan test result directories for sessions in date range."""
    log.info("Collecting test artifacts...")
    result = {
        "total_sessions": 0,
        "total_runs": 0,
        "total_size_mb": 0,
        "sessions": [],
    }

    if not TEST_RESULTS_DIR.exists():
        log.warning("Test results dir not found: %s", TEST_RESULTS_DIR)
        result["error"] = "Test results directory not found"
        return result

    # Date prefix pattern: YYYYMMDD_description
    date_prefix_re = re.compile(r"^(\d{8})_(.+)$")
    # Convert date range to YYYYMMDD for comparison
    start_compact = start_date.replace("-", "")
    end_compact = end_date.replace("-", "")

    # Walk all subdirectories looking for session dirs
    for skill_dir in TEST_RESULTS_DIR.iterdir():
        if not skill_dir.is_dir():
            continue

        # Check raw/ subdirectory first, then the skill dir itself
        scan_dirs = []
        raw_dir = skill_dir / "raw"
        if raw_dir.is_dir():
            scan_dirs.append(raw_dir)
        else:
            scan_dirs.append(skill_dir)

        for scan_dir in scan_dirs:
            try:
                for entry in scan_dir.iterdir():
                    if not entry.is_dir():
                        continue
                    m = date_prefix_re.match(entry.name)
                    if not m:
                        continue
                    session_date = m.group(1)
                    if not (start_compact <= session_date <= end_compact):
                        continue

                    description = m.group(2)
                    # Count fio runs inside
                    fio_dirs = list(entry.glob("**/*_fio"))
                    run_count = len(fio_dirs)

                    # Get total size
                    size_output = run_cmd(
                        ["du", "-sm", str(entry)], timeout=3
                    )
                    size_mb = 0
                    if size_output:
                        try:
                            size_mb = int(size_output.split()[0])
                        except (ValueError, IndexError):
                            pass

                    # Extract device names from fio dir names
                    devices = set()
                    for fd in fio_dirs:
                        parts = fd.name.split("_")
                        for p in parts:
                            if any(p.startswith(pfx) for pfx, _ in DEVICE_PREFIXES):
                                devices.add(p)

                    session = {
                        "name": entry.name,
                        "date": f"{session_date[:4]}-{session_date[4:6]}-{session_date[6:8]}",
                        "description": description,
                        "runs": run_count,
                        "size_mb": size_mb,
                        "devices": sorted(devices),
                        "skill": skill_dir.name,
                    }
                    result["sessions"].append(session)
                    result["total_sessions"] += 1
                    result["total_runs"] += run_count
                    result["total_size_mb"] += size_mb
            except OSError as e:
                log.warning("Error scanning %s: %s", scan_dir, e)

    result["sessions"].sort(key=lambda s: s["date"])
    log.info("Found %d test sessions with %d runs",
             result["total_sessions"], result["total_runs"])
    return result


def collect_claude_sessions(start_date, end_date, detailed=False):
    """Collect Claude Code session data.

    Quick mode: uses history.jsonl + stats-cache.json + sessions-index.json
    Detailed mode: additionally parses per-session .jsonl files
    """
    log.info("Collecting Claude sessions (detailed=%s)...", detailed)
    start_dt, end_dt = parse_range_bounds(start_date, end_date)
    result = {
        "total_prompts": 0,
        "total_sessions": 0,
        "total_messages": 0,
        "total_tool_calls": 0,
        "by_project": [],
        "by_topic": [],
        "by_day": [],
        "session_summaries": [],
        "first_prompt_timestamp": None,
        "last_prompt_timestamp": None,
    }

    # ── 1. stats-cache.json for aggregate daily counts ───────────────────
    stats = safe_json_load(STATS_CACHE)
    if stats:
        last_computed = stats.get("lastComputedDate", "")
        log.info("Stats cache lastComputedDate: %s", last_computed)

        # Use dailyActivity for aggregate counts
        daily = stats.get("dailyActivity", [])
        for entry in daily:
            d = entry.get("date", "")
            if in_range(d, start_date, end_date):
                result["by_day"].append({
                    "date": d,
                    "messages": entry.get("messageCount", 0),
                    "sessions": entry.get("sessionCount", 0),
                    "tool_calls": entry.get("toolCallCount", 0),
                })
                result["total_messages"] += entry.get("messageCount", 0)
                result["total_tool_calls"] += entry.get("toolCallCount", 0)

        # Sum session counts from daily data
        result["total_sessions"] = sum(
            d.get("sessions", 0) for d in result["by_day"]
        )

        # Check staleness: if lastComputedDate is before end_date,
        # days after it need history.jsonl fallback
        stale_after = last_computed

        # Model usage from stats
        if detailed and "modelUsage" in stats:
            result["detailed"] = result.get("detailed", {})
            result["detailed"]["models_used"] = {}
            for model, usage in stats["modelUsage"].items():
                result["detailed"]["models_used"][model] = {
                    "input_tokens": usage.get("inputTokens", 0),
                    "output_tokens": usage.get("outputTokens", 0),
                    "cache_read_tokens": usage.get("cacheReadInputTokens", 0),
                    "cache_creation_tokens": usage.get("cacheCreationInputTokens", 0),
                }
    else:
        stale_after = "1970-01-01"

    # ── 2. history.jsonl for per-project/topic breakdown ─────────────────
    project_counts = {}
    topic_counts = {}
    session_ids = set()
    prompt_count = 0
    prompts_by_day = {}  # date -> count (for filling stale stats gaps)

    if HISTORY_JSONL.exists():
        try:
            with open(HISTORY_JSONL, "r", errors="replace") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        entry = json.loads(line)
                    except json.JSONDecodeError:
                        continue

                    ts = entry.get("timestamp")
                    if not ts:
                        continue

                    entry_dt = ts_ms_to_datetime(ts)
                    if not in_range_dt(entry_dt, start_dt, end_dt):
                        continue

                    entry_date = entry_dt.strftime("%Y-%m-%d")
                    # Track sub-day range bounds at second precision
                    if (result["first_prompt_timestamp"] is None
                            or entry_dt < iso_to_datetime(result["first_prompt_timestamp"])):
                        result["first_prompt_timestamp"] = datetime_to_iso(entry_dt)
                    if (result["last_prompt_timestamp"] is None
                            or entry_dt > iso_to_datetime(result["last_prompt_timestamp"])):
                        result["last_prompt_timestamp"] = datetime_to_iso(entry_dt)

                    prompt_count += 1
                    prompts_by_day[entry_date] = prompts_by_day.get(entry_date, 0) + 1

                    # Track unique sessions
                    sid = entry.get("sessionId")
                    if sid:
                        session_ids.add(sid)

                    # Project breakdown
                    project = entry.get("project", "unknown")
                    # Shorten to relative path from home
                    home_str = str(Path.home())
                    if project.startswith(home_str):
                        project = project[len(home_str):].lstrip("/")
                    project_counts[project] = project_counts.get(project, 0) + 1

                    # Topic classification
                    display = entry.get("display", "")
                    topic = classify_topic(display)
                    topic_counts[topic] = topic_counts.get(topic, 0) + 1
        except OSError as e:
            log.warning("Failed to read history.jsonl: %s", e)

    result["total_prompts"] = prompt_count
    result["by_project"] = [
        {"project": p, "prompts": c}
        for p, c in sorted(project_counts.items(), key=lambda x: -x[1])
    ]
    result["by_topic"] = [
        {"topic": t, "prompts": c}
        for t, c in sorted(topic_counts.items(), key=lambda x: -x[1])
    ]

    # Fill in session count from history.jsonl if stats cache was stale
    if not result["total_sessions"] and session_ids:
        result["total_sessions"] = len(session_ids)
        log.info("Stats cache stale — session count from history.jsonl: %d",
                 len(session_ids))

    # Fill in by_day from history.jsonl if stats cache had no matching days
    if not result["by_day"] and prompts_by_day:
        for d in sorted(prompts_by_day):
            result["by_day"].append({
                "date": d,
                "prompts": prompts_by_day[d],
                "messages": 0,  # not available from history.jsonl
                "sessions": 0,
                "tool_calls": 0,
            })
        # Use prompt count as rough message estimate when stats unavailable
        result["total_messages"] = prompt_count
        log.info("Stats cache stale — using history.jsonl for daily counts")

    # ── 3. sessions-index.json for session summaries ─────────────────────
    if PROJECTS_DIR.exists():
        for proj_dir in PROJECTS_DIR.iterdir():
            if not proj_dir.is_dir():
                continue
            idx_file = proj_dir / "sessions-index.json"
            if not idx_file.exists():
                continue
            idx = safe_json_load(idx_file)
            if not idx:
                continue
            skipped = 0
            for entry in idx.get("entries", []):
                sid = entry.get("sessionId", "")
                if sid not in session_ids:
                    skipped += 1
                    continue
                result["session_summaries"].append({
                    "project": idx.get("originalPath", ""),
                    "session_id": sid,
                    "summary": entry.get("summary", ""),
                })
            if skipped:
                log.debug("Skipped %d sessions not in date range for %s",
                          skipped, proj_dir.name)

    # ── 4. Detailed mode: parse per-session .jsonl files ─────────────────
    if detailed and PROJECTS_DIR.exists():
        log.info("Parsing per-session .jsonl files for detailed analysis...")
        detail = result.get("detailed", {})
        tool_usage = {}
        files_edited = set()
        total_tokens = {"input": 0, "output": 0, "cache_read": 0, "cache_creation": 0}
        models_seen = {}

        for proj_dir in PROJECTS_DIR.iterdir():
            if not proj_dir.is_dir():
                continue
            for jsonl_file in proj_dir.glob("*.jsonl"):
                # Skip non-session files
                if jsonl_file.name == "sessions-index.json":
                    continue
                # Quick check: is any message in range?
                try:
                    session_in_range = False
                    with open(jsonl_file, "r", errors="replace") as f:
                        for jline in f:
                            jline = jline.strip()
                            if not jline:
                                continue
                            try:
                                msg = json.loads(jline)
                            except json.JSONDecodeError:
                                continue

                            msg_ts = msg.get("timestamp", "")
                            if msg_ts and "T" in str(msg_ts):
                                msg_dt = iso_to_datetime(msg_ts)
                                if in_range_dt(msg_dt, start_dt, end_dt):
                                    session_in_range = True

                            if not session_in_range:
                                continue

                            # Extract tool usage from assistant messages
                            if msg.get("type") == "assistant":
                                inner = msg.get("message", {})
                                content = inner.get("content", [])
                                if isinstance(content, list):
                                    for block in content:
                                        if isinstance(block, dict) and block.get("type") == "tool_use":
                                            tool_name = block.get("name", "unknown")
                                            tool_usage[tool_name] = tool_usage.get(tool_name, 0) + 1

                                            # Track file edits
                                            inp = block.get("input", {})
                                            if tool_name in ("Edit", "Write", "Read") and "file_path" in inp:
                                                if tool_name in ("Edit", "Write"):
                                                    files_edited.add(inp["file_path"])

                                # Token usage
                                usage = inner.get("usage", {})
                                if usage:
                                    total_tokens["input"] += usage.get("input_tokens", 0)
                                    total_tokens["output"] += usage.get("output_tokens", 0)
                                    total_tokens["cache_read"] += usage.get("cache_read_input_tokens", 0)
                                    total_tokens["cache_creation"] += usage.get("cache_creation_input_tokens", 0)

                                # Model tracking
                                model = inner.get("model", "")
                                if model:
                                    models_seen[model] = models_seen.get(model, 0) + 1

                except OSError as e:
                    log.debug("Failed to read session %s: %s", jsonl_file, e)

        detail["tool_usage"] = dict(sorted(tool_usage.items(), key=lambda x: -x[1]))
        detail["files_edited"] = sorted(files_edited)[:100]  # Cap at 100
        detail["total_tokens"] = total_tokens
        # Merge model counts if not already set from stats cache
        if "models_used" not in detail:
            detail["models_used"] = {}
        detail["models_message_count"] = dict(
            sorted(models_seen.items(), key=lambda x: -x[1])
        )
        result["detailed"] = detail

    log.info("Found %d prompts across %d projects",
             result["total_prompts"], len(result["by_project"]))
    return result


def collect_opencode_sessions(start_date, end_date, detailed=False):
    """Collect OpenCode session data from its SQLite database.

    Mirrors the shape of collect_claude_sessions output so downstream
    report composition can treat both identically.

    OpenCode stores everything in ~/.local/share/opencode/opencode.db:
      - session: one row per conversation (has cost, tokens, model, title)
      - project: worktree path (like CC's project dir)
      - message: per-turn messages with role in JSON `data` column
      - part:    sub-message parts (text, tool calls) with JSON `data`

    Timestamps are Unix milliseconds (same convention as CC history.jsonl).
    """
    log.info("Collecting OpenCode sessions (detailed=%s)...", detailed)
    start_dt, end_dt = parse_range_bounds(start_date, end_date)

    result = {
        "total_prompts": 0,
        "total_sessions": 0,
        "total_messages": 0,
        "total_cost": 0.0,
        "by_project": [],
        "by_topic": [],
        "by_day": [],
        "session_summaries": [],
        "first_prompt_timestamp": None,
        "last_prompt_timestamp": None,
    }

    if not OPENCODE_DB.exists():
        log.info("OpenCode DB not found: %s — skipping", OPENCODE_DB)
        return result

    import sqlite3
    import shutil
    import tempfile

    # Copy DB+WAL to a temp location to avoid locking a running OpenCode
    tmp_dir = tempfile.mkdtemp(prefix="oc_journal_")
    tmp_db = Path(tmp_dir) / "opencode.db"
    try:
        shutil.copy2(OPENCODE_DB, tmp_db)
        wal = OPENCODE_DB.with_suffix(".db-wal")
        shm = OPENCODE_DB.with_suffix(".db-shm")
        if wal.exists():
            shutil.copy2(wal, tmp_db.with_suffix(".db-wal"))
        if shm.exists():
            shutil.copy2(shm, tmp_db.with_suffix(".db-shm"))
    except OSError as e:
        log.warning("Failed to copy OpenCode DB: %s", e)
        return result

    try:
        conn = sqlite3.connect(str(tmp_db))
        conn.row_factory = sqlite3.Row
        cur = conn.cursor()

        start_ms = int(start_dt.timestamp() * 1000)
        end_ms = int(end_dt.timestamp() * 1000)

        # ── 1. Session-level aggregates ──────────────────────────────────
        cur.execute("""
            SELECT s.id, s.title, s.model, s.cost,
                   s.tokens_input, s.tokens_output,
                   s.tokens_cache_read, s.tokens_cache_write,
                   s.tokens_reasoning,
                   s.time_created, s.time_updated,
                   s.directory, s.agent,
                   p.worktree AS project_worktree
            FROM session s
            LEFT JOIN project p ON s.project_id = p.id
            WHERE s.time_created >= ? AND s.time_created <= ?
            ORDER BY s.time_created
        """, (start_ms, end_ms))

        sessions = cur.fetchall()
        result["total_sessions"] = len(sessions)

        project_counts = {}   # project_path -> prompt_count (estimated from messages)
        topic_counts = {}
        day_agg = {}          # date -> {sessions, cost, tokens_in, tokens_out, ...}
        total_cost = 0.0
        total_tokens_in = 0
        total_tokens_out = 0
        total_cache_read = 0
        total_cache_write = 0
        total_reasoning = 0

        for s in sessions:
            s_id = s["id"]
            created_dt = ts_ms_to_datetime(s["time_created"])
            day_key = created_dt.strftime("%Y-%m-%d")

            # Track first/last prompt timestamp
            iso_ts = datetime_to_iso(created_dt)
            if (result["first_prompt_timestamp"] is None
                    or created_dt < iso_to_datetime(result["first_prompt_timestamp"])):
                result["first_prompt_timestamp"] = iso_ts
            if (result["last_prompt_timestamp"] is None
                    or created_dt > iso_to_datetime(result["last_prompt_timestamp"])):
                result["last_prompt_timestamp"] = iso_ts

            cost = s["cost"] or 0.0
            total_cost += cost
            total_tokens_in += s["tokens_input"] or 0
            total_tokens_out += s["tokens_output"] or 0
            total_cache_read += s["tokens_cache_read"] or 0
            total_cache_write += s["tokens_cache_write"] or 0
            total_reasoning += s["tokens_reasoning"] or 0

            # Project breakdown — use worktree, fall back to directory
            project = s["project_worktree"] or s["directory"] or "unknown"
            home_str = str(Path.home())
            if project.startswith(home_str):
                project = project[len(home_str):].lstrip("/")
            project_counts[project] = project_counts.get(project, 0) + 1

            # Topic classification from title
            title = s["title"] or ""
            topic = classify_topic(title)
            topic_counts[topic] = topic_counts.get(topic, 0) + 1

            # Per-day aggregation
            if day_key not in day_agg:
                day_agg[day_key] = {
                    "date": day_key,
                    "sessions": 0,
                    "cost": 0.0,
                    "tokens_in": 0,
                    "tokens_out": 0,
                }
            day_agg[day_key]["sessions"] += 1
            day_agg[day_key]["cost"] += cost
            day_agg[day_key]["tokens_in"] += s["tokens_input"] or 0
            day_agg[day_key]["tokens_out"] += s["tokens_output"] or 0

            # Session summary
            # Parse model JSON to extract model name
            model_str = s["model"] or ""
            try:
                model_info = json.loads(model_str)
                model_name = model_info.get("id", model_str)
            except (json.JSONDecodeError, TypeError):
                model_name = model_str

            result["session_summaries"].append({
                "session_id": s_id[:12],
                "project": project,
                "summary": title,
                "model": model_name,
                "agent": s["agent"],
                "cost": round(cost, 4),
                "date": day_key,
            })

        # ── 2. Count user messages as "prompts" ─────────────────────────
        cur.execute("""
            SELECT m.id, m.session_id, m.time_created
            FROM message m
            WHERE m.time_created >= ? AND m.time_created <= ?
              AND m.data LIKE '%"role":"user"%'
        """, (start_ms, end_ms))
        user_messages = cur.fetchall()
        result["total_prompts"] = len(user_messages)
        result["total_messages"] = len(user_messages)  # user messages count

        # Also count total messages (user + assistant)
        cur.execute("""
            SELECT COUNT(*) FROM message
            WHERE time_created >= ? AND time_created <= ?
        """, (start_ms, end_ms))
        result["total_messages"] = cur.fetchone()[0]

        result["total_cost"] = round(total_cost, 4)
        result["by_project"] = [
            {"project": p, "prompts": c}
            for p, c in sorted(project_counts.items(), key=lambda x: -x[1])
        ]
        result["by_topic"] = [
            {"topic": t, "prompts": c}
            for t, c in sorted(topic_counts.items(), key=lambda x: -x[1])
        ]
        result["by_day"] = [
            day_agg[d] for d in sorted(day_agg)
        ]

        # ── 3. Detailed mode: tool usage from part table ─────────────────
        if detailed:
            detail = {}
            tool_usage = {}

            cur.execute("""
                SELECT p.data
                FROM part p
                WHERE p.time_created >= ? AND p.time_created <= ?
                  AND p.data LIKE '%"type":"tool"%'
            """, (start_ms, end_ms))
            for row in cur.fetchall():
                try:
                    pdata = json.loads(row[0])
                except (json.JSONDecodeError, TypeError):
                    continue
                if pdata.get("type") == "tool":
                    tool_name = pdata.get("tool", "unknown")
                    tool_usage[tool_name] = tool_usage.get(tool_name, 0) + 1

            detail["tool_usage"] = dict(sorted(tool_usage.items(), key=lambda x: -x[1]))
            detail["total_tokens"] = {
                "input": total_tokens_in,
                "output": total_tokens_out,
                "cache_read": total_cache_read,
                "cache_write": total_cache_write,
                "reasoning": total_reasoning,
            }
            result["detailed"] = detail

        conn.close()
    except Exception as e:
        log.warning("Failed to query OpenCode DB: %s", e)
    finally:
        # Clean up temp copy
        shutil.rmtree(tmp_dir, ignore_errors=True)

    log.info("OpenCode: %d sessions, %d prompts, $%.4f cost across %d projects",
             result["total_sessions"], result["total_prompts"],
             result.get("total_cost", 0), len(result["by_project"]))
    return result


# ── Summary & Output ─────────────────────────────────────────────────────────


def print_summary(data):
    """Print a human-readable summary to stderr."""
    meta = data["meta"]
    print(f"\n{'=' * 60}", file=sys.stderr)
    print(f"Work Report Data: {meta['hostname']}", file=sys.stderr)
    print(f"Period: {meta['start_date']} to {meta['end_date']}", file=sys.stderr)
    print(f"{'=' * 60}", file=sys.stderr)

    cs = data.get("claude_sessions", {})
    print(f"\nClaude Sessions: {cs.get('total_prompts', 0)} prompts, "
          f"{cs.get('total_sessions', 0)} sessions, "
          f"{cs.get('total_messages', 0)} messages", file=sys.stderr)

    git = data.get("git", {})
    print(f"Git: {git.get('total_commits', 0)} commits, "
          f"{git.get('total_prs', 0)} PRs, "
          f"+{git.get('total_insertions', 0)}/-{git.get('total_deletions', 0)} lines",
          file=sys.stderr)
    if git.get("by_repo"):
        for r in git["by_repo"][:5]:
            print(f"  {r['repo']}: {r['commits']} commits", file=sys.stderr)

    init = data.get("initiatives", {})
    dedup = init.get("sha_dedup_stats", {})
    print(f"Initiatives: {len(init.get('cross_repo', []))} cross-repo groups, "
          f"{dedup.get('total_raw', 0)}→{dedup.get('unique_shas', 0)} SHA dedup",
          file=sys.stderr)

    sh = data.get("shell", {})
    print(f"Shell: {sh.get('total_commands', 0)} commands", file=sys.stderr)
    if sh.get("by_category"):
        cats = ", ".join(f"{c['category']}={c['count']}" for c in sh["by_category"][:5])
        print(f"  Top categories: {cats}", file=sys.stderr)

    ta = data.get("test_artifacts", {})
    print(f"Test Artifacts: {ta.get('total_sessions', 0)} sessions, "
          f"{ta.get('total_runs', 0)} runs, "
          f"{ta.get('total_size_mb', 0)} MB", file=sys.stderr)

    infra = data.get("infrastructure", {})
    print(f"Infrastructure: {infra.get('managed_devices', 0)} managed devices "
          f"({infra.get('total_ssh_hosts', 0)} total SSH hosts)", file=sys.stderr)

    if cs.get("detailed"):
        d = cs["detailed"]
        if d.get("tool_usage"):
            top_tools = list(d["tool_usage"].items())[:5]
            tools_str = ", ".join(f"{t}={c}" for t, c in top_tools)
            print(f"  Top tools: {tools_str}", file=sys.stderr)
        if d.get("files_edited"):
            print(f"  Files edited: {len(d['files_edited'])}", file=sys.stderr)

    oc = data.get("opencode_sessions", {})
    if oc.get("total_sessions", 0) > 0:
        print(f"\nOpenCode Sessions: {oc.get('total_prompts', 0)} prompts, "
              f"{oc.get('total_sessions', 0)} sessions, "
              f"{oc.get('total_messages', 0)} messages, "
              f"${oc.get('total_cost', 0):.4f} cost", file=sys.stderr)
        if oc.get("by_project"):
            for p in oc["by_project"][:5]:
                print(f"  {p['project']}: {p['prompts']} sessions", file=sys.stderr)
        if oc.get("detailed", {}).get("tool_usage"):
            top_tools = list(oc["detailed"]["tool_usage"].items())[:5]
            tools_str = ", ".join(f"{t}={c}" for t, c in top_tools)
            print(f"  Top tools: {tools_str}", file=sys.stderr)

    print(f"\n{'=' * 60}\n", file=sys.stderr)


# ── Main ─────────────────────────────────────────────────────────────────────


def main():
    parser = argparse.ArgumentParser(
        description="Collect work activity data from this host into structured JSON."
    )
    parser.add_argument(
        "--start-date", type=str,
        default=date_str(datetime.now(timezone.utc) - timedelta(days=7)),
        help=("Start date YYYY-MM-DD or ISO 8601 with time (default: 7 days ago). "
              "Date-only expands to 00:00:00 UTC."),
    )
    parser.add_argument(
        "--end-date", type=str,
        default=date_str(datetime.now(timezone.utc)),
        help=("End date YYYY-MM-DD or ISO 8601 with time (default: today). "
              "Date-only expands to 23:59:59.999999 UTC."),
    )
    parser.add_argument(
        "--output", type=str, default=None,
        help="Output JSON path (default: ~/work-report-data_<host>_<start>-to-<end>.json)",
    )
    parser.add_argument(
        "--author", type=str, action="append", default=None,
        help="Git author name(s) — can be repeated (default: auto-detect from git config + GitHub)",
    )
    parser.add_argument(
        "--no-fetch", action="store_true",
        help="Skip 'git fetch origin' before scanning repos (for offline use)",
    )
    parser.add_argument(
        "--detailed", action="store_true",
        help="Parse per-session .jsonl for tool/token/file details",
    )
    parser.add_argument(
        "--verbose", "-v", action="store_true",
        help="Verbose logging",
    )
    parser.add_argument(
        "--dry-run", "-n", action="store_true",
        help="Print summary without writing output file",
    )
    parser.add_argument(
        "--skip-covered", action="store_true",
        help="Skip dates already covered by existing work reports in journal/raw/ and journal/integrated/",
    )
    parser.add_argument(
        "--journal-root", type=str, default=None,
        help="Root of journal directory (contains raw/ and integrated/). Default: ~/Awesome-CV/journal",
    )
    args = parser.parse_args()

    # Setup logging
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s: %(message)s",
        stream=sys.stderr,
    )

    # Apply --journal-root override for deduplication paths
    global JOURNAL_RAW, JOURNAL_INTEGRATED
    if args.journal_root:
        jr = Path(args.journal_root)
        JOURNAL_RAW = jr / "raw"
        JOURNAL_INTEGRATED = jr / "integrated"

    hostname = socket.gethostname()
    authors = args.author if args.author else get_git_authors()
    start_date = args.start_date
    end_date = args.end_date

    if args.skip_covered:
        covered = scan_covered_dates(hostname)
        if covered:
            log.info("Found %d existing report(s) covering dates for host %s", len(covered), hostname)
            for cs, ce in covered:
                log.info("  Covered: %s to %s", cs, ce)

        gaps = compute_gaps(start_date, end_date, covered)

        if not gaps:
            log.info("Entire range %s to %s is already covered — nothing to collect", start_date, end_date)
            sys.exit(0)

        if len(gaps) == 1 and gaps[0] == (start_date, end_date):
            log.info("No existing coverage — collecting full range")
        else:
            log.info("Uncovered gaps: %s", gaps)
            # Run collector for each gap (re-invoke self)
            filtered_args = []
            skip_next = False
            for a in sys.argv[1:]:
                if skip_next:
                    skip_next = False
                    continue
                if a == "--skip-covered":
                    continue
                if a in ("--start-date", "--end-date"):
                    skip_next = True
                    continue
                filtered_args.append(a)

            script = sys.argv[0]
            for gap_start, gap_end in gaps:
                log.info("Collecting gap: %s to %s", gap_start, gap_end)
                cmd = [sys.executable, script] + filtered_args + [
                    "--start-date", gap_start, "--end-date", gap_end
                ]
                subprocess.run(cmd)
            sys.exit(0)

        # Single gap matches full range — fall through to normal collection
        start_date = gaps[0][0]
        end_date = gaps[0][1]

    log.info("Host: %s, Authors: %s, Range: %s to %s",
             hostname, authors, start_date, end_date)

    # Resolve range to second-precision UTC datetimes (date-only inputs
    # expand to [00:00:00, 23:59:59.999999]). The string fields remain in
    # the output for backward compat with downstream skills.
    try:
        start_dt, end_dt = parse_range_bounds(start_date, end_date)
    except ValueError as e:
        log.error("Invalid --start-date / --end-date: %s", e)
        sys.exit(2)

    # Cap end to yesterday: a same-day run sees only partial data, but
    # produces a report that --skip-covered treats as "today fully done".
    # Trimming end to yesterday 23:59:59.999999 lets tomorrow's run pick
    # today up cleanly. See cap_end_to_yesterday() docstring.
    capped_end_dt = cap_end_to_yesterday(end_dt)
    if capped_end_dt < end_dt:
        log.info("end-date covers today/future; capping to yesterday (%s)",
                 datetime_to_iso(capped_end_dt))
        end_dt = capped_end_dt
        end_date = end_dt.strftime("%Y-%m-%d")

    if start_dt > end_dt:
        log.warning("Nothing to collect: start (%s) is after capped end (%s). "
                    "Try again tomorrow.", start_date, end_date)
        sys.exit(0)

    # Run all collectors (each handles its own errors)
    data = {
        "meta": {
            "hostname": hostname,
            "start_date": start_date,
            "end_date": end_date,
            "start_timestamp": datetime_to_iso(start_dt),
            "end_timestamp": datetime_to_iso(end_dt),
            "generated": datetime.now(timezone.utc).isoformat(),
            "git_authors": authors,
            "detailed": args.detailed,
        },
    }

    data["infrastructure"] = collect_infrastructure()
    data["shell"] = collect_shell_history(start_date, end_date)
    data["git"] = collect_git(start_date, end_date, authors, no_fetch=args.no_fetch)
    data["initiatives"] = compute_initiatives(data["git"])
    data["git_sar"] = collect_git_sar(start_date, end_date, authors)
    data["test_artifacts"] = collect_test_artifacts(start_date, end_date)
    data["claude_sessions"] = collect_claude_sessions(
        start_date, end_date, detailed=args.detailed
    )
    data["opencode_sessions"] = collect_opencode_sessions(
        start_date, end_date, detailed=args.detailed
    )

    # Print summary
    print_summary(data)

    # Write output
    if args.dry_run:
        log.info("Dry run — skipping file write")
    else:
        output_path = args.output
        if not output_path:
            output_path = str(
                Path.home()
                / f"work-report-data_{hostname}_{start_date}-to-{end_date}.json"
            )
        with open(output_path, "w") as f:
            json.dump(data, f, indent=2, default=str)
        log.info("Wrote %s", output_path)
        print(output_path)


if __name__ == "__main__":
    main()
