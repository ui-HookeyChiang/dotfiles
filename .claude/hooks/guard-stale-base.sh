#!/usr/bin/env bash
# guard-stale-base.sh — PreToolUse hook (Bash matcher).
#
# Guards branch-CREATION commands against a stale local start-point:
# - Bare local branch ref as start-point → deny (may be stale / unpushed)
# - Remote-prefixed ref (origin/main, upstream/dev) → allow + cached fetch
# - Tag or SHA → allow (immutable)
#
# Only these creation forms are inspected (a start-point must be explicit):
#   git checkout -b <name> <start-point>
#   git switch   -c <name> <start-point>
#   git branch      <name> <start-point>   (only when <name> is NOT an option)
#   git worktree add [<path>] <start-point>
#   git worktree add [<path>] -b <name> <start-point>
#
# These creation forms are inspected even without an explicit start-point:
#   git checkout -b <name>  /  git switch -c <name>  /  git branch <name>
#   → when HEAD's branch has an upstream and is behind it, deny.
#
# Chained commands (via ; && || |) are split and each segment inspected.
#
# Escape hatch: ALLOW_STALE_BASE=1 bypasses the check (allow).
set -euo pipefail

if [[ "${ALLOW_STALE_BASE:-}" == "1" ]]; then
  exit 0
fi

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[[ -n "$cmd" ]] || exit 0

cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
# Fall back to CLAUDE_PROJECT_DIR then PWD when cwd is empty
if [[ -z "$cwd" ]]; then
  cwd="${CLAUDE_PROJECT_DIR:-${PWD:-}}"
fi
[[ -n "$cwd" ]] && cd "$cwd" 2>/dev/null || exit 0

git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# Strip heredoc bodies before splitting into segments.
# Handles <<WORD, <<'WORD', <<"WORD", <<-WORD (and <<-'WORD', <<-"WORD").
# Lines between the <<WORD marker and the matching terminator are removed;
# the command line containing <<WORD and the terminator line itself are kept
# as empty lines so segment positions are preserved.
clean_cmd="$(printf '%s' "$cmd" | awk '
BEGIN { in_heredoc = 0; terminator = "" }
{
  if (in_heredoc) {
    # Strip optional leading tabs (<<- form), then compare to terminator
    stripped = $0
    gsub(/^\t+/, "", stripped)
    if (stripped == terminator) {
      in_heredoc = 0
      terminator = ""
    }
    # Suppress heredoc body and terminator lines from output
    next
  }
  # Detect <<[-]["'"'"']?WORD['"'"'"]? on this line
  line = $0
  if (match(line, /<<-?["'"'"']?[[:alpha:]_][[:alnum:]_]*["'"'"']?/)) {
    tok = substr(line, RSTART, RLENGTH)
    # Extract bare word: strip <<, optional -, optional quotes
    word = tok
    sub(/^<<-?/, "", word)
    gsub(/["'"'"']/, "", word)
    in_heredoc = 1
    terminator = word
  }
  print line
}')"

# Split the command on shell separators: ; && || |
# Separators are matched longest-first (&&, || before |) to avoid |
# being consumed from inside || or &&.
# bash-3.2 compatible (macOS /bin/bash has no mapfile)
segments=()
while IFS= read -r _seg; do
  segments+=("$_seg")
done < <(printf '%s' "$clean_cmd" | awk '
{
  line = $0
  while (length(line) > 0) {
    # Find earliest occurrence of each separator; check 2-char forms first.
    pos_and  = index(line, "&&")
    pos_or   = index(line, "||")
    pos_semi = index(line, ";")
    # Single | only counts when it is not part of || at that position.
    pos_pipe = index(line, "|")
    if (pos_pipe > 0 && pos_or > 0 && pos_pipe == pos_or) {
      # This | is the start of ||; look for the next lone |
      rest = substr(line, pos_pipe + 2)
      next_pipe = index(rest, "|")
      pos_pipe = (next_pipe > 0) ? pos_pipe + 1 + next_pipe : 0
    }

    best_pos = 0; best_len = 0

    if (pos_and > 0 && (best_pos == 0 || pos_and < best_pos)) {
      best_pos = pos_and; best_len = 2
    }
    if (pos_or > 0 && (best_pos == 0 || pos_or < best_pos)) {
      best_pos = pos_or; best_len = 2
    }
    if (pos_semi > 0 && (best_pos == 0 || pos_semi < best_pos)) {
      best_pos = pos_semi; best_len = 1
    }
    if (pos_pipe > 0 && (best_pos == 0 || pos_pipe < best_pos)) {
      best_pos = pos_pipe; best_len = 1
    }

    if (best_pos == 0) {
      print line
      line = ""
    } else {
      print substr(line, 1, best_pos - 1)
      line = substr(line, best_pos + best_len)
    }
  }
}')

# A start-point token must be a plain ref: no leading '-' (option/redirect),
# no shell metacharacters.
sp='([^-[:space:];&|<>][^[:space:];&|<>]*)'

# --- Extract the start-point from a branch-CREATION command -----------------
# Patterns are anchored with ^ so `git` must be the first word of the segment
# (after ltrim in check_segment). This prevents matching `git ...` inside
# an argument string like `echo 'git branch x feature-x'`.
#
# checkout -b <name> <start-point>  /  switch -c <name> <start-point>
co_pattern="^git[[:space:]]+(checkout[[:space:]]+-b|switch[[:space:]]+-c)[[:space:]]+[^[:space:]]+[[:space:]]+$sp"
# branch <name> <start-point>  — <name> must NOT be an option (excludes -d/-D/
# --list/-m/…), and a start-point must follow.
branch_pattern="^git[[:space:]]+branch[[:space:]]+([^-[:space:]][^[:space:]]*)[[:space:]]+$sp"
# worktree add [<path>] -b <name> <start-point>
worktree_b_pattern="^git[[:space:]]+worktree[[:space:]]+add[[:space:]]+[^[:space:]]+[[:space:]]+-b[[:space:]]+[^[:space:]]+[[:space:]]+$sp"
# worktree add <path> <start-point>  (no -b)
worktree_pattern="^git[[:space:]]+worktree[[:space:]]+add[[:space:]]+[^[:space:]]+[[:space:]]+$sp"

# HEAD-based creation patterns (no explicit start-point)
co_head_pattern="^git[[:space:]]+(checkout[[:space:]]+-b|switch[[:space:]]+-c)[[:space:]]+[^[:space:]]+[[:space:]]*$"
branch_head_pattern="^git[[:space:]]+branch[[:space:]]+([^-[:space:]][^[:space:]]*)[[:space:]]*$"

deny_output() {
  local reason="$1"
  jq -n --arg reason "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 1
}

warn_output() {
  local warning="$1"
  jq -n --arg warning "$warning" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "allow",
      additionalContext: $warning
    }
  }'
}

# Cached fetch for a specific remote; keys stamp off common gitdir.
do_cached_fetch() {
  local remote="$1"
  local gitdir
  gitdir="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || git rev-parse --absolute-git-dir 2>/dev/null)"
  local stamp="$gitdir/.guard-fetch-stamp"
  local now
  now="$(date +%s)"
  local last
  last="$(cat "$stamp" 2>/dev/null || echo 0)"
  if (( now - last > 300 )); then
    if git fetch "$remote" --quiet 2>/dev/null; then
      printf '%s' "$now" > "$stamp"
      return 0
    else
      return 1
    fi
  fi
  return 0
}

check_segment() {
  local seg="$1"
  # Strip redirections: drop from a bare '>' / '<' or fd+redirect onward
  seg="$(printf '%s' "$seg" | sed -E 's/[[:space:]]+[0-9]*[<>].*$//')"
  seg="${seg#"${seg%%[![:space:]]*}"}"  # ltrim

  local base=""
  local head_based=false

  if [[ "$seg" =~ $worktree_b_pattern ]]; then
    base="${BASH_REMATCH[1]}"
  elif [[ "$seg" =~ $co_pattern ]]; then
    base="${BASH_REMATCH[2]}"
  elif [[ "$seg" =~ $branch_pattern ]]; then
    base="${BASH_REMATCH[2]}"
  elif [[ "$seg" =~ $worktree_pattern ]]; then
    base="${BASH_REMATCH[1]}"
  elif [[ "$seg" =~ $co_head_pattern ]] || [[ "$seg" =~ $branch_head_pattern ]]; then
    head_based=true
  fi

  # HEAD-based: check if current branch is behind upstream
  if $head_based; then
    local upstream
    upstream="$(git rev-parse --abbrev-ref --symbolic-full-name @{upstream} 2>/dev/null || true)"
    [[ -n "$upstream" ]] || return 0  # no upstream → allow
    local behind
    behind="$(git rev-list --count HEAD..@{upstream} 2>/dev/null || echo 0)"
    if (( behind > 0 )); then
      deny_output "Blocked: HEAD is $behind commit(s) behind upstream ($upstream). Branching from here would miss those commits.

  command: $cmd
  fix: git fetch && git rebase @{upstream}, then branch from origin/<branch> instead."
    fi
    return 0
  fi

  [[ -n "$base" ]] || return 0

  # SHA (hex, 7-40 chars) → immutable, allow
  [[ "$base" =~ ^[0-9a-f]{7,40}$ ]] && return 0

  # Tag → immutable, allow
  git rev-parse --verify --quiet "refs/tags/$base" >/dev/null 2>&1 && return 0

  # Remote-prefixed (any remote) → cached fetch, allow
  local remotes
  remotes="$(git remote 2>/dev/null || true)"
  for remote in $remotes; do
    case "$base" in
      "${remote}"/*)
        if ! do_cached_fetch "$remote"; then
          # Fetch failed: allow but warn
          warn_output "Warning: could not fetch from '$remote' — remote refs may be stale. Proceeding with cached state."
        fi
        return 0
        ;;
    esac
  done

  # Bare local ref: check if a same-named remote ref exists with the same SHA
  local local_sha
  local_sha="$(git rev-parse --verify --quiet "refs/heads/$base" 2>/dev/null || true)"
  if [[ -n "$local_sha" ]]; then
    for remote in $remotes; do
      local remote_sha
      remote_sha="$(git rev-parse --verify --quiet "refs/remotes/$remote/$base" 2>/dev/null || true)"
      if [[ -n "$remote_sha" ]]; then
        if [[ "$local_sha" == "$remote_sha" ]]; then
          # SHA matches remote counterpart → allow
          return 0
        fi
        # SHA differs: compute ahead/behind
        local ahead behind
        ahead="$(git rev-list --count "refs/remotes/$remote/$base"..refs/heads/"$base" 2>/dev/null || echo "?")"
        behind="$(git rev-list --count "refs/heads/$base".."refs/remotes/$remote/$base" 2>/dev/null || echo "?")"
        deny_output "Blocked: local \`$base\` differs from \`$remote/$base\` (ahead $ahead, behind $behind). Use the remote ref to avoid missing upstream commits.

  command: $cmd
  fix: git fetch $remote && git worktree add <path> $remote/$base"
      fi
    done
  fi

  # No remote counterpart (or no remotes): bare local deny
  jq -n --arg base "$base" --arg cmd "$cmd" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("Blocked: branching from local `" + $base + "` — may be stale or carry unpushed commits. Use a remote ref (e.g. `origin/" + $base + "`) instead.\n\n  command: " + $cmd + "\n  fix: replace `" + $base + "` with `origin/" + $base + "`, or set ALLOW_STALE_BASE=1.")
    }
  }'
  exit 1
}

# ${segments[@]+...} guards set -u on empty array under bash 3.2
for seg in ${segments[@]+"${segments[@]}"}; do
  check_segment "$seg"
done
