#!/usr/bin/env bash
# validate-bindings.sh -- edit-time schema lint for cross-cli-dispatch bindings.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$SKILL_DIR/.." && pwd)"
BINDINGS="$SKILL_DIR/bindings.tsv"
INVENTORY="$SKILL_DIR/inventory.tsv"
NATIVE="$REPO_ROOT/model-dispatch/native.tsv"
NATIVE_VALIDATOR="$REPO_ROOT/model-dispatch/scripts/validate-native.sh"
REQUIRED_TIERS="scan scan-search execute execute-review execute-deep decide"

usage() {
  echo "Usage: validate-bindings.sh [--bindings <tsv>] [--inventory <tsv>] [--native <tsv>]" >&2
  exit 1
}

while [ $# -gt 0 ]; do case "$1" in
  --bindings) BINDINGS="$2"; shift 2;;
  --inventory) INVENTORY="$2"; shift 2;;
  --native) NATIVE="$2"; shift 2;;
  *) usage;;
esac; done

fail() { echo "FAIL: $*" >&2; FAILS=$((FAILS + 1)); }
model_known() { awk -F'\t' -v b="$1" -v m="$2" '$1==b && $2==m {found=1} END {exit found ? 0 : 1}' "$INVENTORY"; }
row_for_tier() { awk -F'\t' -v t="$1" '$1==t {print $2}' "$BINDINGS"; }
native_binding() { awk -F'\t' -v t="$1" '/^[^#]/ && $1==t {print $2 "," $3}' "$NATIVE"; }

FAILS=0
[ -f "$BINDINGS" ] || { echo "missing bindings: $BINDINGS" >&2; exit 1; }
[ -f "$INVENTORY" ] || { echo "missing inventory: $INVENTORY" >&2; exit 1; }
[ -f "$NATIVE" ] || { echo "missing native: $NATIVE" >&2; exit 1; }
[ -f "$NATIVE_VALIDATOR" ] || { echo "missing native validator: $NATIVE_VALIDATOR" >&2; exit 1; }

bash "$NATIVE_VALIDATOR" --native "$NATIVE" || FAILS=$((FAILS + 1))

for tier in $REQUIRED_TIERS; do
  chain="$(row_for_tier "$tier")"
  [ -n "$chain" ] || fail "missing tier row: $tier"
done

while IFS=$'\t' read -r tier chain extra; do
  case "$tier" in ''|'#'*) continue;; esac
  [ -z "${extra:-}" ] || fail "$tier: too many columns"
  [ -n "$chain" ] || { fail "$tier: blank chain"; continue; }

  case "$chain" in
    unsupported) fail "$tier: unsupported row missing action"; continue;;
    unsupported:*) [ -n "${chain#unsupported:}" ] || fail "$tier: unsupported row missing action"; continue;;
  esac

  last_backend=""; tail_binding=""
  IFS=';' read -r -a channels <<< "$chain"
  for channel in "${channels[@]}"; do
    IFS=',' read -r backend model effort extra_field <<< "$channel"
    [ -n "$backend" ] && [ -n "$model" ] && [ -n "$effort" ] && [ -z "${extra_field:-}" ] || {
      fail "$tier: malformed channel: $channel"; continue
    }
    model_known "$backend" "$model" || fail "$tier: unknown model for $backend: $model"
    last_backend="$backend"; tail_binding="$model,$effort"
  done
  if [ "$last_backend" = claude ]; then
    want="$(native_binding "$tier")"
    [ "$tail_binding" = "$want" ] \
      || fail "$tier: native.tsv mismatch: API tail $tail_binding vs native ${want:-<none>}"
  else
    fail "$tier: chain missing Anthropic API tail"
  fi
done < "$BINDINGS"

[ "$FAILS" -eq 0 ]
