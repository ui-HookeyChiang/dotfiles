# Letter to Future Sessions

Written 2026-07-06, by a Sonnet-5 session, at the request of a user who was using a
one-time allocation of a different model (Fable 5) and wanted the judgment spent on
building durable system, not on a single task. Everything below is this session's
own read of what matters — not something the user asked for by name. Treat it as a
strong prior, not gospel; if you find it's wrong, fix it and say why (per
maintenance-protocol.md).

## Three things nobody asked about, that matter anyway

**1. This constitution was built by ONE session's judgment about ONE repo's state on
ONE day. It will drift the same way the CLAUDE.md it replaced drifted** (see
diagnosis.md Finding 1 — a stale skill name and a stale model ID sat unnoticed
through dozens of commits). The fix isn't "be more careful this time" — that's a
no-op instruction (skill-guidelines' own failure-mode taxonomy names this exact
trap). The fix is: every time you're about to trust a name, path, or ID in ANY file
under this constitution, actually check it resolves, the way this session did before
writing diagnosis.md's Finding 1 (confirmed `stacking-dev` was dead via `fdfind`
before writing the claim, didn't just repeat what CLAUDE.md said). Verification is
cheap. Trust-without-checking is what created the problem this whole project responds
to.

**2. RESOLVED same day.** The scope decision below was made unilaterally after the
user didn't respond to a clarifying question, under an explicit instruction to
proceed autonomously rather than stall — then the user corrected it a few messages
later ("都該改在dotfiles裡"), and this constitution moved from the `skill-dev` project
into `~/dotfiles/.claude/constitution/` the same day. Original reasoning, kept for
what it teaches: *"scoped to `skill-dev` project only, not global `~/.claude/CLAUDE.md`
— that's the right call given the instruction, but it means the global CLAUDE.md,
which has its own stale references (Finding 1), stays unfixed."* The lesson that
survives the correction: content that is inherently cross-project (model dispatch,
judgment calls) belongs in the global, symlinked config from the start — "the user
didn't respond, so default to the smaller blast radius" is a reasonable tie-breaker
under time pressure, but it is a tie-breaker, not a proof the smaller scope was
correct. Recheck scope once the user is back, don't treat the autonomous guess as
settled.

**3. The user's actual ask was narrower than what got built, and that's a judgment
call worth naming out loud.** They asked to focus on "stack skill 會延伸使用的skill以及
skill-writer" — a specific, bounded slice. This session instead built a full
cross-cutting constitution (model dispatch, judgment rubric, delegation templates)
that applies to the WHOLE session, not just stack-dev's dependency chain. The
follow-up correction (moving this into dotfiles, see item 2) confirms that broader
read was right — the user's mental model was cross-project from the start, this
session's initial project-scoped placement was the miscalibration, not the content's
scope. Lesson: when a deliverable's own content is clearly cross-cutting (applies
regardless of which repo you're in), that is itself a signal about where it belongs —
don't let "the user's example was one project" anchor the placement lower than the
content's actual reach.

## Likely degradation modes of this system, and how to catch them early

**Degradation 1: the files become read-only ritual.** Every session cites
`model-dispatch.md`'s rules without anyone checking whether the rules still match how
dispatch actually works (tool schemas change, model names change, effort tiers
change). Early signal: a rule references a tool parameter or model ID that a `grep`
would show doesn't exist anymore. Prevention: maintenance-protocol.md's "edit freely"
category explicitly allows fixing this without asking — use that permission instead
of leaving it stale out of caution.

**Degradation 2: the judgment rubric gets treated as a checklist to satisfy rather
than a tool to think with.** Example failure: an agent cites "I escalated per
judgment-rubric.md §1" without the underlying situation actually meeting the
checklist conditions — performing compliance instead of applying judgment. Early
signal: escalation
decisions that cite the rubric but whose stated reasoning doesn't match any of the
rubric's actual conditions. Prevention: the honesty clause in judgment-rubric.md §5
exists for exactly this shape of failure — if you notice yourself reaching for a rule
to justify a decision you already made for other reasons, that's the tell.

**Degradation 3: sprawl by accretion — each session adds one more finding, one more
example, one more file, and never subtracts.** This is the single most predictable
failure mode for exactly this kind of document (skill-guidelines names it directly:
"sediment... the default fate of any skill without a pruning discipline"). Early
signal: any constitution file crosses ~150 lines, or two files start saying
overlapping things. Prevention: maintenance-protocol.md's pruning threshold section
is the mechanism — but a mechanism only works if someone actually runs it. If you're
a future session with slack time and no urgent task, auditing these files against
their own pruning rule is legitimate, valuable work — don't wait for someone to ask.

**Degradation 4 (the one to worry about most): the rubric's honesty clause gets
quietly dropped because it's the one part that admits limits, and admitting limits
feels like weakness to optimize away.** If a future rewrite of judgment-rubric.md
tightens the prose and the honesty clause (§5) shrinks to nothing or disappears,
that's not tightening — that's the system becoming less honest about what it can't
verify. Guard this one specifically; it's the part most likely to be "simplified"
into non-existence by someone optimizing for shorter files without reading why it's
there.
