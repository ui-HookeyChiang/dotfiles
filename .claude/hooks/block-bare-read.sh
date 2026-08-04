#!/usr/bin/env bash
# block-bare-read.sh — PreToolUse hook (Bash matcher).
#
# Denies bare shell-exploration commands that have native tool alternatives:
# cat/head/tail (→ Read), grep/rg (→ Grep), find (pure search), sed (extract-only),
# awk (trivial forms). Guides callers toward native Read/Grep/Glob tools.
#
# Pipeline, redirect, compound, and heredoc usages pass through — legitimate
# shell-only operations. ALLOW_BARE_READ=1 escape hatch for unavailable tools.
set -euo pipefail

if [[ "${ALLOW_BARE_READ:-}" == "1" ]]; then
  exit 0
fi

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[[ -n "$cmd" ]] || exit 0

# Step 1: allow pipelines, redirects, compound commands, subshells, heredocs
if [[ "$cmd" == *'|'* ]] || [[ "$cmd" == *'>>'* ]] || [[ "$cmd" == *'>'* ]] \
   || [[ "$cmd" == *'$('* ]] || [[ "$cmd" == *'`'* ]] \
   || [[ "$cmd" == *'&&'* ]] || [[ "$cmd" == *';'* ]] || [[ "$cmd" == *'<<'* ]]; then
  exit 0
fi

# Helper: strip one shell word from the start (quoted or unquoted + trailing space)
# Handles VAR=value, VAR="quoted value", flags, etc.
strip_word() {
  local rest="$1"
  # Match a single word: sequence of unquoted/quoted/assignment chars, respecting quotes
  # Pattern: (unquoted|'...'|"...")+[space]*
  if [[ "$rest" =~ ^(([^\'\"[:space:]]+|\'[^\']*\'|\"[^\"]*\")+)[[:space:]]* ]]; then
    printf '%s\n' "${rest#${BASH_REMATCH[0]}}"
  else
    printf '%s\n' "$rest"
  fi
}

# Step 2: strip prefixes (env, command, builtin, nice, nohup, timeout, backslash, bash -c / sh -c)
# Loop until no more prefixes are stripped; unwrap bash -c/sh -c strings recursively.
stripped_cmd="$cmd"
for iter in {1..10}; do
  # Strip leading backslash
  if [[ "$stripped_cmd" == \\* ]]; then
    stripped_cmd="${stripped_cmd#\\}"
    continue
  fi

  # env: strip the word "env", then iteratively strip VAR=val and flags (quote-aware)
  if [[ "$stripped_cmd" =~ ^env[[:space:]]+ ]]; then
    stripped_cmd="${stripped_cmd#env }"
    # Keep stripping tokens while they look like VAR=val (quoted or unquoted) or flags
    while true; do
      # Check if next token (unquoted form) looks like VAR=val or -flag
      # Remove leading quotes to peek at the content
      next_unquoted="${stripped_cmd#\'}"
      next_unquoted="${next_unquoted#\"}"
      # Now check if it matches our patterns
      if [[ "$next_unquoted" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || [[ "$stripped_cmd" =~ ^- ]]; then
        # Strip one word (quote-aware)
        stripped_cmd="$(strip_word "$stripped_cmd")"
      else
        break
      fi
    done
    continue
  fi

  # command/builtin/nice/nohup: just strip the word
  if [[ "$stripped_cmd" =~ ^command[[:space:]]+ ]]; then
    stripped_cmd="${stripped_cmd#command }"
    continue
  fi
  if [[ "$stripped_cmd" =~ ^builtin[[:space:]]+ ]]; then
    stripped_cmd="${stripped_cmd#builtin }"
    continue
  fi
  if [[ "$stripped_cmd" =~ ^nice[[:space:]]+ ]]; then
    stripped_cmd="${stripped_cmd#nice }"
    continue
  fi
  if [[ "$stripped_cmd" =~ ^nohup[[:space:]]+ ]]; then
    stripped_cmd="${stripped_cmd#nohup }"
    continue
  fi

  # timeout: strip "timeout", then flags and duration
  if [[ "$stripped_cmd" =~ ^timeout[[:space:]]+ ]]; then
    stripped_cmd="${stripped_cmd#timeout }"

    # Consume timeout flags: -s SIG, -S SIG, --signal=SIG, --preserve-status, etc.
    while [[ "$stripped_cmd" =~ ^- ]]; do
      # Long flag with = : --signal=KILL (consume as one word)
      if [[ "$stripped_cmd" =~ ^--[^[:space:]]+=[^[:space:]]+ ]]; then
        if [[ "$stripped_cmd" =~ ^(--[^[:space:]]+=[^[:space:]]*)[[:space:]]* ]]; then
          stripped_cmd="${stripped_cmd#${BASH_REMATCH[0]}}"
          continue
        fi
      fi
      # Long flag without value: --preserve-status (consume as one word)
      if [[ "$stripped_cmd" =~ ^--[^[:space:]]+ ]] && ! [[ "$stripped_cmd" =~ ^--[^[:space:]]+= ]]; then
        if [[ "$stripped_cmd" =~ ^(--[^[:space:]]+)[[:space:]]+ ]]; then
          stripped_cmd="${stripped_cmd#${BASH_REMATCH[0]}}"
          continue
        fi
      fi
      # Short flag with value: -s KILL (consume flag and next word separately)
      if [[ "$stripped_cmd" =~ ^-[a-zA-Z][[:space:]]+ ]]; then
        stripped_cmd="${stripped_cmd#-?[[:space:]]}"
        # Now consume the value (one word, quote-aware)
        stripped_cmd="$(strip_word "$stripped_cmd")"
        continue
      fi
      break
    done

    # Consume the timeout duration (numeric, optionally with unit)
    if [[ "$stripped_cmd" =~ ^[0-9]+([smhd])?[[:space:]]+ ]]; then
      if [[ "$stripped_cmd" =~ ^([0-9]+[smhd]?)[[:space:]]+ ]]; then
        stripped_cmd="${stripped_cmd#${BASH_REMATCH[0]}}"
      fi
    fi
    continue
  fi

  # bash -c '...' or sh -c '...'
  if [[ "$stripped_cmd" =~ ^bash[[:space:]]+-c[[:space:]]+ ]]; then
    rest="${stripped_cmd#bash -c }"
    if [[ "$rest" =~ ^\'([^\']*)\' ]]; then
      stripped_cmd="${BASH_REMATCH[1]}"
      continue
    elif [[ "$rest" =~ ^\"([^\"]*)\" ]]; then
      stripped_cmd="${BASH_REMATCH[1]}"
      continue
    fi
  fi

  if [[ "$stripped_cmd" =~ ^sh[[:space:]]+-c[[:space:]]+ ]]; then
    rest="${stripped_cmd#sh -c }"
    if [[ "$rest" =~ ^\'([^\']*)\' ]]; then
      stripped_cmd="${BASH_REMATCH[1]}"
      continue
    elif [[ "$rest" =~ ^\"([^\"]*)\" ]]; then
      stripped_cmd="${BASH_REMATCH[1]}"
      continue
    fi
  fi

  # No more prefixes to strip
  break
done

# Step 3: extract first token after stripping (quote-aware)
# Match first word: (unquoted|'...'|"...")+
if [[ "$stripped_cmd" =~ ^(([^\'\"[:space:]]+|\'[^\']*\'|\"[^\"]*\")+) ]]; then
  first_token="${BASH_REMATCH[1]}"
else
  first_token="${stripped_cmd%%[[:space:]]*}"
fi
bin="${first_token##*/}"
# Remove quotes from bin for matching (in case first token is quoted)
bin="${bin//\"/}"
bin="${bin//\'/}"

# Step 4: tail -f / --follow → allow (monitoring)
if [[ "$bin" == "tail" ]]; then
  if [[ "$stripped_cmd" =~ (^|[[:space:]])-f([[:space:]]|$) ]] \
     || [[ "$stripped_cmd" =~ (^|[[:space:]])--follow([[:space:]]|$) ]]; then
    exit 0
  fi
fi

# Step 5: deny cat/head/tail
case "$bin" in
  cat)
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: "Use the Read tool to read file contents (Read(file_path, offset, limit) for ranges). Example: Read(\"/path/to/file\", 0, 100) to read first 100 chars."
      }
    }'
    exit 0
    ;;
  head)
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: "Use the Read tool to read file contents (Read(file_path, offset, limit) for ranges). Example: Read(\"/path/to/file\", 0, 500) to read first 500 chars."
      }
    }'
    exit 0
    ;;
  tail)
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: "Use the Read tool to read file contents (Read(file_path, offset, limit) for ranges). Example: Read(\"/path/to/file\") to read entire file, or Bash with tail for monitoring (-f)."
      }
    }'
    exit 0
    ;;
esac

# Step 6: deny grep/rg (all bare forms)
case "$bin" in
  grep|rg)
    jq -n --arg bin "$bin" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: ("Use the Grep tool to search file contents (Grep(pattern, path/glob) for grep-like behavior). Example: Grep(\"error\", \"/var/log/*.txt\") or Grep(\"foo\", \"src/**/*.js\"). If the Grep tool is unavailable, retry with ALLOW_BARE_READ=1; to search ignored paths use ALLOW_BARE_READ=1 rg --no-ignore.")
      }
    }'
    exit 0
    ;;
esac

# Step 7: deny find (pure-search form: -name/-iname/-path/-type with no action flag)
if [[ "$bin" == "find" ]]; then
  # Check if find has an action flag (-exec, -execdir, -delete, -ok) or time/size predicate
  has_action=false
  has_predicate=false

  if [[ "$stripped_cmd" =~ -exec(dir)?([[:space:]]) ]] \
     || [[ "$stripped_cmd" =~ -delete([[:space:]]|$) ]] \
     || [[ "$stripped_cmd" =~ -ok([[:space:]]) ]]; then
    has_action=true
  fi

  if [[ "$stripped_cmd" =~ -(mtime|newer|size|atime|ctime|amin|cmin|mmin)([[:space:]]) ]]; then
    has_predicate=true
  fi

  if [[ "$has_action" == "false" && "$has_predicate" == "false" ]]; then
    # Pure search form; deny
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: "Use the Glob tool for file pattern search (Glob(\"path/pattern\")) or Bash with find actions (-exec, -delete). Pure find search without actions should use Glob. Example: Glob(\"src/**/*.ts\") to find TypeScript files."
      }
    }'
    exit 0
  fi
fi

# Step 8: deny sed (bare sed -n 'N,Mp' file or sed -n 'Np' file for extract-only; allow others)
if [[ "$bin" == "sed" ]]; then
  # Check for -n flag (non-printing mode, often used for extraction)
  if [[ "$stripped_cmd" =~ (^|[[:space:]])-n([[:space:]]|$) ]]; then
    # Likely a line-extraction form; deny
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: "Use the Read tool to read file contents (Read(file_path, offset, limit) for ranges) or Bash with sed for transformations. Bare sed -n (extract-only) should use Read. Example: Read(\"/path/to/file\", 0, 1000) to read a range."
      }
    }'
    exit 0
  fi
fi

# Step 9: deny awk (trivial forms: awk 1, awk '{print}', awk 'NR<=N'; allow others)
if [[ "$bin" == "awk" ]]; then
  # Extract the program (first non-flag argument)
  rest="${stripped_cmd#awk}"
  rest="${rest#[[:space:]]}"

  # Remove leading flags (-F, -v, etc.) and their values
  while [[ "$rest" =~ ^- ]]; do
    # Skip -X or -Xvalue forms
    if [[ "$rest" =~ ^-[a-zA-Z]([[:space:]] |:) ]]; then
      # Flag with separate value: -F : or -v x=1
      rest="${rest#-?[[:space:]]}"
      rest="${rest#*[[:space:]]}"
    else
      # Flag without value: -n
      rest="${rest#-?[[:space:]]}"
    fi
  done

  # Get the program token (quoted or unquoted)
  prog=""
  if [[ "$rest" =~ ^\'([^\']*)\' ]]; then
    prog="${BASH_REMATCH[1]}"
  elif [[ "$rest" =~ ^\"([^\"]*)\" ]]; then
    prog="${BASH_REMATCH[1]}"
  else
    prog="${rest%%[[:space:]]*}"
  fi

  # Deny if trivial form: check with regex because literal patterns won't match
  if [[ "$prog" == "1" ]] \
     || [[ "$prog" == "{print}" ]] \
     || [[ "$prog" =~ ^NR\< ]] \
     || [[ "$prog" =~ ^NR\> ]] \
     || [[ "$prog" =~ ^NR== ]]; then
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: "Use the Read tool to read file contents (Read(file_path) for full read or offset/limit for ranges) or Bash with awk for actual data processing. Trivial awk forms (awk 1, awk \"{print}\", awk \"NR<=N\") should use Read. Example: Read(\"/path/to/file\") to read entire file."
      }
    }'
    exit 0
  fi
fi

# Everything else → allow
exit 0
