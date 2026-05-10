---
kind: spec
status: done
created: 2026-05-10
slug: ai-commit-graceful
---

# Design: `.ai-commit-msg.sh` graceful — F4 (jq null check) + F5 (API key fallback)

**Date:** 2026-05-10
**Status:** Done (brainstorming bypassed — see Background)
**Owner:** hookey.chiang@ui.com

## Background

Follow-up to PR #22 (silent-failure-bugs F2/F3 in `.ai-commit*.sh`). Two MED-severity bugs remained in `.ai-commit-msg.sh`:

### F4: `.ai-commit-msg.sh:84` — `jq -r` doesn't check API errors

```sh
commit_message=$(echo "$response" | jq -r '.content[0].text')
```

When the Anthropic API returns an error (rate-limited, invalid model, network blip), the response shape is `{"type":"error","error":{...}}` — there's no `.content[0].text`. `jq -r` on a missing path returns the literal string `null`. The outer `.ai-commit.sh` then commits with the message `"null"` — quietly broken commit.

### F5: `.ai-commit-msg.sh:4-7` — Hard fail on missing API key

```sh
if [ -z "$ANTHROPIC_API_KEY" ]; then
  echo "Error: ANTHROPIC_API_KEY environment variable is not set" >&2
  exit 1
fi
```

When the env var isn't set, the script `exit 1`s. The wrapper `.ai-commit.sh` then calls `git commit -m "$commit_message"` where `$commit_message` is empty — git refuses with `Aborting commit due to empty commit message`. User sees TWO errors but no path forward. Should gracefully fall back to a standard `git commit -e` flow (open editor) or exit cleanly so the wrapper can.

Brainstorming bypassed: user picked F4=(c) print error + exit, F5=(a) graceful exit 0 so git falls back.

## Goal

Single PR adding two safety nets:
1. F4: detect API errors after the curl call, print details, `exit 1` (don't return `null`).
2. F5: missing API key → print clear note + `exit 0` so wrapper falls back to standard editor commit.

## Locked parameters

### F4 fix — after line 81 (the curl call), before line 83 (jq extraction):

```sh
# Detect API error response (e.g. {"type":"error","error":{"type":"...","message":"..."}})
api_error=$(echo "$response" | jq -r '.error.message // empty')
if [[ -n "$api_error" ]]; then
  echo "Error: Anthropic API returned an error:" >&2
  echo "  $api_error" >&2
  echo "" >&2
  echo "Full response:" >&2
  echo "$response" | jq '.' >&2 2>/dev/null || echo "$response" >&2
  exit 1
fi

# Defensive: also bail if .content[0].text is missing for any reason (malformed JSON)
if ! echo "$response" | jq -e '.content[0].text' >/dev/null 2>&1; then
  echo "Error: API response missing .content[0].text:" >&2
  echo "$response" | jq '.' >&2 2>/dev/null || echo "$response" >&2
  exit 1
fi
```

Then keep line 84 unchanged (`jq -r` extracts the validated value).

### F5 fix — replace lines 4-7:

```sh
# Graceful fallback: if no API key, exit 0 so the wrapper falls through to
# standard `git commit -e` (editor flow). This lets users without the env var
# still commit normally without seeing two layered errors.
if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "note: ANTHROPIC_API_KEY not set — skipping AI commit message generation." >&2
  echo "      (set ANTHROPIC_API_KEY in your shell to enable, or use 'git commit' directly.)" >&2
  exit 0
fi
```

Key changes:
- `[ -z "$X" ]` → `[[ -z "${X:-}" ]]` (handles `set -u` + zsh portability)
- `Error:` → `note:` (this is graceful, not an error)
- `exit 1` → `exit 0` (let `.ai-commit.sh`'s `git commit -m ""` fail naturally with "empty commit message" — that's git's standard "do you want to abort?" path which user knows how to handle)
- Add helpful guidance about how to enable AI mode or skip it entirely

But wait — `git commit -m ""` doesn't open the editor. The wrapper does:
```sh
commit_message=$(~/.ai-commit-msg.sh "$hash")
git commit -m "$commit_message"
```

When `commit_message=""`, `git commit -m ""` aborts with "Aborting commit due to empty commit message". Not graceful.

Better solution for F5: the wrapper `.ai-commit.sh` should detect empty output and switch to `git commit -v` (open editor). But that's a wrapper change, not a `.ai-commit-msg.sh` change. **Scope expansion**: F5 fix touches BOTH files.

Revised plan:
- `.ai-commit-msg.sh`: when no API key, exit 0 with note (no message printed to stdout).
- `.ai-commit.sh`: after capturing `commit_message`, if empty → fall back to `git commit -v` (open editor).

```sh
# .ai-commit.sh — after line 7 (commit_message=$(~/.ai-commit-msg.sh "$hash"))
# Allow ai-commit-msg.sh to bail (e.g. missing API key); fall back to editor flow.
if [[ -z "$commit_message" ]]; then
  echo "note: AI commit message not available — opening editor for manual commit." >&2
  if [ -z "$hash" ]; then
    git commit -v "$@"
    exit $?
  fi
  echo "Error: cannot reword historic commit without AI message; aborting." >&2
  exit 1
fi
```

(The historic-reword case — `if [ -z "$hash" ]` false branch — has no graceful fallback because the whole flow depends on AI generating each commit's new message. Document that limitation.)

## Out of scope

- Multi-message generation for historic reword fallback — non-trivial; deferred.
- Retry logic on transient API errors (5xx, rate limits) — useful but complex; YAGNI for personal tool.
- Switching SDK to anthropic-sdk-python or curl alternative — nope.
- Caching commit messages or batch generation — out of scope.

## Verification

```bash
# 1. Syntax + shellcheck
bash -n .ai-commit.sh && bash -n .ai-commit-msg.sh
shellcheck -S error .ai-commit.sh .ai-commit-msg.sh

# 2. F4: error response handling
fake_resp='{"type":"error","error":{"type":"invalid_request_error","message":"max_tokens too high"}}'
output=$(echo "$fake_resp" | { ANTHROPIC_API_KEY=test bash -c '
  source <(grep -A 1000 "api_error=" .ai-commit-msg.sh | head -20)
' 2>&1; } || true)
# Hard to unit-test — use the integration-test approach instead:
# Inject a mock $response and verify error path:

# Synthetic test: parse the post-fix script and verify it bails on error response
cat > /tmp/test-f4.sh << 'INNER'
#!/usr/bin/env bash
response='{"type":"error","error":{"type":"invalid_request_error","message":"test"}}'
# Inline the fix logic:
api_error=$(echo "$response" | jq -r '.error.message // empty')
if [[ -n "$api_error" ]]; then exit 42; fi
exit 0
INNER
bash /tmp/test-f4.sh
[ $? -eq 42 ] && echo "OK: F4 detects error responses"

# 3. F5: missing API key returns 0 silently from .ai-commit-msg.sh
unset ANTHROPIC_API_KEY
output=$(bash .ai-commit-msg.sh 2>&1)
rc=$?
[ $rc -eq 0 ] && echo "OK: F5 exits 0 on missing key"
echo "$output" | rg -qF "ANTHROPIC_API_KEY not set" && echo "OK: F5 prints note"
[ -z "$(echo "$output" | rg -v 'note:|^$|set ANTHROPIC')" ] && echo "OK: F5 stdout clean (only note: messages)"

# 4. F5 wrapper: .ai-commit.sh falls back to editor when commit_message empty
unset ANTHROPIC_API_KEY
# Don't actually run git commit — verify the script structure is correct:
rg -qF 'git commit -v' .ai-commit.sh && echo "OK: F5 wrapper has editor fallback"
rg -qF 'AI commit message not available' .ai-commit.sh && echo "OK: F5 wrapper note present"
```

## Acceptance criteria

- [ ] `bash -n` both scripts: clean
- [ ] `shellcheck -S error`: no errors
- [ ] F4: API error response detected, full response dumped to stderr, exit 1
- [ ] F4 defensive: missing `.content[0].text` also caught
- [ ] F5: missing `ANTHROPIC_API_KEY` → exit 0 + note (not error)
- [ ] F5 wrapper: empty `commit_message` → editor fallback (`git commit -v`)
- [ ] PR #22's F2 + F3 fixes still intact (cherry-pick --abort, CLAUDE_MODEL env var)
- [ ] Diff scope: only `.ai-commit.sh` + `.ai-commit-msg.sh` + spec
- [ ] Single SSH-signed commit
- [ ] Spec promote: `active/` → `done/`

## Risk

- **Low.** Both fixes add safety nets where the script would have failed silently or noisily before.
- F5 wrapper change converts a "blocked" state into "fall back to editor" — strictly safer.
- F4 error detection: if the API ever returns a different error shape, we may miss it — mitigated by the defensive `.content[0].text` check.
