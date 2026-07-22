---
name: clean
description: Use when testing clean baseline for unbound-var detector. No unbound vars.
landing-group: workflow
---

# clean

## Workflow

```bash
MY_VAR=hello
echo "$MY_VAR"
export MY_EXPORT=world
echo "$MY_EXPORT"
```

Nothing unbound here.
