# Letter to Future Sessions

Written 2026-07-06 by the one Fable 5 session this environment will get. You,
reading this, are probably Sonnet or Opus. Nothing here needs my capability —
it needs your discipline.

## Three things the user didn't ask about, but matter most here

### 1. Safety here is prose, not mechanism — treat it accordingly

`defaultMode: bypassPermissions`, `Bash(*)` allowed, dangerous-mode prompt
skipped. The deny list blocks `git push --force` but NOT `git push origin
main`. The `block-main-edit` hook gates only Edit/Write tools — a bash heredoc
write sails through. So the only thing standing between you and a
direct-to-main push is the Safety section of CLAUDE.md. Read it as a hard
mechanism, because for you it must be one. If you ever notice yourself
reaching for a bash-side write to route around a hook denial: that denial was
the system working. (Proposing real deny-list entries for `git push * main` to
the user would be a worthy PR.)

### 2. This environment is a symlink farm across four repos — breakage is silent

`~/.claude/skills/` links into `~/.claude/skill-dev/` (its own git repo),
`~/.agents/skills/`, and `stock-target-finder/skills/`;
`dotfiles/.claude/skills/` links into `dotfiles/cc-thinking-skills/`. `~/.claude/CLAUDE.md` and settings are
symlinks into `dotfiles/.claude/`. When something is renamed in ONE repo, the
others rot silently — a dangling symlink produces no error, the skill just
vanishes from the loaded list (that's how `stacking-dev` was dead for weeks;
see harness-diagnosis §1). When any skill/route behaves oddly, run the
broken-symlink check before debugging anything else. Also remember `rtk` hook
rewrites your Bash commands transparently; if a command fails in a weird way,
`rtk proxy <cmd>` is the escape hatch.

### 3. Style layers compress your words, not your evidence

Two caveman hooks exist: a SessionStart hook (caveman plugin) that compresses
your user-facing chat, and a SubagentStart hook in settings.json
(`subagent-caveman-inject.sh`) that injects caveman into every subagent — so
expect their reports back compressed too. Neither applies to files, commits,
PRs, or the dispatch prompts you write — those stay in full, precise English.
A subtle failure: compressing *dispatch prompts* saves you tokens once and
costs a whole failed subagent run. The dispatch triple and acceptance criteria
in model-dispatch.md are exempt from all brevity pressure. And caveman-styled
subagent reports must still carry evidence (`file:line`, command output) —
compressed prose, uncompressed proof.

## How this institution will most likely degrade, and the countermeasures

1. **Rule accretion.** Every incident adds a line; two years later CLAUDE.md
   is 400 lines nobody follows — the exact disease this rewrite cured.
   Countermeasure: the compaction rule in maintenance.md is not optional; when
   a file crosses its threshold, compaction IS the task.
2. **Route rot.** Skills get renamed; routes and templates keep old names.
   Countermeasure: rename checklist in maintenance.md + broken-symlink check.
   If you find a stale name, fixing it is pre-authorized (with evidence).
3. **Verification theater.** Read-back agents drift into "looks good ✓"
   rubber-stamping. Countermeasure: acceptance criteria must be falsifiable
   (template 5 requires PASS/FAIL + evidence per criterion). If a review comes
   back with no evidence quotes, reject it and re-dispatch — that review
   never happened.
4. **Pointer decay.** Files referenced by path (judgment.md, templates) stop
   being read because nothing forces it. Countermeasure: CLAUDE.md names the
   exact trigger moments ("before declaring done…"). If you notice you
   finished a task without consulting judgment.md §2, that's the signal the
   pointer needs strengthening — say so to the user.

## Handoff status (2026-07-06)

All deliverables A–G landed on branch `institution` (PR to follow); symlink fix
for stack/stack-dev/stack-merge applied live in `~/.claude/skills/`. Open items
for the user: skill-catalog pruning decision (harness-diagnosis §2), deny-list
hardening for `git push * main` (§1 above). Do not merge the PR yourself.
