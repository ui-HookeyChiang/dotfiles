# Planner modes: contexted vs no-context

## contexted (default)

Context file is inlined into the prompt; the model may use nothing else
(`--max-turns 8`, runs in an empty dir). Measures pure decomposition quality:
contract completeness, ordering, hidden-dependency detection WITHIN the given
text. This is the cheap, reproducible mode — same input every run.

## no-context (discovery mode)

The context file is WITHHELD; only its first 3 lines (the objective) are
given. The model runs inside `repo_dir` with read access (`--max-turns 20`)
and must discover the facts itself. Measures three things contexted cannot:

1. **Discovery cost** — turns/tokens spent finding what contexted got free.
   Compare cost/latency against the same model's contexted run.
2. **Hidden-dependency detection from source** — does it find the coupling by
   reading code, not by being told?
3. **Abstention honesty** — facts genuinely absent from the repo must land in
   `unresolved_questions`, not be invented. Seed the objective with one fact
   that is NOT discoverable; a plan that fabricates it fails scoring item 1
   and gets a fabrication note.

Scoring: same 8-item checklist, plus record discovery cost and
fabrication/abstention as first-class metrics.

Caveats: no-context runs are NOT reproducible across repo states — pin a
commit and record it in the ledger notes; runs are slower and cache-heavier,
so compare cost only within a batch (pitfall #3).

Observed 2026-07-23 (Opus 4.6/4.8 low, n=2): with an already-implemented
objective, all runs correctly abstained (tasks: []) — pick NOT-yet-implemented
objectives for fixtures, or the mode only measures abstention. 4.8 found the
shipped PRs and the one residual coverage gap in fewer turns than 4.6.
