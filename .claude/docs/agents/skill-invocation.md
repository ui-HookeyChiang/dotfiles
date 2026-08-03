# Skill-Invoking Skills

When a skill explicitly dispatches another skill (`Skill <name>`),
`disable-model-invocation: true` means "do not auto-trigger", not
"orchestrators may not use it".

Fallback for harnesses that block explicit dispatch: read the target `SKILL.md`
and follow inline.

Keep harness evidence in dogfood reports or mapping docs; orchestrator bodies
should carry only the fallback line.
