---
name: intra-file-skill
description: Synthetic fixture for the intra-file-caller deadcode fix. Use when validating that a function called only within its own (non-live) module is NOT flagged zero-reader, while a function with no caller anywhere still flags. Triggers on reachability intra-file-edge fixture checks.
---

# intra-file-skill

Run the entry point:

```bash
python3 scripts/audit.py
```
