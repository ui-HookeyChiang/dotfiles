# Executor fixture design

An executor fixture = one buggy source file + one immutable test suite +
one golden fix, all under `fixtures/executor-<tier>/`.

Rules (enforced by `scripts/tests/test-fixtures.sh`):

1. **Buggy fails, golden passes.** `run-tests.sh` against the shipped buggy
   file must fail; against `golden.sh` must pass every test. No fixture ships
   without a verified golden — otherwise "unsolvable" and "model failed" are
   indistinguishable.
2. **Marker assert.** The suite prints `pass=N fail=M` as its last line; the
   runner records it (`test_last`). Any batch whose test_last total doesn't
   match the tier's suite is invalid.
3. **Test suite is a forbidden file.** Runner sha256s it before/after;
   mutation = touched_forbidden, auto-fail.

## Difficulty ladder (observed 2026-07)

| Tier | Shape | Result |
|---|---|---|
| v1 | 2 bugs (quoting, wrong cut field), 3/10 failing | all models pass — ceiling |
| v2 | 3 bugs (+case fallthrough, cut -s semantics), 5/10 failing | still ceiling |
| v3 | 5 functions, interaction chain (wt_id fails via 3 underlying bugs), 8/14 failing | still ceiling — Haiku-low floor is BELOW this class |

Knobs that did NOT discriminate: more failing tests, more bugs, cross-function
propagation. Untried knobs for a v4: multi-file scope (root cause in file A,
tests exercise file B), ambiguous spec (two valid fixes, only one satisfies an
unstated invariant), larger fixture (500+ lines of distractor code).
