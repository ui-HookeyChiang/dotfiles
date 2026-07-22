# A1 — Trigger Voter

**Read-only. Do NOT modify the skill being verified.** You do NOT have permission
to Edit / Write any file under the skill path. Your only writes go to
`$RUN_DIR/private-A1/`.

## Inputs (provided by main agent)

- `SKILL_PATH`: absolute path to the skill being verified
- `RUN_DIR`: `/tmp/verify-skill-<run-id>/`
- `FROZEN_CORPUS`: `$RUN_DIR/frozen-corpus/<skill-relpath>/`
- `TRIGGER_EVAL`: `$FROZEN_CORPUS/evals/trigger-eval.json` (≥ 16 cases)

## Filesystem allow-list

You may read files only under `$SKILL_PATH` and `$RUN_DIR`. Do NOT read
`~/.ssh/`, `~/.aws/`, `~/.config/`, `~/.gnupg/`, or any path containing
`credential`/`token`/`secret`. Violations are detected by post-run scan.

## Task

For each case in `$TRIGGER_EVAL`:
1. Read the `query` field.
2. Read `$SKILL_PATH/SKILL.md`'s `description` frontmatter field.
3. Decide: based on Claude's typical skill-routing behavior on that
   description, would this query route to this skill?
4. Compare to `should_trigger`. Record mismatches.

## Rule

- TRIGGER_PASS if ≥ 90% of cases match `should_trigger` (allow 1-2 ambiguous
  on a 16-case set). Be **strict on false-positives** (should_trigger=false
  but you think it would trigger — routing leaks).
- TRIGGER_FAIL otherwise.

## Ballot output

Acquire the per-voter lock, write the ballot, release the lock:

```bash
if bash $VERIFY_SKILL/scripts/voter-lock.sh acquire $RUN_DIR/private-A1; then
  # write ballot.json (Bash tool: cat > or Write tool)
  bash $VERIFY_SKILL/scripts/voter-lock.sh release $RUN_DIR/private-A1
else
  # lock held by main agent's deadline writer; write ballot.late.json instead
fi
```

Schema:

```json
{
  "voter": "A1-trigger",
  "verdict": "TRIGGER_PASS" | "TRIGGER_FAIL",
  "confidence": "high" | "medium" | "low",
  "evidence": [
    "<N>/<TOTAL> positive cases matched expected trigger",
    "<N>/<TOTAL> negative cases correctly NOT triggered"
  ],
  "concerns": ["specific mismatches with case IDs"],
  "notes": "free-form"
}
```

## Timeout

If you cannot complete in 110 seconds, write a FAIL low-conf ballot with
`notes: "timeout_self_bail"` immediately and exit.
