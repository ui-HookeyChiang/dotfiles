---
name: fp-refine-skill
description: Synthetic fixture for the deadcode-audit FP-refine regression. Use when validating cross-script field pairing, prose-root weak edges, and intra-script function liveness. Triggers on reachability fixture checks.
---

# fp-refine-skill

Run the producer:

```bash
bash scripts/producer.sh
```

After Phase 0, `helper-prose.sh` re-validates the emitted lock under its own
flock (it is invoked later in Phase 2). See the schema in
[references/schema.md](references/schema.md).
