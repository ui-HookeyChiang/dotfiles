---
name: guard
description: Use when testing that operator param-expansions do not self-flag in Detector 6.
landing-group: workflow
---

# guard

## Workflow

```bash
: "${MAYBE:?set by harness}"
echo "${MAYBE:-default}"
```
