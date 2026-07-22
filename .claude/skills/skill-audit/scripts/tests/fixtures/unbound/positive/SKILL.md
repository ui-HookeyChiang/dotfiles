---
name: positive
description: Use when testing the positive (true-positive) case for Detector 6. Has 5 unbound vars like skill-writer.
landing-group: workflow
---

# positive

## Phase 2a

```bash
source _shared/lib/sh/sandwich-trace.sh
write_gate_trace dogfood skill-writer "$SPEC_HASH" "$RUN" "$VERDICT" \
  "$(git rev-parse --git-common-dir)/flow-dev-sandwich.log" placement-scan "$DEPTH"
```

## Phase 6d

```bash
source _shared/lib/sh/sandwich-trace.sh
assert_gate_trace dogfood skill-writer "$SPEC_HASH" stop "$(git rev-parse --git-common-dir)/flow-dev-sandwich.log" "$DEPTH" || exit 1
echo "$TARGET"
```
