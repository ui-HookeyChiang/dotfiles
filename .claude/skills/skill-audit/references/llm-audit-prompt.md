# Advisory LLM audit prompt

You are an Explore agent (read-only) auditing one SKILL.md for **semantic-layer**
issues that the syntax-layer detectors in skill-syntax-audit cannot see.

**Target file:** `{SKILL_PATH}`

**Metric prior** (provided by the upstream metric collector — use as a hint, not gospel):

{METRICS_BRIEF}

## What to find

Inspect the target file end-to-end and return YAML covering up to six
categories. Every category is optional — emit only what you find.

1. **paraphrased_redundancy** — same concept described in 2+ sections with
   different wording. The detector misses these because they aren't identical
   bash blocks.
   - **`_shared/lib`-anchor hint:** when the repeated concept is the
     *explanation* of a `_shared/lib/` function (e.g. `write_gate_trace` /
     `assert_gate_trace` re-taught at each call site — the calls differ in args
     so they slip the identical-bash detector, but the surrounding prose repeats
     the mechanism), set `refactor: "extract the explanation to one references/
     table; leave each call site its bash + a one-line pointer"`.

2. **semantic_scriptifiable** — deterministic flows described in prose (NOT in
   fenced code blocks). The detector doesn't read prose. Cross-check against
   the `scripts/` listing in the metric prior — don't recommend extracting a
   flow that's already implemented.

3. **contradictions** — an example or simplified version that conflicts with a
   canonical block elsewhere in the same file. Especially valuable: a
   simplified example whose failure mode is described in the troubleshooting
   section of the same file.

4. **covered_by_wrapper** — teaching content (Mode 1/2/3 explanations, How-To
   sections) that is fully implemented by a script under `scripts/`. The skill
   doesn't need to teach what the wrapper already does.

5. **behavior_mismatch** — prose that may not match the current codebase, sub-tagged
   by `kind`. ONE class, but each kind has its OWN judge (the removed-judge does
   NOT generalize — for unbuilt prose there is no code path, so its question is
   vacuously true). Candidate detection per kind (regex pre-filter, then the
   kind's judge confirms):

   - **`kind=removed`** (the former `legacy_marker`) — deprecation / legacy / TBD
     prose that may or may not still affect LLM behavior.
     - Keywords (case-insensitive): `deprecated`, `legacy`, `obsolete`,
       `will be removed`, `for backward compat(?:ibility)?`, `for one release cycle`,
       `淘汰`, `已廢棄`, `舊版`, `歷史原因`, `原本是`.
     - Prose-context TBD/TODO: in H2/H3 body prose, NOT inside code fences,
       NOT inside list items.
     - HTML comments `<!-- ... -->`. Exception: if the body is a pure
       placeholder token (e.g., `<!-- insights -->`, `<!-- placeholder -->`),
       it is an LLM-targeted directive — do not flag.
     - Parenthetical asides like `(說明：...)`, `(Note: legacy)`,
       `(原本是 X)`, `(deprecated)` in body prose (not table cells, not list items).

     **Judge — anchored to description triggers:** for each candidate marker,
     extract the first 5 user-intent phrases from the audited skill's
     `description:` (use all if fewer). Ask: "If a fresh LLM loads this SKILL.md
     WITHOUT the marker and the user issues ONE of those phrases, will it
     (a) execute the same code path → `behavioral_impact: none`;
     (b) recommend a deprecated alternative → `affects-recommendation`;
     (c) fail or invoke the wrong code path → `affects-execution`?" Tiebreaker
     (mandatory): uncertain a↔b → choose b; uncertain b↔c → choose c. Bias
     toward KEEPING. Information content alone is not grounds to keep.

   - **`kind=unbuilt`** — prose describing a planned/unimplemented feature a fresh
     agent could read as live behavior. Distinct from `removed` by keyword: it
     describes what *hasn't happened*, not what was taken away.
     - Pre-filter (case-insensitive, H2/H3 body prose only): `^> \*\*Flow
       enhancement:`, `doc-only for now`, `deferred to a follow-up`,
       `Future Phase`, `not yet (?:built|implemented|wired)`, `planned`.

     **Judge (NOT the removed-judge):** "Does the described behavior have any
     corresponding code / script / branch under `scripts/` today?
     **If YES → `keep`** (a live in-progress feature note — never delete).
     **If NO and the prose is aspirational/deferred → `consider-removing`**."
     `kind=unbuilt` NEVER emits `safe-remove` — a live WIP coordination marker
     must not be auto-deleted (max suggestion is `consider-removing`).

   - **`kind=stale`** — present-tense prose asserting OR negating a *local*
     mechanism that no longer matches `scripts/`. Distinct from `unbuilt`
     (future-shape) and `removed` (deprecation keywords): `stale` is a
     statement about what the code does *right now*.
     - Pre-filter (case-insensitive, H2/H3 body prose only, NOT in code
       fences, NOT list items):
       - mechanism tokens: `scripts/\w+`, env-var shape `[A-Z][A-Z0-9_]{3,}`,
         call form `` `\w+\(\)` ``;
       - negation / absence forms: `no auto-\w+`, `not (?:bound|gated|wired)`,
         `is (?:human-curated|not)\b`, `never \w+s`.
       The pre-filter is deliberately broad; the judge vetoes over-matches.

     **Judge (read the scripts yourself — there is no pre-computed table):**
     for each candidate mechanism-token, grep `scripts/` of the audited skill.
     A referent counts as **live ONLY IF** it is NOT inside a comment, a
     string-literal, or a disabled/test fixture (e.g. `todo_file:"n"`). Then
     judge by POLARITY (decide assertion-vs-negation FIRST, then check
     referents):
     - *assertion* ("X writes to Y", "scripts/foo enforces Z") + **zero** live
       referent → **drift** (prose claims a mechanism that is gone);
     - *assertion* + a **live** referent → NOT drift (do not emit);
     - *negation* ("no auto-N", "X not bound", "is human-curated") + a **live**
       referent → **drift** (prose denies a mechanism that exists);
     - *negation* + **zero** live referent → NOT drift (the absence is
       accurately described; do not emit);
     - otherwise → not drift (do not emit).

     **External-shape discriminator (mandatory veto before emitting):** if the
     mechanism matches external-shape AND has zero `scripts/` referent →
     **KEEP, not drift** — external mechanisms legitimately have no local
     referent. External-shape signals: `gh `/`git ` and other well-known CLI
     binaries; CI / eval-gate / required-check; device / hardware / reboot /
     power-cycle verbs; other-skill invocations (`Skill X`,
     `bash ~/.claude/skills/...`).

     **Severity & suggestion:** `kind=stale` defaults to **HIGH** (a phantom
     mechanism actively misleads a fresh agent) and **NEVER** emits
     `safe-remove` in EITHER `refactor` OR `removal_suggestion` — a drift
     finding surfaces for a human (cut the stale prose
     OR file the dropped-feature regression); it must not auto-delete the prose
     that may be the only evidence a feature regressed. Set `drift_note` to
     which side drifted (`prose-stale` vs `feature-dropped`) + the grep
     evidence (token; where the only referents, if any, were found).

     **Silent-empty guard:** if the pre-filter produced candidates but the
     judge confirmed none, set `drift_candidates_seen: N` on a single emitted
     item with `kind: stale`, `severity: LOW`, `removal_suggestion: keep`,
     `drift_note: "N candidates seen, 0 confirmed"`. This makes a
     judged-clean pass DISTINGUISHABLE from a detector that produced no
     candidates at all. If the pre-filter produced no candidates, emit nothing.

   **Severity → removal_suggestion mapping** (all kinds):
   - HIGH = `safe-remove` (`removed` only); `unbuilt` caps at MED;
     `stale` caps at `consider-removing` (NEVER `safe-remove`)
   - MED = `consider-removing-with-code-path` (`removed`) /
     `consider-removing` (`unbuilt`, `stale`)
   - LOW = `keep`

6. **provenance_citation** (B-prov) — inline spec-path / amendment citations that
   carry an audit trail but possibly no runtime value: ``(per `docs/spec/archive/…`)``,
   `(Amendment A8, v2.1 wire-up)`. The MANDATORY/gate label is load-bearing; *which
   spec mandated it* often is not — but a citation may be the ONLY pointer to a
   still-live contract not yet absorbed inline, so this NEVER bulk-deletes.
   - Pre-filter — **parenthetical asides only**, in-repo style:
     ``\((?:per|from|ref|spec):? `?docs/spec/(?:done|active)/`` and
     `Amendment A[0-9]`. Do NOT match bare navigation links (`see docs/spec/…`)
     or external references (`Amendment A3 to RFC …`).
   - **Keep-judge (mandatory before any non-LOW grade):** "Does the referenced
     spec carry a contract NOT already inline in this SKILL.md? If it MIGHT →
     `LOW` (human-review, never auto-cut). Only a citation whose target is fully
     inline → `MED`." `provenance_citation` NEVER emits a `safe-remove`-equivalent.

## Output format

Return EXACTLY a YAML document with the keys below. Each value is a list
(possibly empty). Each list item is a mapping with the documented keys.
Indentation is 2 spaces. No flow-style mappings, no anchors, no aliases.

```yaml
paraphrased_redundancy:
  - locations: [START-END, START-END, ...]   # line ranges, dash-separated
    summary: "one-line description"
    severity: HIGH | MED | LOW
    refactor: "what to do, named clearly"
    saved_lines: NUMBER

semantic_scriptifiable:
  - locations: [START-END]
    summary: "..."
    severity: ...
    refactor: "extract scripts/SEMANTIC-NAME.sh <args>"
    saved_lines: ...

contradictions:
  - locations: [START-END, START-END]   # at least 2 ranges
    summary: "..."
    severity: ...

covered_by_wrapper:
  - skill_lines: [START-END]
    wrapper: "scripts/NAME.sh"
    summary: "..."

behavior_mismatch:
  - locations: [START-END]         # short markers MUST use single-line: [N-N]
    summary: "..."                  # ≤ 80 chars human description
    kind: removed | unbuilt | stale   # which sub-detector matched
    severity: HIGH | MED | LOW
    refactor: "safe-remove | consider-removing-with-code-path | consider-removing | keep"
    saved_lines: NUMBER
    # behavior_mismatch fields:
    behavioral_impact: none | affects-recommendation | affects-execution
    removal_suggestion: safe-remove | consider-removing-with-code-path | consider-removing | keep
    keep_reason: "<required if removal_suggestion != safe-remove>"
    quote_is_non_unique: false      # set true if the same short quote (≤5 words)
                                    # appears elsewhere in the file
    drift_note: "<required for kind=stale: prose-stale|feature-dropped + grep evidence>"
    drift_candidates_seen: 0          # kind=stale only: pre-filter candidate count
                                      #   (set on the loud-empty sentinel item)
    # kind=unbuilt and kind=stale MUST NOT use safe-remove; kind=removed only may.

provenance_citation:
  - locations: [START-END]
    summary: "..."                  # ≤ 80 chars
    severity: MED | LOW             # never HIGH; LOW unless target fully inline
    target_fully_inline: true | false   # keep-judge result
    keep_reason: "<required when target_fully_inline is false>"
```

## Constraints

- Do NOT modify the target file.
- Do NOT run any of the commands in the file.
- Severity guide: HIGH = removes a footgun or saves > 30 lines; MED = saves
  10-30 lines or cleans up a real source of confusion; LOW = cosmetic.
- If you genuinely find nothing, return all six keys with empty lists.
- Do not emit any text outside the YAML document — no preamble, no trailing
  explanation. The caller parses the response with a strict YAML subset
  parser; any leading prose breaks it.
