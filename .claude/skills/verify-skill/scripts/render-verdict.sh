#!/usr/bin/env bash
# render-verdict.sh <run-dir>
set -euo pipefail
run_dir="${1:?usage: render-verdict.sh <run-dir>}"
verdict_json="$run_dir/verdict.json"
if [[ ! -f "$verdict_json" ]]; then
  echo "[ERR] $verdict_json not found" >&2; exit 2
fi

python3 - "$run_dir" <<'PYEOF'
import json, sys
from pathlib import Path
run_dir = Path(sys.argv[1])
v = json.loads((run_dir / "verdict.json").read_text())
print("=" * 64)
print(f"  verify-skill verdict: {v['outcome']}")
print(f"  voting_total={v['voting_total']}  pass={v['pass_count']} fail={v['fail_count']} na={v['na_count']}")
if v.get("hc_triggered"):
    print(f"  HC ceiling: {', '.join(v['hc_triggered'])}")
if v.get("pipeline_mode_ceiling_applied"):
    print(f"  pipeline-mode ceiling applied: pipeline_mode={v['pipeline_mode']}")
if v.get("pipeline_mode", "").startswith("auto-pipeline"):
    print("  [PUA-ADVISORY] auto-pipeline mode; max independence requires a separate top-level session.")
print("=" * 64)
for sub in sorted(run_dir.glob("private-A*/ballot.json")):
    try:
        b = json.loads(sub.read_text())
    except Exception as e:
        print(f"  {sub.parent.name}: <malformed: {e}>"); continue
    print(f"  [{b.get('voter','?')}] {b.get('verdict','?')} ({b.get('confidence','?')})")
    for e in (b.get("evidence") or [])[:3]:
        print(f"    - {e}")
    for c in (b.get("concerns") or [])[:3]:
        print(f"    ! {c}")
print("=" * 64)
PYEOF
