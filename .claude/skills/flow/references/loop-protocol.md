# Loop protocol reference (spec-advisory)

Main-agent-driven auto-fix loop for spec quality convergence.

---

## Mechanics

The main agent drives the loop directly (no `/goal`, no Haiku evaluator).

1. Snapshot spec → `/tmp/loop-orig.$$`; init `/tmp/loop-history.$$.jsonl`.
2. Per iteration N:
   - Run spec-advisory; append envelope to history.
   - **Cycle check:** if `spec_hash` matches a prior iteration AND
     `next_action == edit_spec` → `cycle=detected`, stop.
   - **Termination:** stop if ANY of: `next_action == done` / H==0 M==0 /
     `cycle == detected` / `N == max_iter`.
   - Otherwise apply `findings[].suggestion`, N += 1, repeat.
3. On termination: generate summary from history + diff vs snapshot.
   Approval gate runs — the user is always the final writer.

## Knobs

| Env var | Effect |
|---|---|
| `SD_ADVISORY_MAX_ITER=N` | Override cap (default 5, clamped 1..99) |
| `SD_SKIP_ADVISORY=1` | Skip the entire advisory layer |

LOW findings never block termination.

## Status line format

```
loop status: iteration=N/MAX, next_action=<done|edit_spec|max_iter>, findings=H:n M:n L:n, cycle=<none|detected>
```

The status line is the **last stdout line** of each turn (anything else
prints before it).

## Exit-2 fallback

Script exit 2 (bad iteration / missing file) → abort loop, surface stderr,
fall back to one single-pass advisor run. If that also exits 2 → STOP
(vanished spec is an operator problem).

## Edge cases

| Case | Behaviour |
|---|---|
| HIGH finding with empty `suggestion` | Downgrade to MED (`no_rewrite=true`); do not commit empty edit |
| Agent timeout (120s) | Continue with partial findings; all-timeout → `next_action=done` |
| User Ctrl-C | Snapshot + partial history remain on disk; re-run starts fresh (PID-suffixed) |
