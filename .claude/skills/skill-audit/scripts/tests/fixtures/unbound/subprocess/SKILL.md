---
name: subprocess
description: Use when testing subprocess (bash X.sh) does NOT silence unbound vars for Detector 6.
landing-group: workflow
---

# subprocess

## Workflow

```bash
bash scripts/helper.sh
echo "$FOO"
```
