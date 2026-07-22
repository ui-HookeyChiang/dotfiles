# Glossary — Skill Guidelines

The domain model for what makes a skill great. A skill exists to wrangle
determinism out of a stochastic system; the root virtue is **Predictability**,
and every term below is a lever on it. This is the disclosed reference for
[`SKILL.md`](../SKILL.md).

Terms grouped by axis: **Invocation** (how a skill is reached), **Information
Hierarchy** (how content is arranged), **Steering** (how runtime behaviour is
shaped), and **Pruning** (how it is kept lean). Each failure mode lives beside
the lever that cures it.

**Bold terms** in any definition are themselves defined in this glossary.

---

## Predictability

The degree to which a skill makes the agent behave the same _way_ on every
run — the same process, not the same output. The root virtue every other term
serves.

## Invocation

### Model-Invoked

A skill that keeps its **description** field, so the agent can fire it
autonomously. Pays permanent **context load** on every turn. Reachable by
other skills.

### User-Invoked

A skill with its description stripped — invisible to the agent, reachable only
by the human typing its name. Trades discoverability for zero **context load**.

### Context Load

The cost a model-invoked skill imposes — its description, always loaded,
spending tokens and attention.

### Cognitive Load

The cost a user-invoked skill imposes on the human — which skills exist and
when to reach for each.

### Router Skill

A user-invoked skill that points at other user-invoked skills — the cure for
**cognitive load** when user-invoked skills multiply.

### Granularity

How finely you divide skills. Finer division spends one of the two loads.

---

## Information Hierarchy

### Steps

Ordered actions the agent performs — the primary tier. Every step ends on a
**completion criterion**.

### Reference

Material consulted on demand — definitions, facts, parameters, examples. The
prime candidate for **progressive disclosure**.

### External Reference

Reference living outside the skill system — no description, no steps, not
invocable — that any skill can point at.

### Progressive Disclosure

Moving reference down the ladder — out of SKILL.md into a linked file — so the
top stays legible.

### Context Pointer

A reference held in context that names out-of-context material and encodes the
condition for reaching it. Its _wording_, not the target, decides when the
agent reaches.

### Co-location

Keeping material an agent needs at once in one place — a concept's definition,
rules, and caveats under one heading rather than scattered.

---

## Steering

### Branch

A distinct way a skill can be invoked — different runs taking different paths.

### Leading Word

A compact concept already in the model's pretraining that the agent thinks with
while running the skill. Encodes a behavioural principle in the fewest tokens
by invoking priors the model already holds (e.g. _lesson_, _fog of war_,
_tracer bullets_). Serves predictability twice: in the body it anchors
execution; in the description it anchors invocation.

### Completion Criterion

The condition that tells the agent a unit of work is done. Two properties:
**clarity** (can the agent tell done from not-done?) resists premature
completion; **demand** (how much it requires) sets legwork.

### Legwork

The work an agent does behind the scenes within a single step — reading files,
exploring, digging up what it needs. Raised by a demanding completion criterion.

### Post-Completion Steps

The steps that follow the current step. Visible, they pull the agent forward
into premature completion.

---

## Pruning

### Single Source of Truth

Each meaning lives in exactly one authoritative place. **Duplication** is its
violation.

### Relevance

Whether a line still bears on what the skill does — the lens for what to keep.

### No-Op

An instruction that changes nothing because the model already does it by
default. The test: does it change behaviour versus the default?

---

## Failure Modes

### Premature Completion

Ending a step before genuinely done, attention slipping to _being done_.
Defence: sharpen the completion criterion first (cheap); only if irreducibly
fuzzy AND you observe the rush, hide post-completion steps.

### Duplication

Same meaning in more than one source of truth. Costs maintenance, tokens, and
inflates prominence.

### Sediment

Stale layers that settle because adding feels safe and removing feels risky.
The default fate without pruning discipline.

### Sprawl

A skill simply too long, even when every line is live. Cure: disclose reference
behind pointers, split by branch or sequence.

### No-Op (failure mode)

A line the model already obeys by default — you pay load to say nothing. A weak
leading word is a no-op; the fix is a stronger word, not a different technique.
