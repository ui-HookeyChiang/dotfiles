#!/usr/bin/env bash
# tests for flow-dev/scripts/spec-handoff.sh — slug-scoped draft selection
#
# Cases (one per acceptance-criteria row):
#   1: one-arg invocation → exit 64, usage names <slug>
#   2: slug with glob metachar ('foo*') → exit 64, msg names ^[a-z0-9-]+$,
#      BEFORE any pathspec built
#   3: matching draft present → moves ONLY it; sibling *-other.md untouched
#   4: no untracked .md anywhere → stdout {ok:true,moved:0,files:[]}, exit 0
#   5: untracked drafts present but none match slug → exit 1,
#      stdout {ok:false,reason:...}, stderr [STOP-SAFE], sources untouched
#   6: short-slug-vs-long-file: slug 'foo' does NOT match *-foo-bar.md
#   7: long-slug-vs-short-file: slug 'foo-bar' does NOT match *-foo.md
#   8: docs/superpowers/specs/*-<slug>-design.md variant IS matched
#   9: structural — shebang, set -euo pipefail present
#
# Usage: bash flow-dev/scripts/tests/spec-handoff-slug/test.sh

set -u

REPO_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
SCRIPT="$REPO_ROOT/flow-dev/scripts/spec-handoff.sh"

if [[ ! -f "$SCRIPT" ]]; then
    echo "FATAL: spec-handoff.sh not found at $SCRIPT" >&2
    exit 2
fi

PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL $1: $2"; }

TMPDIRS=()
cleanup() { for d in "${TMPDIRS[@]:-}"; do [[ -n "$d" ]] && rm -rf "$d"; done; }
trap cleanup EXIT

# Build an isolated main checkout + linked worktree.
# Echoes "MAIN WT" (space-separated absolute paths).
make_fixture() {
    local root main wt
    root="$(mktemp -d)"; TMPDIRS+=("$root")
    main="$root/main"; wt="$root/wt"
    mkdir -p "$main"
    git -C "$main" init -q
    git -C "$main" config user.email t@t.t
    git -C "$main" config user.name t
    git -C "$main" config commit.gpgsign false
    # need at least one commit before a linked worktree can be added
    : > "$main/.gitkeep"
    git -C "$main" add .gitkeep
    git -C "$main" commit -qm init
    git -C "$main" worktree add -q "$wt" -b feat >/dev/null 2>&1
    mkdir -p "$main/docs/specs/proposed" "$main/docs/superpowers/specs"
    echo "$main $wt"
}

seed() { mkdir -p "$(dirname "$1")"; echo "draft: $2" > "$1"; }

echo "behavioral cases:"

# Case 1: one-arg invocation → exit 64, usage names <slug>
read -r M W <<< "$(make_fixture)"
OUT=$(bash "$SCRIPT" "$W" 2>&1); RC=$?
if [[ $RC -eq 64 && "$OUT" == *"<slug>"* ]]; then
    pass "1 one-arg → exit 64 naming <slug>"
else
    fail "1" "rc=$RC out=$OUT"
fi

# Case 2: slug with glob metachar → exit 64, names ^[a-z0-9-]+$, before pathspec.
# We seed a draft that WOULD be swept if 'foo*' expanded; assert it's untouched.
read -r M W <<< "$(make_fixture)"
seed "$M/docs/specs/proposed/2026-06-02-foo-bar.md" foobar
OUT=$(bash "$SCRIPT" "$W" 'foo*' 2>&1); RC=$?
if [[ $RC -eq 64 && "$OUT" == *'^[a-z0-9-]+$'* && -f "$M/docs/specs/proposed/2026-06-02-foo-bar.md" ]]; then
    pass "2 glob-metachar slug → exit 64 naming charset, source untouched"
else
    fail "2" "rc=$RC out=$OUT exists=$([[ -f "$M/docs/specs/proposed/2026-06-02-foo-bar.md" ]] && echo y || echo n)"
fi

# Case 3: matching draft moved; sibling for a different slug untouched.
read -r M W <<< "$(make_fixture)"
seed "$M/docs/specs/proposed/2026-06-02-myfeat.md" mine
seed "$M/docs/specs/proposed/2026-06-02-other.md" other
OUT=$(bash "$SCRIPT" "$W" myfeat 2>/dev/null); RC=$?
moved=$(echo "$OUT" | jq -r '.files[0] // ""' 2>/dev/null)
movedn=$(echo "$OUT" | jq -r '.moved // -1' 2>/dev/null)
if [[ $RC -eq 0 \
      && "$movedn" == "1" \
      && "$moved" == "docs/specs/proposed/2026-06-02-myfeat.md" \
      && ! -f "$M/docs/specs/proposed/2026-06-02-myfeat.md" \
      && -f "$M/docs/specs/proposed/2026-06-02-other.md" \
      && -f "$W/docs/specs/proposed/2026-06-02-myfeat.md" ]]; then
    pass "3 matching draft moved, sibling untouched"
else
    fail "3" "rc=$RC moved=$moved n=$movedn other-exists=$([[ -f "$M/docs/specs/proposed/2026-06-02-other.md" ]] && echo y || echo n)"
fi

# Case 4: no untracked .md anywhere → {ok:true,moved:0,files:[]}, exit 0
read -r M W <<< "$(make_fixture)"
OUT=$(bash "$SCRIPT" "$W" myfeat 2>/dev/null); RC=$?
ok=$(echo "$OUT" | jq -r '.ok' 2>/dev/null)
mv=$(echo "$OUT" | jq -r '.moved' 2>/dev/null)
fl=$(echo "$OUT" | jq -r '.files | length' 2>/dev/null)
if [[ $RC -eq 0 && "$ok" == "true" && "$mv" == "0" && "$fl" == "0" ]]; then
    pass "4 no drafts → {ok:true,moved:0,files:[]} exit 0"
else
    fail "4" "rc=$RC out=$OUT"
fi

# Case 5: drafts present, none match → STOP-SAFE exit 1, {ok:false,reason}, sources untouched
read -r M W <<< "$(make_fixture)"
seed "$M/docs/specs/proposed/2026-06-02-otherline.md" stranger
ERR=$(bash "$SCRIPT" "$W" myfeat 2>/tmp/sh_e.$$); RC=$?
STDERR=$(cat /tmp/sh_e.$$ 2>/dev/null); rm -f /tmp/sh_e.$$
ok=$(echo "$ERR" | jq -r '.ok' 2>/dev/null)
reason=$(echo "$ERR" | jq -r '.reason // ""' 2>/dev/null)
if [[ $RC -eq 1 \
      && "$ok" == "false" \
      && -n "$reason" \
      && "$STDERR" == *"[STOP-SAFE]"* \
      && -f "$M/docs/specs/proposed/2026-06-02-otherline.md" ]]; then
    pass "5 present-no-match → STOP-SAFE exit 1, sources untouched"
else
    fail "5" "rc=$RC ok=$ok reason=$reason stderr=$STDERR"
fi

# Case 6: short-slug-vs-long-file — slug 'foo' must NOT match *-foo-bar.md
read -r M W <<< "$(make_fixture)"
seed "$M/docs/specs/proposed/2026-06-02-foo-bar.md" longer
ERR=$(bash "$SCRIPT" "$W" foo 2>/dev/null); RC=$?
ok=$(echo "$ERR" | jq -r '.ok' 2>/dev/null)
if [[ $RC -eq 1 && "$ok" == "false" && -f "$M/docs/specs/proposed/2026-06-02-foo-bar.md" ]]; then
    pass "6 slug 'foo' does NOT match *-foo-bar.md (STOP-SAFE, untouched)"
else
    fail "6" "rc=$RC ok=$ok moved=$([[ -f "$M/docs/specs/proposed/2026-06-02-foo-bar.md" ]] && echo no || echo YES)"
fi

# Case 7: long-slug-vs-short-file — slug 'foo-bar' must NOT match *-foo.md
read -r M W <<< "$(make_fixture)"
seed "$M/docs/specs/proposed/2026-06-02-foo.md" shorter
ERR=$(bash "$SCRIPT" "$W" foo-bar 2>/dev/null); RC=$?
ok=$(echo "$ERR" | jq -r '.ok' 2>/dev/null)
if [[ $RC -eq 1 && "$ok" == "false" && -f "$M/docs/specs/proposed/2026-06-02-foo.md" ]]; then
    pass "7 slug 'foo-bar' does NOT match *-foo.md (STOP-SAFE, untouched)"
else
    fail "7" "rc=$RC ok=$ok moved=$([[ -f "$M/docs/specs/proposed/2026-06-02-foo.md" ]] && echo no || echo YES)"
fi

# Case 8: docs/superpowers/specs/*-<slug>-design.md variant IS matched
read -r M W <<< "$(make_fixture)"
seed "$M/docs/superpowers/specs/2026-06-02-myfeat-design.md" design
OUT=$(bash "$SCRIPT" "$W" myfeat 2>/dev/null); RC=$?
moved=$(echo "$OUT" | jq -r '.files[0] // ""' 2>/dev/null)
if [[ $RC -eq 0 \
      && "$moved" == "docs/superpowers/specs/2026-06-02-myfeat-design.md" \
      && ! -f "$M/docs/superpowers/specs/2026-06-02-myfeat-design.md" \
      && -f "$W/docs/superpowers/specs/2026-06-02-myfeat-design.md" ]]; then
    pass "8 -design.md variant matched"
else
    fail "8" "rc=$RC moved=$moved"
fi

echo "caller-sync (integration) check:"

# Caller: SKILL.md Phase 2 Step 2 must invoke spec-handoff.sh with "$slug" as
# the 2nd arg (the breaking interface change must be reflected at the call site,
# else handoff exits 64 on every invocation — the prior dogfood F5 lesson).
SKILL_MD="$REPO_ROOT/flow-dev/SKILL.md"
CALL=$(rg -N 'spec-handoff\.sh' "$SKILL_MD" | rg 'WORKTREE_DIR' | head -1)
if [[ "$CALL" == *'"$WORKTREE_DIR"'*'"$slug"'* ]]; then
    pass "C caller passes \"\$slug\" as 2nd arg"
else
    fail "C" "SKILL.md call line: $CALL"
fi

echo "structural checks:"

# Case 9a: shebang
if head -1 "$SCRIPT" | grep -q '^#!'; then
    pass "9a shebang present"
else
    fail "9a" "no shebang on first line"
fi

# Case 9b: set -euo pipefail
if grep -q 'set -euo pipefail' "$SCRIPT"; then
    pass "9b set -euo pipefail present"
else
    fail "9b" "set -euo pipefail missing"
fi

echo ""
if [[ $FAIL -eq 0 ]]; then
    echo "PASS spec-handoff-slug tests ($PASS passed)"
    exit 0
else
    echo "FAIL spec-handoff-slug tests ($PASS passed, $FAIL failed)"
    exit 1
fi
