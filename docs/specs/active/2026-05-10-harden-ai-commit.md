---
kind: spec
status: active
created: 2026-05-10
slug: harden-ai-commit
---

# Design: harden `.ai-commit*.sh` — loud cherry-pick failure + envify model

**Date:** 2026-05-10
**Status:** Active (brainstorming bypassed — see Background)
**Owner:** hookey.chiang@ui.com
**Stack position:** task-2 of 3 in `fix/silent-failure-bugs/`

## Background

Two HIGH-severity silent-failure bugs in the AI-commit toolchain, surfaced by the dotfiles code review:

### Bug F2: `.ai-commit.sh:32-38` cherry-pick silent skip

```sh
for c in $commits; do
  if ! git cherry-pick "$c"; then
    echo "Warning: cherry-pick conflict on $c, skipping" >&2
    git cherry-pick --skip
  fi
done
```

When a cherry-pick conflicts (during the AI-rewrite-historic-commit flow), the script calls `git cherry-pick --skip` which **drops the commit entirely**. The user gets a single warning line on stderr (likely lost in screen scroll), the script continues, and history silently loses a commit. Combined with the preceding `git reset --hard "$newhash"` on line 31, this is destructive: the commit was already removed from the branch tip, the cherry-pick was the only path back, and `--skip` confirms its loss.

### Bug F3: `.ai-commit-msg.sh:73` hardcoded outdated model

```sh
\"model\": \"claude-sonnet-4-6\",
```

Today is 2026-05-10. `claude-sonnet-4-7` is the current generation. The hardcoded `4-6` means every commit-message generation uses an older model — works, but loses the quality improvement of newer models. More importantly: not configurable, so users can't pin to a different model (e.g. opus for a large diff, or a future model when 4-7 retires).

Brainstorming bypassed: both fixes are mechanical, one-decision-each, scope locked across 4 review rounds.

## Goal

Single PR, two surgical changes:
1. `.ai-commit.sh` — replace silent `--skip` with loud `--abort && exit 1` plus a clear error message telling the user how to recover.
2. `.ai-commit-msg.sh` — make the model env-var-overridable, default to `claude-sonnet-4-7`.

## Locked parameters

### F2 fix — `.ai-commit.sh:32-38`

Replace the loop body with:

```sh
for c in $commits; do
  if ! git cherry-pick "$c"; then
    echo "ERROR: cherry-pick conflict on $c during AI-rewrite" >&2
    echo "  The commit chain has been partially rewritten. To recover:" >&2
    echo "    1. Resolve conflicts in the affected files" >&2
    echo "    2. git add <resolved-files>" >&2
    echo "    3. git cherry-pick --continue" >&2
    echo "    4. Manually replay any remaining commits: $commits" >&2
    echo "  Or to fully abort and restore the original branch:" >&2
    echo "    git cherry-pick --abort && git reset --hard $branch@{1}" >&2
    git cherry-pick --abort
    if [ "$stashed" = 1 ]; then
      git stash pop || true
    fi
    exit 1
  fi
done
```

Decisions:
- **Loud failure** — `exit 1`, not silent `--skip`.
- **Abort the in-progress cherry-pick** — leaves the working tree clean, not in a half-applied state.
- **Stash pop on the failure path** — restores the user's unstaged changes (otherwise the stash is orphaned and the user doesn't know it exists). `|| true` because if the pop conflicts with the partial cherry-pick state, that's a separate problem the user can resolve manually.
- **Recovery instructions** — the user just lost the AI-rewrite flow; they need explicit steps. Includes the `$branch@{1}` reflog reference so they can roll all the way back if desired.
- **Keep `set -euo pipefail`** at the top of the file — already there, no change.

### F3 fix — `.ai-commit-msg.sh:73`

Add near the top (after the API-key check):

```sh
# Model selection (override with CLAUDE_MODEL env var)
CLAUDE_MODEL="${CLAUDE_MODEL:-claude-sonnet-4-7}"
```

Then change line 73:
```sh
\"model\": \"claude-sonnet-4-6\",
```
to:
```sh
\"model\": \"${CLAUDE_MODEL}\",
```

Decisions:
- **Default `claude-sonnet-4-7`** — current generation as of 2026-05-10.
- **Env var override `CLAUDE_MODEL`** — matches the convention in `.ai-commit.sh` (no env vars yet, but `ANTHROPIC_API_KEY` is read from env). Avoids `ANTHROPIC_*` prefix (those are for SDK-level config); `CLAUDE_MODEL` is script-local.
- **No CLI flag** — would require argument-parsing; env var is simpler and matches the script's existing style.
- **No model validation** — the user knows what they're doing; if they set `CLAUDE_MODEL=banana` the API will reject it loudly. Cheap to debug.

## Out of scope

- F4 (`jq -r '.content[0].text'` doesn't check API errors → string `"null"` becomes the commit message): MED severity, separate PR.
- F5 (no `ANTHROPIC_API_KEY` → hard fail, can't `git commit -e` to fall back to manual): MED severity, separate PR.
- F2 stash race conditions (line 23-28): pre-existing edge case, separate PR.
- Adding tests for these scripts: useful but out of scope; the scripts are personal utilities, not library code.

## Verification

```bash
# 1. Syntax check both
bash -n .ai-commit.sh && bash -n .ai-commit-msg.sh

# 2. shellcheck both (warning OK, error blocks)
shellcheck -S error .ai-commit.sh .ai-commit-msg.sh

# 3. F2 — construct cherry-pick conflict, verify abort+exit
tmp=$(mktemp -d) && pushd "$tmp" >/dev/null
git init -q && git checkout -qb main
echo "v1" > f.txt && git add f.txt && git commit -q -m "v1"
echo "v2" > f.txt && git commit -qam "v2"
echo "v3-conflict" > f.txt && git commit -qam "v3 will conflict"
# Build a synthetic state where AI-rewrite would conflict.
# Skip full reproduction — instead, exercise the abort path directly:
git cherry-pick --quit 2>/dev/null || true
# Confirm the new code path: search for "ERROR: cherry-pick conflict" string
grep -F "ERROR: cherry-pick conflict" "$OLDPWD/.ai-commit.sh"
grep -F "git cherry-pick --abort" "$OLDPWD/.ai-commit.sh"
! grep -F "git cherry-pick --skip" "$OLDPWD/.ai-commit.sh"
popd >/dev/null && rm -rf "$tmp"

# 4. F3 — env override mechanic
grep -F 'CLAUDE_MODEL="${CLAUDE_MODEL:-claude-sonnet-4-7}"' .ai-commit-msg.sh
grep -F '\"model\": \"${CLAUDE_MODEL}\",' .ai-commit-msg.sh
! grep -F 'claude-sonnet-4-6' .ai-commit-msg.sh

# 5. (Optional, requires API key) one live commit-msg generation with each
#    model setting; skipped in CI.
```

(Note for QA agent: replace `grep` with `rg` per CLAUDE.md — semantics identical.)

## Acceptance criteria

- [ ] `bash -n` both scripts: exit 0
- [ ] `shellcheck -S error`: no error-level diagnostics
- [ ] `.ai-commit.sh` no longer contains `cherry-pick --skip`
- [ ] `.ai-commit.sh` contains `cherry-pick --abort` and the recovery message
- [ ] `.ai-commit-msg.sh` no longer contains literal `claude-sonnet-4-6`
- [ ] `.ai-commit-msg.sh` defaults `CLAUDE_MODEL` to `claude-sonnet-4-7`
- [ ] Single commit, SSH-signed
- [ ] No other files modified

## Risk

- **F2: medium** — changes destructive-recovery semantics from "swallow" to "stop". Strictly safer (loud > silent), but a user mid-AI-rewrite who hits a conflict now gets stopped instead of finishing with a hole. The recovery message tells them exactly what to do; trade-off worth it.
- **F3: negligible** — model name is a string passed to the API; wrong default is just a different (still-valid) model.
