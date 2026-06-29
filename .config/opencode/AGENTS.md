# Rules

## Workflow routing

For code changes, invoke `stacking-dev` (it handles spec creation if missing) — it sizes the work and routes all changes, including small single-file fixes, through the full flow.
For non-code work (questions, debug, config, deploy, perspective audits), use the matching domain skill — not stacking-dev.
superpowers skills are subordinate — used within stacking-dev's phases, not directly.
Always delegate execution to subagents.

## Safety

**Never push directly to main** — all changes go through PRs.

**Release exception:** `semver-release` may push directly to main, but ONLY commits limited to `debian/changelog`, `releases/`, and version tags (`v*`). Any release that also needs code changes: those land via PR first, then `semver-release` tags the merged result.

**Never merge PRs without explicit user consent.**

# Delegation

The main agent orchestrates and handles single-file changes directly (session model). Everything else — multi-file changes, code review, exploration — delegates to a subagent on `claude-sonnet-4-6`.

# Language

Reply to the user in **Traditional Chinese (繁體中文)** rather than Simplified Chinese. Keep technical terms, code symbols, command names, file paths, and library names in English (e.g. don't translate `git rebase`, `setMyCommands`, `SessionManager`).

# PR title format

Ubiquiti commit log style per [Confluence](https://ubiquiti.atlassian.net/wiki/spaces/UDX/pages/2526740772).

**Debbox / Debfactory:** `[JIRA ID] <type>: <item> -- <summary>`

- **type** — lowercase: `package`, `kernel`, `conf`, `framework`, `builder`,
  `image`, `initramfs`, `bootloader`, `bootstrap`, `overlay`, `ci`, `tools`,
  `updater`, `include`, or product/platform names (`efg`, `alpine`, `sysid`).
  Debfactory mostly uses `package`; also `cm`, `ci`.
- **item** — system/product/package name, lowercase, comma-separated if multiple.
- **summary** — lowercase, no trailing period, explains what/why/how.

**Separate projects (ustd, unifi-drive-config, etc.):** `[JIRA ID] <type>: <summary> (#merge number)`
- Uses conventional-commit types: `fix`, `feat`, `ci`, `chore`.

**API call:** always `gh api PATCH` — **never** `gh pr edit --title` (silently capitalizes first letter):
```bash
gh api "repos/{owner}/{repo}/pulls/{number}" -X PATCH \
  -f title="[${KEY}] ${TYPE}: ${ITEM} -- ${SUMMARY}"
```
