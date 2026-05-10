---
kind: spec
status: active
created: 2026-05-10
slug: fix-ctags-find-args
---

# Design: fix `.ctags.sh` find-args silent skip

**Date:** 2026-05-10
**Status:** Active (brainstorming bypassed — see Background)
**Owner:** hookey.chiang@ui.com
**Stack position:** task-1 of 3 in `fix/silent-failure-bugs/`

## Background

The dotfiles code review (4 parallel review agents) flagged `.ctags.sh:2` as **HIGH severity, silent failure**: the `find` invocation has tokens like `'*.C'-o` and `'*.s'-o` where the closing quote is jammed against `-o` with no space. `find` parses these as a single literal pattern, so:

- `.C` (capital — common for C++ legacy code) — never indexed
- `.s` (assembly) — never indexed
- `.S` (assembly with cpp preprocessing) — never indexed

…even though the user's intent (per the file structure) is clearly to include them. The `cscope.files` and `tags` outputs silently miss those file types — bug, no error.

Brainstorming bypassed: range is mechanical, fix is one-line, user confirmed scope across 4 review rounds.

## Goal

Single PR fixing the `find` invocation:
1. Add proper `-name` clauses with spaces around `-o`.
2. Add explicit grouping `\( ... \)` and a single `-print` after the prune-or-match split, so `./build` itself is not emitted into `cscope.files`.

## Locked parameters

### Current (broken) source

```sh
find ./ -path ./build -prune -o -name "*.c" -o -name "*.h" -o -name "*.cpp" -o -name 'Makefile' -o -name 'rules' -o -name 'make*' -o -name '*.cc' -o -name '*.C'-o -name '*.s'-o -name '*.S' > cscope.files
```

The fragment `'*.C'-o -name '*.s'-o -name '*.S'` is parsed as:
- `-name '*.C'-o`  ← single literal pattern starting with `*.C` (won't match anything; `find -name` glob doesn't match against `'*.C'-o`)
- `-name '*.s'-o`  ← same problem
- `-name '*.S'`    ← OK alone, but combined with the prune logic missing `-print`, behaviour is messy

Plus, `-path ./build -prune -o ... > cscope.files` without a `-print` action emits `./build` itself (the prune branch's default action) into the output.

### Replacement

```sh
find ./ -path ./build -prune -o \
  \( -name '*.c' -o -name '*.h' \
     -o -name '*.cpp' -o -name '*.cc' -o -name '*.cxx' \
     -o -name '*.hpp' -o -name '*.hxx' \
     -o -name '*.C' -o -name '*.s' -o -name '*.S' \
     -o -name 'Makefile' -o -name 'rules' -o -name 'make*' \
  \) -print > cscope.files
```

Changes:
- All `-name` clauses gain explicit spacing.
- All extensions wrapped in `\( ... \)` group with a single `-print` after.
- The `-prune` branch has no `-print`, so `./build` is excluded.
- Adds `*.cxx`, `*.hpp`, `*.hxx` (clearly intended C++ types missing from the original — defensible scope creep, brings header coverage in line with `*.cpp/*.cc`).

### Why not migrate to `fdfind`?

The user's CLAUDE.md notes `find` is denied for *Claude's tools*, but user-authored shell scripts using `find` are fine — that's a tool-policy boundary, not a code-quality issue. Migrating to `fdfind` would expand scope and break on systems without it (BSD, fresh installs). Out of scope for this task.

## Out of scope

- `fdfind` migration.
- Replacing `cscope` / `ctags` invocations (lines 3-4) — they work as-is.
- Touching anything else.

## Verification

```bash
# 1. Syntax check
bash -n .ctags.sh

# 2. Behavioural test in a sandbox
tmp=$(mktemp -d) && pushd "$tmp" >/dev/null
mkdir -p src build
touch src/foo.c src/foo.h src/foo.cpp src/foo.cc src/foo.cxx \
      src/foo.hpp src/foo.hxx src/foo.C src/foo.s src/foo.S \
      Makefile rules makefile.dep \
      build/ignore_me.c
cp "$OLDPWD/.ctags.sh" .
sh .ctags.sh
echo '--- cscope.files ---'
sort cscope.files
echo '---'
# Expect: every src/foo.* listed, Makefile/rules/makefile.dep listed,
#         build/ignore_me.c NOT listed, ./build NOT listed,
#         no spurious bare './build' line.
popd >/dev/null && rm -rf "$tmp"

# 3. Regression test: confirm OLD broken script misses .C/.s/.S — kept as a
#    one-shot demonstration during dev, removed before commit.
```

## Acceptance criteria

- [ ] `bash -n .ctags.sh` exits 0
- [ ] Behavioural test (Verification 2) finds all 11 expected source files in the sandbox cscope.files
- [ ] `./build` literal not in cscope.files
- [ ] `./build/ignore_me.c` not in cscope.files
- [ ] Single commit, SSH-signed
- [ ] No other files modified

## Risk

- **Negligible.** One-line fix to a developer utility script. Wrong outcome at worst means cscope.files has different contents — easy to detect by visual inspection or the sandbox test.
