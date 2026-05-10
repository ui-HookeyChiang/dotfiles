---
kind: spec
status: done
created: 2026-05-10
slug: gitconfig-cleanup
---

# Design: `.gitconfig` F12 — drop duplicate insteadOf, restore https default

**Date:** 2026-05-10
**Status:** Done (brainstorming bypassed — see Background)
**Owner:** hookey.chiang@ui.com

## Background

`.gitconfig:67-76` has TWO `[url ...] insteadOf` blocks targeting GitHub:

```ini
[url "ssh://git@github.com/"]
    insteadOf = https://github.com/
[gpg]
    format = ssh
[gpg "ssh"]
    allowedSignersFile = ~/.git_allowed_signers
[tag]
    gpgsign = true
[url "git@github.com:"]
    insteadOf = https://github.com/
```

Two issues:

### F12.1: Duplicate redirect

Both blocks rewrite `https://github.com/` → SSH form. Git applies the **last matching** rule, so the second one (`git@github.com:`) wins; the first (`ssh://git@github.com/`) is dead config. Should be one block.

### F12.2: SSH rewrite breaks public-repo clone for SSH-key-less users

Anyone who clones this dotfiles repo (it's PUBLIC: `github.com/ui-HookeyChiang/dotfiles`) and runs `git submodule update --init` will hit this rewrite. The submodules in `.gitmodules` use HTTPS URLs:
```
https://github.com/dreamsxin/nvim
https://github.com/gpakosz/.tmux
```
But the user's `~/.gitconfig` (which is symlinked from this repo's `.gitconfig`) rewrites these to `git@github.com:...` — silently. Then `git submodule update` tries SSH, fails if the user has no GitHub SSH key configured, and the clone is incomplete.

Brainstorming bypassed: this hits real users. Scope locked.

## Goal

Single PR:
1. Drop the duplicate `[url "ssh://git@github.com/"]` block (F12.1).
2. Make the rewrite **opt-in via comment** rather than default — comment-out the remaining `[url "git@github.com:"]` block with a note explaining "uncomment if you want to push via SSH instead of HTTPS+credential-helper" (F12.2).

This makes the dotfiles **clone-clean for fresh users** (HTTPS submodules just work) while preserving the option for the dotfiles author (who has SSH keys) to enable SSH push.

## Locked parameters

### F12 fix — `.gitconfig:67-76`

Remove lines 67-68 entirely (duplicate ssh:// block). Replace lines 75-76 with commented-out version:

```ini
# Before (lines 67-76):
[url "ssh://git@github.com/"]
    insteadOf = https://github.com/
[gpg]
    format = ssh
[gpg "ssh"]
    allowedSignersFile = ~/.git_allowed_signers
[tag]
    gpgsign = true
[url "git@github.com:"]
    insteadOf = https://github.com/

# After (lines 67-?):
[gpg]
    format = ssh
[gpg "ssh"]
    allowedSignersFile = ~/.git_allowed_signers
[tag]
    gpgsign = true
# Optional: rewrite all GitHub https URLs to SSH form. Useful if you push via
# SSH key. Comment out if you clone via HTTPS + credential helper (default).
# [url "git@github.com:"]
#     insteadOf = https://github.com/
```

That is:
- Lines 67-68 (`ssh://git@github.com/` block): removed entirely.
- Lines 75-76 (`git@github.com:` block): commented out with explanation.

### Why comment vs delete?

- Delete: simpler, but loses author's intent (push via SSH).
- Comment: documents intent, lets author re-enable trivially.

Decision: **comment**. Adds 4 lines (3 comment + 2 rewrite block lines = 5 lines total, vs 2 lines if uncommented), but communicates choice for future-self and forks.

## Out of scope

- Migrating to credential helpers (`git-credential-osxkeychain` on macOS, `libsecret` on Linux) — orthogonal feature.
- Adding `[init] defaultBranch = main` or other modern defaults — separate PR.
- Auditing other gitconfig sections for staleness — this PR fixes one specific hazard.

## Verification

```bash
# 1. git accepts the new file
git config -f .gitconfig --list >/dev/null && echo "OK: parses"

# 2. F12.1: ssh:// duplicate gone
! rg -F '[url "ssh://git@github.com/"]' .gitconfig && echo "OK: F12.1 ssh:// duplicate removed"

# 3. F12.2: git@github.com: block is commented out, not deleted
rg -qF '# [url "git@github.com:"]' .gitconfig && echo "OK: F12.2 SSH rewrite is opt-in"
rg -qF '#     insteadOf = https://github.com/' .gitconfig && echo "OK: F12.2 instructions present"
# OR (alternative form): the commented insteadOf:
rg -qF 'insteadOf = https://github.com/' .gitconfig | head -1
# Should appear inside a comment line — verify by counting non-comment matches:
non_comment_count=$(rg -c '^[^#]*insteadOf' .gitconfig 2>/dev/null || echo 0)
[ "$non_comment_count" = "0" ] && echo "OK: no active insteadOf rules"

# 4. Behavioural: git config doesn't apply the rewrite
git config -f .gitconfig --get-all url."git@github.com:".insteadOf 2>&1
# Expect: empty (not set, because commented out)

# 5. Other config (gpg, tag, alias, color, branch, pull) unchanged
diff <(git show "origin/master:.gitconfig" | rg -F '[gpg' -A 2) <(rg -F '[gpg' -A 2 .gitconfig) && echo "OK: gpg sections unchanged"
diff <(git show "origin/master:.gitconfig" | rg -F '[alias' -A 100 | head -50) <(rg -F '[alias' -A 100 .gitconfig | head -50) && echo "OK: alias section unchanged"

# 6. Diff scope
git diff --name-only origin/master..HEAD
# Expect: .gitconfig + spec
```

## Acceptance criteria

- [ ] `git config -f .gitconfig --list` parses (no syntax error)
- [ ] `[url "ssh://git@github.com/"]` block removed entirely
- [ ] `[url "git@github.com:"]` block commented out with explanatory note
- [ ] No active `insteadOf` rules (every match is inside a comment)
- [ ] All other sections (`[user]`, `[core]`, `[commit]`, `[alias]`, `[color]`, `[branch]`, `[pull]`, `[gpg]`, `[gpg "ssh"]`, `[tag]`) unchanged byte-identical
- [ ] Diff scope: only `.gitconfig` + spec
- [ ] Single SSH-signed commit
- [ ] Spec promote

## Risk

- **Low for new users**: removes a hidden hazard (HTTPS clone fails because of secret SSH rewrite).
- **Low for author (you)**: pushing requires switching to SSH manually, but the comment makes it 1-second trivial. Or use HTTPS + credential helper (modern default).
- **Existing repos**: any local clone where you set up SSH remotes manually (`git remote set-url ... git@...`) still works — gitconfig insteadOf only rewrites HTTPS URLs at clone time, not existing remote URLs.

## Migration notes (for the author)

After this PR lands:
- Clones via HTTPS work for everyone (default modern path).
- To push via SSH (existing workflow), one of:
  1. Uncomment the `[url ...]` block in `~/.gitconfig`. (Minimum friction.)
  2. Per-clone: `git remote set-url origin git@github.com:owner/repo.git`.
  3. Per-shell: `git -c url."git@github.com:".insteadOf=https://github.com/ push`.
- Most modern git installs come with HTTPS credential helpers — push via HTTPS works out of the box on macOS (osxkeychain) and most Linux distros (libsecret).
