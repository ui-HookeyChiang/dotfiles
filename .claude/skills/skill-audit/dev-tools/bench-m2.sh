#!/usr/bin/env bash
# bench-m2.sh — M2 imbalance calibration corpus replay (syntax-leg Phase 2, T1).
# DEV TOOL, not a runtime audit leg: mutates metrics.py in place to A/B-calibrate
# the imbalance weight. Lives under dev-tools/, never invoked by run.sh.
#
# Modes:
#   bench-m2.sh                          → emit "before" snapshot (current metrics.py)
#   bench-m2.sh --formula <A|B|C|D|C+D>  → before/after compare with candidate formula
#   bench-m2.sh --record-darwin-baseline → record AC8 baseline JSON at commit 24b1f80
#
# Crash-safety strategy (survives SIGKILL):
#   - On entry, if metrics.py.bak exists (prior crash leftover) → restore it first.
#   - Before any mutation: copy metrics.py → metrics.py.bak, then atomic-write via
#     metrics.py.tmp → mv to metrics.py.
#   - EXIT trap restores from .bak and removes .bak/.tmp on clean exit.
#
# Output: markdown tables on stdout. JSON only written for --record-darwin-baseline.

set -euo pipefail

# ----------------------------------------------------------------------------
# Resolve paths (work from any cwd; absolute-ize everything)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_AUDIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$SKILL_AUDIT_DIR/.." && pwd)"

AUDIT_PY="$SCRIPT_DIR/audit.py"
METRICS_PY="$SCRIPT_DIR/advisory/metrics.py"
METRICS_BAK="$METRICS_PY.bak"
METRICS_TMP="$METRICS_PY.tmp"
BASELINE_JSON="$SCRIPT_DIR/advisory/baseline-darwin.json"

# ----------------------------------------------------------------------------
# Crash-safety: restore leftover .bak from prior crashed run BEFORE doing anything.

if [[ -f "$METRICS_BAK" ]]; then
    echo "bench-m2: detected metrics.py.bak from prior crashed run, restoring..." >&2
    mv -f "$METRICS_BAK" "$METRICS_PY"
fi
rm -f "$METRICS_TMP"

# ----------------------------------------------------------------------------
# EXIT trap: clean restore on any exit (success, error, signal except SIGKILL).

cleanup() {
    local exit_code=$?
    if [[ -f "$METRICS_BAK" ]]; then
        mv -f "$METRICS_BAK" "$METRICS_PY"
    fi
    rm -f "$METRICS_TMP"
    exit "$exit_code"
}
trap cleanup EXIT INT TERM

# ----------------------------------------------------------------------------
# Args

FORMULA=""
RECORD_BASELINE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --formula)
            FORMULA="${2:-}"
            shift 2
            ;;
        --record-darwin-baseline)
            RECORD_BASELINE=1
            shift
            ;;
        -h|--help)
            sed -n '2,12p' "$0" >&2
            exit 0
            ;;
        *)
            echo "bench-m2: unknown arg: $1" >&2
            exit 1
            ;;
    esac
done

if [[ -n "$FORMULA" ]]; then
    case "$FORMULA" in
        A|B|C|D|C+D) ;;
        *)
            echo "bench-m2: --formula must be one of A|B|C|D|C+D (got: $FORMULA)" >&2
            exit 1
            ;;
    esac
fi

# ----------------------------------------------------------------------------
# Helper: run audit and emit a "name composite imbalance" TSV (sorted by name).

run_rank_all_tsv() {
    python3 "$AUDIT_PY" --rank-all "$REPO_ROOT" --top 0 --json --no-llm \
        | python3 -c '
import json, sys
d = json.load(sys.stdin)
ranking = d.get("ranking") or []
# Preserve rank from ranking order, then sort by name for stable diff.
ordered = [(i + 1, r["name"], r["composite"], r["imbalance"]) for i, r in enumerate(ranking)]
ordered.sort(key=lambda x: x[1])
for rank, name, comp, imb in ordered:
    print(f"{name}\t{rank}\t{comp:.2f}\t{imb:.2f}")
'
}

# ----------------------------------------------------------------------------
# Formula bodies (verbatim from spec §Design → Candidate formulas).
# Each emits the FULL replacement function body for compute_imbalance's last
# two lines (the formula proper) — i.e. replaces lines:
#     ratio = substantive / max(1, scripts_count)
#     score = min(100.0, ratio * 10)
#
# For D (orthogonal threshold), we tweak the threshold constant inside the
# loop. C+D combines both.

write_modified_metrics() {
    local formula="$1"
    # Read original, emit modified to .tmp.
    python3 - "$METRICS_PY" "$METRICS_TMP" "$formula" <<'PYEOF'
import sys, re
src_path, dst_path, formula = sys.argv[1], sys.argv[2], sys.argv[3]
with open(src_path) as f:
    src = f.read()

# --- Formula bodies (verbatim from spec) ---
FORMULA_A = '''    if scripts_count == 0:
        score = min(60.0, substantive * 4.0)
        ratio = float(substantive)
    else:
        ratio = substantive / scripts_count
        score = min(100.0, ratio * 10)
'''

FORMULA_B = '''    denom = 1 + scripts_count * 2
    ratio = substantive / denom
    score = min(100.0, ratio * 10)
'''

FORMULA_C = '''    if substantive <= 3:
        score = 0.0
        ratio = 0.0
    else:
        effective_scripts = math.log2(1 + scripts_count) + 1
        ratio = substantive / effective_scripts
        score = min(100.0, ratio * 8)
'''

# D is orthogonal: bump the SUBSTANTIVE_THRESHOLD from 3 to 5 (in the
# non_comment_non_blank >= 3 check). D alone keeps formula A/B/C unchanged,
# but the spec only validates "C+D" as a combined candidate, so when used
# alone we keep the original formula (max(1, scripts_count)) and just tighten
# the substantive filter.
FORMULA_D_ONLY = '''    ratio = substantive / max(1, scripts_count)
    score = min(100.0, ratio * 10)
'''

FORMULA_C_PLUS_D = FORMULA_C  # same formula body; D's effect is in the threshold.

bodies = {
    "A": FORMULA_A,
    "B": FORMULA_B,
    "C": FORMULA_C,
    "D": FORMULA_D_ONLY,
    "C+D": FORMULA_C_PLUS_D,
}
new_body = bodies[formula]

# Replace the formula lines. Match the two-line "ratio = ..." / "score = ..."
# at the end of compute_imbalance (inside the function, before `return`).
pattern = re.compile(
    r"(    ratio = substantive / max\(1, scripts_count\)\n"
    r"    score = min\(100\.0, ratio \* 10\)\n)"
)
m = pattern.search(src)
if not m:
    print("bench-m2: failed to locate formula in metrics.py", file=sys.stderr)
    sys.exit(2)
modified = src[:m.start()] + new_body + src[m.end():]

# Apply D's substantive threshold bump: 3 → 5 in the
# `non_comment_non_blank >= 3` check.
if formula in ("D", "C+D"):
    thr_pattern = re.compile(r"if non_comment_non_blank >= 3:")
    if not thr_pattern.search(modified):
        print("bench-m2: failed to locate substantive threshold in metrics.py", file=sys.stderr)
        sys.exit(2)
    modified = thr_pattern.sub("if non_comment_non_blank >= 5:", modified)

with open(dst_path, "w") as f:
    f.write(modified)
PYEOF
}

# ----------------------------------------------------------------------------
# Mode: --record-darwin-baseline

if [[ "$RECORD_BASELINE" -eq 1 ]]; then
    # Try to invoke darwin-skill — but we're in bash, no Claude harness, so
    # always falls back to placeholder per CONTEXT.md §Special attention point.
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "bench-m2: --record-darwin-baseline — no Claude harness in bash; writing placeholder JSON" >&2
    python3 - "$BASELINE_JSON" "$ts" <<'PYEOF'
import json, sys
path, ts = sys.argv[1], sys.argv[2]
data = {
    "commit": "24b1f80",
    "skill": "skill-syntax-audit",
    "darwin_score": None,
    "recorded_at": ts,
    "note": "harness unavailable — placeholder; T4 must re-record via Skill darwin-skill",
}
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PYEOF
    echo "bench-m2: wrote $BASELINE_JSON" >&2
    exit 0
fi

# ----------------------------------------------------------------------------
# Capture BEFORE snapshot (always).

BEFORE_TSV="$(mktemp)"
trap 'rc=$?; rm -f "$BEFORE_TSV" "${AFTER_TSV:-}"; if [[ -f "$METRICS_BAK" ]]; then mv -f "$METRICS_BAK" "$METRICS_PY"; fi; rm -f "$METRICS_TMP"; exit $rc' EXIT INT TERM

run_rank_all_tsv >"$BEFORE_TSV"

# ----------------------------------------------------------------------------
# No-formula mode: emit before-only table and exit.

if [[ -z "$FORMULA" ]]; then
    echo "# bench-m2 — before snapshot (current metrics.py)"
    echo ""
    echo "| Skill | Rank | Composite | Imbalance |"
    echo "|---|---|---|---|"
    sort -k3,3 -t$'\t' -nr "$BEFORE_TSV" \
        | python3 -c '
import sys
for ln in sys.stdin:
    name, rank, comp, imb = ln.rstrip("\n").split("\t")
    print(f"| {name} | {rank} | {comp} | {imb} |")
'
    exit 0
fi

# ----------------------------------------------------------------------------
# Formula mode: mutate metrics.py, capture AFTER snapshot, emit comparison.

# Step 1: backup original (the trap will restore from .bak on any exit).
cp -f "$METRICS_PY" "$METRICS_BAK"

# Step 2: write modified version to .tmp.
write_modified_metrics "$FORMULA"

# Step 3: atomic swap in place. After this, metrics.py is mutated; .bak holds
# the original. SIGKILL between mv and cleanup → next run sees .bak and restores.
mv -f "$METRICS_TMP" "$METRICS_PY"

# Step 4: capture AFTER snapshot.
AFTER_TSV="$(mktemp)"
run_rank_all_tsv >"$AFTER_TSV"

# Step 5: render comparison table.
echo "# bench-m2 — formula $FORMULA"
echo ""
echo "| Skill | Composite (before) | Composite (after) | Rank (before) | Rank (after) | Δ composite | Δ rank |"
echo "|---|---|---|---|---|---|---|"
python3 - "$BEFORE_TSV" "$AFTER_TSV" <<'PYEOF'
import sys
before_path, after_path = sys.argv[1], sys.argv[2]
def load(p):
    out = {}
    with open(p) as f:
        for ln in f:
            name, rank, comp, _imb = ln.rstrip("\n").split("\t")
            out[name] = (int(rank), float(comp))
    return out
b = load(before_path)
a = load(after_path)
names = sorted(set(b) | set(a))
# Sort by before-rank ascending (top of corpus first).
names.sort(key=lambda n: b.get(n, (999, 0.0))[0])
for name in names:
    br, bc = b.get(name, (None, None))
    ar, ac = a.get(name, (None, None))
    if br is None or ar is None:
        continue
    dc = ac - bc
    dr = ar - br
    sign_c = "+" if dc >= 0 else ""
    sign_r = "+" if dr >= 0 else ""
    print(f"| {name} | {bc:.2f} | {ac:.2f} | {br} | {ar} | {sign_c}{dc:.2f} | {sign_r}{dr} |")
PYEOF

# trap will restore metrics.py from .bak on exit.
exit 0
