# Expectation-Spec Standard

Owns the `rewrite` mode expectation-spec freeze + TEST absolute acceptance protocol. Mandatory
INTENT · expectation-spec freeze for any v1 → v2 rewrite; no `--skip-expectation-spec` escape hatch.

## Rules

1. **Mandatory for `rewrite` mode.** INTENT · expectation-spec freeze runs before
   any v2 design work. `--skip-expectation-spec` is not a valid flag; if you think
   you need it, the change is `modify` or `improve`, not `rewrite`.
2. **Spec contents.** The frozen spec must include:
   (a) **behavior expectations** — does the skill, followed on real tasks, produce
   correct artifacts (defined concretely, checkable by a fresh agent);
   (b) **trigger-accuracy threshold** — minimum true-positive % on a held-out set;
   (c) **cost expectations** — output-token budget per invocation, ONLY when the
   rewrite goal explicitly includes cost reduction; omit otherwise;
   (d) **v1's known failures** — write each as an explicit expectation the v2 must
   satisfy (the failing-test equivalent; positive-only specs silently drop failure signal).
3. **Freeze before v2.** Write spec to
   `docs/dogfoods/<skill-name>-vN/iteration-M/expectation-spec.md`
   (cumulative iteration numbering — see `docs/dogfoods/README.md`).
   Frozen at INTENT boundary; no edits after v2 authoring begins (anti-self-grading).
4. **Fresh-verifier at TEST.** Dispatch a fresh agent (subtype: general-purpose)
   that has NOT seen the spec-authoring session. Agent runs v2 on real tasks and
   judges each spec item PASS or FAIL — absolute, not comparative to v1.
   Agent MUST NOT read v1 skill files (contamination risk).
5. **User-review floor.** **auto-PASS is forbidden** — the user must explicitly
   accept the acceptance report. The fresh agent reports verdicts; the human closes the loop.
6. **Expectation-spec freeze ≠ audit-v1 ≠ resident dogfood — none substitutes for another.**
   Expectation-spec freeze is an *absolute acceptance criterion* set before v2 (anti-self-grade).
   INTENT · audit-v1 is a *static read* of v1 ("what to fix") and does NOT satisfy the spec
   freeze. TEST · resident dogfood is a *live, open-ended* run of v2 ("does it work now") and
   does NOT satisfy expectation acceptance either. Both run independently; a `rewrite` owns all three.
7. **Navigability dimension — count, don't score (structural rewrites).** When the
   rewrite is a phase/stage REORG, navigability is measured by two `rg`-countable
   proxies, not an LLM rating:
   (a) **top-level ID count** — `## ` stage/phase headings + sub-letters a reader
   must hold to know the flow; (b) **per-mode lookup-site count** — how many
   non-adjacent places state "rewrite only / modify skips" (or is there ONE
   unified map?). Write these as explicit spec expectations: "ID count ≤ N" and
   "per-mode lookup sites ≤ M". The acceptance agent counts them independently —
   it must NOT have seen the spec author's numbers before counting (anti-self-grade).
   A restatement that EXPLICITLY points at the SSOT ("per the Mode table") is NOT
   a drift site; only an independent restatement of the value counts.

## Trust root

Spec is taken from the v1 skill at `origin/main` HEAD, never from a self-authored
prior iteration. Chaining a self-graded "after" into the next "before" moves the
bar off the trust root; always re-freeze from `origin/main`.

## Examples

Expectation spec template (fill in per iteration):

```markdown
# Expectation Spec — <skill-name> v2 (iteration N)

Frozen: <ISO date> | Source: origin/main HEAD

## Behavior expectations
- [ ] Skill produces <artifact> given <input> (PASS = artifact matches criteria; FAIL = does not)
- [ ] ...

## Known failures (v1) — v2 must fix these
- [ ] v1 fails when <condition>: v2 MUST NOT fail under same condition

## Trigger-accuracy threshold
- Minimum true-positive %: NN% on held-out set (≥ 8 positive cases)

## Cost expectations (only if rewrite goal includes slimming)
- Output tokens per invocation: ≤ NNNN
```

## Anti-patterns

| Pattern | Why bad | What to do instead |
|---|---|---|
| Fresh agent reads spec-authoring session context | contamination; verdicts are self-graded | dispatch truly fresh agent with no prior context |
| Positive-only spec (no known failures listed) | silently drops v1 failure signal | write v1 known failures as explicit expectations |
| Cost expectation added without slimming goal | scope creep; punishes correct rewrites | include cost expectation only when rewrite goal names slimming |
| Auto-PASS without user review | user is the floor on subjective dimensions | print acceptance report; require explicit accept |
| Spec edited after v2 authoring begins | invalidates anti-self-grade guarantee | freeze spec before opening skill-creator |
| Spec from working tree instead of trust root | drift between spec and actual v1 | snapshot from `origin/main` HEAD |

## Override

Trivial single-line rewrites can declare `modify` instead of `rewrite`
to skip INTENT · expectation-spec freeze legitimately. The mode boundary is described in
[`equivalence-criteria.md`](equivalence-criteria.md): if the change is
local optimization with skeleton unchanged, it is `improve`; if the
skeleton changes (stage/phase reorganization, description change), it is
`rewrite` and INTENT · expectation-spec freeze is mandatory.

## Validation

`scripts/dispatch-expectation-acceptance-agent.sh` allocates the iteration directory,
writes the spec template, and prints the acceptance-agent dispatch prompt. A3 Equivalence
voter checks that the declared mode matches the actual change (per
Rule 2 of equivalence-criteria); a `rewrite` declaration with no INTENT · expectation-spec
artifacts in `docs/dogfoods/` routes to NEEDS_HUMAN.
