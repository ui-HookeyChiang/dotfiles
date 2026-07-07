# Delegation Templates

Copy the matching template into the Agent prompt, fill every `{…}` slot, delete
nothing. Rules behind them: `.claude/model-dispatch.md`. All templates end with
the same report contract — keep it verbatim.

**Shared report contract (append to every dispatch):**

> Report back: conclusions only, each with `file:line` references. Any artifact
> longer than ~30 lines goes to a file under {artifact-dir, e.g. /tmp or the
> worktree}; return the path. State explicitly what you did NOT check. No raw
> file dumps.

---

## 1. Search / locate  (Explore or caveman:cavecrew-investigator, haiku, low)

> Find {what} in {repo/path}. I need this to decide {decision it feeds}.
> Search breadth: {"medium" | "very thorough — multiple naming conventions"}.
> Acceptance: every match listed as `file:line` with a one-line role
> description; say "none found" explicitly if zero; list which directories or
> naming patterns you did NOT search.
> + report contract

## 2. Implementation  (general-purpose, sonnet, medium)

> Implement {change} in {files/module}. Motivation: {why — what breaks or is
> missing without it}. Constraints: {APIs to keep stable, style to match,
> things NOT to touch}.
> Acceptance: {falsifiable checks — e.g. "`pytest {path}` passes; new behavior
> covered by a test that fails without the change; `rg {old-symbol}` → 0 hits"}.
> Run the checks yourself before reporting; paste their output.
> If you hit a design ambiguity, pick the option consistent with {named
> convention/file} and flag it in the report — do not stall.
> + report contract

## 3. Refactor  (general-purpose, sonnet, medium; worktree isolation if parallel)

> Refactor {what} from {current shape} to {target shape}. Behavior must be
> IDENTICAL — no functional changes, no drive-by fixes; if you find a real bug,
> report it, don't fix it.
> Acceptance: {test suite command} passes before AND after with the same
> results; every call site updated (`rg {old-name}` → 0 hits); diff contains
> only the refactor.
> + report contract

## 4. Research  (general-purpose, sonnet, medium-high; web allowed)

> Research {question}. This feeds {decision}. Prioritize {official docs /
> source code / primary sources} over blogs; note the date of each source.
> Acceptance: direct answer up front; each claim carries a source URL or
> file:line; conflicting sources reported as a conflict, not silently merged;
> unknowns listed as unknowns — do not fill gaps by guessing.
> Write the full findings to {path}; return the path + a ≤10-line summary.
> + report contract

## 5. Review / verification  (FRESH general-purpose or caveman:cavecrew-reviewer, sonnet, medium)

Never the agent (or context) that produced the work.

> Review {diff/branch/files} against these acceptance criteria: {paste the
> exact criteria from the original dispatch}. For each criterion answer
> PASS/FAIL with evidence (`file:line`, command output). Then look for: behavior
> changes outside the stated goal, orphaned references to renamed/removed
> things, silent error swallowing at trust boundaries, tests weakened to pass.
> Do not praise; do not restate the diff; findings only, severity-tagged.
> If everything passes, say exactly: "All criteria PASS" + the evidence list.
> + report contract
