---
name: example-skill
description: An example skill demonstrating a blockquote flow-enhancement marker for an unbuilt feature that the LLM could read as live behavior.
expected: POSITIVE — kind=unbuilt; no scripts/ backing this behavior; consider-removing
---

# Example Skill

## Output formatting

The skill emits a Markdown table of findings sorted by severity.

> **Flow enhancement:** When the composite score exceeds 80, the skill will
> automatically open a flow-dev spec draft and pre-fill the affected line
> ranges so the user can approve without any manual copy-paste.

Current output always goes to stdout regardless of composite score.
