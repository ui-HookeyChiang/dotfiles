---
name: example-skill
description: An example skill citing an external standards document as "Amendment A3 to RFC 7231" — the B-prov pre-filter must NOT match because it is not an in-repo spec path.
expected: NEGATIVE — external RFC amendment, not an in-repo docs/spec/ citation; must NOT flag provenance_citation
---

# Example Skill

## HTTP redirect handling

When the skill fetches remote URLs for broken-link detection it follows
HTTP 3xx redirects up to a configurable hop limit (default 5). Permanent
redirects (301) are treated as broken links because the original URL in the
SKILL.md is stale. This behaviour aligns with the caching semantics defined in
Amendment A3 to RFC 7231.

Pass `--no-follow-redirects` to treat any non-2xx response as broken.
