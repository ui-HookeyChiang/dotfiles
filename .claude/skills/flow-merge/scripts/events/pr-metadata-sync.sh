#!/usr/bin/env bash
# Update GitHub PR metadata before a merge without mutating the git checkout.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: pr-metadata-sync.sh [--pr <number|url>] [--repo <owner/repo>] [--title <title>] [--body <text> | --body-file <path>]

Env:
  FLOW_MERGE_PR             PR number or URL. Falls back to FLOW_MERGE_PR_NUMBER or PR_NUMBER.
  FLOW_MERGE_REPO           Optional GitHub repo slug, e.g. owner/repo.
  FLOW_MERGE_PR_TITLE       Optional PR title.
  FLOW_MERGE_PR_BODY        Optional PR body text.
  FLOW_MERGE_PR_BODY_FILE   Optional path to a file containing the PR body.
EOF
}

PR="${FLOW_MERGE_PR:-${FLOW_MERGE_PR_NUMBER:-${PR_NUMBER:-}}}"
REPO="${FLOW_MERGE_REPO:-}"
TITLE="${FLOW_MERGE_PR_TITLE:-}"
BODY="${FLOW_MERGE_PR_BODY:-}"
BODY_FILE="${FLOW_MERGE_PR_BODY_FILE:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr)
      PR="${2:-}"; shift 2 ;;
    --repo)
      REPO="${2:-}"; shift 2 ;;
    --title)
      TITLE="${2:-}"; shift 2 ;;
    --body)
      BODY="${2:-}"; shift 2 ;;
    --body-file)
      BODY_FILE="${2:-}"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "$PR" ]]; then
  echo "ERROR: pr-metadata-sync requires FLOW_MERGE_PR or --pr" >&2
  exit 2
fi
if [[ -n "$BODY" && -n "$BODY_FILE" ]]; then
  echo "ERROR: pass only one of FLOW_MERGE_PR_BODY/--body or FLOW_MERGE_PR_BODY_FILE/--body-file" >&2
  exit 2
fi
if [[ -n "$BODY_FILE" ]]; then
  if [[ ! -f "$BODY_FILE" ]]; then
    echo "ERROR: PR body file not found: $BODY_FILE" >&2
    exit 2
  fi
  BODY="$(<"$BODY_FILE")"
fi
if [[ -z "$TITLE" && -z "$BODY" ]]; then
  echo "ERROR: pr-metadata-sync requires a title or body update" >&2
  exit 2
fi

args=(api "repos/{owner}/{repo}/pulls/$PR" -X PATCH)
if [[ -n "$REPO" ]]; then
  args+=(--repo "$REPO")
fi
if [[ -n "$TITLE" ]]; then
  args+=(-f "title=$TITLE")
fi
if [[ -n "$BODY" ]]; then
  args+=(-f "body=$BODY")
fi

gh "${args[@]}" >/dev/null
changes=()
[[ -n "$TITLE" ]] && changes+=("title")
[[ -n "$BODY" ]] && changes+=("body")
echo "OK: updated PR $PR ${changes[*]}"
