---
kind: spec
status: active
created: 2026-05-10
slug: harden-install-sh
---

# Design: harden `install.sh` — loud module failure, source-safe, Debian-aware

**Date:** 2026-05-10
**Status:** Active (brainstorming bypassed — see Background)
**Owner:** hookey.chiang@ui.com
**Stack position:** task-3 of 3 in `fix/silent-failure-bugs/`

## Background

Three HIGH-severity silent-failure bugs in `install.sh`, all surfaced by the dotfiles code review.

### F6: `install.sh:781-787` — `(( X )) && fn || true` swallows module failures

```sh
(( WITH_NODE ))   && install_node   || true
(( WITH_GO ))     && install_go     || true
(( WITH_RUST ))   && install_rust   || true
(( WITH_DOCKER )) && install_docker || true
(( WITH_LATEX ))  && install_latex  || true
(( WITH_SKILLS )) && install_skills || true
(( WITH_PROJECTS )) && install_projects || true
```

The `&&`/`||` chain has subtle semantics:
- When `WITH_X=1` and `install_x` succeeds → `(( 1 )) && install_x` is true, `|| true` short-circuits → exit 0. ✓
- When `WITH_X=0` → `(( 0 ))` returns 1, `&& install_x` skipped, `|| true` runs → exit 0. ✓ (intended skip)
- When `WITH_X=1` and **`install_x` fails** → `(( 1 )) && install_x` is false because `install_x` failed, `|| true` swallows the failure → exit 0. ✗

The third case is the bug: a module the user explicitly asked for fails halfway, and `install.sh` says "done". User logs out, comes back, finds half-installed Node, no error message, no log entry indicating which module failed.

### F7: `install.sh:792` — `main "$@"` runs unconditionally

```sh
main "$@"
```

`tests/test-install-projects.sh` needs to source `install.sh` to extract the `seed_env` function for unit testing, but can't because sourcing the file always invokes `main`. The current workaround is awk-slicing the function out (test-install-projects.sh:191):

```sh
awk '/^seed_env\(\) \{$/{flag=1} flag{print} flag && /^\}$/{flag=0; exit}' "$install_sh" > "$tmp_dir/seed_env.bash"
```

Brittle: any future bash function syntax change breaks the slice. Standard bash convention is to guard `main` so the file is library-friendly.

### F8: `install.sh:594-598` — Docker repo URL hardcodes `linux/ubuntu`

```sh
run sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg ...
run bash -c 'echo "deb [...] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" ...'
```

`install.sh:192-195` whitelists both Debian and Ubuntu (`*ubuntu*|*debian*`), but the docker block hardcodes `linux/ubuntu`. On Debian:
- The GPG key URL still works (Docker hosts both, partly identical), but
- The `deb [...]` line writes Ubuntu's repo into Debian's `sources.list.d/`, and
- `apt-get update` may pull mismatched packages (Docker for Ubuntu Jammy installed on Debian Bookworm), causing dependency hell.

Brainstorming bypassed: all three fixes are mechanical, scope is locked, no design choices to litigate.

## Goal

Single PR, three surgical changes to `install.sh`:
1. F6 — replace the 7 `(( X )) && fn || true` lines with explicit `if` blocks.
2. F7 — guard the trailing `main "$@"` with `BASH_SOURCE`/`$0` test.
3. F8 — branch the Docker repo URL on `$DISTRO_ID`.

## Locked parameters

### F6 — replace lines 781-787

```sh
if (( WITH_NODE ));     then install_node;     fi
if (( WITH_GO ));       then install_go;       fi
if (( WITH_RUST ));     then install_rust;     fi
if (( WITH_DOCKER ));   then install_docker;   fi
if (( WITH_LATEX ));    then install_latex;    fi
if (( WITH_SKILLS ));   then install_skills;   fi
if (( WITH_PROJECTS )); then install_projects; fi
```

`set -e` is in effect (line 6: `set -euo pipefail`), so a non-zero return from any `install_*` function now propagates and aborts the install. The behavioural change:
- Successful install → still exits 0.
- Disabled module (`WITH_X=0`) → still skipped, exits 0.
- **Failed enabled module → now aborts loudly with the failing function's exit code.**

Trade-off: a partial install no longer claims success. If the user wants "best-effort" semantics, they can wrap individual modules with `|| note "<module> failed (continuing)"`, but that's an explicit decision per module — not a default that swallows everything.

### F7 — replace line 792

From:
```sh
main "$@"
```
to:
```sh
# Run main only when invoked directly. Sourcing the file (e.g. for unit tests
# that want to extract individual functions like seed_env) skips main.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
```

`BASH_SOURCE[0]` is the path to the file being sourced; `$0` is the script that bash was invoked as. They match only when the file is run directly. Standard idiom.

`tests/test-install-projects.sh` is **not** modified in this PR — its current awk-slice approach still works (defensive: loose slices are tolerant). A follow-up PR can simplify the test once the BASH_SOURCE guard is on master, but that's deferred to keep this PR's scope tight.

### F8 — replace lines 594-598

From:
```sh
note "installing Docker Engine via official apt repo"
run sudo install -m 0755 -d /etc/apt/keyrings
run sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
run sudo chmod a+r /etc/apt/keyrings/docker.asc
run bash -c 'echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null'
```

To:
```sh
note "installing Docker Engine via official apt repo"
local docker_distro=""
case " $DISTRO_ID " in
  *ubuntu*) docker_distro="ubuntu" ;;
  *debian*) docker_distro="debian" ;;
  *)        err "install_docker: unsupported distro '$DISTRO_ID'; expected ubuntu or debian"; return 1 ;;
esac
run sudo install -m 0755 -d /etc/apt/keyrings
run sudo curl -fsSL "https://download.docker.com/linux/${docker_distro}/gpg" -o /etc/apt/keyrings/docker.asc
run sudo chmod a+r /etc/apt/keyrings/docker.asc
run bash -c "echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${docker_distro} \$(. /etc/os-release && echo \\\"\$VERSION_CODENAME\\\") stable\" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null"
```

Decisions:
- **Use `case " $DISTRO_ID "` with whitespace padding** — matches the convention at line 192 (the existing distro whitelist). `$DISTRO_ID` is `${ID_LIKE:-$ID}` so on derivatives like Mint/Pop_OS it'll contain `ubuntu`; on MX/Devuan it contains `debian`.
- **Explicit `err` + `return 1` on unsupported** — F6 makes the `install_docker` failure now propagate via the new `if`-block contract. No silent fallback to ubuntu.
- **Heredoc-style mixed-quoting on the `bash -c` line** — original used single-quoted with `$(. /etc/os-release && ...)` evaluated at run-time; new version uses double-quote to interpolate `${docker_distro}` once but keeps `$(...)` and `$VERSION_CODENAME` lazy by escaping. Verified: `dpkg --print-architecture` and `VERSION_CODENAME` evaluate at the `bash -c` runtime, not at `install.sh`'s parse time. Same behaviour as before.

## Out of scope

- Migrating the awk-slice in `tests/test-install-projects.sh` to clean source — follow-up PR (deferred to land BASH_SOURCE guard first).
- F9-F14 (zprofile, tmux, gitconfig, zshrc, zshenv MED bugs) — separate PRs.
- Refactoring `install_node`/`install_go`/etc. internals — out of scope.
- `--keep-going` / `--best-effort` mode for the new strict behaviour — YAGNI for now; user can always re-run with subset flags.

## Verification

```bash
# 1. Syntax + shellcheck
bash -n install.sh
shellcheck -S error install.sh

# 2. F6 — module failure now propagates
#    Mock: source install.sh in a sub-shell with install_node overridden to fail.
(
  set -e
  source ./install.sh 2>/dev/null  # F7 guard means main doesn't run
  install_node() { return 1; }
  WITH_NODE=1 WITH_GO=0 WITH_RUST=0 WITH_DOCKER=0 \
  WITH_LATEX=0 WITH_SKILLS=0 WITH_PROJECTS=0 \
  set +e
  # run only the relevant module loop fragment manually:
  if (( WITH_NODE )); then install_node; fi
  echo "exit=$?"
)
# Expect: exit=1 (was: exit=0 with the old || true pattern)

# 3. F7 — sourcing skips main
(
  source ./install.sh 2>&1 | head -5
  type seed_env >/dev/null && echo "OK: seed_env is callable"
  type main >/dev/null && echo "OK: main is defined but not invoked"
)
# Expect: no apt-get / brew commands executed; "OK:" lines printed.

# 4. F8 — DISTRO_ID branching
#    Static check: replacement contains both linux/ubuntu and linux/debian
grep -E 'linux/\$\{docker_distro\}' install.sh   # OK once
! grep -E 'linux/ubuntu/gpg' install.sh           # gone
! grep -E 'linux/ubuntu \$\(' install.sh          # gone
grep -F 'install_docker: unsupported distro' install.sh

# 5. End-to-end smoke
bash install.sh --help                                          # exit 0
bash install.sh --dry-run --with-projects=0 2>&1 | tail -10     # no errors
bash tests/test-zsh-init.sh        # all PASS
bash tests/test-install-projects.sh  # all PASS (existing awk-slice still works)
```

(Note for QA agent: replace `grep` with `rg` per CLAUDE.md.)

## Acceptance criteria

- [ ] `bash -n install.sh` exits 0
- [ ] `shellcheck -S error install.sh` no error-level diagnostics
- [ ] F6 — All 7 module dispatch lines use `if (( WITH_X )); then install_x; fi`
- [ ] F6 — Mock failure of `install_node` causes overall non-zero exit
- [ ] F7 — `BASH_SOURCE[0] == $0` guard around `main "$@"`
- [ ] F7 — Sourcing `install.sh` does NOT trigger `main` (no apt/brew calls)
- [ ] F7 — `seed_env` and `main` callable via source
- [ ] F8 — Docker URL uses `${docker_distro}` interpolation
- [ ] F8 — Unsupported distro (`DISTRO_ID=fedora`) returns 1 with explicit error
- [ ] All existing tests pass: `tests/test-zsh-init.sh`, `tests/test-install-projects.sh`
- [ ] Single commit, SSH-signed
- [ ] No other files modified beyond `install.sh` and the spec promotions (final task)

## Risk

- **F6: low-medium** — semantic change from "report success on partial failure" to "abort on partial failure". Strictly safer behaviour; users who relied on partial installs (probably nobody — this is personal dotfiles) will need to re-run with explicit per-module flags.
- **F7: negligible** — pure additive guard. Backward-compatible with every existing invocation.
- **F8: negligible** — only Debian users see behavioural change, and that change is "now works correctly" instead of "broke silently".

## Phase 3 integration test (final task only)

In task-3's worktree, after task-3's own self-test passes:

1. **Static checks across all touched files**:
   - `bash -n .ctags.sh .ai-commit.sh .ai-commit-msg.sh install.sh` → all green
   - `shellcheck -S error .ctags.sh .ai-commit.sh .ai-commit-msg.sh install.sh` → no error-level diagnostics

2. **Existing TAP-13 test suite**:
   - `bash tests/test-zsh-init.sh` → all PASS (no regression from any task)
   - `bash tests/test-install-projects.sh` → all PASS (awk-slice still works post-F7)

3. **End-to-end smoke**:
   - `bash install.sh --help` → exit 0
   - `bash install.sh --dry-run --with-projects=0` → exit 0, no apt/brew side effects

4. **Cross-task regression**:
   - F1 (`.ctags.sh`): re-run the sandbox behavioural test
   - F2 (`.ai-commit.sh`): grep confirms `--skip` gone, `--abort` present
   - F3 (`.ai-commit-msg.sh`): grep confirms `claude-sonnet-4-7` default

5. **Skill flow tests**: N/A (no `*/SKILL.md` modified)
