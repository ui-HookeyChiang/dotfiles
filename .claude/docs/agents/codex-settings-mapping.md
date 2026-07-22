# Codex settings mapping — Claude Code ↔ Codex CLI

Codex CLI 0.144.6. Claude Code uses `~/.claude/settings.json` (JSON);
Codex uses `~/.codex/config.toml` (TOML) + `~/.codex/hooks.json` (JSON).

---

## 1. Hooks registration

| Claude Code (`~/.claude/settings.json`) | Codex CLI (`~/.codex/hooks.json`) |
|---|---|
| `hooks.<event>[].hooks[].command` | `hooks.<event>[].hooks[].command` |
| `hooks.<event>[].matcher` | `hooks.<event>[].matcher` |
| `hooks.<event>[].hooks[].timeout` | `hooks.<event>[].hooks[].timeout` |
| `hooks.<event>[].hooks[].statusMessage` | `hooks.<event>[].hooks[].statusMessage` |

The JSON schema is identical. The only difference is the file path.

**Hook events supported by Codex (≥ v0.143.0):** `PreToolUse`, `SubagentStart`.
Claude Code additionally fires `PostToolUse`, `SessionStart`, `SessionEnd`.

**Codex-only PreToolUse fields** not present in Claude Code:
- `turn_id` — turn counter within the session
- `permission_mode` — Codex approval policy in effect for this turn
- `model` — model name used for the turn

**Tool name differences:** Codex uses `apply_patch` where Claude Code uses
`Edit`/`Write`/`MultiEdit`/`NotebookEdit`. A matcher that needs to cover both
harnesses must include `apply_patch` (see repo `hooks/codex/hooks.json`).

**Registration:** install user-level (`~/.codex/hooks.json`), not project
`.codex/hooks.json`. Project-layer hooks require `projects.<path>.trust_level =
"trusted"` in `config.toml` and are unreliable for cross-repo guards.
The repo ships an absolute-path template at `hooks/codex/hooks.json`; the
installed copy is `~/.codex/hooks.json` (see ticket
`docs/ticket/2026-07-21-codex-hooks-registration.md`).

---

## 2. Permission mode

| Claude Code (`~/.claude/settings.json`) | Codex CLI (`~/.codex/config.toml`) |
|---|---|
| `defaultMode` (`"default"` / `"acceptEdits"` / `"bypassPermissions"`) | `approval_policy` (`"suggest"` / `"auto-edit"` / `"full-auto"`) |
| n/a | `sandbox_mode` (`"danger-full-auto"` enables full sandbox bypass) |

Approximate equivalences:

| Claude Code `defaultMode` | Codex `approval_policy` | Notes |
|---|---|---|
| `"default"` | `"suggest"` | every tool call prompted |
| `"acceptEdits"` | `"auto-edit"` | file edits auto-approved, shell prompted |
| `"bypassPermissions"` | `"full-auto"` | all tool calls auto-approved |

Codex `approval_policy` can also be set per-project:

```toml
[projects."/path/to/repo"]
# config key: projects.<path>.approval_policy
approval_policy = "suggest"
```

Codex `sandbox_mode` enables OS-level sandboxing (macOS Seatbelt / Linux
namespaces). No Claude Code equivalent; the agent worktree guard
(`hooks/guard-agent-worktree.sh`) is the Claude Code path-level substitute.

---

## 3. Filesystem allowlist

| Claude Code (`~/.claude/settings.json`) | Codex CLI (`~/.codex/config.toml`) |
|---|---|
| `permissions.allow[]` — tool + path patterns | `permissions.<profile>.filesystem[]` — path/glob allowlist |
| `permissions.deny[]` — explicit denials | (no native deny list; use hooks to block) |

Claude Code example:
```json
{
  "permissions": {
    "allow": ["Read(~/.claude/**)", "Edit(~/projects/**)"],
    "deny": ["Edit(~/.worktrees/**)"]
  }
}
```

Codex equivalent (config key: `permissions.<profile>.filesystem`):
```toml
[permissions.default]
# config key: permissions.default.filesystem
filesystem = [
  "~/.claude/**",
  "~/projects/**"
]
```

Codex does not have a native deny list in `config.toml`. Denied paths must be
enforced via `PreToolUse` hooks (see `hooks/block-main-edit.sh` and
`hooks/guard-agent-worktree.sh` which apply to both harnesses).

---

## 4. Project trust

| Claude Code (`~/.claude/settings.json`) | Codex CLI (`~/.codex/config.toml`) |
|---|---|
| `projects` — per-repo settings object | `projects.<path>.trust_level` |

Claude Code `projects` holds arbitrary per-repo overrides (mcpServers, permissions, etc.).
Codex `projects.<path>.trust_level` is a single enum:

| Value | Effect |
|---|---|
| `"trusted"` | project-layer `.codex/` hooks and config are loaded |
| `"untrusted"` | project-layer config ignored; user-layer config only |

Config key: `projects.<path>.trust_level` (path is the absolute repo root).

---

## 5. Ready-to-paste `config.toml` snippet — filesystem-deny profile

Covers the three protected path classes in this repo: `.worktrees/`,
`.claude/`, and dotfiles (`~/.*`). Install by merging into
`~/.codex/config.toml` (does not overwrite existing keys; TOML table blocks
are additive).

**Note:** `install.sh` does NOT write `~/.codex/config.toml` automatically.
Apply this snippet manually. A `--register-codex` opt-in flag is a possible
follow-up (see spec `docs/spec/2026-07-21-codex-compat-hooks-settings.md`,
Decisions).

```toml
# config key: permissions.<profile>.filesystem
[permissions.default]
filesystem = [
  "~/**"
]

# config key: permissions.<profile>.filesystem (deny via hooks, not this list)
# Codex has no native deny list — blocked paths are enforced by PreToolUse hooks:
#   ~/.codex/hooks.json → ~/.claude/hooks/block-main-edit.sh
#   ~/.codex/hooks.json → ~/.claude/hooks/guard-agent-worktree.sh

# config key: projects.<path>.trust_level
[projects."/home/hookey/.claude/skill-dev"]
trust_level = "trusted"

# config key: approval_policy
# Set per-project if you want stricter prompting in this repo:
# approval_policy = "suggest"
```

Validate with `python3 -c "import tomllib; tomllib.loads(open('snippet.toml').read()); print('OK')"` (Python 3.11+).

---

## Summary table

| Concern | Claude Code key | Codex config key |
|---|---|---|
| Hook registration | `hooks` in `~/.claude/settings.json` | `hooks` in `~/.codex/hooks.json` |
| Default permission mode | `defaultMode` | `approval_policy` |
| OS-level sandbox | n/a | `sandbox_mode` |
| Filesystem allowlist | `permissions.allow[]` | `permissions.<profile>.filesystem[]` |
| Filesystem denylist | `permissions.deny[]` | hooks only (`PreToolUse`) |
| Project trust | `projects` | `projects.<path>.trust_level` |
| Per-project approval | `projects.<path>.defaultMode` | `projects.<path>.approval_policy` |
