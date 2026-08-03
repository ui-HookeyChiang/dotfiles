#!/usr/bin/env bash
# skill-audit/scripts/audit-leg-gate.sh
#
# Mechanical completion gate for the two LLM advisory legs.
# Usage:
#   audit-leg-gate.sh mark <probabilistic|prose> <skill-name-or-path> <log>
#   audit-leg-gate.sh assert <skill-name-or-path> <log>
set -u

usage() {
  echo "usage: $0 mark <probabilistic|prose> <skill-name-or-path> <log>" >&2
  echo "   or: $0 assert <skill-name-or-path> <log>" >&2
}

has_leg() {
  local leg="$1" skill="$2" log="$3"
  [ -f "$log" ] || return 1
  grep -E "gate=audit-leg[[:space:]].*leg=${leg}([[:space:]]|$).*skill=${skill}([[:space:]]|$)" "$log" >/dev/null 2>&1
}

cmd="${1:-}"
case "$cmd" in
  mark)
    [ "$#" -eq 4 ] || { usage; exit 1; }
    leg="$2"
    raw="${3%/}"
    if [ "$(basename "$raw")" = "SKILL.md" ]; then
      skill="$(basename "$(dirname "$raw")")"
    else
      skill="$(basename "$raw")"
    fi
    log="$4"
    case "$leg" in
      probabilistic|prose) ;;
      *) echo "skill-audit: unknown audit leg: $leg" >&2; exit 1 ;;
    esac
    mkdir -p "$(dirname "$log")"
    printf 'gate=audit-leg leg=%s skill=%s\n' "$leg" "$skill" >>"$log"
    ;;
  assert)
    [ "$#" -eq 3 ] || { usage; exit 1; }
    raw="${2%/}"
    if [ "$(basename "$raw")" = "SKILL.md" ]; then
      skill="$(basename "$(dirname "$raw")")"
    else
      skill="$(basename "$raw")"
    fi
    log="$3"
    missing=()
    for leg in probabilistic prose; do
      has_leg "$leg" "$skill" "$log" || missing+=("$leg")
    done
    if [ "${#missing[@]}" -ne 0 ]; then
      printf 'skill-audit: missing legs for %s: %s\n' \
        "$skill" "${missing[*]}" >&2
      exit 1
    fi
    ;;
  *)
    usage
    exit 1
    ;;
esac
