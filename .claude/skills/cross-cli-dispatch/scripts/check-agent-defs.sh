#!/usr/bin/env bash
# check-agent-defs.sh — cross-ref docs/agent-definitions/*.md against native.tsv.
#
# model-dispatch/native.tsv is the dispatch authority; the agent defs are the surface the Agent
# tool actually reads. This check fails when a def's `model` or `effort` pin
# diverges from its tier's native binding, the drift class that went unnoticed
# until PR #1188 (validate-bindings.sh covers bindings.tsv tails, not defs).
#
# The tier->def mapping lives in agent-def-map.tsv so adding a def for a tier
# that has none today (execute-review, execute-deep, fable) is a data change.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$SKILL_DIR/.." && pwd)"
NATIVE="$REPO_ROOT/model-dispatch/native.tsv"
DEFS_DIR="$REPO_ROOT/docs/agent-definitions"
MAP="$SKILL_DIR/agent-def-map.tsv"

usage() {
  echo "Usage: check-agent-defs.sh [--native <tsv>] [--defs-dir <dir>] [--map <tsv>]" >&2
  exit 2
}

while [ $# -gt 0 ]; do case "$1" in
  --native)   [ $# -ge 2 ] || usage; NATIVE="$2"; shift 2;;
  --defs-dir) [ $# -ge 2 ] || usage; DEFS_DIR="$2"; shift 2;;
  --map)      [ $# -ge 2 ] || usage; MAP="$2"; shift 2;;
  -h|--help)  usage;;
  *) echo "Unknown argument: $1" >&2; usage;;
esac; done

for f in "$NATIVE" "$MAP"; do
  [ -f "$f" ] || { echo "FAIL: missing file: $f" >&2; exit 1; }
done
[ -d "$DEFS_DIR" ] || { echo "FAIL: missing defs dir: $DEFS_DIR" >&2; exit 1; }

FAILS=0
fail() { echo "FAIL: $*" >&2; FAILS=$((FAILS + 1)); }

native_binding() { awk -F'\t' -v t="$1" '/^[^#]/ && $1==t {print $2 "\t" $3; exit}' "$NATIVE"; }

# Read a top-level scalar from the def's YAML frontmatter (first --- block).
# Empty output means absent; a bare key with no value also reads as empty and is
# reported as a mismatch rather than silently skipped.
frontmatter_value() {
  awk -v key="$2" '
    NR == 1 && $0 == "---" { inside = 1; next }
    inside && $0 == "---" { exit }
    inside {
      k = $0; sub(/:.*$/, "", k)
      if (k == key) {
        v = $0; sub(/^[^:]*:[[:space:]]*/, "", v)
        sub(/[[:space:]]+$/, "", v)
        gsub(/^["'"'"']|["'"'"']$/, "", v)
        print v; exit
      }
    }
  ' "$1"
}

while IFS= read -r line; do
  case "$line" in ''|'#'*) continue;; esac
  IFS=$'\t' read -r tier def_file extra <<< "$line"
  [ -n "$tier" ] && [ -n "$def_file" ] && [ -z "${extra:-}" ] \
    || { fail "agent-def-map.tsv: malformed row: $line"; continue; }

  binding="$(native_binding "$tier")"
  [ -n "$binding" ] || { fail "$tier: no native.tsv row for mapped tier"; continue; }
  IFS=$'\t' read -r want_model want_effort <<< "$binding"

  path="$DEFS_DIR/$def_file"
  [ -f "$path" ] || { fail "$tier: mapped agent def not found: $path"; continue; }

  got_model="$(frontmatter_value "$path" model)"
  got_effort="$(frontmatter_value "$path" effort)"

  [ "$got_model" = "$want_model" ] \
    || fail "$tier: model mismatch: $def_file has '${got_model:-<unset>}', native.tsv wants '$want_model'"
  [ "$got_effort" = "$want_effort" ] \
    || fail "$tier: effort mismatch: $def_file has '${got_effort:-<unset>}', native.tsv wants '$want_effort'"
done < "$MAP"

[ "$FAILS" -eq 0 ]
