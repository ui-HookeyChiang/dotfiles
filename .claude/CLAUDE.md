# Rules

Invoke `stacking-dev` for all requests. Always delegate execution to subagents.

**Never push directly to main** — all changes go through PRs.

**Never merge PRs without explicit user consent.**

# Delegation

The main agent orchestrates — it delegates and decides, never executes directly.

**Handoff:** pass context in the subagent's prompt for one-shot tasks. Use CONTEXT.md for worktree-based agents that need persistent context. Subagents return results directly — don't poll files for output.

# Shell Tools

When using Bash for tasks without a dedicated tool:

| Task | Use | Never use |
|------|-----|-----------|
| Search file contents | `Grep` tool (ripgrep) or `rg` | `grep`, `egrep`, `fgrep` (denied) |
| Find files by name | `fdfind` (Linux) / `fd` (macOS) | `find` (denied) |
| Code structure | `ast-grep` | |
| JSON | `jq` | |
| YAML/XML | `yq` | |
| Interactive select | `fzf` | |

`grep`/`find` are denied in settings.json. Don't try `bash -c` or pipeline workarounds — use the alternatives above. Note: `fd` alias from `.zshrc` doesn't expand in Bash tool (non-interactive zsh) — call the binary directly by its OS-specific name.

# Language

Reply to the user in **Traditional Chinese (繁體中文)** rather than Simplified Chinese. Keep technical terms, code symbols, command names, file paths, and library names in English (e.g. don't translate `git rebase`, `setMyCommands`, `SessionManager`).

# Sandbox: protected paths

Claude Code's built-in sensitive-file detection (not settings.json `deny`) gates `Edit`/`Write` and `> redirect`/`sed -i` on all paths.

| Action on protected path | Result |
|---|---|
| `Edit` / `Write` tool | Dialog (need click) |
| Bash `> file` truncate, `sed -i` | Dialog (need click) |
| Bash `/bin/cat >> file` (append) | **Allowed**, append-only |
| `python3` / `node` direct file write | **Allowed**, full rewrite |

**SOPs**:
1. **Full rewrite preferred**: use `python3 << 'PYEOF' ... PYEOF` heredoc with `Path(...).write_text(...)` or `json.dump(...)` — works for any in-place modification, not just append.
2. **Append-only path** (`/bin/cat >> file`) still works for additive edits; remember `/bin/cat` not `cat` (zsh aliases `cat=bat`).
3. Chat "allow" ≠ dialog click; stop retrying after first deny — switch tool, don't tweak parameters.
4. Always backup first: `cp <file> /tmp/<file>.bak-$(date +%s)` before Python rewrite, since there's no dialog safety net.
5. Skill rewrites: park at `docs/specs/proposed/<slug>-DRAFT.md` with BEGIN/END markers — Python rewrite of skill files still works but DRAFT-then-merge keeps history clean.
