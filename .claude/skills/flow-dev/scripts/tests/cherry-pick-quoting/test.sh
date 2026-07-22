#!/usr/bin/env bash
# Regression test for SKILL.md squash-merge cherry-pick block.
# During the 8-PR squash-merge of #356-#371, the unquoted form
#     COMMITS=$(git log --reverse --format='%H' ...) ; git cherry-pick $COMMITS
# silently produced empty cherry-picks under set -euo pipefail with hostile
# IFS, which then got force-pushed and destroyed the task branch head.
# This test asserts the new mapfile+array form survives that scenario.
set -euo pipefail

TMP="$(mktemp -d -t cherry-pick-quoting.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# --- Fixture: 1 base commit on parent + 3 commits on top branch ----------
git -C "$TMP" init -q -b main
git -C "$TMP" config user.email t@t
git -C "$TMP" config user.name t
echo base > "$TMP/f"; git -C "$TMP" add f
git -C "$TMP" commit -q -m base
git -C "$TMP" branch feat/dummy/parent
git -C "$TMP" checkout -q -b feat/dummy/task-1
for i in 1 2 3; do
  echo "c$i" >> "$TMP/f"; git -C "$TMP" add f
  git -C "$TMP" commit -q -m "commit-$i"
done
git -C "$TMP" checkout -q main

# --- Step 3: positive — new array form must apply all 3 commits ----------
(
  cd "$TMP"
  set -euo pipefail
  IFS=$'\n\t'  # hostile IFS as set by Phase 4 hook scripts
  mapfile -t COMMITS < <(git log --reverse --format='%H' feat/dummy/parent..feat/dummy/task-1)
  [[ ${#COMMITS[@]} -gt 0 ]] || { echo "ERROR: empty"; exit 1; }
  git checkout -q -B task-1-v2 main
  git cherry-pick "${COMMITS[@]}" >/dev/null
) || fail "new array form failed under hostile IFS"

count=$(git -C "$TMP" log --format='%s' main..task-1-v2 | wc -l | tr -d ' ')
[[ "$count" == "3" ]] || fail "new form applied $count commits, expected 3"
git -C "$TMP" log --format='%s' main..task-1-v2 | grep -q '^commit-1$' || fail "missing commit-1"
git -C "$TMP" log --format='%s' main..task-1-v2 | grep -q '^commit-2$' || fail "missing commit-2"
git -C "$TMP" log --format='%s' main..task-1-v2 | grep -q '^commit-3$' || fail "missing commit-3"

# --- Step 4: negative (best-effort) — old unquoted form with IFS= ---------
# Empty IFS disables word splitting; $COMMITS expands to ONE arg with
# embedded newlines, which cherry-pick treats as a single bad revision.
git -C "$TMP" checkout -q main
old_result=$(
  cd "$TMP"
  set +e
  IFS=
  COMMITS=$(git log --reverse --format='%H' feat/dummy/parent..feat/dummy/task-1)
  git checkout -q -B task-1-old main
  git cherry-pick $COMMITS >/dev/null 2>&1
  echo "exit=$?"
  echo "count=$(git log --format='%s' main..task-1-old 2>/dev/null | wc -l | tr -d ' ')"
)
# best-effort: reproduces the bug on bash >= 4 with IFS=. The positive
# assertion above is the real gate; the negative just documents the bug.
echo "$old_result" | grep -q 'count=3' && \
  echo "NOTE: old form did not reproduce the bug in this shell" >&2

echo "PASS: cherry-pick-quoting"
