---
name: example-skill
description: An example skill demonstrating a prose-context TBD marker.
---

# Example Skill

## Caching strategy

TBD: we have not decided whether to use disk cache or memcached for the
cross-skill fan-out path. For now the implementation skips caching.

(The TBD lives in H2 prose body — not a list item, not inside a fence —
so the detector treats it as a legacy/incomplete marker.)
