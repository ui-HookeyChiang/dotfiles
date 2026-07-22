# ubiquiti-flow fixture (Task 22 testdata)

Paraphrased counterpart of skill-a; same meaning, different wording.

## Ordering the source merge before the package merge

For changes that touch a source codebase together with its
debfactory packaging counterpart, the source repository pull
request has to merge ahead of the debfactory pull request.
That ordering lets the debfactory build pipeline pick up the
freshly published dependency on its next incremental run.
Once the source merge is in, the packaging pull request can be
raised with a version bump that points at the new source commit.
Reversing the sequence locks debfactory to the previous release
hash, so the build reports a confusing dependency-resolution
error and the only fix is to redo the merge on top of source.
