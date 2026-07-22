# flow-dev fixture (Task 22 testdata)

Regression anchor for G1. Do not edit wording below.

## Two-repo debfactory flow

When a change spans both a source repository and the debfactory
packaging repo, you must land the source repo pull request first,
so that the downstream debfactory continuous-integration job can
observe the new upstream dependency on its next build.
The debfactory pull request is opened only after the source merge
completes, and it carries a manual version bump that points the
package metadata at the just-landed source commit.
Skipping this ordering leaves the debfactory build pinned to a
stale revision, which surfaces as an opaque dependency mismatch
later in the release pipeline and forces a manual rebase to recover.
