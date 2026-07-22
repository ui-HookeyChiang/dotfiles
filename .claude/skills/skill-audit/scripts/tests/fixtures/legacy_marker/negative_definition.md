---
name: example-skill
description: An example skill that uses the word "deprecated" in a definitional context that must NOT fire the legacy_marker detector.
---

# Example Skill

## Glossary

A **deprecated** feature is one whose use is discouraged because it is
slated for removal. Skills should annotate deprecated entries so consumers
know to migrate.

(The word "deprecated" appears in a definitional sentence — it is
documentation ABOUT deprecation, not a deprecation marker on the skill
itself. The LLM judge should classify this as not-a-marker.)
