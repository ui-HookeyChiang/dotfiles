# Triage labels

The five canonical triage roles → the `Status:` strings written in each
`docs/ticket/` file. `triage` drives issues through these; `to-tickets` tags
new issues with the agent-ready string.

| Role | Status string | Meaning |
|------|---------------|---------|
| needs-triage | `needs-triage` | Maintainer evaluation required (default for new, unscoped issues). |
| needs-info | `needs-info` | Awaiting reporter input; blocked until clarified. |
| ready-for-agent | `ready-for-agent` | Fully specified, AFK-ready — an agent can pick it up with no human context. |
| ready-for-human | `ready-for-human` | Needs human implementation/judgment; not agent-safe. |
| wontfix | `wontfix` | No action planned (terminal rejection state). |

Apply a role by writing/editing the `Status:` line near the top of the issue
file, e.g. `Status: ready-for-agent`.

## Completion

Pocock defines no `done` triage role — upstream signals completion via GitHub
issue-closed. The local-markdown backend has no close, so **completion is
`Status: done`**. This repo treats `done` as the terminal success state
(distinct from `wontfix` = terminal rejection).
