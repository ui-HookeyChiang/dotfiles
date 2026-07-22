# Design notes — skill-audit

## Historical context: engine code was once duplicated

Prior to the merge (2026-06-28), the audit engine code existed as byte-identical
copies under `skill-audit/` and `skill-audit/`. This
was deliberate: each audit skill was self-contained. The accepted cost was dual
maintenance — a bugfix had to be applied to both copies.

The merge consolidates all engine code into `skill-audit/scripts/`. The
duplication, the logic-sync rule, and the per-skill self-naming divergence are
all eliminated.

## Engine code now lives in skill-audit/scripts/

`syntax_audit.py`, `semantic_audit.py`, `detectors/`, `advisory/`, and
`references/llm-audit-prompt.md` are the single authoritative copies.
Reports identify themselves as `skill-audit`.

## Deterministic vs probabilistic recall — which leg owns recall

`coding-guidelines` §6 gives the universal rule (deterministic first; a closed concept needs no LLM). This is the detector-design refinement of it: when a deterministic layer pre-filters for an LLM judge, the **concept's shape decides the architecture, not just the order**. Three cases:

- **Closed concept** — the thing checked is finitely enumerable (graph reachability, byte-identical duplication, a schema, a path that resolves). Deterministic IS the final answer; do NOT bolt on a probabilistic stage — an LLM only adds nondeterminism to a question already settled.
- **Open concept WITH a cheap recall signal** — a judgement over an open set, but a cheap deterministic signal ranks or gates candidates well (token-Jaccard / embeddings for duplication; a date/version/provenance SHAPE for history-prose). Make the deterministic layer a WIDE-RECALL pre-filter (gate on the *shape*, not an enumerated keyword whitelist; cast broad, accept false positives) and let the LLM supply precision. (Model: the G1 axis — token-Jaccard wide pre-filter → LLM judge.)
- **Open concept with NO cheap recall signal** — no deterministic gate, however broad, covers the open set; any whitelist (verbs OR shapes) misses the next phrasing ("前身是", "used to live in", "back when"). The LLM OWNS recall: it scans the whole artifact, not just confirms candidates. Pay the LLM call — completeness wins over the saved dispatch, advisory or not; a deterministic gate cannot be made complete here, so don't pretend a wider whitelist will get there. In `--no-llm`, an open concept returns **N/A (fail-loud)** — it does NOT emit a lossy regex answer as a finding. The deterministic fallback may still RUN to gather candidates for an INFO count, but it must not present them as findings; it reports "N/A: open-concept recall needs an LLM; not run". Returning a bare `[]` or a regex finding in `--no-llm` is **fail-silent** (the caller cannot distinguish "nothing found" from "axis not run").

**"Does a cheap signal exist?" is a fuzzy line, not a decidable test** — a shape-gate covers most history-prose but never all. When unsure whether a signal is cheap *enough*, treat the concept as having none and let the LLM own recall; the cost of an extra dispatch is smaller than a silent recall gap. Reserve the deterministic-only path (closed concept) for concepts that are genuinely closed.

Smell: an open-concept detector with a hand-maintained *keyword* whitelist (vs a broad shape-gate) and no LLM precision stage under-recalls by construction.
