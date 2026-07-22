---
name: property-skill
description: Synthetic fixture for the @property false-positive fix. Use when validating that @property accessors accessed via local instance vars are not flagged (c) zero-reader, while genuinely dead plain functions still are. Triggers on reachability property-accessor fixture checks.
---

# property-skill

Run the entry point:

```bash
python3 scripts/main.py
```

Each `item.prose_only_prop` reflects whether the item is active. (This dotted
attribute mention in prose is the only occurrence outside its definition; there
is no real `.py` access, so it must not count as a live edge.)
