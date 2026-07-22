#!/bin/bash
# check-verify-skill.sh — verify verify-skill is installed before Phase 6 runs.
# Contract: exit 0 if found, exit 2 with a remediation hint otherwise.
set -euo pipefail

for cand in \
    "$HOME/.claude/skills/verify-skill/SKILL.md" \
    "$HOME/.agents/skills/verify-skill/SKILL.md"; do
  if [[ -f "$cand" ]]; then exit 0; fi
done

echo "check-verify-skill: verify-skill not installed" >&2
echo "  remediation: ./install.sh from repo root (PHASE 3 symlinks verify-skill)" >&2
echo "  or: npx -y skills add <future-canonical-source>" >&2
exit 2
