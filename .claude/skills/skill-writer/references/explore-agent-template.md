# Explore Agent Sweep Template

```
Launch 1 agent (subagent_type: Explore, thoroughness: very thorough):
  Skill request: <user's description>
  Prefilter shortlist (focus here): <brief.shortlist>
  1. List skills: ls */SKILL.md
  2. Compare each description to the request
  3. grep -l "<keywords>" */SKILL.md for keyword overlap
  4. Check _shared/ for existing utilities
  5. Check cross-skill flows in orchestrators (flow-dev etc.)
  6. When the change touches ≥ 2 SKILL.md: also flag paraphrased /
     cross-file duplication (the cross-skill "G1" signal), not just
     verbatim keyword overlap.
  7. Cross-reference cycle: the pre-pass already computed the candidate's
     cycle status exactly (`candidate_cycles` in the brief). Do NOT re-trace —
     instead, if a candidate cycle was reported, judge whether it is a real
     infinite-delegation risk (A delegates to B which delegates back) vs a
     benign prose reference (one names the other in docs). Report CIRCULAR only
     for the former.
  Report: DUPLICATE | PARTIAL OVERLAP | REFACTOR OPPORTUNITY | CIRCULAR | NO OVERLAP
  Cite the specific SKILL.md lines that overlap.
```
