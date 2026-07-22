# Fusion Regression Test Spec

Validates that Phase 3.5 (Layer A), Gate A, Gate C, and Gate D all behave correctly.

**To run:** execute `./run-fusion-regression.sh` from this directory (or pass the full path).
The script is the test — it produces `[PASS]`/`[FAIL]` output and exits non-zero on any failure.
This markdown is the spec; it describes what each test exercises and why.

```bash
cd code-review/evals
./run-fusion-regression.sh
echo "exit: $?"
```

---

## Test 1: Phase 3.5 Layer A — Pre-Flight Line Validation

**What it exercises:**
Layer A's Gate 1 (hunk-range check) and Gate 2 (added-line check) from Phase 3.5 of SKILL.md.

**Fixture:**
A synthetic `pulls/{n}/files` JSON with one file, one hunk, and two candidate comments:
- Candidate A targets an added (`+`) line inside the hunk — should pass both gates.
- Candidate B targets a context (` `) line inside the same hunk — should be dropped by Gate 2.

**Why it matters:**
The original Test 1 used PR #321 (a markdown cleanup with 0 code candidates), so Phase 3.5
was never reached. This synthetic fixture ensures the gate logic is actually invoked and
produces the correct pass/drop split.

**Assertions:**
- 1 comment survives both gates (Candidate A, added `+` line).
- 1 comment is dropped silently (Candidate B, context ` ` line).

---

## Test 2: Gate C — Concurrent Lockfile Prevention

**What it exercises:**
Gate C from Phase 1 of SKILL.md: the `flock`-based lockfile that prevents two concurrent
code-review invocations from running simultaneously on the same PR.

**Implementation:**
Two real `bash -c '...'` background processes both attempt `flock -n 9` on the same lockfile.
Process A gets a 0.1s head start. The test waits for both to complete and reads their result files.

**Why it matters:**
The original Test 2 wrote a fake PID into a lockfile in the same shell — no concurrency at all.
This test spawns real OS-level processes with real file locking.

**Assertions:**
- Exactly one process writes `acquired` (won the lock).
- Exactly one process writes `lock held — skipping` (lost the race).
- Stale lock (age > 1800s, via `touch -d "31 minutes ago"`) is auto-removed by cleanup logic.

---

## Test 3: Gate A — Bot Review Detection

**What it exercises:**
Gate A's `jq` filter from Phase 1 of SKILL.md: selecting recent bot reviews
(`github-actions[bot]` or `claude[bot]`) within the last 1 hour.

**Fixture:**
A JSON array matching the shape of the real `gh api .../pulls/{n}/reviews` response
(fields: `id`, `user.login`, `submitted_at`, `state`, `body`) with:
- `claude[bot]` review 40 minutes ago — inside the 1h window → should be selected.
- `alice` review 40 minutes ago — human, not a bot → should be ignored by the filter.
- `github-actions[bot]` review 2 hours ago — outside the 1h window → should be dropped.

**Assertions:**
- Filter returns exactly 1 entry.
- The matched entry is `claude[bot]` (40m ago).
- `github-actions[bot]` (2h ago) is not included.

---

## Test 4: Gate D — Jaccard Deduplication (Q5 of Senior Engineer Filter)

**What it exercises:**
Q5 of the senior-engineer-filter: "Does a same-author comment on (file, line) already exist
with Jaccard similarity >70%? If yes → drop."

**Implementation:**
Python tokenizer: lower-case, split on non-alpha, remove stop words and single-char tokens.
Jaccard = |A∩B| / |A∪B| on the resulting token sets.

**Test pairs:**
- Pair (A, B): near-identical comments about null-check / segfault on the same line.
  Expected Jaccard > 70% → verdict `dedup`.
- Pair (A, C): null-check vs. buffer-size validation — completely different topics.
  Expected Jaccard < 70% → verdict `keep`.
- Pair (D, E): "Fix this." vs. "Fix it." — 2-word comments that reduce to a single token
  after stop-word removal. This pair exercises a known limitation: Jaccard is unreliable
  when fewer than 3 content tokens survive. The test prints a warning but does not assert
  on this pair.

**Known limitation (flagged in runner output):**
Short comments (< 3 meaningful tokens) should use a minimum-token-count guard in production,
falling back to raw string equality when the token count is too low for Jaccard to be
meaningful.

---

## Removed from previous version

- Self-declared `RESULT: PASS` labels — the runner produces verdicts at runtime.
- Fake-PID concurrent simulation — replaced by real background processes.
- Zero-candidate Phase 3.5 "test" — replaced by a synthetic 2-candidate fixture.
