---
kind: spec
status: done
created: 2026-05-10
slug: security-untrack-zsh-history
---

# Design: untrack `.zsh_history` and tighten `.gitignore`

**Date:** 2026-05-10
**Status:** Done
**Owner:** hookey.chiang@ui.com

## Background

A four-axis code review of this dotfiles repo (security, shell config, install/test, Claude config + docs lifecycle) flagged one P0 finding and a related hygiene gap:

- **`.zsh_history` (514 KB) is tracked and pushed to a public GitHub repo** (`github.com/ui-HookeyChiang/dotfiles`). It leaks internal SSH topology (`ui@10.59.1.x`, `elliott@10.59.1.44:4422`), four internal usernames, internal product firmware filenames (`UNASPRO.al324.v3.x.y…bin`), and 1,214 hits on internal corp keywords (`ubnt`, `ui.com`, `ubiquiti`, internal Jira/Confluence URLs).
- **`.gitignore` covers only build artefacts** (`*.swp`, `build/`, `coverage/`). Standard sensitive patterns (history files, auth state, env/secrets, completion cache) are not ignored — the same class of leak can recur via any other history-style file.
- **`.git_allowed_signers` line 1 ends with `hookeychiang@C1153---MacBook-Pro`** — the `C1153---MacBook-Pro` segment is a Ubiquiti corporate asset tag. The comment field is ignored by git's SSH signature verification, so it can be sanitised without functional impact.

Brainstorming is bypassed here: the user and the review agents converged on the exact remediation set across four rounds of confirmation. Scope is locked; this spec records the decisions for traceability and gives the Dev/QA loop a concrete target.

## Goal

Three changes, one PR, one commit:

1. Untrack `.zsh_history` from git (working tree file kept).
2. Extend `.gitignore` with standard sensitive-file patterns (history, auth, completion cache, env/secrets) so the same class of leak cannot recur.
3. Sanitise the asset tag comment in `.git_allowed_signers` line 1.

## Locked parameters

These are inputs to this spec, not open questions.

### 1. Untrack strategy: `git rm --cached` only — no history rewrite

| Option | Action | Trade-off | Decision |
|--------|--------|-----------|----------|
| A. Stop the bleed | `git rm --cached .zsh_history` + add to `.gitignore` | Painless, no force push, history stays public | **CHOSEN** |
| B. Full purge | A + `git filter-repo --invert-paths --path .zsh_history` + force push | Removes file from history, but GitHub already cached views, forks already exist, archive.org may have snapshotted — marginal benefit, real cost | Rejected |

User decision (recorded): public-repo + cached-views + forks make the marginal benefit of B small relative to the force-push cost. Treat past leakage as already-disclosed; focus on preventing future commits.

### 2. `.gitignore` additions (kebab-categorised, appended after existing entries)

```
# Shell / interpreter history
.zsh_history
.zsh_sessions/
.bash_history
.lesshst
.viminfo
.python_history
.node_repl_history

# Network / auth state
.netrc
.ssh/
.aws/
.gnupg/
.config/gh/

# Compiled zsh completion cache
.zcompdump*

# Env files / secrets
.env
.env.*
*.pem
*.key
id_*
*.kdbx
```

**Why these and not others:**
- `.claude/` runtime state (`projects/`, `todos/`, `shell-snapshots/`) is **not** added: the repo's `.claude/` directory is a *source* of files that `install.sh` symlinks into `~/.claude/`. Runtime state lives under `~/.claude/`, not the repo. Ignoring `.claude/*` here would risk masking a tracked source file (`CLAUDE.md`, `settings.json`, `statusline-command.sh`) if anyone ever ran `git add .claude/` from the repo root.
- `.zcompdump*` is included even though it's regenerated per machine — a stray `git add .zcompdump-…` is a known footgun on dotfiles repos.
- `id_*` covers `id_rsa`, `id_ed25519`, etc. plus the `.pub` siblings (still wins from defence-in-depth even though pubkeys are safe to publish).

### 3. `.git_allowed_signers` line 1 comment sanitisation

| Field | Old | New |
|-------|-----|-----|
| Email | `hookey.chiang@ui.com` | unchanged |
| Key type | `ssh-ed25519` | unchanged |
| Public key | `AAAAC3NzaC1lZDI1NTE5AAAAINxtQQRiwvd2qIO+xXcMzjk5aJ2vQnZAZac6pIWpZ4j0` | unchanged |
| Comment | `hookeychiang@C1153---MacBook-Pro` | `hookey.chiang@ui.com` |

Line 2 is left untouched (its comment is already the neutral email).

**Why this is functionally safe:** the SSH allowed-signers format is documented in `ssh-keygen(1)` under `ALLOWED SIGNERS`. Verification matches against the `principals` field (the email) and the public key bytes. The trailing comment is a free-form human-readable label — `git verify-commit` and `ssh-keygen -Y verify` ignore it entirely.

## Out of scope (explicitly excluded)

- `git filter-repo` / force push — see decision 1 above.
- `.claude/` runtime ignore — see decision 2 rationale.
- P1 silent-failure bugs surfaced in the review (`.ctags.sh` find-args, `.ai-commit*.sh` cherry-pick `--skip`, `install.sh:781/792/594`) — separate PR.
- `.claude/CLAUDE.md` rewrite to drop globally-duplicated rules — separate PR.
- `docs/decisions/` first ADR — separate PR.

## Verification

All commands run from the repo root after the change is committed.

```bash
# 1. .zsh_history is no longer tracked
test "$(git ls-files -- .zsh_history | wc -l)" -eq 0

# 2. .zsh_history is now ignored
git check-ignore -v .zsh_history  # should print the .gitignore line that matches

# 3. git status doesn't surface .zsh_history (neither tracked nor untracked-untracked)
! git status --short | grep -q '\.zsh_history$'

# 4. .git_allowed_signers line 1 ends with the neutral email
test "$(awk 'NR==1 {print $NF}' .git_allowed_signers)" = "hookey.chiang@ui.com"

# 5. .git_allowed_signers line 2 is unchanged (sanity check we didn't over-edit)
test "$(awk 'NR==2 {print $NF}' .git_allowed_signers)" = "hookey.chiang@ui.com"

# 6. SSH signature verification still works on existing signed commits
#    (skip if repo has no signed history; non-fatal)
git log --show-signature -1 HEAD~1 2>&1 | grep -q "Good\|No signature" || true

# 7. .gitignore contains all expected categories
for pat in '.zsh_history' '.bash_history' '.netrc' '.ssh/' '.zcompdump*' '.env' '*.pem' 'id_*'; do
  grep -qxF "$pat" .gitignore || { echo "MISSING: $pat"; exit 1; }
done
```

## Acceptance criteria

- [ ] All 7 verification commands above pass.
- [ ] PR description explicitly notes "history retained, past commits still expose `.zsh_history` — informed decision."
- [ ] PR description notes that `.git_allowed_signers` comment is non-functional (per `ssh-keygen(1)`).
- [ ] Commit is signed (preserves the SSH signing chain we just sanitised).
- [ ] No other files modified (Dev agent must keep scope tight).

## Risk

- **Negligible.** All three changes are reversible in a single commit. The only behaviour change is "future `git add .zsh_history` no longer succeeds without `--force`" — exactly the desired effect.
