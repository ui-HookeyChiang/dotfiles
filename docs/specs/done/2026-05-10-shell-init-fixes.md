---
kind: spec
status: done
created: 2026-05-10
slug: shell-init-fixes
---

# Design: shell init F9 + F13 + F14 — Go path / compinit cache / brew shellenv guard

**Date:** 2026-05-10
**Status:** Done (brainstorming bypassed — see Background)
**Owner:** hookey.chiang@ui.com

## Background

Three MED-severity bugs in shell init files, surfaced by the dotfiles code review.

### F9: `.zprofile:23` — `/home/${USER}/go/bin` hardcoded `/home/`

```sh
elif [[ ! "$PATH" == *"/home/${USER}/go/bin"* ]]; then
  export PATH="${PATH:+${PATH}:}/home/${USER}/go/bin"
fi
```

This is the elif fallback when `go` is not installed. It tries to add `~/go/bin` to PATH defensively. But `/home/${USER}` is hardcoded — on macOS that's `/Users/${USER}`. macOS users with go uninstalled hit this branch and silently get a non-existent path on PATH. Should use `$HOME/go/bin`.

### F13: `.zshrc:2,63` — `ZSH_COMPDUMP` set but not passed to `compinit`

```zsh
# .zshrc:2
: ${ZSH_COMPDUMP:=$HOME/.zcompdump-${ZSH_VERSION}}

# .zshrc:63
zinit wait lucid atinit"zicompinit; zicdreplay" for \
    zsh-users/zsh-syntax-highlighting
```

Line 2 sets `ZSH_COMPDUMP` (with a stable filename per zsh version) — the comment says "prevents race-suffix dumps from accumulating". But the canonical path **only takes effect** if `compinit` is invoked with `compinit -d "$ZSH_COMPDUMP"`. Zinit's `zicompinit` macro is a wrapper around `autoload -Uz compinit && compinit "$@"` — it forwards args. Currently called with no args → uses default `${HOME}/.zcompdump.{host}.{pid}` → defeats the whole point.

Also: `zicompinit` runs every shell with no daily-cache check. Standard idiom is `compinit -C -d "$ZSH_COMPDUMP"` (use cached dump if mtime fresh) or `compinit -d "$ZSH_COMPDUMP"` (full rebuild). Without `-C`, every shell pays the parse-all-fpath cost (50–200ms).

### F14: `.zshenv:46-50` — `eval $(brew shellenv)` re-extends PATH on re-source

```zsh
if (( IS_MAC )); then
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
fi
```

`brew shellenv` exports `PATH=/opt/homebrew/bin:/opt/homebrew/sbin:$PATH` (and similar for MANPATH, INFOPATH). Each re-source of `.zshenv` (e.g. tmux re-init, IDE shell-spawning) **prepends** these again, so PATH grows: `/opt/homebrew/bin:/opt/homebrew/bin:/opt/homebrew/bin:...`.

`typeset -U path` (line 40) deduplicates, but only for `path` array — `MANPATH`, `INFOPATH` lack equivalent. Plus, `eval` itself has cost.

Standard guard: only run `brew shellenv` once per shell (check `$HOMEBREW_PREFIX`).

Brainstorming bypassed: scope locked.

## Goal

Single PR with three surgical fixes:
1. F9: `.zprofile:23-24` — replace `/home/${USER}` with `$HOME`.
2. F13: `.zshrc:63` — change `zicompinit` invocation to use `compinit -C -d "$ZSH_COMPDUMP"`.
3. F14: `.zshenv:45-51` — add `[[ -z "${HOMEBREW_PREFIX:-}" ]]` guard around the brew shellenv block.

## Locked parameters

### F9 fix — `.zprofile:23-24`

```sh
# Before:
elif [[ ! "$PATH" == *"/home/${USER}/go/bin"* ]]; then
  export PATH="${PATH:+${PATH}:}/home/${USER}/go/bin"

# After:
elif [[ ! "$PATH" == *"$HOME/go/bin"* ]]; then
  export PATH="${PATH:+${PATH}:}$HOME/go/bin"
```

`$HOME` is set by login (PAM/launchd) before any shell initialisation, always reflects the right path on both Linux (`/home/...`) and macOS (`/Users/...`).

### F13 fix — `.zshrc:63`

```zsh
# Before:
zinit wait lucid atinit"zicompinit; zicdreplay" for \

# After:
zinit wait lucid atinit"zicompinit -C -d \"\$ZSH_COMPDUMP\"; zicdreplay" for \
```

Two changes:
- `-C` enables dump-cache reuse (the **C** in compinit, not bash `-c`)
- `-d "$ZSH_COMPDUMP"` forces use of the canonical path from line 2 (escaped because the value is consumed inside an `atinit"..."` zinit string)

The escaping: zinit's `atinit"..."` is essentially a delayed string. We need `$ZSH_COMPDUMP` to expand at execution time (when zinit runs the hook), not at zinit-source time. The `\$` ensures deferred expansion.

### F14 fix — `.zshenv:45-51`

```zsh
# Before:
if (( IS_MAC )); then
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
fi

# After:
if (( IS_MAC )) && [[ -z "${HOMEBREW_PREFIX:-}" ]]; then
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
fi
```

Single `&&` clause added to the outer `if`. `HOMEBREW_PREFIX` is set by `brew shellenv` itself; subsequent re-sources skip the eval. Idempotent.

## Out of scope

- Switching to `bash`-style PATH manipulation in `.zprofile` (it's already zsh-only, OK)
- Migrating Conda init to a faster path (`.zshrc:153-180`) — separate concern
- `infocmp` fork in `.zshenv:32` — not a P1
- Suffix alias hygiene — not a bug

## Verification

```bash
# 1. Syntax
zsh -n .zshrc && zsh -n .zshenv && zsh -n .zprofile

# 2. F9 marker
rg -qF '$HOME/go/bin' .zprofile && echo "OK: F9 uses $HOME"
! rg -F '/home/${USER}/go/bin' .zprofile && echo "OK: F9 no /home/ literal"

# 3. F13 markers
rg -qF 'zicompinit -C -d' .zshrc && echo "OK: F13 daily-cache + canonical path"
rg -qF '\\\$ZSH_COMPDUMP' .zshrc && echo "OK: F13 deferred expansion"

# 4. F14 marker
rg -qF '[[ -z "${HOMEBREW_PREFIX:-}" ]]' .zshenv && echo "OK: F14 guard"

# 5. F14 behavioural: re-source .zshenv twice, PATH must not grow brew duplicates
zsh -ic 'source .zshenv; source .zshenv; echo "$PATH" | tr : "\n" | sort | uniq -c | sort -rn | head -5'
# (Manual eyeball — but /opt/homebrew/bin should appear at most once on Linux too)

# 6. Existing tests
bash tests/test-zsh-init.sh        # 10/10
bash tests/test-install-projects.sh  # 9/9
bash tests/test-install-os.sh        # 12/12

# 7. Diff scope
git diff --name-only origin/master..HEAD
# Expect: .zshrc + .zshenv + .zprofile + spec
```

## Acceptance criteria

- [ ] `zsh -n` clean on all three files
- [ ] F9: `$HOME/go/bin` (no `/home/${USER}` literal)
- [ ] F13: `compinit -C -d` invocation present; `\$ZSH_COMPDUMP` properly escaped for deferred expansion
- [ ] F14: `[[ -z "${HOMEBREW_PREFIX:-}" ]]` guard on outer if
- [ ] Linux test-zsh-init.sh: 10/10 PASS (T6 PASS) — confirm zsh init still works post-F13
- [ ] Diff scope: only the three files + spec
- [ ] Single SSH-signed commit
- [ ] Spec promote

## Risk

- **F9**: trivially low. Branch was previously broken on macOS (silent), now correct.
- **F13**: low-medium. compinit `-C` reuses cache aggressively — if completion data goes stale (after `zinit update`), user runs `zinit cclear` to nuke. Behaviour change: 50-200ms faster shell start, slightly staler completions until next compdump rebuild.
- **F14**: low. Idempotent guard only. If user manually unsets `HOMEBREW_PREFIX` for some reason, second source rebuilds — no behaviour change from current state.
