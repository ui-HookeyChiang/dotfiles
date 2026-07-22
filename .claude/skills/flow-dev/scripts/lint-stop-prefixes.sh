#!/bin/bash
# lint-stop-prefixes.sh — enforce the §4.7 condition→prefix table on
# every STOP emission in phase-5-cleanup.sh (and any file passed as arg).
#
# Rules (lint-enforced, pre-commit + CI):
#   (a) every stderr write of a [STOP-*] line must be tagged with the
#       prefix required for its condition (canonical table below); the
#       lint resolves helper indirection — call sites like
#       `stop_danger "Lock mismatch..."` are matched against the helper's
#       actual emitted prefix AND the §4.7 canonical mapping.
#   (b) no `rm`-form command may appear on the same line as a
#       [STOP-DANGER] tag OR as an argument passed to `stop_danger`
#       (System-1 muscle-memory guard, per K1);
#   (c) only the three canonical tier prefixes are allowed:
#       [STOP-SAFE], [STOP-DANGER], [STOP-RETRY].
#
# Usage:
#   lint-stop-prefixes.sh [file ...]
#
# Exit 0: clean. Exit non-zero: prints file:line offending lines and
#   the rule violated.
#
# DESIGN — canonical condition→prefix table:
#   The spec §4.7 (also referenced from §4.5 "Lint enforcement") owns
#   the canonical mapping. Rather than parse the markdown table at
#   runtime (fragile — the spec has many similar tables), we INLINE
#   the table here as the lint's single source of truth.
#
#   *** MUST STAY IN SYNC WITH spec §4.7 condition→prefix table ***
#   spec path: docs/specs/active/2026-05-14-optimize-flow-dev-phase-0.md
#   If §4.7 grows a new condition, add it here AND add a matching
#   substring fragment to CANONICAL_TABLE below.

set -euo pipefail

if [[ $# -eq 0 ]]; then
  # Default target: phase-5-cleanup (relative to this script).
  HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  set -- \
    "$HERE/phase-5-cleanup.sh"
fi

FAIL=0

# Canonical condition→prefix table (§4.7). Format: each line is
#   <PREFIX>|<case-insensitive substring fragment>
# A call-site condition string matches if the fragment appears in it
# (case-insensitive). If multiple fragments match, the LONGEST wins
# (most specific). PREFIX is one of SAFE / DANGER / RETRY.
CANONICAL_TABLE=$(cat <<'EOF'
SAFE|not in a git repository
SAFE|not in a linked worktree
SAFE|not in a worktree
SAFE|Run inside a worktree
SAFE|missing required arguments
SAFE|gh auth status` failed
SAFE|No `origin` remote
SAFE|no longer on disk
SAFE|is not under
SAFE|Unknown `.flow-dev-lock` schema version
SAFE|Spec lifecycle drift detected
SAFE|Spec lifecycle drift check unavailable
DANGER|Lock mismatch
DANGER|Branch mismatch
DANGER|Detached HEAD inside locked worktree
DANGER|current_branch_at_phase_0 missing
DANGER|Branch drift between Phase 0 and write-lock
DANGER|Cannot start flow-dev on Phase 3 merge-train integration branch
RETRY|Another flow-dev invocation
RETRY|flock acquisition
RETRY|SD_WORKTREE_ROOT not accessible
RETRY|verify-after retry
SAFE|spec not found
SAFE|spec must be in active
SAFE|verify-before mismatch
DANGER|promote claimed success but verify shows drift
DANGER|cannot regress from done to active
EOF
)

# Normalize a string for canonical-table matching:
#   - lowercase
#   - strip backticks and backslash-escaped backticks
#   - collapse runs of whitespace to single space
normalize_for_match() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -e 's/\\`//g' -e 's/`//g' \
    | tr -s '[:space:]' ' '
}

# Given a condition string ($1), echo the canonical prefix (SAFE/DANGER/RETRY)
# or "UNKNOWN" if no fragment matches. Uses longest-fragment-wins.
resolve_canonical_prefix() {
  local cond="$1"
  local cond_n best_prefix="UNKNOWN" best_len=0
  cond_n=$(normalize_for_match "$cond")
  while IFS='|' read -r prefix frag; do
    [[ -z "$prefix" || -z "$frag" ]] && continue
    local frag_n
    frag_n=$(normalize_for_match "$frag")
    if [[ "$cond_n" == *"$frag_n"* ]]; then
      if (( ${#frag_n} > best_len )); then
        best_prefix="$prefix"
        best_len=${#frag_n}
      fi
    fi
  done <<<"$CANONICAL_TABLE"
  printf '%s' "$best_prefix"
}

# Parse helper definitions from a file. Sets HELPER_PREFIX_<name> to the
# prefix emitted by that helper. Returns 0 on success (always; missing
# helpers are simply absent from the map).
declare -A HELPER_PREFIX
parse_helpers() {
  local file="$1"
  # Reset map for this file.
  HELPER_PREFIX=()
  # awk over the file: find lines matching `^(stop_safe|stop_danger|stop_retry)\(\)`
  # then for the following lines until `^}`, grab the first [STOP-*] token.
  local fn_lines
  fn_lines=$(awk '
    /^(stop_safe|stop_danger|stop_retry)\(\)/ {
      fn = $1; sub(/\(\)$/, "", fn); sub(/\(\).*$/, "", fn);
      # Extract the function name without trailing ()
      gsub(/\(.*$/, "", fn)
      in_fn = fn; next
    }
    in_fn != "" && /\[STOP-(SAFE|DANGER|RETRY)\]/ {
      match($0, /\[STOP-(SAFE|DANGER|RETRY)\]/)
      tok = substr($0, RSTART, RLENGTH)
      sub(/^\[STOP-/, "", tok); sub(/\]$/, "", tok)
      print in_fn "|" tok
      in_fn = ""
    }
    in_fn != "" && /^\}/ { in_fn = "" }
  ' "$file")
  while IFS='|' read -r fn pref; do
    [[ -z "$fn" || -z "$pref" ]] && continue
    HELPER_PREFIX["$fn"]="$pref"
  done <<<"$fn_lines"
}

# Find call sites of stop_safe / stop_danger / stop_retry. For each call,
# extract the condition string (the $1 argument) and the line number.
# Echoes lines of the form:
#   <line_no>|<helper_name>|<condition_string>
# Handles two forms:
#   (i)  single-line: `stop_danger "Lock mismatch: ..."`
#   (ii) multi-line:  `stop_danger \\` then next non-blank line `  "Lock mismatch ..."`
find_call_sites() {
  local file="$1"
  awk '
    function strip_quotes(s,    n) {
      n = length(s)
      if (n >= 2 && substr(s, 1, 1) == "\"" && substr(s, n, 1) == "\"") {
        return substr(s, 2, n - 2)
      }
      return s
    }
    {
      line = $0; lineno = NR
      # Skip the function definition lines themselves (those are helper
      # decls, not call sites).
      if (line ~ /^(stop_safe|stop_danger|stop_retry)\(\)/) next
      # Skip lines inside the helper bodies — heuristic: a line that
      # already contains a [STOP-*] token AND is preceded by `echo ` is
      # the helper definition body, not a call.
      # We rely on call sites NOT having an immediate [STOP-*] string
      # literal — they pass a condition string, the helper emits the
      # prefix.
      if (line ~ /\[STOP-(SAFE|DANGER|RETRY)\]/) next

      # Look for helper invocation.
      if (match(line, /(^|[^a-zA-Z_])(stop_safe|stop_danger|stop_retry)([[:space:]]|\\$|$)/)) {
        # Extract helper name.
        rest = substr(line, RSTART, RLENGTH)
        if (match(rest, /stop_(safe|danger|retry)/)) {
          fn = substr(rest, RSTART, RLENGTH)
        } else { next }

        # Extract arg portion: everything after the helper name on this line.
        # Find position of fn in line.
        fn_idx = index(line, fn)
        if (fn_idx == 0) next
        arg_part = substr(line, fn_idx + length(fn))

        # Strip a leading line-continuation: arg_part might be "" or "\\"
        gsub(/^[[:space:]]+/, "", arg_part)

        # Multi-line case: arg_part begins with `\` (line continuation),
        # condition is on the next non-blank line.
        if (arg_part == "\\" || arg_part == "") {
          # Need to peek ahead via getline.
          while ((getline next_line) > 0) {
            nl = next_line
            gsub(/^[[:space:]]+/, "", nl)
            if (nl == "" || nl ~ /^#/) continue
            arg_part = nl
            break
          }
        }

        # arg_part now starts with `"...` ideally; pull the first quoted string.
        # We allow quoted strings spanning to the matching `"` on this line.
        # If the string itself contains escaped \", we accept simple parsing
        # (the call sites in this codebase use simple double-quoted strings).
        if (match(arg_part, /"[^"]*"/)) {
          cond = substr(arg_part, RSTART, RLENGTH)
          cond = strip_quotes(cond)
        } else {
          cond = arg_part
        }

        print lineno "|" fn "|" cond
      }
    }
  ' "$file"
}

for f in "$@"; do
  if [[ ! -f "$f" ]]; then
    echo "lint: missing file: $f" >&2
    FAIL=1
    continue
  fi

  # --- Parse helpers in this file ---
  parse_helpers "$f"

  # --- Rule (c): only three canonical prefixes ---
  # Flag any [STOP-XYZ] where XYZ is not SAFE/DANGER/RETRY (excluding
  # comment lines that document the family).
  while IFS= read -r match; do
    line_no="${match%%:*}"
    rest="${match#*:}"
    # Skip comment lines (a leading # — handles indented comments too).
    trimmed="$(printf '%s' "$rest" | sed -e 's/^[[:space:]]*//')"
    if [[ "$trimmed" == \#* ]]; then continue; fi
    if ! printf '%s' "$rest" | grep -Eq '\[STOP-(SAFE|DANGER|RETRY)\]'; then
      echo "$f:$line_no: rule (c) violation — unknown STOP tier prefix: $rest" >&2
      FAIL=1
    fi
  done < <(grep -nE '\[STOP-[A-Z]+\]' "$f" || true)

  # --- Rule (b)/(a) on direct emission lines (no helper indirection) ---
  # These are the helper-definition lines themselves AND any direct
  # `echo '[STOP-...' >&2` outside helpers (e.g., phase-5-cleanup.sh's
  # inline emissions).
  while IFS= read -r match; do
    line_no="${match%%:*}"
    rest="${match#*:}"
    # Skip comment lines.
    trimmed="$(printf '%s' "$rest" | sed -e 's/^[[:space:]]*//')"
    if [[ "$trimmed" == \#* ]]; then continue; fi

    # Rule (b) — no `rm <space>` on a [STOP-DANGER] line.
    if printf '%s' "$rest" | grep -Eq '\[STOP-DANGER\]' && \
       printf '%s' "$rest" | grep -Eq '(^|[^a-zA-Z_])rm[[:space:]]'; then
      echo "$f:$line_no: rule (b) violation — \`rm\` form not allowed on [STOP-DANGER] line: $rest" >&2
      FAIL=1
    fi

    # Rule (a) on direct emit lines: e.g., phase-5-cleanup.sh
    # have inline `echo "[STOP-SAFE] ..." >&2`. Match the message body
    # against the canonical table.
    # We extract the prefix and the trailing message string. We only
    # apply this check to lines that look like a direct stderr emit:
    # they contain `>&2` AND a quoted message.
    if printf '%s' "$rest" | grep -Eq '\[STOP-(SAFE|DANGER|RETRY)\].*>&2'; then
      # Skip if this is a helper definition line — those use $1 as the
      # condition placeholder, and the actual condition is supplied at
      # call sites (checked in the call-site loop below).
      if printf '%s' "$rest" | grep -Eq '\$1|\$\{1\}'; then
        continue
      fi
      # Extract emitted prefix.
      emitted_prefix=$(printf '%s' "$rest" | grep -Eo '\[STOP-(SAFE|DANGER|RETRY)\]' | head -1 | sed -e 's/^\[STOP-//' -e 's/\]$//')
      # Extract first double-quoted string after the prefix.
      msg=$(printf '%s' "$rest" | sed -nE 's/.*\[STOP-(SAFE|DANGER|RETRY)\][[:space:]]*([^"]*)"([^"]*)".*/\3/p')
      if [[ -z "$msg" ]]; then
        # Fallback: pull anything after the prefix up to end-of-line.
        msg=$(printf '%s' "$rest" | sed -nE 's/.*\[STOP-(SAFE|DANGER|RETRY)\][[:space:]]*(.*)/\2/p')
      fi
      canonical=$(resolve_canonical_prefix "$msg")
      if [[ "$canonical" == "UNKNOWN" ]]; then
        echo "$f:$line_no: rule (a) WARN — condition not in §4.7 table: $msg" >&2
        # WARN: still fail to keep the contract strict; if false-positive
        # arises, extend CANONICAL_TABLE.
        FAIL=1
      elif [[ "$canonical" != "$emitted_prefix" ]]; then
        echo "$f:$line_no: rule (a) violation — Tier mismatch: '$msg' expects [STOP-$canonical], emits [STOP-$emitted_prefix]" >&2
        FAIL=1
      fi
    fi
  done < <(grep -nE '\[STOP-[A-Z]+\]' "$f" || true)

  # --- Rule (a) + (b) on call sites (helper indirection) ---
  while IFS='|' read -r line_no fn cond; do
    [[ -z "$line_no" || -z "$fn" ]] && continue

    # Resolve which prefix this helper actually emits in THIS file.
    resolved_prefix="${HELPER_PREFIX[$fn]:-}"
    if [[ -z "$resolved_prefix" ]]; then
      echo "$f:$line_no: rule (a) violation — call site uses '$fn' but helper not defined in this file" >&2
      FAIL=1
      continue
    fi

    # Resolve canonical prefix for the condition string.
    canonical=$(resolve_canonical_prefix "$cond")
    if [[ "$canonical" == "UNKNOWN" ]]; then
      echo "$f:$line_no: rule (a) WARN — condition not in §4.7 table — add to CANONICAL_TABLE or fix message: '$cond'" >&2
      FAIL=1
      continue
    fi

    # Compare canonical vs resolved.
    if [[ "$canonical" != "$resolved_prefix" ]]; then
      echo "$f:$line_no: rule (a) violation — Tier mismatch: condition '$cond' expects [STOP-$canonical], helper '$fn' emits [STOP-$resolved_prefix]" >&2
      FAIL=1
    fi

    # Rule (b) on call sites: stop_danger argument must not contain `rm `.
    if [[ "$fn" == "stop_danger" ]]; then
      if printf '%s' "$cond" | grep -Eq '(^|[^a-zA-Z_])rm[[:space:]]'; then
        echo "$f:$line_no: rule (b) violation — \`rm\` form not allowed in stop_danger argument: '$cond'" >&2
        FAIL=1
      fi
    fi
  done < <(find_call_sites "$f")
done

if (( FAIL == 0 )); then
  echo "lint-stop-prefixes: PASS ($# file(s) checked)"
  exit 0
else
  echo "lint-stop-prefixes: FAIL" >&2
  exit 1
fi
