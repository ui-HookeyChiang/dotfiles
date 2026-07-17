# Shell Tools

When using Bash for tasks without a dedicated tool:

| Task | Use |
|------|-----|
| Search file contents | `Grep` tool (ripgrep) or `rg` |
| Find files by name | `fdfind` (Linux) / `fd` (macOS) |
| Code structure | `ast-grep` |
| JSON | `jq` |
| YAML/XML | `yq` |
| Interactive select | `fzf` |

`grep`/`egrep`/`fgrep`/`find` are `deny`-blocked — use the table above, don't reach for `bash -c` or a pipeline to route around it. Note: the `fd` alias from `.zshrc` doesn't expand in the Bash tool (non-interactive zsh) — call the binary directly by its OS-specific name.
