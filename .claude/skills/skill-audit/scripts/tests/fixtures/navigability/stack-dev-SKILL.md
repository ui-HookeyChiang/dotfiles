---
name: flow-dev
description: "Use when making any code change — feature development, refactoring, bug fixes, single-file fixes, or multi-file/multi-subsystem work. The default workflow for all code changes in this repo, including small <20-line single-file fixes: it sizes the work, then runs spec, stacked-PR, and independent-review phases. Do NOT use for non-code work like PR review, deploys, builds, benchmarks, or config (use the matching domain skill)."
argument-hint: "<feature-description>"
test-devices: local
landing-group: workflow
---

# Stacked Feature Development

Default workflow for non-trivial code changes. Phase 1 Step 1 explores intent and sizes the work — single-task PR or multiple stacked PRs with worktrees. Exploration requests funnel through brainstorming into tasks; implementation follows the Dev agent → red-replay + code-review loop.

## Routing

Run `router.sh` first. It always returns `recommended_skill == stack-dev`
(all code changes — any size — run the full flow), plus the `flow` and
`jira_capability` fields the phases below consume. No sibling-skill switch and
no banner: there is one workflow for every code change.

If `router.sh` fails (e.g. `jq` missing), proceed with `flow-dev` anyway;
stderr prints the error.

## Overview

```
main <- task-1/branch <- task-2/branch <- task-3/branch
         PR #1              PR #2             PR #3
       (base: main)    (base: task-1)    (base: task-2)
```

Each task runs a **Dev agent** plus two independent fan-in checks:
1. **Dev agent** — implement + self-test loop in an isolated worktree (no cross-agent context transfer)
2. **PR** — push and create stacked PR
3. **red-replay agent** — independent (non-author) re-run of THIS task's red→green transition in a scratch checkout + compile/lint/type-check (runs in background, parallel with code-review)
4. **code-review step** — independent diff review delegating to the `code-review` skill (parallel with red-replay)
5. **Fix** — address red-replay / review feedback, resolve conversations, loop if needed

After all tasks: **integration test** on the final worktree validates the assembled feature.

> **Ubiquiti repos:** For debbox, debfactory, and source package development, see `ubiquiti-flow` which adds CI polling, multi-repo coordination, and device deployment on top of this workflow.

## Workflow

### Pre-flight: route the task with router.sh

Before reading the rest of this document, run:

```bash
bash ~/.claude/skills/flow-dev/scripts/router.sh "<feature description>"
```

Returns a versioned JSON blob (v4 schema, 6 keys: `version` / `flow` /
`recommended_skill` / `rationale` / `default_branch` / `jira_capability`).

`recommended_skill` is always `flow-dev` (see `## Routing` above). All code
changes — any size — run the full phase narrative below; there is no size-based
phase skipping.

Other fields (`flow`, `default_branch`, `jira_capability`) drive Phase 4 Jira
dispatch — see the relevant phases below. `rationale` is cheap diff-size
telemetry (`diff: N files, M lines`). The router never fails; safe defaults
fall through on any error. Override hook: `SD_JIRA_CAPABILITY`.

## Phase 0 — Preflight (HARD GATE)

Before any brainstorming, agent dispatch, or worktree mutation, run:

```bash
bash ~/.claude/skills/flow-dev/scripts/phase-0-preflight.sh \
  "${SD_SPEC_PATH:-}" "${PWD}" ${SD_AUTONOMOUS:+--autonomous}
```

The script runs seven checks in order. **Failure of any check is a hard STOP.**

1. **flock(1)** advisory mutex at `<worktree>/.git/flow-dev.flock` —
   prevents two concurrent `flow-dev` invocations in the same worktree.
2. **Worktree detection** — `git rev-parse --git-common-dir` must differ
   from `--git-dir`. The main checkout, a bare repo, and a submodule's own
   `.git`-file directory all fail this check.
3. **Prereqs** — `gh auth status` ok (with a 5-minute per-worktree
   cache at `<worktree>/.git/.gh-auth-cache` so transient API flakes
   don't STOP `pua-loop`), `origin` remote set.
4. **Spec lifecycle drift (Check G)** — the lifecycle-drift check runs
   immediately after the prereqs gate. There is no spec lifecycle, so
   this check always passes (effectively a no-op).
   It remains in the sequence as the earliest of three audit defenses
   (Phase 0 here → pre-merge sanity #437 → L5 detector in #434). Test
   fixtures self-skip via `SD_PHASE0_TEST_MODE=1`.
5. **Lock validity** — if `<worktree>/.flow-dev-lock` exists, parse it
   and verify `spec_path` resolves to an existing file (the healthy spec
   lives at `docs/superpowers/specs/`).
   Corrupt JSON or spec missing entirely → see table below.
6. **Brainstorming gate decision** — never scans `docs/spec/proposed/` or
   `docs/superpowers/specs/`. Decision is based only on `SD_SPEC_PATH`
   and the lock file. The script computes a `mode` field in its stdout
   JSON; Phase 1 Step 1.2 branches on this value:

   | Input state | `mode` value | Phase 1 Step 1.2 action |
   |---|---|---|
   | `SD_SPEC_PATH` set OR lock exists | `skip-brainstorming` | use that spec, do not re-resolve |
   | otherwise (neither spec nor lock) | `invoke-brainstorming` | invoke `Skill brainstorming` |
7. **Branch consistency** — if a lock exists, `git symbolic-ref --short
   HEAD` must equal `lock.feature_branch`. Detached HEAD is a hard
   `[STOP-DANGER]` (non-overridable by design). Branch mismatch is a
   `[STOP-DANGER]` whose first line documents the override env var.
   Override: `SD_FORCE_BRANCH=1` (single-shot; not persisted into the
   lock; audit-logged under `--autonomous` as `force-branch`).
   `write-lock.sh` re-checks under its own flock (TOCTOU defense) using
   the `current_branch_at_phase_0` field Phase 0 embeds in the stdout
   JSON when a lock is present.

See **[references/phase-0-preflight-protocol.md](references/phase-0-preflight-protocol.md)** for STOP-tier exit codes, `.flow-dev-lock` schema, and the stdout JSON shape (consumed by Phase 2 Step 2 `write-lock.sh`).
### Phase 1: Task Decomposition

The main agent orchestrates — it does NOT read the codebase directly. Delegate research, then make decomposition decisions based on the findings.

#### Step 1: Spec gate

The spec lives at `docs/superpowers/specs/<date>-<slug>-design.md`,
directly consumed from the `superpowers:brainstorming` output. There is
no spec lifecycle — no promote, no `proposed/active/done/` directories.

**Step 1.1** — Resolve spec location via `resolve-spec.sh`:

```bash
bash ~/.claude/skills/flow-dev/scripts/resolve-spec.sh <slug>
```

Returns JSON with `spec_path`, `branch_prefix`, `slug`, `date`.
`spec_path` is populated purely by the slug glob (see Step 1.3 for
branch semantics). Override hook: `SD_SPEC_PATH=<value>` (bypasses spec
resolution entirely).

**Step 1.2** — Brainstorming gate: branch on the `mode` value Phase 0 step 6 computed (see the input-state → mode table above; the "no disk scan" guarantee is enforced there, not re-checked here).

- `mode == "invoke-brainstorming"` → invoke `Skill brainstorming` per spec contract; the brainstorming output lands at `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md` and stays there unmoved (no lifecycle, no adoption step).
- `mode == "skip-brainstorming"` → use the `spec_path` Phase 0 returned (resolved from `SD_SPEC_PATH` or from an existing lock); do NOT re-resolve from disk. Read it, summarize key decisions, present to user for review. Proceed to spec-lint → spec-advisory → approval gate below.

**Spec review gate** — before proceeding past the spec, run spec-lint → spec-advisory (auto-fire advisory, which writes a mandatory agent-completion trace) → approval gate (user approve). The trace is re-asserted at the Phase 2 completion gate, so a skipped spec-advisory cannot silently advance. Single-writer principle: the user is always the writer, the advisor has zero write authority.

**spec-lint** — deterministic structural lint (soft warn):

```bash
bash ~/.claude/skills/flow-dev/scripts/spec-lint.sh "$SPEC_PATH" || true
```

`|| true` is intentional — exit 1 prints schema warnings (missing
frontmatter, missing success-criteria section, etc.) but does NOT
block the flow. The user retains override.

**spec-advisory** — auto-fire advisory (always 3 agents, no word-count tiering). Runs before the approval gate. The 3-agent advisor has zero write authority — prints findings only; the **main agent** drives the spec-advisory loop (Phase 1 default — see *spec-advisory Loop mode*) and is sole writer. Auto-dispatch (not opt-in): opt-in advisor risks "exists on paper only". After agents return, main agent writes an `agents=3` trace (`gate=spec-advisory` → [SSOT](../_shared/references/trace-grammar-contract.md)); Phase 2 gate refuses without it — absent-trace is detectable.

1. **Phase 1 spec-advisory enters the loop by default** (see *spec-advisory Loop mode* below). Set `N=1`; each iteration runs steps 2-6 below, then the loop's termination decision (see *spec-advisory Loop mode* § termination, below). Invoke `bash ~/.claude/skills/flow-dev/scripts/spec-advisory.sh --mode=full-loop --iteration=N "$SPEC_PATH"` and read the emitted envelope. (The script only routes/echoes — it does NOT itself run the agents; you dispatch them in step 3 and you write the completion trace afterward. The script-call alone is not the trace.) A clean spec returns `next_action == done` at iteration 1 and terminates immediately. The single-pass `--mode=full` is the loop's exit-2 fallback (below).
2. Print the observability line BEFORE dispatching: `advisor: mode=deep, words=N, agents=3, voters=3/3`. `mode=deep` and `agents=3` are constant under the always-three rule; `words=N` is the live `wc -w` count.
3. Dispatch — **always 3 agents in parallel** regardless of word count (1 Explore blind-spot + 1 general-purpose consistency + 1 general-purpose acceptance-sharpness) using `### deep prompt` from `references/spec-advisory-prompt.md`. Join barrier: wait for all three before printing findings; one agent's failure does NOT block the others; parallel agents share no mutable state, results labeled `(partial)` if fewer than three returned.
4. Per-agent wall-clock timeout 120s. If an agent has not returned within 15s, print a heartbeat line `advisor: agent <id> still running (<elapsed>s)`. On timeout: print `advisor: agent <id> failed (timeout 120s), proceeding without findings` and continue to the approval gate with whatever findings were collected.
5. On any other agent failure (API error, etc): print `advisor: agent <id> failed (<reason>), proceeding without findings`.
6. Print findings (severity HIGH / MED / LOW as defined in `references/spec-advisory-prompt.md` — the script is a router, not a judge).

Bypass: `SD_SKIP_ADVISORY=1` forces `mode=skip` without reading the spec (preserves V2's escape hatch). This is the **only** path that produces `mode=skip` under the always-three rule — no word-count threshold bypasses agent dispatch.

**Trace contracts (grammar moved to SSOT).** The three completion traces below
(`gate=spec-advisory`, `gate=e2e-pass:stack-dev`, `gate=tdd:red`/`gate=tdd:green`) share
one log + grammar with `skill-writer` — the byte-shape lives in
`_shared/lib/sh/sandwich-trace.sh`, its prose contract in
[`_shared/references/trace-grammar-contract.md`](../_shared/references/trace-grammar-contract.md)
(field order, load-bearing trailing spaces, `spec_hash` provenance, per-`test=`
scoping, `agents=0`/`run=0` skip semantics, write-after-the-barrier rule). Only the
imperative fire-sites are inline here; grammar + exact bash live in the SSOT.

- **`gate=spec-advisory` (MANDATORY,** per `docs/spec/archive/2026-06-01-spec-advisor-l1-5-enforcement.md`): **AFTER** all three advisor agents return (or time out) in steps 3-5 above — after the join barrier, never before dispatch — you (main agent) write the `gate=spec-advisory` trace via `write_spec_advisory_trace` per the SSOT. Under `SD_SKIP_ADVISORY=1` still write a line, as `agents=0 verdicts=skip` (present-and-auditable, still fails the Phase 2 `agents=3` assert). This trace is the sole evidence the Phase 2 entry assert reads.
- **`gate=e2e-pass:stack-dev` (MANDATORY,** per `docs/spec/archive/2026-06-01-dogfood-residency-enforcement.md`): when a changeset touches the three parallel-stacks scripts (`merge-train.sh`, `parallel-layers.sh`, `squash-merge.sh` — detect with `scripts/detect-dogfood-consumer.sh <file>`), **AFTER** `bash scripts/tests/dogfood-smoke.sh` returns — never before — write the `gate=e2e-pass:stack-dev` trace via `write_gate_trace` per the SSOT. It is a residency gate at the Phase 3 → Phase 4 boundary (see Phase 3 § *dogfood completion gate*).
- **`gate=tdd:red` / `gate=tdd:green` (MANDATORY,** per `docs/spec/archive/2026-06-02-tdd-residency-enforcement.md`): the Dev phase invokes `superpowers:test-driven-development`. **The Dev agent** (not the main agent) writes these via `write_tdd_trace` per the SSOT — one line after the upstream **Verify RED** point, one after **Verify GREEN** (full contract: new test passes AND whole suite green AND output pristine). The upstream skill is invoked verbatim and knows nothing about the trace — zero upstream change.


**spec-advisory Loop mode (`--mode=full-loop`) — the Phase 1 default** — an auto-fix loop; the **main agent** is sole writer (script only routes/echoes). Clean spec terminates at iteration 1; dirty spec has main agent auto-apply `findings[].suggestion` and re-run. `--mode=full` survives only as the `script exit 2` fallback. Set `N=1` and repeat; **terminate when ANY of:**

- envelope `next_action == done` (advisor reports HIGH/MED clean), OR
- `findings_summary` H==0 AND M==0 (objective clean signal), OR
- `cycle == detected` (livelock — `spec_hash` repeats with `next_action == edit_spec`), OR
- `N == max_iter` (cap, default 5).

Snapshot bookkeeping (`/tmp/loop-orig.$$` + history), the per-iteration
main-agent contract, loop knobs (`SD_ADVISORY_MAX_ITER`), the cycle-override
semantics, and the exit-2 fallback ladder live in
**[references/loop-protocol.md § Loop-mode mechanics](references/loop-protocol.md#loop-mode-mechanics)**.
The exit-2 ladder is terminal — if the `--mode=full` fallback ITSELF exits 2,
STOP and surface stderr (**no further fallback**).

**spec-advisory sandwich (sidecar-observed prose-guidelines wrap)** — on every
spec-bearing path the **pre pass runs unconditionally** before the advisor
(capturing `spec_hash` as `H_pre`) and the **post pass is hash-gated**:
compute `H_now` after the advisor — if `H_now == H_pre` SKIP post (record
`reason=spec-unchanged-since-pre`); if `H_now != H_pre` re-run prose-guidelines.
Both passes are advisory (WARN-and-proceed); the main agent writes a sidecar
record at each boundary before invoking the Skill. Escape hatches:

- `SD_SKIP_ADVISORY=1` — skip the entire spec-advisory layer (including sandwich). (Env var name kept; it bypasses the spec-advisory layer.)
- `SD_SKIP_SANDWICH=1` — skip prose-guidelines pre + post, keep the advisor
  (sidecar still records `outcome=skipped, reason=SD_SKIP_SANDWICH=1`).

The full pre/post hash-gate decision tree, the imperative sidecar contract,
write-failure fallback, and the quorum-accept telemetry rule live in
**[references/loop-protocol.md § Sandwich cadence](references/loop-protocol.md#sandwich-cadence)**.

**approval gate** — user pause + checklist + two-key prompt (no countdown, no auto-approve):
- Print spec path, `wc -w` word count, and the spec-lint result (PASS / WARN with reasons).
- Print the 5-item checklist from `references/spec-review-checklist.md` (success criteria measurable / test plan runnable / task contract / scope creep / advisory points).
- **approval gate prompt** — two keys (V6 removed the `[a]` opt-in key; advisor already ran at spec-advisory):
  - `[y]es` → approve the spec (proceed to Step 1.3).
  - `[n]o` → abort, leave the spec untouched.
- Wait for the user. **No other key triggers any action.** This preserves single-writer ownership — there is no default-approve and no AFK timeout.

**Step 1.3** — Final spec path: read the JSON from Step 1.1's
`resolve-spec.sh` output (no lifecycle, no promote — see Step 1).

Use the returned `spec_path` and `branch_prefix` in subsequent steps
(TaskCreate, HANDOFF.md, branch naming).

#### Plan adoption (optional)

When the active spec was produced by the `superpowers:brainstorming` →
`superpowers:writing-plans` chain, a TDD-granularity plan may already exist
at `docs/superpowers/plans/<date>-<slug>.md`. Plan adoption detects it, parses
it via the read-only PR1 parser, and offers the user an adopt / discard /
edit decision before Step 2 launches the Explore agent.

**Detection** — read frontmatter from Step 1.1's `spec_path`. If a
`source_plan: <path>` field is present, use it verbatim; frontmatter
wins over fuzzy-match. Otherwise fall back to
`docs/superpowers/plans/<date>-<slug>.md` built from Step 1.1's fields.

**No-op contract** (verbatim from spec §Architecture) — when `source_plan`
frontmatter field is absent AND no fuzzy-match plan exists at
`docs/superpowers/plans/<date>-<slug>.md`, plan adoption short-circuits before
any prompt or script invocation. Zero stdout. Zero TaskCreate mutation.
Behavior is byte-identical to current Phase 1.3 → 2 flow. Regression guard:
`flow-dev/scripts/tests/plan-adoption-noop/test.sh`.

**Invocation** — when a plan path resolves, invoke the parser and consume
its JSON (`tasks[]`, `suggested_merge_groups[]`, `warnings[]`, `plan_mtime`):

```bash
bash ~/.claude/skills/flow-dev/scripts/adopt-superpowers-plan.sh <plan-path>
```

| Parser exit | Meaning | Action |
|---|---|---|
| 0 | Parse OK; JSON on stdout | Present 3-option prompt below |
| 1 | Malformed plan; stderr names offending Task | Print stderr; prompt `[d]iscard / [e]dit / [a]bort` |
| 2 | Plan file vanished (race) | STOP with `[STOP-SAFE]` |

**Prompt** — surface detected task count, `plan_mtime`,
`suggested_merge_groups` (with `estimated_lines` + any group > 500-line
warnings), and exactly three options:

- `[a]dopt` — seed Step 4's TaskCreate from `suggested_merge_groups` (one
  group → one task). Step 4 still appends the mandatory integration-test
  and pre-merge-cleanup tasks per single-writer rule.
- `[d]iscard` — skip the plan, fall through to Step 2 (Explore agent).
- `[e]dit <plan-path>` — open the plan, re-invoke parser on save, loop.

Wait for the user; no default-approve (mirrors the approval gate in Step 1.2 — parser
SUGGESTS, user DECIDES). Behavior under upstream `writing-plans` format
drift follows the §Operational commitments decision tree in the spec.

**Parallel-mode confirmation (Amendment A8, v2.1 wire-up).** After
`[a]dopt`, dispatch on whether the parser's `parallel_layers` has any
multi-group layer. Single-group plans skip the prompt entirely.

```bash
PARALLEL_LAYERS=$(echo "$PARSER_JSON" | jq -c '.parallel_layers')
HAS_PARALLEL=$(echo "$PARSER_JSON" | jq '.parallel_layers | any(.[]; length >= 2)')

if [[ "$HAS_PARALLEL" != "true" || "${SD_PARALLEL_MODE:-}" == "y" ]]; then
  export SD_PARALLEL_LAYERS="$PARALLEL_LAYERS"
elif [[ ! -t 0 ]] || [[ "${SD_AUTONOMOUS:-0}" == "1" ]]; then
  export SD_PARALLEL_LAYERS=$(pl_flatten "$PARALLEL_LAYERS")
  echo "non-interactive ([s]equential fallback): $(pl_group_count "$PARALLEL_LAYERS") groups across $(pl_layer_count "$SD_PARALLEL_LAYERS") layers"
else
  echo "Detected $(pl_layer_count "$PARALLEL_LAYERS") parallel layers: $(pl_layer_summary "$PARALLEL_LAYERS")"
  read -r -p "Proceed with parallel stacks? [y]es / [s]equential fallback / [n]o > " choice
  case "$choice" in
    y) export SD_PARALLEL_LAYERS="$PARALLEL_LAYERS" ;;
    s) export SD_PARALLEL_LAYERS=$(pl_flatten "$PARALLEL_LAYERS") ;;
    n) echo "aborted by user"; exit 0 ;;
    *) echo "unknown choice '$choice' — aborting"; exit 1 ;;
  esac
fi
```

`SD_PARALLEL_LAYERS` then flows into `write-lock.sh` (Phase 2 Step 2)
as the lock's `parallel_layers` field. Branch rationale +
non-interactive default choice: `references/parallel-stacks.md` § *Plan adoption
— parallel-mode confirmation decision precedence*.

#### Step 2: Launch research agent

```
Launch 1 agent (subagent_type: Explore):
  Analyze this feature request: <description>
  Design spec: <path or summary of key decisions from Step 1>
  Working directory: <path>

  1. Explore the codebase — find relevant files, interfaces, patterns
  2. Identify what needs to change and where
  3. List all affected files, interfaces, and dependencies
  4. Return findings — do NOT propose a task split or make any changes
  5. If any `*/SKILL.md` files will be modified, note which skills and their `test-devices` frontmatter values — these determine Phase 3 skill flow test scope
```

#### Step 3: Review and finalize task list

The main agent presents findings to the user with tradeoffs and a recommendation. The user picks, refines, or asks questions.

> **Pause here.** Do not invoke TaskCreate until the user confirms the chosen task split. The decomposition decision locks branch names and dependencies — recovering from a wrong split mid-Phase-2 is expensive.

**If clarification reveals new requirements or unknowns**, loop back to Step 2 for additional research before finalizing (or back to Step 1 if the spec itself needs revision).

Then finalize:
- Ensure each task is independently valid and <500 lines
- Finalize test plans — concrete, runnable verification steps

**Create a task list** using TaskCreate for each sub-task with clear acceptance criteria.

**Each task must include a test plan** — concrete, runnable verification steps. Examples:
- `lua script.lua --help` exits 0
- `make test` passes
- `diff <(cmd_old input) <(cmd_new input)` produces no diff
- `luac -p file.lua` — no syntax errors

Test plans are executed in Step 4 before creating the PR. Vague plans like "syntax check passes" are acceptable for intermediate tasks, but the final task should have integration validation.

**Write the integration test plan** — define cross-task acceptance criteria upfront, before any dev work starts. This locks in "what does done look like?" so Dev agents have a concrete target and Phase 3 just executes the plan instead of inventing tests after the fact.

The integration test plan should be created as a dedicated TaskCreate entry (see Step 4 for required fields) — a task that is blocked by all dev tasks. Actual test *code* is written in Phase 3 once interfaces exist, but the test *specs* are defined here.

**Rules for splitting:**
- Each task must compile/pass tests independently
- Later tasks may depend on earlier ones, but each PR diff should be self-contained
- Prefer: types/interfaces first, then implementation, then integration, then tests
- If a task would exceed ~500 changed lines, split it further

#### Step 4: Record metadata and create dependency tasks

After creating tasks with TaskCreate, store feature metadata for crash recovery:

```
# Store feature metadata as task metadata on the first task
# spec_path comes from `resolve-spec.sh` (Step 1.1)
TaskUpdate({ taskId: "1", metadata: {
  feature: "<short description>",
  spec: "<spec_path-from-resolve-spec>",
  branch_prefix: "${FEATURE_PREFIX}",
  worktree_ns: "${WORKTREE_NS}",
  default_branch: "${DEFAULT_BRANCH}"
}})
```

Create these additional tasks with dependencies:
- **Integration test task** — `TaskCreate` with description containing the integration test plan. Set `addBlockedBy` to all dev task IDs.
- **Pre-merge task** — "Pre-merge cleanup" (worktree removal, Jira, pre-merge sanity). Set `addBlockedBy` to integration test task ID. `TODO.md` is human-curated and no longer pre-merge bound — see Phase 4.

Example task structure for a 3-task feature:
```
Task 1: "Implement types/interfaces"        (no blockers)
Task 2: "Implement core logic"              (blockedBy: [1])
Task 3: "Add integration + tests"           (blockedBy: [2])
Task 4: "Integration tests (Phase 3)"       (blockedBy: [1,2,3])
Task 5: "Pre-merge cleanup"                 (blockedBy: [4])
```

**Parallel-mode `blockedBy` rule (Amendment A4).** With multi-group
layers, each task's `blockedBy` spans **all** groups in the prior layer
(wider than the git `BASE_BRANCH`). Worked example +
runtime-gating rationale: `references/parallel-stacks.md` § *Phase 2 —
A4 blockedBy full example*.

The integration test plan in Task 4's description should specify:
- **Cross-task flows** — full user-facing scenarios that span multiple tasks
- **Cross-task contracts** — expected interfaces between components introduced in different tasks
- **Edge cases** — boundary conditions that only emerge when all pieces are combined
- **Comparison against reference** — diff against the old implementation if this is a rewrite
- **Concrete commands** — runnable verification steps (not vague "verify it works")

### Phase 2: Per-Task Dev Loop

> **Main agent stays in `$PROJECT_ROOT`.** All worktree operations use `(cd "$DIR" && ...)` subshell or `git -C "$DIR" ...`. Never persist cwd inside a worktree — Phase 4 `git worktree remove` will fail if the main agent's cwd is inside the worktree being removed.

**spec-advisory completion gate (Phase 1 → Phase 2 boundary assert).** Before any
Phase 2 work — before Step 1 — assert that the 3-agent spec-advisory
actually ran for this spec. `$SPEC_HASH` is the same `spec_hash` used at
the spec-advisory trace-write and the sandwich sidecar:

```bash
# Shared trace lib (_shared/lib/sh/sandwich-trace.sh). assert_spec_advisory_trace subsumes
# the `agents=3 ` trailing-space grep + `tail -1` + the absent-trace [STOP-SAFE];
# it `return`s 1 on a missing trace (sourced lib never `exit`s) and prints the
# "advisor: spec-advisory completion verified (...)" line on success.
source _shared/lib/sh/sandwich-trace.sh
assert_spec_advisory_trace "$SPEC_HASH" ".git/flow-dev-sandwich.log" \
  || echo "  -> go back to Phase 1 spec-advisory, dispatch the 3 agents, write the trace, then re-enter Phase 2."
```

- The trailing space in `agents=3 ` excludes `agents=0` skip traces and any `agents=30`-style prefix collision.
- `tail -1` selects the most recent trace, so a re-run supersedes an earlier skip/stale line.
- This assert is itself main-agent-run; it is a self-check, not a hook. Its guarantee ceiling is documented in the spec § *Residual risk* — it converts "did spec-advisory run?" from a memory question into one with an objective log-backed answer, but a main agent that fabricates the trace or skips this grep still defeats it. That is the accepted ceiling (a tamper-proof guarantee needs hook infra, declined).

Each task runs a **Dev agent** (implement + self-test loop), then two independent fan-in checks: a **red-replay agent** (independent re-run of this task's red→green transition + compile/lint/type-check) and a **code-review step** (independent diff review). Context is passed via `HANDOFF.md` files in each worktree, not in prompt text.

#### Step 1: Detect defaults (once, before first task)

```bash
# Set FEATURE_PREFIX from the feature description (kebab-case, short),
# then derive DEFAULT_BRANCH and WORKTREE_NS via detect-defaults.sh.
FEATURE_PREFIX="feat/short-feature-name"
eval "$(bash ~/.claude/skills/flow-dev/scripts/detect-defaults.sh "$FEATURE_PREFIX")"
# Now $DEFAULT_BRANCH, $FEATURE_PREFIX, $WORKTREE_NS are exported.
# Override hooks: SD_DEFAULT_BRANCH, SD_WORKTREE_NS.
```

#### Step 2: Create worktree + HANDOFF.md

**BASE_BRANCH has two modes** (switched by `parallel_layers`): linear
(N-1 chain) vs. parallel (lexicographically-first group of prior layer
as base; same-layer groups share a base, Jaccard < 0.5). Rationale +
Phase 3 implications: `references/parallel-stacks.md` § *Phase 2 —
BASE_BRANCH dual-mode rationale*.

```bash
# Dual-mode dispatch on .flow-dev-lock.parallel_layers.
. "${HOME}/.claude/skill-dev/flow-dev/scripts/lib/parallel-layers.sh"

LOCK_LAYERS=$(jq -c '.parallel_layers // null' .flow-dev-lock 2>/dev/null || echo null)
if [[ "$LOCK_LAYERS" == "null" ]]; then
  # Linear fallback (Amendment A2: v1 lock compat).
  [ "$N" -eq 1 ] && BASE_BRANCH="$DEFAULT_BRANCH" || BASE_BRANCH="${FEATURE_PREFIX}/task-$((N-1))"
  TASK_BRANCH="${FEATURE_PREFIX}/task-${N}"
else
  # Parallel mode. GROUP_ID via $SD_GROUP_ID (default "PR-${N}").
  if [[ "$LOCK_LAYERS" == "[]" ]]; then
    echo "[STOP-SAFE] .flow-dev-lock.parallel_layers is empty array — lock corruption or parser bug." >&2
    exit 1
  fi
  GROUP_ID="${SD_GROUP_ID:-PR-${N}}"
  if ! LAYER=$(pl_layer_of "$LOCK_LAYERS" "$GROUP_ID" 2>&1); then
    echo "[STOP-SAFE] GROUP_ID '$GROUP_ID' not found in parallel_layers. Export SD_GROUP_ID for non-numeric IDs." >&2
    exit 1
  fi
  if [[ "$LAYER" == "1" ]]; then
    BASE_BRANCH="$DEFAULT_BRANCH"
  else
    BASE_BRANCH="${FEATURE_PREFIX}/task-$(pl_first_in_layer "$LOCK_LAYERS" "$((LAYER - 1))")"
  fi
  TASK_BRANCH="${FEATURE_PREFIX}/task-${GROUP_ID}"
fi

git fetch origin
WORKTREE_DIR=".worktrees/${WORKTREE_NS}/task-${N}"
mkdir -p ".worktrees/${WORKTREE_NS}"

# Clean up stale state from previous attempts
git worktree prune
git branch -D "$TASK_BRANCH" 2>/dev/null || true
rm -rf "$WORKTREE_DIR" 2>/dev/null || true

# Create worktree inside .worktrees/ (gitignored) to keep worktrees discoverable
git worktree add "$WORKTREE_DIR" -b "$TASK_BRANCH" "origin/$BASE_BRANCH" 2>/dev/null \
  || git worktree add "$WORKTREE_DIR" -b "$TASK_BRANCH" "$BASE_BRANCH"

# Hand off THIS feature's untracked spec draft from the main checkout into
# the new worktree (copy → verify byte-identical → remove source → git add).
# Selection is slug-scoped: only the draft whose filename ends in "$slug"
# (docs/spec/proposed/*-<slug>.md or docs/superpowers/specs/*-<slug>-design.md)
# is handed off, so concurrent worktrees don't sweep each other's drafts.
# No-op when there are no untracked specs at all.
bash ~/.claude/skills/flow-dev/scripts/spec-handoff.sh "$WORKTREE_DIR" "$slug"
```

On `[STOP-SAFE]` from `spec-handoff.sh`, fix the issue and re-run. Two STOP-SAFE cases: (a) a spec failed `diff -q` verification (disk full, permission denied, partial write); (b) untracked drafts exist in the main checkout but none match `"$slug"` — cross-contamination signature (another line's draft present, or this draft mis-named). Fix the slug/filename or hand off manually. The script leaves sources intact on failure; do not bypass.

No promote commit lands in task-1's worktree (no lifecycle — see Step 1).

**Write `HANDOFF.md`** in the worktree root — single source of context for the Dev agent, the red-replay agent, and the code-review step. Template: **[references/handoff-md-template.md](references/handoff-md-template.md)**.

**Update task status:**
```
TaskUpdate({ taskId: "<N>", status: "in_progress" })
```

#### Step 3: Dev agent (implement + self-test)

Launch a single agent that implements the task AND tests it. The agent loops internally until tests pass. This step is called twice: first for initial implementation, then again if the red-replay agent or code-review step (Step 5) finds issues (include those findings so the agent knows what to fix).

**Subagent type selection** — pick by judgement on cross-cutting risk:

| Task | `subagent_type` | Why |
|---|---|---|
| Any cross-cutting / multi-file change | `pua:senior-engineer-p7` *(if PUA plugin installed)* | P7's "方案 + 影響分析 + 三問自審查" gives a documented impact trace, surfaces missed consumers (`rg` consumer-discovery), and produces a `[P7-COMPLETION]` block. Worth the extra ceremony when reviewer fatigue or cross-file inconsistency is a real risk. |
| (PUA not installed, or you explicitly want vanilla) | `general-purpose` | Falls back to the prompt below; no self-review structure. |

The agent prompt below works for both `general-purpose` and `pua:senior-engineer-p7` — P7 layers its self-review protocol on top of the same instructions.

```
Launch 1 agent (subagent_type: <picked from table above>):
  Read HANDOFF.md in .worktrees/${WORKTREE_NS}/task-${N}/

  You are a Dev agent. Implement the task, then test it yourself.

  # Include ONLY when re-running after red-replay / code-review feedback:
  These issues were found — fix them: <paste red-replay log and/or review findings>

  Phase 1 — Implement (or fix):
  - Read HANDOFF.md for what to do, which files to modify, and relevant context
  - Keep changes focused on this task only
  - MUST invoke `Skill coding-guidelines` before writing any code — apply the four guardrails (think before coding, simplicity first, surgical changes, goal-driven execution)
  - MUST invoke `Skill superpowers:test-driven-development` before writing any code
  - Follow Red-Green-Refactor: write failing test, verify it fails, write minimal code, verify pass
  - TDD red/green trace (MANDATORY when the changeset touches testable code — `bash ~/.claude/skills/flow-dev/scripts/detect-tdd-required.sh <changed-files...>` prints `tdd-required`): immediately AFTER the upstream skill's **Verify RED** point confirms the test fails as expected, append a `gate=tdd:red` line; AFTER its **Verify GREEN** point confirms the FULL contract (the new test passes AND the whole suite still passes AND output is pristine), append a `gate=tdd:green` line. Use `git rev-parse --git-common-dir` (your worktree `.git` is a file) and the `$SPEC_HASH` from HANDOFF.md (do NOT re-compute it). Grammar + exact bash: the `gate=tdd:red`/`gate=tdd:green` bullet under Phase 1 *Trace contracts* → [SSOT](../_shared/references/trace-grammar-contract.md). Per-`test=` paths if you drive more than one test file.
  - Stage and commit with conventional commit messages

  Phase 2 — Self-test:
  - Run the test plan from HANDOFF.md
  - Run the project's test suite (auto-detect: make test, npm test, pytest, etc.)
  - If anything fails, fix and re-test. Loop until all pass.

  Phase 3 — Commit:
  - Stage all changes and commit with conventional commit messages
  - If `git status` shows a pre-staged `.md` under `docs/spec/archive/` or `docs/superpowers/specs/`, include it in your first commit alongside code changes
  - Do NOT stage or commit HANDOFF.md
  - Do NOT push or create PRs

  Report: what you changed, test results, and any decisions you made.
```

#### TDD completion gate (Dev → PR boundary assert)

When the Dev task's changeset touches testable code (run `bash scripts/detect-tdd-required.sh $(git -C "$WORKTREE_DIR" diff --name-only "origin/$BASE_BRANCH"...HEAD)` → `tdd-required`), assert — before push / PR creation — that a red→green TDD cycle was actually traced for this spec, in the right order, for every test the Dev agent drove. A `tdd-skip` changeset (all prose/`*.md`) does NOT fire this gate (no failing test possible; verify-skill / dogfood / spec-advisory cover prose). The per-`test=` order check is the TDD-specific addition over dogfood's presence-only check. `$SPEC_HASH` is the same hash used at the spec-advisory / dogfood trace:

```bash
# changed-file list MUST come from the worktree's COMMITTED diff vs its base — the
# main agent stays in $PROJECT_ROOT (see Phase 2 Step 2), so a bare `git diff` here
# reads the (clean) main checkout and the gate silently skips. Scope to the worktree.
if [ "$(bash scripts/detect-tdd-required.sh $(git -C "$WORKTREE_DIR" diff --name-only "origin/$BASE_BRANCH"...HEAD))" = "tdd-required" ]; then
  # Shared trace lib (_shared/lib/sh/sandwich-trace.sh). assert_tdd_order reproduces
  # the exact per-`test=` loop + [STOP-SAFE] messages: for EVERY distinct test=
  # value traced for this spec_hash it asserts red present + green present +
  # red_ts < green_ts (per-test scoped — NOT a global tail -1, so a multi-test task
  # can't false-pass by comparing test-B's green against test-A's red). It is the
  # single implementation scripts/verify-tdd.sh delegates to. Sourced lib `return`s
  # 1 on any violation; the `|| exit 1` keeps this a hard STOP gate.
  source _shared/lib/sh/sandwich-trace.sh
  assert_tdd_order "$SPEC_HASH" "$(git rev-parse --git-common-dir)/flow-dev-sandwich.log" || exit 1
fi
```

Testable form of `scripts/verify-tdd.sh` (`<log> <spec_hash>`, exercised by `scripts/tests/tdd-trace/`). Self-check ceiling is the same as the spec-advisory gate (Phase 2 entry assert) — a Dev agent writing code first can backfill BOTH traces with a fabricated earlier `red` timestamp; red<green is mechanical evidence, not proof. The red-replay agent (Step 5) re-runs THIS task's tests from scratch on every task, catching green traces over tests that never actually flipped red→green — it, plus CI, remains the ceiling.

#### Step 4: Push and create PR

The main agent runs these commands directly (simple git — no subagent needed). No promote-to-`done/` step before push (no lifecycle — see Step 1).

```bash
(cd "$WORKTREE_DIR" && \
  git push origin HEAD:refs/heads/$TASK_BRANCH)
# WORKTREE_DIR = .worktrees/${WORKTREE_NS}/task-${N}
```

Then create the PR — body template at **[references/pr-body-template.md](references/pr-body-template.md)**.

**Update task metadata with PR number:**
```
TaskUpdate({ taskId: "<N>", metadata: { pr: "<PR_NUMBER>" } })
```

> **Merge contract.** This PR is part of a stack: merge via `scripts/squash-merge.sh stack` (Phase 5), **not** `gh pr merge --delete-branch` per-PR. See the Phase 5 **HARD GATE** for why hand-rolling the merge cascade-closes the stack.

#### Step 5: Independent fan-in checks — red-replay agent + code-review step

At fan-in the task is verified by **two independent checks that run in parallel** and share no state: a **red-replay agent** (dynamic execution — re-runs this task's red→green transition) and a **code-review step** (static reading — reviews the diff). Both are independent of the Dev agent; neither is the test author. They replace the old single fused verifier — test-replay and code-review are different activities with different failure modes, so they are split.

**Why two checks, not one role:** the red-replay agent is *action/evaluation separation* (a non-author re-runs what the Dev agent authored), not an authorship split — the Dev agent remains sole author of BOTH red and green. The code-review step is the static-reading counterpart. Neither is a new top-level role.

##### 5a. red-replay agent (background, parallel with code-review step)

An independent (non-author) per-task verifier that REPLAYS the Dev agent's red→green transition in a **scratch checkout** — it does NOT reuse the Dev agent's worktree, test logs, env vars, or temp fixtures (those could bias the result; the whole point is an independent re-run).

| property | value |
|---|---|
| independence | a non-author agent — NOT the Dev agent that wrote the test |
| what it runs | THIS task's own tests (impl-absent ref → real red, impl ref → green) + compile/lint/type-check on the impl ref |
| what it does NOT run | the full project test suite (Phase 3 integration owns that) |
| timing | per-task, source-level, BEFORE fan-in — parallel with code-review step |
| authorship | does NOT author tests; Dev remains sole author of red AND green |
| role status | NOT a new top-level role; the per-task independent verifier |
| on failure | block fan-in, route the log back to the Dev agent (same loop as below) |

```
Launch 1 agent (background):
  Read HANDOFF.md in .worktrees/${WORKTREE_NS}/task-${N}/

  You are a red-replay agent. Independently REPLAY this task's red→green
  transition. You are NOT the test author — do not edit tests or impl.

  Work in a SCRATCH checkout, created as a DETACHED worktree at a specific SHA
  (NOT a branch — the task branch is already checked out by the Dev worktree, so
  `git worktree add <path> <branch>` would collide). Use:
      SCRATCH=$(mktemp -d)
      git worktree add --detach "$SCRATCH" <impl-absent-sha>
  Reuse this ONE scratch worktree for both legs (step 2 does
  `git -C "$SCRATCH" checkout --detach <impl-sha>`). Do NOT reuse the Dev
  agent's worktree, cached results, env vars, or temp fixtures.

  1. impl-absent ref (the task's base SHA / pre-impl commit): re-run THIS task's
     own tests from HANDOFF.md's test plan. Expect RED — and verify it is a
     REAL, RIGHT-REASON failure, not an artifact: the test file must load/parse
     cleanly (e.g. `source`/import succeeds) and fail on the ASSERTION, not on a
     missing-file / import-error / syntax error. A non-zero exit that is really
     a setup error does NOT count as red. compile is NOT asserted on this ref
     (a new-file task is legitimately uncompilable without its impl).
  2. impl ref: `git -C "$SCRATCH" checkout --detach <impl-sha>`, re-run THIS
     task's own tests. Expect GREEN. Then run compile/lint/type-check on the
     impl ref — the project's standard targets/linters, whatever the Dev
     self-test runs; no new tooling. Run syntax checks PER FILE (one invocation
     per file, e.g. `bash -n <file>` each, so a failure names the file) — do not
     bundle files in one invocation. A deeper linter (e.g. shellcheck, mypy) is
     BEST-EFFORT: run it if present, skip-and-note if not installed. This leg is
     UNCONDITIONAL.
  3. Do NOT run the full project test suite — Phase 3 integration owns that.

  Pass only if BOTH the transition holds (real right-reason red on impl-absent,
  green on impl) AND the per-file syntax check passes on the impl ref. On any
  failure or a divergence from the Dev self-test (e.g. flakiness) → report it;
  do NOT silently pass a divergence.

  Run every command fresh in the scratch checkout. Include actual command
  output and exit codes as evidence. Be concise.

  TEARDOWN (always, even on failure): remove the scratch worktree so no orphan
  is left registered in the repo —
      git worktree remove --force "$SCRATCH" 2>/dev/null || rm -rf "$SCRATCH"
      git worktree prune

  Report: red/green transition result + per-file syntax + best-effort lint
  result, with evidence.
```

##### 5b. code-review step (background, parallel with red-replay agent)

Its own independent step that delegates to the `code-review` skill. **Unconditional** — Gate B was abolished (PR #665), so there is no CI-auto-review gating.

| property | value |
|---|---|
| timing | per-task, BEFORE fan-in — parallel with red-replay agent (they share no state) |
| scope | THIS task's diff (`git diff <base>..HEAD`) |
| reviewer | independent of the Dev agent; delegates to the `code-review` skill |
| on failure | findings route back to the Dev agent (same loop as below); blocking until resolved or accepted |
| report artifact | appends the review summary to the PR description under `## Review results` |
| dependency | if the `code-review` skill is unavailable, STOP and surface — do not silently skip (review is mandatory) |

```
Launch 1 agent (background):
  Read HANDOFF.md in .worktrees/${WORKTREE_NS}/task-${N}/

  You are the code-review step. Review THIS task's diff (git diff <base>..HEAD).

  Invoke the `code-review` skill on this task's diff for comprehensive review.
  If the `code-review` skill is unavailable, STOP and surface — do not skip
  (review is mandatory).

  Report: list of review issues (if any), with severity. Be concise.
```

**While the red-replay agent + code-review step run in background**, the main agent can start the next task — see Parallel Work Rules below.

**When both checks return:**

- **Both clean (no issues):** mark task done, proceed to next task
- **red-replay failed or review found issues:** loop back to Step 3 with the findings, then:
  1. Dev agent fixes + self-tests (Step 3 with the red-replay log / review findings)
  2. Push: `(cd "$WORKTREE_DIR" && git push origin HEAD:refs/heads/$TASK_BRANCH)` (always use explicit refspec — worktree branches track the parent base, not their own remote)
  3. Resolve every review conversation via `gh api graphql` (list unresolved threads, resolve each by ID). Unresolved threads block merge.
  4. If task N+1 is already in-flight, it must rebase onto task N before pushing
  5. Re-run Step 5 (both checks) if substantial changes were made. If 3+ fix attempts fail, question the approach.

Continue to next task only when both checks are clean and **all conversations are resolved**.

Append a `## Review results` section to the PR description via `gh api repos/{owner}/{repo}/pulls/$PR_NUM -X PATCH -f body="..."` — summarize the red-replay result (red→green + compile/lint/type-check) and the code-review findings. Mark task complete: `TaskUpdate({ taskId: "<N>", status: "completed" })`. Proceed to next task (Step 2), or Phase 3 if all dev tasks are complete (check with `TaskList`).

### Parallel Work Rules

Multiple tasks can be `in_progress` simultaneously when safe:

| Task N is at... | Can start task N+1? | Constraint |
|-----------------|---------------------|------------|
| Step 5 (red-replay + code-review in background) | Yes — Steps 2-3 (worktree + dev agent) | Task N's branch must be pushed (Step 4 done) so N+1 has a valid base |
| Step 3 (fixing red-replay / review feedback) | Yes — if N+1 hasn't pushed yet | N+1 must rebase before Step 4 if task N pushed new commits |
| Step 4 (PR not yet created) | No | N+1's base branch doesn't exist on remote yet |
| Same layer, any state | Yes — N+1's worktree + Dev agent run alongside N | Both base on the same prior-layer branch; their file sets satisfy Jaccard < 0.5 |

**Rebase rule:** if task N pushes new commits (red-replay / review fixes) while task N+1 is already in-flight, task N+1 must rebase onto task N before pushing:
```bash
(cd ".worktrees/${WORKTREE_NS}/task-$((N+1))" && \
  git fetch origin && \
  git rebase "origin/${FEATURE_PREFIX}/task-${N}")
```

> **Rebase conflicts:** resolve files, `git add`, `git rebase --continue`. If too tangled, `git rebase --abort` and reconsider task boundaries. Always push with `--force-with-lease`.

### Layer advancement gate (parallel mode, Amendment A5)

Before opening any worktree for layer L+1, the main agent must verify
all groups in layer L are `completed`. The `blockedBy` chain is
planning-time only — `TaskUpdate` does not refuse `in_progress` on a
blocked task, so this runtime gate is the sole enforcement of layer
ordering. Pseudocode + STOP-SAFE error path:
`references/parallel-stacks.md` § *Phase 2 — A5 advancement gate
pseudocode*.

### Phase 3: Feature Integration

After all tasks are complete and reviewed, validate the assembled feature's integration:

#### Merge-train: collapse N leaves into integration worktree (parallel mode)

With `parallel_layers != null`, N file-disjoint leaves must be
reassembled before integration testing. Run from a leaf worktree
(merge-train.sh reads `.flow-dev-lock` from `$PWD`):

```bash
cd ".worktrees/${WORKTREE_NS}/task-PR-1"
bash ~/.claude/skills/flow-dev/scripts/merge-train.sh \
  --feature-prefix "$FEATURE_PREFIX" \
  --worktree-ns "$WORKTREE_NS" \
  --default-branch "$DEFAULT_BRANCH"
```

Creates ephemeral `.worktrees/${WORKTREE_NS}/integration/` from
`origin/$DEFAULT_BRANCH`, rebases every leaf in layer order, STOP-SAFEs
on conflict. Conflict-resolution + linear-mode exit-2 fallback:
`references/parallel-stacks.md` § *Rebase conflicts during merge-train*
and § *Phase 3 — merge-train linear-mode fallback*.

#### Write integration test code

Integration tests live in `.worktrees/${WORKTREE_NS}/integration/`
(parallel mode) or the final task's worktree (linear mode). Implement
the integration test plan from the integration test task (retrieve via
`TaskGet`). The plan specifies *what* to test — this step writes the
*code*.

Write tests in `scripts/tests/` (or the project's existing test directory). Use the project's test framework (pytest, jest, go test, etc.). If the project has no test framework, write executable scripts that exit non-zero on failure. Tests must be runnable standalone (no manual setup steps). These tests are **kept permanently** as the project's regression suite.

If the integration test plan needs updates (e.g., interfaces changed during dev, new edge cases discovered), update the task description with `TaskUpdate` first, then write the code to match.

Commit the integration tests in the final task's worktree.

#### Run integration tests

Launch an **integration agent** to execute the integration tests plus the full project test suite:

```
Launch 1 agent:
  Read HANDOFF.md in the integration container:
    - Parallel mode: .worktrees/${WORKTREE_NS}/integration/
    - Linear mode:   .worktrees/${WORKTREE_NS}/task-${TOTAL_TASKS}/

  You are an integration agent.
  - Run the integration tests written above
  - Run the full project test suite
  - Run the feature's integration test plan (defined in Phase 1 or the final task)
  - Report pass/fail with full output for any failures
```

**If integration tests fail:** fix in the appropriate task's worktree, re-run that task's test plan, push, and rebase downstream tasks:

```bash
# After fixing task N, rebase all later tasks onto updated task N
for t in $(seq $((N+1)) $TOTAL_TASKS); do
  (cd ".worktrees/${WORKTREE_NS}/task-${t}" && \
    git fetch origin && \
    git rebase "origin/${FEATURE_PREFIX}/task-$((t-1))" && \
    git push --force-with-lease origin HEAD:refs/heads/${FEATURE_PREFIX}/task-${t})
done
```

Note: this uses plain `rebase` (not `--onto`) because the branches haven't been squash-merged yet — task-N's branch still exists with its original commits. `--onto` is only needed after squash-merge during the final merge phase.

#### Skill flow testing

When the changeset modifies `*/SKILL.md` files, run skill flow tests on real hardware (or locally). See **[references/skill-flow-testing.md](references/skill-flow-testing.md)** for the full procedure (detect modified skills, extract device types, launch test agents, result aggregation).

All skill flow tests must pass (or SKIP) before proceeding to merge.

#### Update final PR with integration test results

After all Phase 3 tests pass, append `## Integration test results (Phase 3)` to the final task's PR description via `gh api repos/{owner}/{repo}/pulls/$FINAL_PR_NUM -X PATCH -f body="..."`. Include a table of test results (check + PASS/FAIL) and skill flow test results if applicable.

#### Overall feature review (optional)

Optionally launch one agent to review cross-task consistency, composition, and edge cases across all PRs. Post findings on the final task's PR.

#### dogfood completion gate (Phase 3 → Phase 4 boundary assert)

When the changeset touches the three parallel-stacks scripts (detect with
`bash scripts/detect-dogfood-consumer.sh <file>` → `flow-dev`), assert that
the Smoke e2e-pass actually ran for this spec before advancing to Phase 4. The
trace is written per the `gate=e2e-pass:stack-dev` bullet under Phase 1 *Trace contracts* → [SSOT](../_shared/references/trace-grammar-contract.md). This is
the same place integration tests already gate — and it would have *forced* the
hand-dogfooded F1-F4 discovery instead of it being luck. `$SPEC_HASH` is the same
hash used at the spec-advisory trace + sandwich sidecar:

```bash
# Shared trace lib (_shared/lib/sh/sandwich-trace.sh). assert_gate_trace in
# `stop` mode subsumes all three former inline ops: the depth=smoke trailing-
# space grep, the run= extraction, and the run-NNN evidence-dir cross-check
# (with target= defaulting to the consumer name "flow-dev" when the trace
# line carries no target= field — matching the back-compat write above). It
# `return`s 1 on any failure; the `|| exit 1` keeps this a hard STOP gate.
source _shared/lib/sh/sandwich-trace.sh
assert_gate_trace e2e-pass flow-dev "$SPEC_HASH" stop \
  "$(git rev-parse --git-common-dir)/flow-dev-sandwich.log" smoke || exit 1
```

- The trailing space after `depth=smoke ` excludes prefix collisions and the other consumers' lines (same discipline as the spec-advisory `agents=3 ` assert). `tail -1` lets a re-run supersede a stale line. The assert READS the existing trace; it does not replace the integration-test gate above.
- Self-check ceiling is the same as the spec-advisory gate (Phase 2 entry assert): a main agent that fabricates BOTH the line AND a matching empty dir defeats it (hook infra declined).

### Phase 4: Pre-merge tasks

#### TODO.md (human-curated, not pre-merge bound)

`TODO.md` is a human-curated cross-skill backlog — nothing writes to it automatically, and pre-merge does not require updating it. Edit it ad hoc when adding or completing cross-skill items unrelated to a specific spec.

There is no spec-completion tracking, milestone generation, or indexing (no lifecycle — see Step 1).

#### Jira Ticket (before merge)

Run `bash ~/.claude/skills/flow-dev/scripts/jira-phase4.sh`. The script branches on 3 axes (`USES_JIRA`, `JIRA_CAPABILITY`, `JIRA_DECISION`) and either skips Jira, prompts for a ticket key (manual `ask` only), invokes `/jira` to backfill + retitle PRs (capability=`ready`), or degrades to PR-title-only updates (capability missing/invalid). Full per-branch behavior, manual prompt UX, and ticket-prefix conventions (`[UOF-…]`, `[DEBFACT-…]`, `[DEBBOX-…]`): **[references/jira-phase4.md](references/jira-phase4.md)**.

#### Pre-merge sanity (Oracle 6 manual)

Run `bash ~/.claude/skills/flow-dev/scripts/pre-merge-sanity.sh "${FEATURE_PREFIX}"` — exit 0 = all PRs merge-ready, 1 = BLOCKED with per-PR remediation, 2 = bad input. Full exit-code semantics: **[references/pre-merge-sanity.md](references/pre-merge-sanity.md)**.

- Includes a **lifecycle-drift gate** that auto-passes (the drift check is a no-op) — there is no spec lifecycle to drift. The `final-task promote reverse-guard` (`pms_check_spec_promoted`) likewise early-returns. Both gates are inert in this flow.

#### Pre-Merge Cleanup

Remove **all** worktrees before merging (they pin branch checkouts and block deletion). Run from the main worktree, not one being removed:

```bash
cd "$PROJECT_ROOT"
for dir in .worktrees/${WORKTREE_NS}/task-*; do
  git worktree remove "$dir" --force 2>/dev/null || true
done
rmdir ".worktrees/${WORKTREE_NS}" 2>/dev/null || true
git worktree prune
```

> Remote/lock cleanup (`git push origin --delete`, `.flow-dev-lock` removal, `git remote prune origin`) is deferred to Phase 5 via `post-merge-cleanup.sh stack` — see Phase 5 below.

#### Warning — spec-PR-as-stack-base unsupported

Do **not** base a feature stack on a spec PR whose head branch lives in a lifecycle dir (`docs/spec/proposed|active|done/`). Pattern observed in production:

- Spec PR (e.g. #471 `spec/foo`) is opened separately from the feature stack.
- Stack task-1 PR's `base` points at the spec PR's head (e.g. `feat/foo/task-1` → `spec/foo`).
- When the spec PR merges and its head branch is deleted, every stacked dev PR based on that branch hits the **same cascade-close failure** documented in the Phase 5 **HARD GATE** (auto-close + lost review history). PR #471's merge auto-closed PR #478 — the documented failure mode for this **spec-PR-as-stack-base** anti-pattern.

**Recommended pattern.** Commit any spec changes **inside `task-1`** of the same feature stack rather than as an independent spec PR — the spec lives at `docs/superpowers/specs/` and travels with the feature. There is no separate promote commit. No independent spec PR exists, so no cascade-close risk.

**Opt-out (advanced).** Future Phase 0 preflight will refuse spec-PR-as-stack-base unless `SD_ALLOW_SPEC_BASE=1` is exported. Detection logic is deferred to a follow-up PR — this section is doc-only for now.

#### CI Check (before merge)

`gh pr checks $PR_NUM --watch` per PR. Required status checks would block the merge anyway — this just surfaces failures earlier.

### Phase 5: Merging

**Merge gate:** verify all tasks (including the integration test) are `completed` via `TaskList`. Do NOT skip — incomplete tasks mean unmerged work.

> ### HARD GATE — Never `gh pr merge --squash` a stacked PR manually
>
> Squash-merging a stacked-PR feature one-PR-at-a-time with `gh pr merge --squash` **will destroy the rest of the stack**. Symptoms (observed in production 2026-05-21 — `feat/spec-advisory-fixer/task-1..5` cascade failure):
>
> - The first PR merges cleanly. Its branch is deleted if **either** (a) you pass `--delete-branch` to `gh pr merge`, **or** (b) the repo has `delete_branch_on_merge: true` in its settings (verify with `gh api repos/<owner>/<repo> --jq .delete_branch_on_merge`). For `ubiquiti/prompt-hub` this setting is currently `false` — so `--delete-branch` is the only trigger here; on a repo with the setting enabled the cascade fires regardless of the flag.
> - Every PR whose `base` pointed to the just-merged branch **auto-closes** (state=CLOSED with `mergedAt=null`). They cannot be reopened (the base branch is gone).
> - The remaining PRs still in the stack become `mergeable=CONFLICTING` against main, because their branches still contain the **original commit hashes** of the now-squashed work, while main has a different commit hash representing the same content. Git sees same-content/different-hash as a 3-way merge conflict on every touched line.
> - Recovery cost: ~3 hours per 5-PR stack to cherry-pick onto main, force-push, retarget base, supersede closed PRs with new ones. Plus inevitable rebase conflicts when a stale stacked branch carries the original commit hashes of work that main already has as a single squash commit.
>
> **Do not manually squash-merge a stacked PR.** Use the script below — it does the cherry-pick / force-push / retarget atomically per PR.
>
> Allowed manual paths:
> - **Single PR, no safety concerns**: `gh pr merge --squash` is fine.
> - **Single PR, want CI-watch + merge-state-assertion safety**: `bash ~/.claude/skills/flow-dev/scripts/squash-merge.sh single <branch> <default_branch>`.
> - **Stacked PRs with `--merge` (not squash)**: `gh pr merge --merge` directly per PR — original SHAs preserved, no rebase needed.

#### Squash-merge with rebase-before-merge

```bash
bash ~/.claude/skills/flow-dev/scripts/squash-merge.sh stack \
  "$FEATURE_PREFIX" "$TOTAL_TASKS" "$DEFAULT_BRANCH"
```

The script: mergeability pre-check (every PR must be `MERGEABLE`) → per-PR cherry-pick onto fresh main → force-push → re-point PR base to main → squash-merge. Branches are cleaned up after all merges. Exit codes: 0 success, 1 failure, 2 bad args.

**Iteration order (Amendment A3).** With `parallel_layers != null`,
`squash-merge.sh stack` walks layers in order; PARENT comes from
`pl_first_in_layer`. Linear mode is byte-identical to pre-2026-05-29.
Full contract: `references/parallel-stacks.md` § *Phase 5 — A3
cherry-pick layer ordering*.

> **Don't unquote the cherry-pick.** The script uses `mapfile -t COMMITS` + `git cherry-pick "${COMMITS[@]}"` to prevent a silent-empty-cherry-pick regression (covered by `scripts/tests/cherry-pick-quoting/test.sh`).

For merge-commit repos (not squash), call `gh pr merge --merge` directly per PR — original SHAs are preserved, no cherry-pick needed.

> **Drop `--delete-branch`.** `squash-merge.sh stack` already (a) omits `--delete-branch` on each `gh pr merge` and (b) defers `git push origin --delete <branch>` to `post-merge-cleanup.sh stack` (runs only after **all** PRs merge) — which is what avoids the HARD GATE cascade above. If you merge manually (incl. the `gh pr merge --merge` fallback), replicate both halves: never pass `--delete-branch`, defer branch deletion to post-merge-cleanup.

#### Phase 5 cleanup — run post-merge-cleanup

After the final squash-merge lands, run `post-merge-cleanup.sh stack` to
delete remote/local task branches, remove the Phase 0 lock, and prune:

```bash
# post-merge cleanup.
bash ~/.claude/skills/flow-dev/scripts/post-merge-cleanup.sh stack \
  "$FEATURE_PREFIX" "$TOTAL_TASKS" "$DEFAULT_BRANCH"
```

No promote step — so no bookkeeping PR and no post-merge `done/` move (no lifecycle — see Step 1).

`post-merge-cleanup.sh` is idempotent — running it twice (or when branches
and lock are already gone) is a no-op. For a single-PR merge, use
`post-merge-cleanup.sh single <branch> <default_branch>` instead.

## Extensions

- **A — semver-release** (optional, post-merge): after all PRs merged, optionally run `/semver-release <level> [profile]` to bump `debian/changelog`, tag, generate release notes, and publish. Skip when the repo doesn't use semantic versioning. The `skill` profile adds Confluence wiki publishing.
- **B — Two-Repo Debfactory PR** (Ubiquiti): when the source repo has a corresponding debfactory package, create ONE debfactory PR for the entire feature after per-task verification (red-replay + code-review). See **[ubiquiti-flow/references/two-repo-debfactory.md](../ubiquiti-flow/references/two-repo-debfactory.md)**.
- **C — audit gates** (optional, Phase 3 integration): for skill PRs touching ≥ 2 SKILL.md files, run the deterministic leg first (`Skill skill-deterministic-audit <skill>`) then the probabilistic leg (`Skill skill-probabilistic-audit <skill>`, axis G1/G8, advisory) before merge. Findings are diagnostic, never blocking.
- **D — resident dogfood** (optional, real-run verification of the parallel-stacks flow). Two entrypoints under `scripts/`:
  - **Smoke** (deterministic, no agent): `bash scripts/tests/dogfood-smoke.sh` runs `parallel-layers.sh` + `merge-train.sh` against an isolated fixture and captures evidence to `docs/dogfoods/flow-dev/run-NNN/smoke/`.
  - **Behavior** (opt-in, agent-driven): `bash scripts/dogfood-prepare.sh` allocates the next `run-NNN` and writes a byte-stable `behavior/dispatch-prompt.md` for the main agent to dispatch a controlled multi-group run. The prompt FORCES sandbox overrides (`--feature-prefix feat/dogfood-run-NNN`, `--worktree-ns dogfood-run-NNN`) so a Behavior run never touches the real PR list. The preparer never spawns the agent. Contract: `docs/dogfoods/README.md` Part 2.

## Crash Recovery

On restart, reconstruct feature state from `git worktree list`, `gh pr list`, and `TaskList` (same session) — full procedure: **[references/crash-recovery.md](references/crash-recovery.md)**.
