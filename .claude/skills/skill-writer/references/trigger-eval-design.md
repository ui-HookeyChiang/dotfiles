# Trigger-Eval Design

Owns the `evals/trigger-eval.json` design principles. Strengthens
A1 Trigger by ensuring the eval cases are realistic and anti-overfit.

## Rules

1. **≥ 16 cases total**, with ≥ 8 `should_trigger: true` and ≥ 8
   `should_trigger: false`. A4 Contract enforces this threshold.
2. **≥ 50% near-misses.** A near-miss shares keywords with a positive
   case but has different intent (e.g. "format this JSON" should NOT
   trigger a YAML-formatting skill). Without near-misses, A1 measures
   keyword matching, not intent inference.
3. **Realistic prose.** Include file paths, column names, company /
   product names, casual language, typos, mixed Chinese / English where
   relevant. Abstract cases ("format data") prove nothing.
4. **Cover axes:** happy path, edge case (rewrite / refactor / "small
   edit"), cross-skill conflict (two skills could match, this one must
   win), multilingual.
5. **Anti-overfit.** Cases SHOULD be drafted by someone OTHER than the
   description author — or by a fresh Claude session — to avoid the
   author anchoring the cases to the description they just wrote.
   If unavoidable, mark `author_self_drafted: true` in the case and
   A1 will down-weight it.

## Examples

GOOD case (realistic, near-miss):

```json
{
  "id": 7,
  "prompt": "I just split skill-writer SKILL.md by extracting verify-skill gate details into a references/phase-6-gate.md file; can you check it still triggers correctly?",
  "should_trigger": true,
  "rationale": "Refactor that touches description-adjacent surface — covers the 'small edit' rationalization axis."
}
```

BAD case (abstract, exact-match-only):

```json
{
  "id": 7,
  "prompt": "create a skill",
  "should_trigger": true,
  "rationale": "happy path"
}
```

Why bad: "create a skill" matches by keyword regardless of context;
proves only that the description contains the word "skill". No near-
miss, no realistic prose, no edge case.

## Anti-patterns

| Pattern | Why bad | What to do instead |
|---|---|---|
| All cases `should_trigger: true` | no negative side; A1 can't measure precision | balance ≥ 8 / ≥ 8 |
| Exact-match phrasing only | tests keyword match, not intent | add near-misses + paraphrased positives |
| Cases drafted by the description author | overfit risk; A1 looks falsely good | use fresh-session author OR mark `author_self_drafted: true` |
| `prompt` < 10 words | too abstract; no signal | use realistic paragraph-length user queries |
| Missing `rationale` field | A1 can't explain false negatives | always include 1-line rationale |

## TEST · 5a trigger-eval live (advisory)

TEST · 5a trigger-eval live optionally runs the corpus against a LIVE model to measure whether the
description ACTUALLY triggers the skill. It is **advisory / non-blocking** — TEST · verify-skill 5-voter
stays the binding gate; a non-deterministic live-LLM measurement must
never auto-PASS or auto-block. The SKILL.md body holds the runnable snippets; this
section is the SSOT for the two governing rules.

### Skip when the description is frozen (modify / equivalence)

TEST · 5a trigger-eval live measures *trigger-rate*, a function of the `description` only. Compute whether the
description text changed vs the trust root (the `origin/main` merge-base — the same ref
TEST · verify-skill auto-detects):

```bash
base=$(git merge-base origin/main HEAD)
git diff "$base" HEAD -- <skill>/SKILL.md | grep -qE '^[-+]description:'
# exit 0 (match)    => description line changed => RUN 5a
# exit 1 (no match) => description frozen       => SKIP (verdict=skip-desc-frozen)
```

When frozen (the common case in a `modify` prose-slim or an equivalence-mode rewrite
that holds the description), the trigger-rate cannot have moved — 5a would measure a
constant. Record a traced `verdict=skip-desc-frozen` and move on. The grep is precise:
only a changed `description:` line triggers the run, so a body-only edit correctly skips
and a real description edit correctly runs. (Multi-line block-scalar descriptions are
not used in this repo; the single-line `description:` match holds.)

### Anti-self-grading invariant (MUST hold)

`run_eval`'s output is a measurement ONLY — it is **NEVER** wired into a description
mutator. The moment a measure feeds an auto-rewrite, `run_loop` (a rejected SSOT
Non-Goal) is rebuilt. Report the numbers; never act on them automatically.

### Traced skips (never a silent all-fail)

Per [[feedback_advisory_non_blocking_silent_skip]], every non-run records a traced
`verdict=skip-<reason>`, never a silent drop or a fake all-False:
- `skip-desc-frozen` — description unchanged (above).
- `skip-no-auth` — no `claude` CLI auth (CI / cron / `SD_AUTONOMOUS`).
- `skip-no-skill-creator` — upstream skill-creator not resolvable.
- `skip-no-corpus` — `evals/trigger-eval.json` not yet authored.

## Override

None. Trigger eval is the **fundamental** measurement for A1; weakening
it weakens the floor of the whole 5-voter gate.

## Validation

A1 Trigger consumes `evals/trigger-eval.json` (frozen from trust root).
A4 Contract verifies the ≥ 16-case threshold and the ≥ 8 / ≥ 8 split.
Anti-overfit is partially mechanical (down-weight self-drafted cases)
and partially process (encourage fresh-session drafting).
