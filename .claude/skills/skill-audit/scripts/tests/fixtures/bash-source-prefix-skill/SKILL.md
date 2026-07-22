---
name: bash-source-prefix-skill
description: Synthetic fixture exercising the ${BASH_SOURCE[0]%/*}/ dynamic source-path form. Use when validating that a lib sourced via a BASH_SOURCE parameter-expansion dir prefix is not flagged dead. Triggers on reachability fixture checks.
---

# bash-source-prefix-skill

Run the entry script:

```bash
bash scripts/entry.sh
```
