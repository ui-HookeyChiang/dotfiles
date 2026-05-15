#!/bin/bash

# Graceful fallback: if no API key, exit 0 so the wrapper falls through to
# standard `git commit -v` (editor flow). This lets users without the env var
# still commit normally without seeing two layered errors.
if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "note: ANTHROPIC_API_KEY not set — skipping AI commit message generation." >&2
  echo "      (set ANTHROPIC_API_KEY in your shell to enable, or use 'git commit' directly.)" >&2
  exit 0
fi

# Model selection (override with CLAUDE_MODEL env var)
CLAUDE_MODEL="${CLAUDE_MODEL:-claude-opus-4-7}"

if [ -z "${1:-}" ]; then
  diffopt="--cached"
  range="HEAD"
else
  hash=$(git rev-parse "$1")
  range="$hash~1..$hash"
fi

# Get git diff context
diff_context=$(git diff ${diffopt:-} --diff-algorithm=minimal "$range")

if [ -z "$diff_context" ]; then
  echo "Error: No staged changes found" >&2
  exit 1
fi

# Get last 3 commit messages
recent_commits=$(git log -3 --pretty=format:"%B" | sed 's/"/\\"/g')

# Prepare the prompt
prompt="Generate a git commit message following this structure:
1. First line: conventional commit format (type: concise description) (remember to use semantic types like feat, fix, docs, style, refactor, perf, test, chore, etc.)
2. Optional bullet points if more context helps:
   - Keep the second line blank
   - Keep them short and direct
   - Focus on what changed
   - Always be terse
   - Don't overly explain
   - Drop any fluffy or formal language

Return ONLY the commit message - no introduction, no explanation, no quotes around it.

Examples:
feat: add user auth system

- Add JWT tokens for API auth
- Handle token refresh for long sessions

fix: resolve memory leak in worker pool

- Clean up idle connections
- Add timeout for stale workers

Simple change example:
fix: typo in README.md

Very important: Do not respond with any of the examples. Your message must be based off the diff that is about to be provided, with a little bit of styling informed by the recent commits you're about to see.

Recent commits from this repo (for style reference):
$recent_commits

Here's the diff:

$diff_context"

# Properly escape the prompt for JSON
json_escaped_prompt=$(jq -n --arg prompt "$prompt" '$prompt')

# Call Claude API with properly escaped JSON
response=$(curl -s https://api.anthropic.com/v1/messages \
    -H "content-type: application/json" \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    --data-raw "{
        \"model\": \"${CLAUDE_MODEL}\",
        \"max_tokens\": 1024,
        \"messages\": [
            {
                \"role\": \"user\",
                \"content\": ${json_escaped_prompt}
            }
        ]
    }")

# Detect API error response shape (e.g. {"type":"error","error":{...}})
api_error=$(echo "$response" | jq -r '.error.message // empty')
if [[ -n "$api_error" ]]; then
  echo "Error: Anthropic API returned an error:" >&2
  echo "  $api_error" >&2
  echo "" >&2
  echo "Full response:" >&2
  (echo "$response" | jq '.' >&2 2>/dev/null) || echo "$response" >&2
  exit 1
fi

# Defensive: also bail if .content[0].text is missing (malformed response)
if ! echo "$response" | jq -e '.content[0].text' >/dev/null 2>&1; then
  echo "Error: API response missing .content[0].text:" >&2
  (echo "$response" | jq '.' >&2 2>/dev/null) || echo "$response" >&2
  exit 1
fi

# Extract the commit message from the response
commit_message=$(echo "$response" | jq -r '.content[0].text')

# Output the commit message
echo "$commit_message"
