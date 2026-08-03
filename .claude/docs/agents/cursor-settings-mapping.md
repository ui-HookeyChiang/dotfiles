# Cursor settings mapping — Claude Code ↔ Cursor

Verified against `~/.cursor/` config tree, 2026-07-23. Cursor uses
`~/.cursor/cli-config.json` (JSON); Claude Code uses
`~/.claude/settings.json` (JSON).

---

## 1. Hooks registration

| Claude Code (`~/.claude/settings.json`) | Cursor |
|---|---|
| `hooks.<Event>[].hooks[].command` | Two formats coexist (verified 2026-07-23) |
| `hooks.<Event>[].matcher` | Same field in Claude-format `hooks.json` |
| `hooks.<Event>[].hooks[].timeout` | Same field in Claude-format `hooks.json` |

**Cursor hook formats:**

- **Claude-compatible** (`hooks.json`): identical schema —
  `hooks.<Event>[].hooks[].command` with `matcher`, `timeout`, `async`.
  Found in plugins (e.g. `~/.cursor/plugins/cache/.../hooks/hooks.json`).
- **Cursor-native** (`hooks-cursor.json`): simplified —
  `hooks.<event>[].command` (no nested `hooks[]` array, lowercase event
  names). Found alongside the Claude-compatible file in plugins.

**User-level hooks location:** `~/.cursor/managed/team_<id>/hooks/`
(currently empty on this install). Team ID from
`cli-config.json → authInfo.teamId`.

**Hook events:** Cursor supports `sessionStart` (verified in
`hooks-cursor.json`). Claude Code additionally fires `PreToolUse`,
`PostToolUse`, `SubagentStart`, `SessionEnd`. Cursor's coverage of
Claude Code hook events beyond `sessionStart` is unverified — the
mapping doc from the superpowers plugin shows only `SessionStart` in
Claude-format and `sessionStart` in Cursor-native format.

**Registration target:** for cross-harness hooks (path guard, etc.),
target the Claude-compatible `hooks.json` format in the managed hooks
directory. The `--register-cursor` flag merges into this location.

---

## 2. Permission model

| Claude Code (`~/.claude/settings.json`) | Cursor (`~/.cursor/cli-config.json`) |
|---|---|
| `permissions.allow[]` | `permissions.allow[]` (verified 2026-07-23) |
| `permissions.deny[]` | `permissions.deny[]` (verified 2026-07-23) |
| `defaultMode` (`"default"` / `"acceptEdits"` / `"bypassPermissions"`) | `approvalMode` (`"allowlist"`) (verified 2026-07-23) |

The `permissions.allow[]` / `permissions.deny[]` arrays use the same
`Tool(pattern)` syntax in both harnesses (e.g. `"Shell(ls)"`).
`install.sh --register-cursor` merges the repo template at
`hooks/cursor/cli-config.json` into `~/.cursor/cli-config.json`, adding the
shared deny rules without replacing unrelated Cursor CLI config.

Cursor adds `approvalMode` with at least `"allowlist"` — the full enum
is undocumented. Claude Code's `defaultMode` three-way split
(`default`/`acceptEdits`/`bypassPermissions`) has no verified Cursor
equivalent beyond `"allowlist"`.

---

## 3. Sandbox

| Claude Code | Cursor (`~/.cursor/cli-config.json`) |
|---|---|
| n/a (uses PreToolUse hooks for path guarding) | `sandbox.mode` (`"disabled"`) (verified 2026-07-23) |
| n/a | `sandbox.networkAccess` (`"user_config_with_defaults"`) (verified 2026-07-23) |

Cursor has a native sandbox mode. Claude Code relies on hooks
(`guard-agent-worktree.sh`) for path-level isolation. The sandbox
surfaces are not equivalent.

---

## 4. Model configuration

| Claude Code (`~/.claude/settings.json`) | Cursor (`~/.cursor/cli-config.json`) |
|---|---|
| `model` (string, e.g. `"claude-opus-4-8[1m]"`) | `model.modelId` / `model.displayModelId` (verified 2026-07-23) |
| n/a | `modelParameters.<modelId>[]` — per-model param arrays with `{id, value}` pairs (verified 2026-07-23) |
| n/a | `selectedModel` — active model + parameters (verified 2026-07-23) |

Cursor's model config is richer: per-model parameter arrays (thinking,
context window, effort, fast mode) vs Claude Code's single model string
with bracket notation.

---

## 5. Instruction files

| Claude Code | Cursor |
|---|---|
| `~/.claude/CLAUDE.md` (user-level) | No file-based user-level instruction surface (verified 2026-07-23) |
| Project `CLAUDE.md` / `AGENTS.md` | Project `AGENTS.md` (same via agentskills.io) |
| `@docs/agents/*.md` includes in CLAUDE.md | No `@`-include mechanism (verified 2026-07-23) |

Cursor's user-level instruction surface ("rules") is UI-driven, not a
file editable from CLI. The `--register-cursor` flag cannot inject
user-level instructions the way `--register-claudemd` does for Claude
Code. This is a gap.

Project-level instructions work via `AGENTS.md`, which both harnesses
read through the agentskills.io standard. The repo's existing
`AGENTS.md → CLAUDE.md` symlink covers project scope.

---

## 5.5. Cursor editor settings

Cursor's VS Code-compatible user settings live at
`~/.config/Cursor/User/settings.json`. `install.sh --register-cursor` merges
`hooks/cursor/user-settings.json` into that file. The template currently
persists:

- `terminal.integrated.shellIntegration.enabled: false` — prevents Cursor
  terminal shell integration from fighting tmux split scrollback.
- `cursor.cpp.experimental.agentParity: true` — local experiment marker for
  enabling/expecting the Cursor agent-parity axis.

---

## 6. Skills

| Claude Code | Cursor |
|---|---|
| `~/.claude/skills/<name>/SKILL.md` | `~/.cursor/skills-cursor/<name>/SKILL.md` (verified 2026-07-23) |
| `~/.agents/skills/<name>/SKILL.md` (agentskills.io) | Same — shared store (verified 2026-07-23) |
| SKILL.md frontmatter: `name`, `description`, `disable-model-invocation` | Same frontmatter fields (verified 2026-07-23) |

Both harnesses read the agentskills.io store (`~/.agents/skills/`).
Cursor also has its own skill directory (`~/.cursor/skills-cursor/`)
with a sync manifest (`.sync-manifest.json`). install.sh's agentskills
phase already populates the shared store; no Cursor-specific skill
installation is needed.

**`disable-model-invocation`:** honoured. Cursor's own built-in skills
use this frontmatter field (e.g. `~/.cursor/skills-cursor/review/SKILL.md`
has `disable-model-invocation: true`). Conclusion: the agentskills.io
standard is the mechanism; Cursor respects it. (Verified 2026-07-23.)
For skills that explicitly invoke other skills, use the inline fallback
contract in `docs/agents/skill-invocation.md`.

**No per-skill sidecar needed:** unlike Codex (which requires
`agents/openai.yaml` per ADR-0006), Cursor reads SKILL.md frontmatter
directly. See ADR-0009.

---

## 7. Commands / plugin-equivalent surface

| Claude Code | Cursor |
|---|---|
| Skills invoked via `/skill-name` | Skills invoked via `/skill-name` (same mechanism) |
| n/a | Built-in skills: babysit, canvas, create-hook, create-rule, create-skill, create-subagent, loop, review, etc. |

Cursor has no separate "commands" surface distinct from skills. The
skill mechanism IS the command-equivalent surface. OpenCode has a
separate plugins directory; Cursor does not — skills cover both
discovery and invocation.

---

## 8. Agent definitions

| Claude Code | Cursor |
|---|---|
| `~/.claude/agents/{scan,execute,decide,...}.md` | Project `.cursor/agents/{scan,execute,decide,...}.md` |

Cursor project subagent descriptors are generated from
`docs/agent-definitions/*.md` into `.cursor/agents/*.md`. The descriptor
frontmatter uses Cursor model IDs from `cross-cli-dispatch/bindings.tsv`,
tracked through `model-dispatch/runtime-model-pins.tsv`. Cursor model effort is
encoded in `model:` bracket parameters such as `gpt-5.3-codex[effort=low]`,
not in a separate `effort:` frontmatter field.

This is a model-pin surface, not a routing guarantee: Cursor still chooses a
subagent by descriptor matching unless the caller explicitly invokes one.

---

## 9. Attribution

| Claude Code | Cursor (`~/.cursor/cli-config.json`) |
|---|---|
| Co-Authored-By trailer (convention) | `attribution.attributeCommitsToAgent` (verified 2026-07-23) |
| n/a | `attribution.attributePRsToAgent` (verified 2026-07-23) |

Cursor has native attribution config for commits and PRs. Claude Code
uses a Co-Authored-By trailer convention with no settings-level toggle.

---

## detect-agents.sh paths

For ticket 04 (agent-parity cursor axis), the Cursor stanza in
`detect-agents.sh` should emit:

| Field | Path |
|---|---|
| `settings` | `~/.cursor/cli-config.json` |
| `instructions` | (none — no file-based user-level instructions) |
| `hooks` | `~/.cursor/managed/team_<id>/hooks/` |
| `skills` | `~/.cursor/skills-cursor/` + `~/.agents/skills/` (shared) |

Detection: `[ -d "$HOME/.cursor" ]` (presence of config directory).
Binary detection (`command -v cursor`) is unreliable — the AppImage
symlink can break while the config tree remains active.

---

## Gap column — Claude Code surfaces with no Cursor analogue

| Claude Code surface | Cursor status | Notes |
|---|---|---|
| User-level `CLAUDE.md` | **GAP** | Cursor rules are UI-only, not file-based |
| `@`-includes in CLAUDE.md | **GAP** | No include mechanism |
| `PostToolUse` hook event | **UNVERIFIED** | Only `sessionStart` confirmed |
| `SubagentStart` hook event | **UNVERIFIED** | Only `sessionStart` confirmed |
| `SessionEnd` hook event | **UNVERIFIED** | Only `sessionStart` confirmed |
| `PreToolUse` hook event | **UNVERIFIED** | Only `sessionStart` confirmed |
| `permissions.deny[]` tool patterns | Partial | Array exists but population/enforcement unverified |
| `defaultMode` three-way split | **GAP** | `approvalMode` has no verified equivalents for `acceptEdits`/`bypassPermissions` |
| Per-project settings (`projects` key) | **GAP** | No equivalent in `cli-config.json` |
| OS-level sandbox | Different | Cursor has native `sandbox.mode`; Claude Code uses hooks |

---

## Summary table

| Concern | Claude Code key | Cursor key | Parity |
|---|---|---|---|
| Hook registration | `hooks` in `settings.json` | Claude-format `hooks.json` or Cursor-native `hooks-cursor.json` in `~/.cursor/managed/team_<id>/hooks/` | Partial |
| Permission allowlist | `permissions.allow[]` | `permissions.allow[]` in `cli-config.json` | Match |
| Permission denylist | `permissions.deny[]` | `permissions.deny[]` in `cli-config.json` | Match (shape) |
| Approval mode | `defaultMode` | `approvalMode` | Partial |
| Sandbox | hooks-based | `sandbox.mode` | Different |
| Model | `model` (string) | `model` + `modelParameters` (structured) | Different |
| User instructions | `~/.claude/CLAUDE.md` | UI rules only | GAP |
| Project instructions | `AGENTS.md` / `CLAUDE.md` | `AGENTS.md` (agentskills.io) | Match |
| Agent definitions | `~/.claude/agents/*.md` | Project `.cursor/agents/*.md` | Partial: generated for Cursor tiers with binding evidence; routing remains descriptor-driven |
| Skills | `~/.claude/skills/` + `~/.agents/skills/` | `~/.cursor/skills-cursor/` + `~/.agents/skills/` | Match |
| `disable-model-invocation` | SKILL.md frontmatter | SKILL.md frontmatter (agentskills.io) | Match |
| Sidecar | `agents/openai.yaml` (Codex only) | Not needed | n/a |
| Attribution | convention | `attribution.*` in `cli-config.json` | Different |
