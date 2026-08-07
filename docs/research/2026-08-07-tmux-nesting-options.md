# Research: tmux two-layer nesting options under oh-my-tmux

Status: done
Ticket: docs/ticket/2026-08-07-research-tmux-nesting-options.md (branch `wayfinder-tmux-nvim-map`)
Date: 2026-08-07
Environment probed: tmux 3.4 (`/opt/homebrew/bin/tmux -V`)

## Context — repo's current setup

- oh-my-tmux lives at `.config/tmux` (submodule, gpakosz/.tmux). `install.sh`
  whitelists it in `DIRS` (install.sh:106-109) and symlinks it to
  `~/.config/tmux`.
- User customization is repo-root `.tmux.conf.local`, symlinked INTO the
  submodule working tree via `SUBMODULE_OVERRIDES=(".tmux.conf.local:.config/tmux/.tmux.conf.local")`
  (install.sh:111-123) by `link_submodule_override` (install.sh:679-698). This
  exact path is mandatory: oh-my-tmux's `.tmux.conf` forces
  `TMUX_CONF_LOCAL="$TMUX_CONF.local"` when unset (.config/tmux/.tmux.conf:156-157)
  and then `run '"$TMUX_PROGRAM" -S #{socket_path} source "$TMUX_CONF_LOCAL"'`
  (.tmux.conf:160) — the `.local` is sourced AFTER the main conf, so anything
  in it wins.
- oh-my-tmux keeps `C-b` as primary prefix and adds `set -g prefix2 C-a`
  plus `bind C-a send-prefix -2` (.config/tmux/.tmux.conf:26-27; README.md
  "C-a acts as secondary prefix, while keeping default C-b prefix").
- `.tmux.conf.local` already uses runtime conditionals for cross-platform
  behavior: `if-shell 'command -v pbcopy ...'` and an `SSH_CONNECTION` check
  for xclip (.tmux.conf.local:9-16) — precedent for option (3).
- One shared `.tmux.conf.local` is deployed everywhere; install.sh has no
  per-host parameterization today.

## Findings

### (1) Distinct inner/outer prefixes

tmux man (OPTIONS): `prefix key` — "Set the key accepted as a prefix key …
can be set to the special key 'None'"; `prefix2 key` — "a secondary key
accepted as a prefix key. Like prefix, prefix2 can be set to 'None'."

Options:

- **a. Different prefix per layer.** Outer (mac) keeps `C-b`/`C-a`; inner
  (server) sets e.g. `set -g prefix C-s` (or keeps `C-b` and outer moves).
  Under oh-my-tmux this is one line in the `.local` file, but it must be
  conditional per host (see (3)) since both layers share the same repo file.
  Also unbind the stale default: `unbind C-b; set -g prefix C-s; bind C-s send-prefix`.
- **b. Double-tap passthrough.** Keep identical prefixes on both layers and
  reach the inner tmux by pressing the prefix twice: oh-my-tmux already binds
  `bind C-a send-prefix -2` (.tmux.conf:27); adding `bind C-b send-prefix`
  in `.local` forwards `prefix prefix` to the inner tmux. Zero per-host
  config; costs one extra keystroke for every inner command.
- **c. Repurpose prefix2.** Since oh-my-tmux gives two prefixes anyway, use
  `C-b` to talk to outer and dedicate `C-a` as "always forwarded":
  outer does `set -g prefix2 None; bind -n C-a send-keys C-a` so `C-a` falls
  through to inner, whose prefix is `C-a`. Requires per-host split too.

### (2) Passthrough toggle (F12 keys-off pattern)

Primary source: tmux man KEY BINDINGS — `bind-key [-T key-table] key command`
binds into a named key table; OPTIONS — `key-table key-table` "Set the default
key table to key-table instead of root". The canonical pattern (widely used;
originates from samoshkin/tmux-config) on the OUTER tmux:

```tmux
bind -T root F12 \
  set prefix None \;\
  set key-table off \;\
  refresh-client -S

bind -T off F12 \
  set -u prefix \;\
  set -u key-table \;\
  refresh-client -S
```

- `set prefix None` is explicitly supported ("prefix can be set to the
  special key 'None'", man OPTIONS).
- `set key-table off` moves the client's default table to an (empty) `off`
  table, so EVERY root binding — including this repo's `bind -n C-h/j/k/l`
  vim-navigator keys (.tmux.conf.local:74-77) and the `MouseDrag1Pane`
  override (.tmux.conf.local:62) — is released to the inner tmux. This is
  the key advantage over option (1): the repo's root-table bindings would
  otherwise shadow the inner tmux even with distinct prefixes.
- Visual cue: oh-my-tmux status line is configured via plain
  `tmux_conf_theme_status_right` assignments in the `.local` file (README
  "Configuring the status line"); add
  `#{?#{==:#{client_key_table},off},OFF,}` to show mode state.
- Only the OUTER tmux needs this block — another reason it must be
  host-conditional or gated on "am I the outermost tmux".

### (3) Per-host local-vs-server conditionals from one shared repo

Three mechanisms, all usable inside the single shared `.tmux.conf.local`:

- **a. `%if` on `#{host}` / format variables (parse-time).** tmux man
  CONFIGURATION FILES: "Commands may be parsed conditionally by surrounding
  them with '%if', '%elif', '%else' and '%endif' … example:
  `%if "#{==:#{host},myhost}" set -g status-style bg=red … %endif`".
  Fast (no shell fork), but keys on exact hostname — needs a maintained
  hostname list in the shared file. tmux ≥3.0 required (fine; 3.4 local).
- **b. `if-shell` on environment (run-time).** tmux man COMMANDS:
  `if-shell [-bF] shell-command command [command]`. Test
  `[ -n "$SSH_CONNECTION" ]` (or `SSH_TTY`) to detect "I am the remote/inner
  tmux" without any hostname list. Caveat: tmux evaluates against the
  environment of the SERVER process at first launch; `SSH_CONNECTION` is
  reliably set when the server is started by the ssh login shell — the
  normal case here. The repo already uses exactly this test
  (.tmux.conf.local:14). With `-F` the argument is a tmux format instead of
  a shell command (no fork), but plain `if-shell` at config parse is
  simplest and runs once.
- **c. Per-host `.local` fragments + `source-file`.** tmux man COMMANDS:
  `source-file [-Fnqv] path …` (`-q` suppresses missing-file errors).
  Shared `.tmux.conf.local` ends with
  `source-file -q ~/.tmux.conf.host` (or `~/.config/tmux/host-#{host}.conf`
  with `-F` to expand formats). Repo ships `hosts/<name>.conf` fragments or
  a `local.conf` written by install.sh; machine identity lives in a file,
  not in shared logic.
- Also relevant either way: the OUTER tmux must pass true-color and OSC 52
  through; `.tmux.conf.local` already sets `allow-passthrough on` and
  clipboard terminal-features (.tmux.conf.local:27-29,102), which apply on
  both layers harmlessly.

Recommendation inside this repo: (b) `SSH_CONNECTION` as the primary
discriminator ("inner = any ssh'd host") matches the actual question
(local mac vs remote servers) and needs zero per-host data; (c) as escape
hatch for genuine per-host quirks.

### (4) What install.sh would need to parameterize

Current state: `link_submodule_override` deploys ONE shared
`.tmux.conf.local` identically everywhere (install.sh:117-123, 679+).

- **Nothing (preferred).** If the split is expressed with `if-shell`/`%if`
  inside the shared `.tmux.conf.local` (options 3a/3b), install.sh is
  unchanged — same file everywhere, self-classifying at tmux start. This
  matches the repo's existing pattern (pbcopy/xclip detection).
- **Host-fragment seam (if 3c chosen).** Additions:
  1. Ship fragments in-repo (e.g. `tmux-hosts/mac.conf`, `tmux-hosts/server.conf`).
  2. A role flag or hostname map (env var `DOTFILES_TMUX_ROLE=outer|inner`,
     or derive from `[ -n "$SSH_CONNECTION" ]` at install time) selecting
     which fragment to symlink to a fixed path, e.g.
     `~/.config/tmux/host.local.conf`, via a second `SUBMODULE_OVERRIDES`-style
     entry or a small `link_host_fragment` helper.
  3. Shared `.tmux.conf.local` gains one trailing
     `source-file -q ~/.config/tmux/host.local.conf`.
  Note install-time detection is weaker than runtime detection: the same
  $HOME synced/cloned to a server would need re-running install.sh with the
  other role, whereas runtime `if-shell` never goes stale.
- Either way, no change is needed to the oh-my-tmux submodule itself; all
  hooks are in the `.local` file, which oh-my-tmux sources last by design
  (.tmux.conf:160).

## Recommended options

| # | Option | Inner/outer prefixes | Passthrough | Per-host mechanism | install.sh change | Tradeoffs |
|---|--------|---------------------|-------------|--------------------|-------------------|-----------|
| A | **F12 keys-off on outer, gated by `if-shell '[ -z "$SSH_CONNECTION" ]'`** | identical everywhere (keep oh-my-tmux C-b/C-a) | explicit F12 toggle, releases ALL root bindings (incl. C-h/j/k/l, mouse drag) | runtime env test, zero host data | none | must remember mode; needs status-line OFF indicator; F12 key must reach terminal (iTerm2 fn-keys) |
| B | Distinct prefixes: outer keeps C-b/C-a, inner (`SSH_CONNECTION` set) rebinds to C-s | different per layer | not needed for prefix cmds, but root `-n` bindings (C-h/j/k/l) still swallowed by outer | runtime env test | none | muscle-memory split; vim-navigator keys still don't reach inner without extra forwarding |
| C | Double-tap: `bind C-b send-prefix` + existing `bind C-a send-prefix -2` | identical | prefix-prefix reaches inner; no mode state | none needed | none | +1 keystroke per inner command; root `-n` bindings still outer-only |
| D | Per-host fragments via `source-file -q` + install.sh role flag | anything | anything | file-based, explicit | new fragment-link seam + role parameter | most flexible, most machinery; install-time role can go stale |

Practical pick for this repo: **A**, optionally combined with **C** as a
no-mode fallback. A is the only option that also releases the repo's heavy
root-table bindings (vim-navigator, mouse-drag override) to the inner tmux;
B/C leave those captured by the outer layer. D only if genuinely per-host
theme/behavior divergence appears later.

## Sources

- tmux 3.4 man page (`man tmux`, /opt/homebrew): CONFIGURATION FILES (`%if`
  example keying on `#{host}`), COMMANDS (`if-shell`, `source-file -q`,
  `bind-key -T key-table`), OPTIONS (`prefix`/`prefix2` accept `None`,
  `key-table`).
- oh-my-tmux: `.config/tmux/.tmux.conf` (prefix2 C-a at 26-27,
  TMUX_CONF_LOCAL forcing at 156-157, `.local` sourced last at 160);
  `.config/tmux/README.md` (secondary-prefix feature, `.local`
  customization file, `tmux_conf_theme_status_*` variables).
- This repo: `install.sh` (DIRS 106-109, SUBMODULE_OVERRIDES 117-123,
  `link_submodule_override` 679+), `.tmux.conf.local` (SSH_CONNECTION
  precedent 14, root-table bindings 62/74-77, allow-passthrough 102).
- keys-off pattern: samoshkin/tmux-config (widely-cited origin of the F12
  off-table toggle); mechanics verified against tmux man `key-table` option.
