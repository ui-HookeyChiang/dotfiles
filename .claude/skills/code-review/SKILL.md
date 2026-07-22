---
name: code-review
description: Comprehensive pull request review using specialized agents. Use when reviewing PRs, performing code review, or when the user mentions "review PR", "code review", or "/review-pr".
argument-hint: "<PR-number> [focus: security|performance|...]"
landing-group: workflow
---

# Pull Request Review Instructions

**Review Aspects (optional):** "$ARGUMENTS"
**IMPORTANT**: Skip `spec/` and `reports/` unless asked.

**CRITICAL**: In GitHub mode — post inline comments only, no overall review report. Each comment must be inline, code-related, and meaningful. In local mode — return structured findings to caller.

## Review Workflow

Run a multi-agent PR review. Each agent focuses on a different quality aspect. Follow these steps:

### Phase 1: Preparation

Run in order:

1. **Determine Review Scope**
   - `git diff --stat origin/main...HEAD` (or `origin/master`) — lines changed
   - Parse `$ARGUMENTS` for user-requested aspects

2. **Launch up to 6 parallel Haiku agents:**
   - Eligibility: PR closed or draft → exit early
   - Find instruction files: CLAUDE.md, AGENTS.md, **/constitution.md, relevant README.md
   - Find reusable types/utilities: type headers, similar structs/classes (paths + summary → pattern-reuse-reviewer)
   - Summarize changes: split files across 1-3 agents by line count; each returns per-file summary

3. CRITICAL (GitHub mode only): If PR lacks description, add one via `gh api repos/{owner}/{repo}/pulls/<num> -X PATCH -f body="..."`.

## Mode Detection

This skill operates in two modes, auto-detected by environment:

| Signal | Mode | Behavior |
|--------|------|----------|
| MCP `mcp__github_inline_comment__create_inline_comment` available OR `gh api` available + PR context | **GitHub mode** | Full flow: find issues → score → filter → post inline comments |
| Neither available (invoked by flow-dev as subagent) | **Local mode** | Find issues → score → filter → return findings |

Local mode skips: Gate A, Gate C, Phase 3.5 Layer A (line validation), Q5 (dedup against posted comments), Phase 4 (thread cleanup). These require GitHub API access that local mode doesn't have.

### Phase 2: Searching for Issues

Determine applicable reviews, then launch up to 6 parallel (Sonnet or Opus) agents. Each independently reviews all changes and returns issues with flagging reasons (CLAUDE.md adherence, bug, historical context, etc.).

**Available Review Agents**:

- **security-auditor** - Find vulnerabilities with concrete exploitation paths (≤2 sentences). Can't confirm reachability → downgrade to MED. Ref: [`security-checklist.md`](references/security-checklist.md).
- **bug-hunter** - Scan for bugs including silent failures. Focus: error handling anti-patterns, boundary conditions, performance traps.
- **code-quality-reviewer** - Project guidelines, maintainability, clarity. Ref: [`code-quality-checklist.md`](references/code-quality-checklist.md) + [`solid-checklist.md`](references/solid-checklist.md) + [`fowler-smell-baseline.md`](references/fowler-smell-baseline.md).
- **pattern-reuse-reviewer** - Verify new code reuses existing types/utilities rather than reinventing. Must READ actual source files. See detailed instructions below. Ref: [`fowler-smell-baseline.md`](references/fowler-smell-baseline.md) (Primitive Obsession, Shotgun Surgery, Duplicated Code).
- **contracts-reviewer** - Type invariants, API changes, data modeling.
- **test-coverage-reviewer** - Test coverage quality and completeness.
- **historical-context-reviewer** - Git blame, history, prior PRs. Flag dead code / deprecated paths via [`deadcode-removal-guideline.md`](../docs/deadcode-removal-guideline.md) P0/P1/P2 framework.
- **spec-reviewer** - Compare diff against originating issue/PRD requirements. Find: (a) requirements the spec asked for that are missing or partial; (b) behaviour in the diff that wasn't asked for (scope creep); (c) requirements that look implemented but where the implementation looks wrong. Locate the originating spec by: commit message issue refs (#123), branch name match in docs/ticket/ or docs/spec/, or user-supplied path.

Default: run **all** applicable agents.

#### Determine Applicable Reviews

Based on Phase 1 summary and complexity:

- **Code/config changes (non-cosmetic)**: bug-hunter, security-auditor
- **Code changes (logic, infra, formatting)**: code-quality-reviewer
- **New types/structs/classes or primitives for domain concepts**: pattern-reuse-reviewer
- **Test files changed**: test-coverage-reviewer
- **Types/API/data modeling changed**: contracts-reviewer
- **High complexity or historical context needed**: historical-context-reviewer
- **Branch/commit references an issue or PRD**: spec-reviewer

#### Launch Review Agents

**Parallel approach**: Launch all simultaneously. Provide: modified file list, PR summary, which PR they review, and guideline files (README.md, CLAUDE.md, constitution.md if present). Results return together.

#### Pattern-Reuse Reviewer — Detailed Instructions

Catches reinvention — new code duplicating existing codebase patterns. Must **read actual source files**, not just the diff. Checklist:

1. **Type reuse**: For every raw primitive used for a domain concept (e.g., `uint16_t` for VLAN ID), search type headers for existing typed wrappers. Flag primitives duplicating existing abstractions.

2. **Structural pattern adherence**: For every new struct/class, find 2-3 similar existing ones and compare:
   - "manager" → methods like existing managers, or passive container?
   - data type → interface match (naming, RAII, accessors)?
   - handler functions → same return/error pattern as existing handlers?

3. **RAII and resource cleanup**: For ad-hoc cleanup code (explicit rollback, manual sequences), check if RAII wrappers exist. Read existing wrappers to confirm pattern.

4. **Utility reuse**: For validation/conversion/formatting logic, check for existing equivalents (`from_json`/`to_json`, validation helpers).

**Critical**: MUST use Read/Grep/Glob to examine source files — cannot assess reuse from diff alone. Spend most effort reading existing code, not the diff.

### Phase 3: Confidence & Impact Scoring + Progressive Filter + Senior Filter (Q1-Q4)

1. For each Phase 2 issue, launch a parallel Haiku agent with the PR, issue description, and CLAUDE.md files. Returns TWO scores:

   **Confidence Score (0-100)** — how likely the issue is real:

   | Score | Meaning |
   |-------|---------|
   | 0 | Not confident at all. False positive that doesn't stand up to light scrutiny, or is a pre-existing issue. |
   | 25 | Somewhat confident. Might be a real issue, but may be a false positive. If stylistic, not explicitly called out in relevant CLAUDE.md. |
   | 50 | Moderately confident. Verified as real issue, but might be a nitpick or not happen often in practice. Not very important relative to the rest of the PR. |
   | 75 | Highly confident. Double checked and verified as very likely a real issue that will be hit in practice. Existing approach in the PR is insufficient. Very important and will directly impact functionality, or directly mentioned in relevant CLAUDE.md. |
   | 100 | Absolutely certain. Double checked and confirmed as a definite issue that will happen frequently in practice. Evidence directly confirms this. |

   **Impact Score (0-100)** - Severity and consequence of the issue if left unfixed:

   | Score | Level | Meaning |
   |-------|-------|---------|
   | 0-20 | Low | Minor code smell or style inconsistency. Does not affect functionality or maintainability significantly. |
   | 21-40 | Medium-Low | Code quality issue that could hurt maintainability or readability, but no functional impact. |
   | 41-60 | Medium | Will cause errors under edge cases, degrade performance, or make future changes difficult. |
   | 61-80 | High | Will break core features, corrupt data under normal usage, or create significant technical debt. |
   | 81-100 | Critical | Will cause runtime errors, data loss, system crash, security breaches, or complete feature failure. |

   For issues flagged due to CLAUDE.md instructions, the agent should double check that the CLAUDE.md actually calls out that issue specifically.

2. **Filter issues using the progressive threshold table below** - Higher impact issues require less confidence to pass:

   | Impact Score | Minimum Confidence Required | Rationale |
   |--------------|----------------------------|-----------|
   | 81-100 (Critical) | 50 | Critical issues warrant investigation even with moderate confidence |
   | 61-80 (High) | 65 | High impact issues need good confidence to avoid false alarms |
   | 41-60 (Medium) | 75 | Medium issues need high confidence to justify addressing |
   | 21-40 (Medium-Low) | 85 | Low-medium impact issues need very high confidence |
   | 0-20 (Low) | 95 | Minor issues only included if nearly certain |

   **Filter out any issues that don't meet the minimum confidence threshold for their impact level.**

   **IMPORTANT: Do NOT post inline comments for:**
   - **Low impact issues (0-20)** - These are minor code smells or style inconsistencies. Even with high confidence, they add noise without meaningful value.
   - **Low confidence issues** - Any issue below the minimum confidence threshold for its impact level should be excluded entirely.

   Focus inline comments on Medium impact (41+) and higher issues that meet confidence thresholds.

3. **Senior Filter Q1-Q4** — Apply to all surviving candidates (both modes). See [`references/senior-engineer-filter.md`](references/senior-engineer-filter.md) for Q1-Q4 definitions, auto-drop list, and dedup formula.

4. Use a Haiku agent to repeat the eligibility check from Phase 1, to make sure that the pull request is still eligible for code review. (In case if there was updates since review started)

---

## Local mode output

When in local mode, return findings as structured output:

```json
{
  "findings": [
    {"file": "path", "line": 42, "severity": "HIGH", "confidence": 75, "impact": 70, "message": "...", "suggestion": "..."}
  ],
  "summary": {"total": 5, "high": 2, "med": 2, "low": 1, "filtered": 8},
  "spec_coverage": {"missing": [], "scope_creep": [], "misimplemented": []}
}
```

The caller (flow-dev) uses this to decide whether to loop (fix cycle) or proceed.

---

## GitHub mode (post inline comments)

When in GitHub mode (MCP or gh API available): follow
**[references/github-mode.md](references/github-mode.md)** for the agent-owned
posting pipeline — Line validation → Q5 (Jaccard dedup) → Noise budget →
Post inline comments.

Gate A (bot dedup), Gate C (lock), and Phase 4 (auto-resolve + dismiss stale)
are **workflow-owned** — the agent does not execute them.

> **Back-compat contract:** Phase 4 emits a "Layer C: resolved N threads" log
> line that caller workflows grep. Do NOT rename.

## Comment Templates

See [`references/github-mode.md`](references/github-mode.md#post-inline-comments) and [`references/inline-comment-rules.md`](references/inline-comment-rules.md#comment-body-templates).


## Notes

- Run build/lint/test commands when available — they surface non-obvious issues
- Use `gh` for GitHub interaction, not web fetch
- Make a todo list first
- Cite and link each bug (link CLAUDE.md references)
- Link code with full SHA + line range: `https://github.com/owner/repo/blob/<sha>/README.md#L13-L17`
- Format: `L[start]-L[end]`, at least 1 line of context
- **Security First**: High/Critical security → automatic blocker
- **Quantify**: numbers, not "some"/"many"/"few"
- **Large PRs (>500 lines)**: focus on architecture and security

Goal: catch bugs and security issues while maintaining velocity. Thorough but pragmatic.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `gh` CLI not authenticated | `gh auth login` |
| PR not found or wrong repo | Verify cwd matches repo; `gh pr view <num>` to confirm |
| PR is draft or already closed | Exits early by design — mark PR ready first |
| Review agents return false positives | Expected for large PRs — scoring filters low-quality findings |
| `gh pr edit --body` fails (Projects Classic) | Use `gh api repos/{owner}/{repo}/pulls/<num> -X PATCH -f body="..."` |
| Review takes too long | Normal for large PRs with 6 parallel agents |
| Agent can't find CLAUDE.md | Ensure at repo root; searches `.claude/`, `.github/`, project root |

**Counterpart:** `coding-guidelines` (write-side); these checklists are the read-side SSOT.

## References

| File | Used by | Contents |
|------|---------|----------|
| [`references/github-mode.md`](references/github-mode.md) | GitHub mode § | Agent-owned pipeline: Line validation, Q5 dedup, Noise budget, Post, Phase 4 resolve commands |
| [`references/inline-comment-rules.md`](references/inline-comment-rules.md) | Phase 3.5 Layer A, Post step | Pre-flight line/hunk/endpoint gates + comment-body templates |
| [`references/senior-engineer-filter.md`](references/senior-engineer-filter.md) | Phase 3 Q1-Q4, GitHub Q5 | 5-question quality filter, auto-drop list, noise budget, dedup API |
| [`references/security-checklist.md`](references/security-checklist.md) | Phase 2 security-auditor | Input/output safety, authN/Z, JWT, secrets, races, crypto |
| [`references/fowler-smell-baseline.md`](references/fowler-smell-baseline.md) | Phase 2 code-quality/pattern-reuse reviewers | Fowler refactoring smells — universal baseline |
| [`../docs/deadcode-removal-guideline.md`](../docs/deadcode-removal-guideline.md) | Phase 2 historical-context-reviewer | P0/P1/P2 dead-code / deprecated-path removal framework |

Evals: [`evals/trigger-eval.json`](evals/trigger-eval.json) (trigger boundaries), [`evals/run-fusion-regression.sh`](evals/run-fusion-regression.sh) / [`evals/fusion-regression.md`](evals/fusion-regression.md) (regression harness).
