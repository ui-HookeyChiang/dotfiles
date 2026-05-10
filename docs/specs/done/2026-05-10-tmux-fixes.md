---
kind: spec
status: done
created: 2026-05-10
slug: tmux-fixes
---

# Design: tmux F10 + F11 — `sed -E` portability + xclip `$DISPLAY` guard

**Date:** 2026-05-10
**Status:** Done (brainstorming bypassed — see Background)
**Owner:** hookey.chiang@ui.com

## Background

Two MED-severity bugs in tmux helpers, surfaced by the dotfiles code review.

### F10: `.tmux.reset.sh:3` — `sed -r` is GNU-only

```sh
tmux -f /dev/null -L temp start-server \; list-keys | \
  sed -r \
  -e "s/bind-key(\s+)..." \
  ...
```

`sed -r` is GNU sed's flag for ERE (extended regex). macOS / BSD sed uses `-E`. Modern GNU sed accepts `-E` as an alias for `-r` (since GNU sed 4.0, 2003). **`-E` works on both**; `-r` only works on Linux.

This file is for regenerating `~/.tmux.reset.conf` (a one-shot user utility), so the breakage is rare but real on macOS.

### F11: `.tmux.conf.local:14` — xclip `if-shell` missing `$DISPLAY` guard

```tmux
if-shell 'command -v xclip >/dev/null 2>&1 && [ -z "${SSH_CONNECTION:-}" ]' \
    "bind-key -T copy-mode-vi y send-keys -X copy-pipe-and-cancel 'xclip -in -selection clipboard' ; \
     bind-key -T copy-mode-vi Enter send-keys -X copy-pipe-and-cancel 'xclip -in -selection clipboard'"
```

`xclip` requires an X server connection. When `$DISPLAY` is empty (Linux console TTY, headless servers, Wayland-without-Xwayland sessions), `xclip` blocks indefinitely waiting for an X connection — tmux's copy-mode `y` keybinding becomes a hang. The current condition checks `command -v xclip` (binary presence) and `SSH_CONNECTION` (skip when over SSH) but **never checks $DISPLAY**.

Brainstorming bypassed: both fixes are mechanical, scope locked.

## Goal

Single PR fixing both:
1. `.tmux.reset.sh` — `sed -r` → `sed -E`
2. `.tmux.conf.local` — add `[ -n "${DISPLAY:-}" ]` to xclip if-shell condition

## Locked parameters

### F10 fix

```sh
# Before:
sed -r \

# After:
sed -E \
```

That's it — single character change. `-E` is portable to GNU sed (4.0+) and BSD sed.

### F11 fix

```tmux
# Before:
if-shell 'command -v xclip >/dev/null 2>&1 && [ -z "${SSH_CONNECTION:-}" ]' \
    "..."

# After:
if-shell 'command -v xclip >/dev/null 2>&1 && [ -z "${SSH_CONNECTION:-}" ] && [ -n "${DISPLAY:-}" ]' \
    "..."
```

Adds `&& [ -n "${DISPLAY:-}" ]` — only register xclip bindings when an X server is reachable. The `${DISPLAY:-}` form (with default empty string) is safe under `set -u` even though tmux's if-shell doesn't enable strict mode — defensive habit.

## Out of scope

- OSC52 fallback for SSH-without-X case (no clipboard works there): follow-up. The current shell still has `pbcopy` branch for macOS users; Linux SSH users without X server lose clipboard silently — improvement opportunity, not regression.
- Wayland clipboard (`wl-copy`): follow-up. Most Linux users still use X11 or Xwayland; `wl-copy` would be additional branch.
- Re-running `bash .tmux.reset.sh` to regenerate `~/.tmux.reset.conf` post-PR: not auto-triggered. User runs manually if they want the new file.

## Verification

```bash
# 1. Syntax sanity
bash -n .tmux.reset.sh

# 2. F10: confirm sed -E used, sed -r gone
rg -qF 'sed -E' .tmux.reset.sh
! rg -F 'sed -r' .tmux.reset.sh

# 3. F10 behavioural: run on host (BSD sed — macOS — would have failed pre-fix)
.tmux.reset.sh && head -3 ~/.tmux.reset.conf
# Expect: file written, no error. Cleanup: rm ~/.tmux.reset.conf

# 4. F11: confirm $DISPLAY guard added
rg -qF '[ -n "${DISPLAY:-}" ]' .tmux.conf.local

# 5. F11 syntax: tmux can parse the file
tmux -f /dev/null -L temp-test start-server \; source-file .tmux.conf.local 2>&1 || true
# (tmux may complain about missing other config — acceptable; we just want no parse error on our file)

# 6. Diff scope
git diff --name-only origin/master..HEAD
# Expect: .tmux.reset.sh + .tmux.conf.local + spec
```

## Acceptance criteria

- [ ] `bash -n .tmux.reset.sh` exits 0
- [ ] F10: `.tmux.reset.sh` uses `-E`, no `-r` flag
- [ ] F10 behavioural: running `.tmux.reset.sh` on Linux still produces correct output (BSD sed — macOS — was the failure target, but Linux must also still work)
- [ ] F11: xclip if-shell condition has `[ -n "${DISPLAY:-}" ]`
- [ ] F11: pbcopy block (lines 9-12) NOT modified (already correct)
- [ ] Diff scope: only the two tmux files + spec
- [ ] Single SSH-signed commit
- [ ] Spec promote: `active/` → `done/` in same commit

## Risk

- **Low.** Both fixes are mechanical. F10 is a flag rename (sed accepts both on Linux). F11 adds a stricter condition (xclip bindings now register in fewer environments — but the new excluded environments were already broken).
