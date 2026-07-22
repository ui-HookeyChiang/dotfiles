#!/usr/bin/env bash
# freeze-corpus.sh — snapshot corpus from $TRUST_ROOT into run workspace.
# Args: <skill-relpath> <trust-root-sha> <run-dir> [--pipeline-mode <mode>]
# Exits 0 on success; exit 2 if required corpus missing at trust root
# (standalone / auto-pipeline-improve only — auto-pipeline-create falls
# back to working tree).
set -euo pipefail
skill_relpath="${1:?usage: freeze-corpus.sh <skill-relpath> <trust-root> <run-dir> [--pipeline-mode <mode>]}"
trust_root="${2:?missing trust-root}"
run_dir="${3:?missing run-dir}"

pipeline_mode="standalone"
shift 3
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pipeline-mode) pipeline_mode="${2:?--pipeline-mode requires value}"; shift 2 ;;
    *) echo "[STOP] unknown arg: $1" >&2; exit 2 ;;
  esac
done

out_root="$run_dir/frozen-corpus/$skill_relpath"
mkdir -p "$out_root/evals"

# Worktree root (for fallback path resolution). Anchored from the skill
# location so we work even when CWD has been changed by the caller.
wt_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
src_root="${wt_root:+$wt_root/}$skill_relpath"

# Required corpus: trigger-eval.json (A1 has no surrogate/N-A path).
# test-prompts.json is handled separately below (A2 degrades to surrogate
# or NOT_APPLICABLE when absent — see references/voter-a2-behavior.md).
for f in evals/trigger-eval.json; do
  if git show "$trust_root:$skill_relpath/$f" > "$out_root/$f" 2>/dev/null; then
    continue
  fi
  rm -f "$out_root/$f"   # do not leave empty file
  if [[ "$pipeline_mode" == "auto-pipeline-create" && -f "$src_root/$f" ]]; then
    # auto-pipeline-create: corpus authored same-run, not yet in trust
    # root. Fall back to working tree copy. WARN advisory only — caller
    # already capped at APPROVE_WITH_NOTES under pipeline-mode ceiling.
    mkdir -p "$(dirname "$out_root/$f")"
    cp "$src_root/$f" "$out_root/$f"
    echo "[WARN] auto-pipeline-create: corpus '$f' copied from working tree (same-run authored)" >&2
    continue
  fi
  echo "[STOP] required corpus $f not in trust root $trust_root" >&2
  echo "  this is auto-pipeline-create flow (corpus authored same-run) OR" >&2
  echo "  corpus was renamed in the working tree — see A4 rename detection" >&2
  echo "  hint: re-run with --pipeline-mode auto-pipeline-create if appropriate" >&2
  exit 2
done

# Optional: test-prompts.json (A2 degrades to evals.json surrogate, else
# NOT_APPLICABLE — voter-a2-behavior.md L29-47). Same pattern as adversarial.
if git show "$trust_root:$skill_relpath/test-prompts.json" \
     > "$out_root/test-prompts.json" 2>/dev/null; then
  :
elif [[ "$pipeline_mode" == "auto-pipeline-create" && -f "$src_root/test-prompts.json" ]]; then
  cp "$src_root/test-prompts.json" "$out_root/test-prompts.json"
  echo "[WARN] auto-pipeline-create: test-prompts.json copied from working tree" >&2
else
  rm -f "$out_root/test-prompts.json"
  echo "[INFO] no test-prompts.json at trust root — A2 will use evals.json surrogate or be NOT_APPLICABLE" >&2
fi

# Optional: adversarial-cases.json (degrades to N/A if missing)
if git show "$trust_root:$skill_relpath/evals/adversarial-cases.json" \
     > "$out_root/evals/adversarial-cases.json" 2>/dev/null; then
  :
elif [[ "$pipeline_mode" == "auto-pipeline-create" && -f "$src_root/evals/adversarial-cases.json" ]]; then
  cp "$src_root/evals/adversarial-cases.json" "$out_root/evals/adversarial-cases.json"
  echo "[WARN] auto-pipeline-create: adversarial-cases.json copied from working tree" >&2
else
  rm -f "$out_root/evals/adversarial-cases.json"
  echo "[INFO] no adversarial corpus at trust root — A5 will be NOT_APPLICABLE" >&2
fi

echo "frozen_root=$out_root"
exit 0
