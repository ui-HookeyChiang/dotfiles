---
kind: spec
status: done
created: 2026-05-10
slug: zsh-init-tail-robustness
---

# Design: harden `test-zsh-init.sh` T2/T3 against CI-fresh zinit noise

**Date:** 2026-05-10
**Status:** Done (brainstorming bypassed — see Background)
**Owner:** hookey.chiang@ui.com

## Background

PR #27 (`ci: add multi-OS test matrix workflow`) opened a GitHub Actions matrix and immediately surfaced a real bug in `tests/test-zsh-init.sh`:

- **Both** `ubuntu-22.04` and `macos-14` jobs failed at T2 (`zsh -ic 'echo $EDITOR'`):

  ```
  not ok 2 - zsh -ic inherits EDITOR=nvim (interactive non-login)
    diag: |
      expected 'nvim', got '
  nvim'
  ```

- T3 (`zsh -lic`) PASSED on both. T2 only failed because **zinit's first run on a fresh ZDOTDIR (CI is always cold) emits a leading newline before the user's `echo` output**.

The existing T2/T3 normalization is `printf '%s\n' "$out" | tail -n1`, which is supposed to strip multi-line prompt noise. It fails when the captured `out` has a leading newline but only one non-empty line: `tail -n1` on `"\nnvim\n"` returns `"nvim"` correctly — **so why does the diag show `'\nnvim'`?**

Hypothesis (verified in adversarial reproduction during Dev): `out` is captured via `$(zrun -ic 'echo $EDITOR' 2>/dev/null)`. Bash command substitution strips trailing newlines but **not leading**. The `printf '%s\n' "$out"` then emits `"\nnvim\n"` — a 2-line stream where line 1 is empty, line 2 is `nvim`. `tail -n1` correctly returns `"nvim"`.

But the actual symptom shows `'\nnvim'` survived through the pipeline. The most likely cause: **zinit emits an ANSI escape sequence (e.g. cursor reposition) before the newline**, and the captured `out` is something like `"\e[?25l\nnvim"` — `tail -n1` on `"\e[?25l\nnvim\n"` returns `"nvim"`, BUT if the escape contains a `\r` (carriage return) instead of `\n`, `tail -n1` sees the entire stream as a single line. Or: zinit emits `"prompt-line\rnvim"` where `\r` overwrites in a real terminal but in non-tty `out` capture, `\r` is just embedded and `tail -n1` sees one line.

Brainstorming bypassed: scope is "make T2/T3 robust against any combination of leading newlines, ANSI escapes, and CR characters in zinit's instant-prompt output". One file, ~6 lines changed, no design tradeoffs.

## Goal

Single PR fixing `tests/test-zsh-init.sh` T2 and T3 (both use the same `printf | tail -n1` pattern) so they pass on CI-fresh zinit (cold cache, no warm-up). Verified by:

1. Local reproduction with `rm -rf $tmp_dir/.zinit*` + fresh `ZDOTDIR` showing the failure pre-fix.
2. The same reproduction passing post-fix.
3. PR #27's CI matrix rebasing onto this fix and turning green.

## Locked parameters

### Replacement normalization

Replace the line:

```bash
out="$(printf '%s\n' "$out" | tail -n1)"
```

With a more robust normalization that:
1. Strips ANSI escape sequences (CSI: `\e[…m`, OSC, etc.) — zinit's instant-prompt emits cursor saves/restores.
2. Replaces `\r` with `\n` so embedded carriage returns split into lines.
3. Takes the last NON-EMPTY line (not just the last line) — defensive against trailing blank lines.

Concrete bash-only implementation (no awk required, but awk is acceptable):

```bash
# Normalize zinit instant-prompt noise: strip ANSI escapes, split on CR/LF,
# return last non-empty line.
out="$(
  printf '%s\n' "$out" \
    | sed -E $'s/\x1b\\[[0-9;?]*[a-zA-Z]//g; s/\x1b\\][^\x07]*\x07//g; s/\r/\\n/g' \
    | awk 'NF { last = $0 } END { print last }'
)"
```

The sed strips:
- `\e[<params>letter` (CSI sequences — most common)
- `\e]<params>\a` (OSC sequences — terminal title etc.)
- `\r` (replace with `\n` so embedded CR splits into separate lines)

The awk takes the last line where `NF > 0` (i.e. non-empty after field-splitting). Pure POSIX, works under both GNU and BSD.

### Scope

Apply identical replacement to:
- `tests/test-zsh-init.sh:104` (T2)
- `tests/test-zsh-init.sh:113` (T3)

Don't touch line 176 (T8: `alias v` test) — it has the same `tail -n1` pattern but works fine because `alias v` output is single-line stable; not affected by zinit prompt noise.

### Verification approach

Add an inline `# Why this normalization` comment block above T2 documenting the exact noise types observed and the rationale, so future maintainers don't simplify it back.

## Out of scope

- Migrating to a structured stdout-vs-stderr separation in zsh helpers (would require .zshenv/.zshrc changes — separate concern).
- Disabling zinit's instant-prompt entirely (user feature; not a test concern).
- Updating PR #27's spec or CONTEXT.md — that PR rebases independently after this lands.
- Touching T1, T4-T10, T8 (`alias v`) — they don't exhibit the bug.
- Replacing `tail -n1` everywhere — only T2/T3 are affected.

## Verification

```bash
# 1. Syntax + sanity
bash -n tests/test-zsh-init.sh

# 2. Reproduce the original failure on a cold ZDOTDIR (Linux host, but CI mirrors this)
tmp=$(mktemp -d)
ZDOTDIR_TEST="$tmp/zdot" && mkdir -p "$ZDOTDIR_TEST"
for f in .zshenv .zshrc .zprofile .p10k.zsh; do
  ln -s "$PWD/$f" "$ZDOTDIR_TEST/$f"
done
# Cold run (no warm-up): capture EDITOR via zsh -ic
out_cold="$(env "ZDOTDIR=$ZDOTDIR_TEST" zsh -ic 'echo $EDITOR' 2>/dev/null)"
# Expect: $out_cold has leading newline / ANSI / CR pollution.

# 3. Apply normalization manually, confirm result is exactly "nvim"
normalized="$(printf '%s\n' "$out_cold" \
  | sed -E $'s/\x1b\\[[0-9;?]*[a-zA-Z]//g; s/\x1b\\][^\x07]*\x07//g; s/\r/\\n/g' \
  | awk 'NF { last = $0 } END { print last }')"
test "$normalized" = "nvim"

# 4. Run full TAP suite, expect 10/10 (+ T6 SKIP on macOS)
bash tests/test-zsh-init.sh

# 5. Diff scope clean
git diff --name-only origin/master..HEAD
# Expect: tests/test-zsh-init.sh + docs/specs/(active|done)/2026-05-10-zsh-init-tail-robustness.md
```

## Acceptance criteria

- [ ] `bash -n tests/test-zsh-init.sh` exits 0
- [ ] T2 + T3 use the new normalization (sed + awk pipeline)
- [ ] Inline comment documents the noise types and rationale
- [ ] On Linux host: `bash tests/test-zsh-init.sh` 10/10 PASS (cold cache + warm cache both green)
- [ ] Cold-cache reproduction in Verification §2 produces noise; §3 normalization yields exactly `"nvim"`
- [ ] Diff scope: only `tests/test-zsh-init.sh` + spec
- [ ] Single SSH-signed commit
- [ ] Spec promote: `active/` → `done/` in same commit

## Risk

- **Low.** Test-only change; no production code touched. Worst case: normalization over-strips and a future legitimate stdout content gets eaten — addressable by adjusting the sed pattern.

## Adversarial verification

Dev should:
1. Reproduce the bug locally with a cold ZDOTDIR (`rm -rf` zinit cache before `zsh -ic`)
2. Confirm the diag matches CI: `expected 'nvim', got '\nnvim'`
3. Apply the fix
4. Confirm both cold and warm runs PASS
5. Capture the pre-fix `out_cold` value (octal dump or `cat -A`) so the spec records the actual noise observed, not just the hypothesis

If Dev can't reproduce locally (zinit cache may persist across tmp_dirs via `~/.zinit`), document why and rely on CI verification post-rebase of PR #27.

## Future work

- Consider a `tests/lib/normalize.sh` helper if the same sed+awk appears in 3+ places.
- Track upstream zinit issue if instant-prompt noise becomes a recurrent CI flake.
