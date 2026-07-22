# Senior Engineer Filter

Apply these 5 questions to every candidate comment before posting.
A comment that fails any question is **auto-dropped** — do not post it.

---

## The 5 Questions

### Q1: Senior Test
> "Would a senior engineer on this team call this out in a face-to-face review?"

If the answer is "probably not" or "it depends on preference" — drop it.
Senior engineers focus on correctness, safety, and architectural risk.
They do not comment on style preferences unless the style creates bugs.

### Q2: Linter Test
> "Would a linter, typechecker, or compiler catch this automatically?"

If yes — drop it. Assume CI runs linting, type-checking, and compilation.
Examples: missing imports, type errors, unused variables, formatting,
indentation, import ordering, trailing whitespace.

### Q3: Blame Test
> "Did the PR author introduce this, or was it pre-existing?"

Only comment on lines the author actually changed in this PR.
Run `git diff origin/<base>..HEAD` to identify changed lines.
Pre-existing issues are out of scope — drop them.

### Q4: Actionable Test
> "Does this comment give the author a concrete, specific action to take?"

Vague comments ("Consider refactoring this", "This could be better") — drop.
Every comment must state: what the problem is, why it matters, and
(where possible) a concrete fix or `suggestion` block.

### Q5: Dedup Test
> "Has the same issue already been raised — either in a posted comment OR in another candidate from this same review run?"

Run **two passes**:

- **PASS 1 (historical)**: check existing same-author comments on the
  same `(file, line)` via the API call below. If any historical body has
  Jaccard similarity > 70% with the new candidate body, drop.
- **PASS 2 (in-batch)**: for the candidates that survive PASS 1, compute
  Jaccard pairwise on candidates that share the same `(file, line)` key
  — **including `(file, null)` for file-level findings**. For each pair
  with Jaccard > 70%, drop the candidate with the lower Impact Score.
  Tie-break: drop the later one in scoring order.

The in-batch pass exists because the historical API call returns an empty
set for findings that nobody has posted yet, so two candidates raised in
the same review run would each pass PASS 1 and produce a visible duplicate.

---

## Auto-Drop List

Always drop comments about the following — no exceptions:

| Category | Examples |
|----------|---------|
| Missing docstrings | "Add a docstring to this function" |
| Naming conventions | "Rename `x` to `xCoordinate`", "Use camelCase" |
| Import ordering | "Sort imports alphabetically" |
| Indentation / whitespace | "Fix indentation", "Remove trailing space" |
| "Consider…" suggestions | "Consider using a map here", "Consider extracting this" |
| Missing tests (general) | Unless CLAUDE.md explicitly mandates test coverage for this path |
| Pre-existing code | Anything not changed in this PR's diff |
| False SOLID violations | OCP/SRP issues in code the author didn't touch |

---

## Noise Budget by PR Size

Cap the total number of inline comments based on diff size:

| PR diff size | Max inline comments |
|--------------|-------------------|
| < 100 lines  | 5 comments        |
| 100–500 lines | 10 comments      |
| > 500 lines  | 15 comments       |

When candidates exceed the budget:
1. Sort remaining candidates by Impact Score (descending)
2. Post only the top N (budget cap)
3. Log the dropped count in the QA summary (not as a PR comment)

---

## Dedup API Call

Both passes share this Jaccard computation:

```
jaccard(a, b) = |tokens(a) ∩ tokens(b)| / |tokens(a) ∪ tokens(b)|
```

### PASS 1 — Historical

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments \
  --jq '[.[] | select(.path == "FILE" and .line == LINE and .user.login == "AUTHOR")]'
```

`line == null` is a valid filter value (file-level scope). Drop the candidate if any historical body scores `jaccard > 0.70`.

### PASS 2 — In-batch

```
for group in groupBy(candidates_after_PASS_1, key=(path, line)):
    for a, b in pairs(group):
        if jaccard(a.body, b.body) > 0.70:
            drop(min(a, b, key=lambda c: (c.impact_score, c.scoring_order)))
```

`(path, null)` is a valid group. PASS 2 closes the case where two
candidates from the same review run both pass PASS 1 against empty
history and produce a visible duplicate.

### Worked example — file-level findings (ubios-udapi-server#3910)

Two candidates, same path, both `line=null`, both warning of use-after-free on `host_ref` in async lambda (different wording, impacts 80 vs 75). PASS 1 both pass (no prior comments). PASS 2 same key `(domain-resolver.cpp, null)`, `jaccard ≈ 0.74` > 0.70 → drop impact-75. One finding posted.
