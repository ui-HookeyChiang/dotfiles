# Grilling: final adopt/reject decision

Status: open
Labels: wayfinder:grilling
Parent: 2026-08-06-wayfinder-codebase-memory-mcp-map.md
Blocked-by: 2026-08-06-cmm-security-review.md, 2026-08-06-cmm-benchmark-large-repos.md, 2026-08-06-cmm-adoption-behavior.md

## Question

Synthesize all closed tickets into the destination decision: adopt or reject; if adopt — which repos, which mattpocock skill prose changes, and docs-layer (context.md/adr/spec) integration shape. Run /adversarial-review on the draft verdict before closing. Output is the decision document; execution of any integration edits is a fresh effort beyond this map.

- [ ] Pre-adoption verification (from security verdict 2026-08-08): confirm cmm respects .gitignore and does not index secrets/keys files (dotfiles run showed dir exclusion; secrets handling untested).

## Draft verdict v2 (2026-08-09, post adversarial-review — pending user sign-off)

Adversarial review (3 independent reviewers + domain-naive moderator; no finding dismissed) downgraded the draft from ADOPT to **CANDIDATE**, gated:

**Gate (do not adopt until):** pre-registered pilot on cpss-app AND one of debbox/debfactory — 8 hops-stratified queries via code-nav-eval, thresholds and per-repo language-mix measurement written down BEFORE the run (correctness >= native AND >=2x token cut at hops>=2, zero confident false negatives on function-pointer probes). Rationale: all five eval grounds were proxies; "evals show" was literally false for the target repos; debbox/debfactory are Makefile/shell-heavy build systems that may fall under the NEVER clause.

**Rules rewritten:**
1. Routing is language-of-TARGET, not repo allowlist: cmm answers only for C/statically-resolved symbols; queries touching python/shell/Makefile targets fall back native even inside allowlisted repos (debian/rules and helper scripts are guaranteed present there).
2. Mandatory invariant: any cmm negative ("no callers" / dead code) requires one native grep confirmation before any code action — the django-measured ruin channel.
3. Correctness claim reworded: token effect (2-4x at hops>=2 on statically-resolvable grounds) is robust; correctness margins are within single-flip noise at n=1, author-scored. Bash prohibition is predicted, not measured (dotfiles pilot superseded).

**Falsifiers (adoption becomes reversible):**
- Router replay test before enabling: 40 existing queries through the routing prose, >=80% correct routing floor (misroute measured 3.5x cost).
- 30-day telemetry review: zero cmm calls in transcripts -> REJECT (silent non-adoption is the most likely failure; prompting is the weakest lever per our own baselines research).
- One confirmed production false negative -> suspend cmm on that repo.
- Version bump or maintainer inactive 6 months -> re-run code-nav-eval on one C ground + cross-repo harness before the pin moves; treat the pin as an expiry, not a fixture.
- Staleness bound: index older than HEAD by >N commits (set in pilot) -> answers untrusted; re-index on checkout/pull in skill prose.

**Supply-chain hardening (accepted HIGH):** checksums/cosign live in the same attacker-controllable release pipeline — verify consistency, not authorship. Prefer build-from-source at an audited commit for company-repo use; add a one-script checker for the five security invariants.

**Echo-chamber close:** (1) The three-lens consensus on "targets unmeasured" is genuinely independent (different evidence paths), not correlated echo. (2) Collective blind spot named by the moderator: nobody challenged whether the EVAL QUERIES resemble real usage — the token-savings claim inherits that assumption; the pilot should log real queries for a week to check. (3) Structural bias: adversarial review has kill-bias — a defensible CANDIDATE verdict is also the reviewer-safe verdict; the pilot gate keeps it honest by making adoption cheap to re-earn. (4) Owner-only input: expected multi-hop queries/month on the three repos — only the user knows if that is 5 or 500, and the break-even flips on it.
