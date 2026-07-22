# Legacy detector internals

The legacy detector pipeline (reached only via `--write-spec` / `--no-spec`) runs
six detectors against the parsed SKILL.md + `scripts/`. Detectors 1 and 2 are
first-class findings (HIGH/MED/LOW severity, shown in the summary table).
Detectors 3 and 6 are passive — info-level hints only, never flip the exit code.
Detectors 4 (frontmatter, kind=F) and 5 (broken links, kind=L) are documented
inline in `scripts/syntax_audit.py` (via `scripts/audit.py` shim) (`detect_frontmatter_pathology` / `detect_broken_links`).

## Detector 1: redundant steps

**Rule**: a redundancy finding is emitted when the same instruction pattern
appears in **2 or more distinct locations** within the SKILL.md.

What counts as "same instruction pattern":
- Identical bash command sequence (≥ 3 lines) appearing in multiple code blocks
- Identical prose paragraph (≥ 30 words) appearing in multiple sections
- The same imperative step (e.g., "run X, then verify Y, then push Z") described in 2 distinct phases

What does **not** count:
- Single-line bash commands repeated (too noisy, often unavoidable)
- Section headers that look similar but cover different topics
- Different phrasings of the same idea (this is darwin-skill's territory)

For each finding, the report names:
- The two (or more) locations by line range
- A 1-line summary of the duplicated content
- Severity: HIGH (≥ 3 occurrences or ≥ 10 lines each) / MED (2 occurrences ≥ 5 lines) / LOW (2 occurrences < 5 lines)
- Proposed refactor: usually "extract to a named anchor and reference it from both call sites", or "extract to scripts/foo.sh and replace both with `bash scripts/foo.sh`"
- Estimated lines saved (sum of all but one occurrence, minus the reference line)

## Detector 2: scriptifiable instructions

**Rule**: a scriptifiable finding is emitted when a code block contains **3 or
more chained bash commands** that:

- Form a deterministic sequence (no human judgement between steps)
- Have no inline natural-language interjection ("If X, decide whether Y")
- Are not in a "reference example" context (e.g., inside a "## Example output" section)

Counter-examples that should NOT be flagged:
- Two commands chained with `&&` (too short to justify script)
- Commands followed by "review the diff before continuing" (judgement step present)
- Snippets shown for context inside narrative ("for example, you might run...")

For each finding:
- Line range of the block
- Severity: HIGH (≥ 8 chained cmds, exact duplication exists across skill) / MED (5-7 cmds) / LOW (3-4 cmds)
- Proposed refactor: "extract to scripts/<name>.sh with arguments <list>"
- Suggested script name based on the dominant verb of the sequence
- Estimated lines saved (block lines minus 1 reference line)

## Detector 3 (passive): script-side redundancy

When auditing the skill's `scripts/` directory, scan for **literal duplication
across scripts** (e.g., two scripts each open with the same 20-line setup block).
This catches cases where extraction already happened but didn't go far enough.

This detector produces info-level findings only (never blocks the spec). It's a
hint, not a verdict.

## Detector 6: unbound variables (kind=V)

**Rule**: a `bash` fence in SKILL.md references `$VAR` / `${VAR}` that is never
bound anywhere the file can reach statically.

**Bound** means: `VAR=` assignment, `for VAR in`, `read VAR`, `export VAR`, or
`VAR=$(cmd)` capture — in the same SKILL.md, OR in a script the fence explicitly
`source`s / `.`-includes (strict source-aware: `bash X.sh` subprocess does NOT
count).

**Silenced by** `scripts/known-env.txt` — POSIX/common env vars (`HOME`, `PWD`,
`PATH`, …) and repo-harness prefixes (`SD_*` glob) declared there are never
flagged. If the file is missing, treats known_env as empty (no crash).

**Reference-scan guards (false-positive floor)**:
1. `#` comment content is stripped (but not `#` inside `${}` or quoted strings).
2. Single-quoted `'...'` spans are skipped (no expansion).
3. `<<'QUOTED'` / `<<"QUOTED"` heredoc bodies are skipped; unquoted `<<EOF` bodies are scanned.
4. Operator param-expansions `${VAR:-x}` `${VAR:=x}` `${VAR:?x}` `${VAR:+x}` are excluded — this stops the detector flagging the guard it prescribes.
5. Positional / special params `$1 $@ $* $# $? $$ $! $0 $-` are always skipped.

**Granularity**: one finding per distinct unbound var name, listing all line
numbers where it appears.

**Severity**: `INFO`. **Passive** — never flips the exit code (same as Detector 3).
The exit-code logic in `_run_legacy` skips kinds `I` and `V` when deciding 0 vs 2.

**Prescription**: add a guard `: "${VAR:?set by <X>}"` near the fence, or add a
contract prose line above the block stating who binds `VAR`.
