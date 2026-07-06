# Model Dispatch Protocol

Addresses [diagnosis.md](diagnosis.md) Finding 2 (model/effort never pinned) and
Finding 3 (verification defaults to self-verification). Read this before dispatching
any subagent — via the `Agent` tool, or the equivalent `Task`/`Workflow` `agent()`
primitive if your harness exposes one.

## Rule 1: Commander doesn't execute

The main session (you, reading this in the primary conversation) does research,
decides, and writes conclusions. It does not do the legwork itself. Concretely:

| Task shape | Who does it |
|---|---|
| Reading 1 file to answer a specific question | Main session (cheap, no dispatch overhead) |
| Reading 3+ files, or an open-ended "where is X" | Subagent (`Explore` or `general-purpose`) |
| Scanning/grepping across the repo | Subagent |
| Web search / fetching external pages | Subagent (unless a single URL the user gave you) |
| Editing 2+ files, or any multi-step implementation | Subagent |
| Editing exactly 1 file, mechanical, bounded | Main session may do it directly |
| Forming a conclusion that will be acted on | Main session synthesizes; verification is a SEPARATE dispatch (Rule 4) |

**Positive example:** user asks "which skills call `stack-dev`" — that's a repo-wide
grep shape, dispatch to `Explore`, don't `rg` it yourself in the main session context.

**Negative example:** dispatching a subagent to fix one typo in one line you already
located. That's main-session work; dispatch overhead costs more than it saves.

## Rule 2: The delegation triad — every dispatch states three things

Every `Agent`/`Task`/`agent()` call must make explicit, in the prompt itself:

1. **Goal and motivation** — not just "read file X" but *why*: what decision or
   change depends on the answer. A subagent that knows the motivation makes better
   judgment calls when it hits an edge case you didn't anticipate.
2. **Acceptance criteria** — the condition that tells the subagent (and you) it's
   done. Must be checkable: "confirm the function exists and list its callers" not
   "look into the function." See [judgment-rubric.md](judgment-rubric.md) for the
   general premature-completion guard this feeds.
3. **Report format** — what shape the answer should come back in. Default: text
   summary under ~200 words, `file:line` citations for anything the main session
   might need to act on directly. Long artifacts (full file rewrites, big diffs) get
   written to disk by the subagent; the report is the path, not the content.

Templates for the five common shapes (search/implement/refactor/research/review) are
in [delegation-templates.md](delegation-templates.md) — fill in the blanks, don't
freehand a new prompt shape each time.

## Rule 3: Pin model and effort explicitly — don't accept silent defaults

Every dispatch that has a `model` or `effort`/`reasoning effort` parameter available
sets it deliberately. "I didn't set it" is not a decision, it's an unexamined default
inherited from whatever the harness picked — sometimes right, but never because you
checked.

**Model tiers available this session** (verify against your own session's system
context before trusting this list — models ship faster than this file gets updated):
`claude-haiku-4-5-20251001` (fast/cheap), `claude-sonnet-5` (default workhorse),
`claude-opus-4-8` (hardest judgment calls), `claude-fable-5` (distinct
tier — check current session docs for what differentiates it before assuming it's a
drop-in Opus/Sonnet swap).

**Effort tiers** (where the tool exposes one): `low`, `medium`, `high`, `xhigh`,
`max`. Higher effort = more reasoning tokens spent before answering, not a different
model.

**Escalation rule** (full rubric in [judgment-rubric.md](judgment-rubric.md) §1):
default to the session's inherited model+effort for mechanical/bounded work. Escalate
model tier and/or effort when the task is a judgment call with real consequences if
wrong (architectural decisions, "should we merge/retire X," anything the user can't
trivially undo) — not for merely "long" or "many files" tasks, which need more
*dispatches*, not a stronger model per dispatch.

**Positive example:** deciding whether two near-duplicate skills should be merged —
an irreversible-ish call with downstream effects — escalate effort (`high` or above)
even if the research itself is a simple file comparison.

**Negative example:** escalating model tier for a 500-file rename-and-grep sweep.
That's breadth, not depth — more parallel `Explore` agents at default tier beats one
agent at a higher tier.

## Rule 4: Verify ≠ self-verify

Stated as a standing rule (previously only lived inside `stack-dev`'s Phase 2 — see
diagnosis.md Finding 3). Any conclusion that will be acted on gets checked by
someone/something that didn't produce it:

- **File/artifact correctness** → read it back after writing (cheap, main session can
  do this itself — it's not re-deriving the conclusion, just confirming the write
  landed).
- **Code correctness** → tests, or an actual run of the affected path. Never "I read
  the diff and it looks right" as the only check.
- **Judgment calls / high-stakes or hard-to-reverse decisions** → dispatch a
  fresh-context subagent to argue the other side, or get a second independent pass,
  before treating the decision as settled. Fresh-context matters: an agent that
  already saw your reasoning tends to agree with it.
- **Multiple plausible answers, no clear tiebreaker** → dispatch N independent agents,
  compare, let a judge (or you) pick — don't let the first plausible answer win by
  default.

**Positive example:** after rewriting a SKILL.md body, dispatch a fresh-context agent
to read only the new file (not your reasoning) and try to find contradictions or
ambiguous phrasing — this is exactly what deliverable list item "collateral: adversarial
review" in this constitution project does to itself.

**Negative example:** writing a decision to memory and treating "I re-read what I
wrote and it sounds right" as verification. That's self-verification wearing a
disguise — it checks prose quality, not whether the decision was correct.

## Escalation path (when to go up, not just how)

1. Default tier handles it → done, no escalation.
2. Default tier's output looks uncertain, contradictory, or the task has failed 2+
   times with different approaches → escalate effort first (cheaper than escalating
   model).
3. Effort escalation still unresolved, or the task is explicitly a hard architectural
   /irreversible judgment call → escalate model tier.
4. Model+effort maxed and still unresolved, or the call requires taste/values the
   model structurally can't verify against anything (see judgment-rubric.md's honesty
   clause) → stop, surface to the user. Do not keep escalating in a loop hoping a
   bigger hammer fixes a nail-shaped problem that was never about model capability.
