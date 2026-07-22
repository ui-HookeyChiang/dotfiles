---
name: adversarial-review
description: >-
  Adversarial review of a hard decision, plan, spec, claim, or design by
  fanning out N INDEPENDENT reviewer subagents (separate contexts), then a
  fresh-context Moderator agent synthesizes findings and forces an
  echo-chamber warning.
  Use when a judgment is high-stakes, irreversible, or you suspect you are
  fooling yourself and a single pass would miss what it cannot see — "stress
  test this", "what am I missing", "review this decision/plan/claim",
  "premortem", "is this argument sound", "epistemic audit", "幫我審這個決定",
  "我會死在哪". The mechanism that empirically adds quality is
  INDEPENDENT-CONTEXT FAN-OUT plus synthesis, NOT persona role-play and NOT a
  single agent listing lenses to itself (both measured to add ~nothing). NOT
  for routine questions one answer handles, NOT for code edits (use
  coding-guidelines / flow-dev).
argument-hint: "<decision|plan|claim|spec to stress-test> [angles: outside-ruin,falsifiability,incentives]"
landing-group: workflow
standards-applied: [description, contract, behavior, adversarial, disclosure, trigger-eval]
---

# Adversarial Review

Adversarial review by independent fan-out. Empirically verified (blind-judged
across decision / risk / claim problems, this is the measured ranking):

- **Bare single agent** — loses to every fan-out arm.
- **Single agent that lists many lenses to itself / appends an echo section** —
  ≈ bare. Lenses collapse into one context and self-agree.
- **N independent reviewer subagents + synthesis** — wins decisively
  (best-answer ~8-9/9, blind-spot ~9/9). **The only structure that adds quality.**
- **Lens-diverse vs identical reviewers, agent count held fixed** — near tie;
  diversity adds a small edge on blind-spot-dense problems (decisions, claims),
  little on technical ones.

So: **independence + count is the engine; lens diversity is a minor topping.**
Spend the fan-out on INDEPENDENT CONTEXTS, give them a few orthogonal angles
(not personas, not a long lens list), and always run the
echo-chamber close.

## When to run it (and when not)

Run it when **the cost of being wrong won't let you accept a single-pass
answer** AND the problem has **more than one orthogonal way to be wrong**:

- a hard / irreversible decision, a strategy bet
- a plan or design before committing
- a claim or argument you need stress-tested
- anywhere you suspect self-deception (attached, invested, or rushed)

Do NOT run it for: routine questions one answer handles, lookups, mechanical
edits, or a problem with a single obvious failure mode — it just burns N× tokens
for no extra coverage. A single competent answer is the right default; this is
the escalation.

## Procedure

### 1. Frame the object + pick orthogonal angles

State in one line what is under review and its **orthogonal error axes** (the
independent ways it can be wrong). Pick **2-4 angles**, each attacking a
different axis. Default orthogonal set for decisions / claims:

| Angle | Attacks |
|---|---|
| **outside-view + ruin** | base rate of comparable real cases (ignore the inside story); and the irreversible worst case, gated BEFORE any expected-value reasoning |
| **falsifiability** | what concrete observation would prove this wrong? is it even refutable? cheapest disconfirming test? |
| **incentives + inversion** | who benefits from each choice and how does it distort judgment; and "how would I guarantee the worst outcome?" |

Object not decision/claim-shaped (a system, a design, an estimate, a plan)?
**Fan out N independent reviewers anyway and let each find its own error-axis** —
that is the proven lever. Do NOT enumerate a long axis list to a single agent:
the model already reasons in these axes natively, and single-agent lens
enumeration measured ≈ bare. Pick at most a couple of obviously-orthogonal
seeds if it helps you frame, then spend the budget on independent reviewer
count, not on the lens menu.

Swap/extend angles to fit the object. Keep angles **orthogonal** — overlapping
angles waste a slot. More than ~4 rarely adds a non-redundant axis.

### 2. Fan out — INDEPENDENT subagents (the load-bearing step)

Dispatch one subagent per angle **in parallel, in separate contexts** (one
message, multiple Agent calls). Each gets ONLY its angle and the object — it
MUST NOT see the others' work. Independence is what lets synthesis catch what a
single context cannot.

- Do NOT collapse the angles into one agent (measured ≈ bare).
- Do NOT ask agents to role-play named personas (measured ≈ bare; persona voice adds nothing).
- Each reviewer returns concise findings.

### 3. Moderator synthesis (independent, domain-naive agent)

A fresh-context Moderator agent (NOT the gen agent) receives the artifact +
all reviewer findings and **integrates, does NOT concatenate**:

1. **Findings disposition table** — for each finding: accept / dismiss + reason.
   HIGH findings CANNOT be dismissed (must be accepted and addressed).
2. **Consensus** — points multiple reviewers reached independently (high signal).
3. **Conflicts** — where reviewers disagree: surface the tension, do NOT average;
   give an "in which case, listen to whom" rule.
4. **Weight** — rank findings by leverage; mark load-bearing vs marginal.
5. **Actions** — 1-3 concrete next steps; if blocking: "do not proceed until X".

The Moderator is fresh-context AND **domain-naive** — do NOT inject CONTEXT.md
or ADRs into its prompt. Domain context causes the Moderator to echo reviewers
instead of critically synthesizing (evidence: `docs/experiments/2026-07-0{3,4}-*.md`).
Reviewers get domain grounding; the Moderator gets none.

### 4. Caller contract (gen receives Moderator output)

The gen agent (artifact author) receives the Moderator's synthesized output
and must:

1. **Fix all accepted HIGH findings** — no dismissal permitted at this stage.
2. **Address MED findings** — fix or explain why not (documented in commit).
3. **Run echo-chamber close** (§5 below) in structured output.

The caller does NOT moderate — it receives already-moderated findings and fixes.

### 5. Echo-chamber warning (mandatory close)

Independent reviewers can still share a model and fail *together*. Force a final
self-critical pass naming:

1. **Is the consensus independent confirmation, or correlated-lens echo?** Agreement ≠ truth.
2. **What are all reviewers collectively blind to?** — the un-voiced stakeholder, the option the framing excludes, a measurement bias (forcing quantification silently penalizes high-uncertainty / high-upside options), the wrong time-scale.
3. **What structural bias does this analysis carry?** — e.g. kill-bias; advisor giving the *defensible* answer not the *best* one.
4. **Which load-bearing input is owner-only?** — the private fact the model cannot supply; if filled wrong, everything downstream is wrong.

The echo-chamber close was the measured blind-spot decider — do NOT skip it.

## Scaling

- Default **3 reviewers**. Raise count BEFORE raising lens variety — independent count is the bigger lever.
- Token cost is N×+1; justified only at the stakes bar in *When to run it*.
- Unknown-size review: loop — re-fan until a round surfaces nothing new.

## Context injection (reviewers only — D9)

When dispatching independent reviewers (§2), each reviewer's prompt includes
domain context so reviews are grounded in project reality:

1. **CONTEXT.md** — project domain model, bounded contexts, vocabulary (if exists)
2. **Relevant ADRs** — architecture decisions that constrain the object under review (from `docs/adr/`)
3. **Codebase structure summary** — top-level directory layout, key module boundaries

Reviewers receive context at dispatch but still run independently (§2 rules
apply). The Moderator remains domain-naive (§3).

In spec-gating mode, context is injected into each reviewer's dispatch prompt
automatically.

## Spec-gating mode (used by flow-dev)

flow-dev's spec gate calls this skill with **N=3 independent reviewers**
over a spec object, severity-graded output. Each reviewer attacks one
orthogonal axis (do NOT collapse into one agent):

| Reviewer | Agent type | Attacks |
|---|---|---|
| A | Explore | blind-spot scan: missing assumptions, failure modes, untested edges, dependency drift |
| B | general-purpose | cross-section consistency: internal contradictions across spec sections |
| C | general-purpose | acceptance-criteria sharpness: vague verbs in Success criteria / Test plan / Acceptance criteria |

Each finding is a JSON object:

```json
{ "severity": "HIGH|MED|LOW", "title": "short", "where": "section/line/absent",
  "why": "1-2 sentences", "suggestion": "proposed rewrite (REQUIRED for HIGH)" }
```

Severity rubric:
- **HIGH** — internal contradiction, missing success↔test mapping, task-contract gap. Requires a concrete rewrite diff; if no rewrite is possible, downgrade to MED.
- **MED** — scope creep with a removable section, vague test steps, broken cross-references.
- **LOW** — style / formatting / word-choice nitpick.

The Moderator (§3) synthesizes findings; gen receives output per §4's caller contract.
The echo-chamber close (§5) still runs.

## Adversarial scenarios (resist these shortcuts)

This skill enforces a discipline (real fan-out). Common pressure to cut it, and
the required response:

1. **"Just list the angles in one answer to save agents."** → Refuse. Single-agent
   multi-lens was measured ≈ bare; the lenses self-agree in one context. The cost
   is the point — if the stakes don't justify N agents, you should not be running
   the council at all (run a single answer).
2. **"Let the reviewers see each other's findings so they build on them."** → Refuse.
   Shared context destroys independence — the exact property that makes synthesis
   catch cross-context blind spots. Reviewers run blind; the Moderator (§3)
   is the only integration point.
3. **"Skip the echo-chamber warning, the consensus is clearly right."** → Refuse.
   Unanimous agreement is the *trigger* for the echo-chamber check, not a reason to
   skip it — correlated-lens echo looks exactly like strong consensus. It was the
   measured blind-spot decider.
4. **"Use the Munger / Taleb persona skills for richer voices."** → Refuse. Persona
   role-play measured ≈ bare. Diversity of *orthogonal angle* helps marginally;
   diversity of *named voice* does not. Spend the budget on independent count.
5. **"The HIGH finding is a false positive, I'll dismiss it with a good reason."** → Refuse.
   HIGH findings cannot be dismissed — this is a structural safeguard, not a judgment
   call. If the finding is genuinely wrong, downgrade its severity with evidence
   (explain why it doesn't meet the HIGH rubric), then dismiss at the lower level.
   The caller contract (§4) enforces this unconditionally.
6. **"Let the gen agent moderate its own findings — it knows the context best."**
   → Refuse. D7 experiment (PR #937) measured this: gen-as-Moderator rubber-stamps
   all findings (accepts uncritically to avoid appearing defensive), including
   reviewer errors it should dismiss. A fresh-context Moderator has no identity
   stake and exercises genuine critical judgment. The experiment showed independent
   Moderator won 3/6, gen-as-Moderator 1/6, with the gen failure mode being
   indiscriminate acceptance, not motivated dismissal.
7. **"Inject CONTEXT.md into the Moderator too — it'll catch terminology drift."**
   → Refuse. Domain grounding belongs in reviewers; the Moderator's value is its
   outsider perspective (§3).
