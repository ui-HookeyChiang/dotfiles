---
kind: spec
status: done
created: 2026-05-10
slug: test-install-os
---

# Design: `tests/test-install-os.sh` — install.sh OS-branch unit tests

**Date:** 2026-05-10
**Status:** Done (brainstorming bypassed — see Background)
**Owner:** hookey.chiang@ui.com

## Background

The dotfiles code review (and the silent-failure-bugs stack that closed PR #19/#21/#22/#24) made a structural finding: **`install.sh` has multiple OS branches (`linux`/`macos`, `ubuntu`/`debian`, bash version, distro-id detection) with zero unit-test coverage**. All existing TAP-13 tests run on the test host's native OS:

- `tests/test-zsh-init.sh` — 9 of 10 tests OS-agnostic; only T6 has a `Linux`-only branch (mesg tty-guard) that SKIPs on macOS.
- `tests/test-install-projects.sh` — 9 of 9 tests OS-agnostic (all `--dry-run` plumbing).
- `tests/test-install-secrets.sh` — 5 of N tests are macOS-only (Keychain).

Concrete consequences observed during the silent-failure-bugs work:
- F8 (Docker repo URL `linux/ubuntu` hardcode) had a **Debian regression** lurking unnoticed because no test exercised `DISTRO_ID=debian`.
- F6 (`(( X )) && fn || true` swallowing module failures) was silently re-introduced by PR #20 when it copy-pasted the broken pattern for the new `WITH_SECRETS` module — no test caught it.
- F7 (`main "$@"` source-safety) — verified by ad-hoc Dev/QA tests but not encoded as regression suite.
- macOS ships bash 3.2 by default; `install.sh` uses associative arrays (`declare -A PKG_BINARIES`) which bash 3.2 can't parse. **PR #25** added a Linux-only guard so macOS bash 3.2 doesn't choke at load. T10 in this PR verifies the guard holds (sourcing install.sh exits 0 under any host bash version).

Brainstorming bypassed: scope is "encode the install.sh OS-branch contracts as regression tests". One file, ~200 lines, no design tradeoffs.

## Goal

Single PR adding `tests/test-install-os.sh` (TAP-13 format, matching `test-install-projects.sh` style). 12 numbered tests covering install.sh's OS branches, F6/F7/F8 regression, bash version requirement, and OS-aware sanity.

This PR is **prerequisite for PR #2** (`.github/workflows/test.yml`) — the CI workflow needs this test file to exist before it can be wired into the matrix.

## Locked parameters

### Test inventory (12 tests)

| # | Test | Covers | Gate |
|---|------|--------|------|
| T1 | `bash -n install.sh` clean | sanity (subset of test-install-projects T1) | always |
| T2 | source-safe: `source install.sh` does NOT invoke `main` | F7 regression | always |
| T3 | sourced exposes `seed_env`, `seed_secrets`, `main` | F7 regression | always |
| T4 | F6 propagation: mock `install_node` failure → rc=1 | F6 regression | always |
| T5 | F6 skip: `WITH_NODE=0` → `install_node` not called | F6 negative case | always |
| T6 | F8 ubuntu: `DISTRO_ID=ubuntu` + `--dry-run` → output contains `linux/ubuntu` | F8 ubuntu branch | always |
| T7 | F8 debian: `DISTRO_ID=debian` + `--dry-run` → output contains `linux/debian`, NOT `linux/ubuntu` | **F8 debian branch (previously untested)** | always |
| T8 | F8 unsupported: `DISTRO_ID=fedora` → `install_docker` returns 1 + emits `unsupported distro` error | F8 fail-loud | always |
| T9 | F8 ID_LIKE: `DISTRO_ID="something ubuntu"` matches ubuntu branch (case spaces) | F8 ID_LIKE matching for derivatives (Mint/Pop on Ubuntu, MX/Devuan on Debian) | always |
| T10 | source-cleanly: `bash -c 'source install.sh'` exits 0 under host bash (incl. bash 3.2 post-PR #25) | macOS bash 3.2 guard verification (PR #25) | always |
| T11 | (macOS-only) `seed_secrets` function exists and is callable; `is_macos`-style guards present | macOS path sanity | SKIP on Linux |
| T12 | (Linux-only) `detect_os` reads `/etc/os-release` and populates `DISTRO_ID` non-empty | Linux distro detection | SKIP on macOS |

### Test approach (CRITICAL — no real installs)

Each test runs in a subshell that:
1. Overrides `run()`, `note()`, `log()`, `err()` with no-ops or capture-to-variable, so `sudo apt-get`, `brew install`, `git clone` are never executed.
2. Sources `install.sh` (now safe per F7 guard — `main` won't run).
3. Sets `DRY_RUN=1` (or relevant flag-derived state) before invoking the function under test.
4. For F8/T6-T9: also sets `DISTRO_ID=<value>` and `OS=linux` (since `install_docker` is Linux-only). Calls `install_docker` directly. Captures `note`/`err` output, checks for the expected URL substring.
5. For F6 propagation (T4): uses the BashFAQ #105 workaround — `bash -c '...'` instead of `( ... )` subshell, because bash disables `set -e` inside subshells whose parent is in a `&&`/`||` context.

### File location

`tests/test-install-os.sh`. Permissions: `+x` (match other test scripts).

### TAP plan

```
1..12
# OS=<host_os> bash=<host_bash_version>
ok 1 - install.sh passes bash -n syntax check
ok 2 - source install.sh does not invoke main (F7 regression)
ok 3 - sourced install.sh exposes seed_env, seed_secrets, main
...
# passed=N failed=M of 12
```

### What's NOT covered (out of scope)

- Real `apt-get install` / `brew install` execution — too slow, requires network/sudo, host pollution.
- macOS Keychain interaction — `tests/test-install-secrets.sh` already covers.
- `tests/test-install-projects.sh` OS-aware extensions — separate concern.
- Container-based testing (Debian 12 image, Arch unsupported-distro test) — deferred to follow-up PR after CI matrix lands.
- Migration of `tests/test-install-projects.sh:191` awk-slice to clean source (now possible post-F7) — separate cleanup PR.

## Verification

```bash
# 1. Syntax
bash -n tests/test-install-os.sh

# 2. shellcheck
shellcheck -S error tests/test-install-os.sh

# 3. TAP-13 format compliance
bash tests/test-install-os.sh | head -1 | rg -qF '1..12'
bash tests/test-install-os.sh | tail -1 | rg -qE '^# passed=[0-9]+ failed=[0-9]+ of 12$'

# 4. All non-OS-gated tests pass on the host
bash tests/test-install-os.sh
# Expect: 0 failed; some SKIP entries on T11 (Linux host) or T12 (macOS host)

# 5. Existing test suite still green (no install.sh regression)
bash tests/test-zsh-init.sh        # 10/10
bash tests/test-install-projects.sh  # 9/9

# 6. The new test file does NOT modify install.sh — diff scope guard
test -z "$(git diff --name-only origin/master..HEAD | rg -v '^tests/test-install-os\.sh$|^docs/specs/(active|done)/.+\.md$')"
```

## Acceptance criteria

- [ ] `bash -n tests/test-install-os.sh` exits 0
- [ ] `shellcheck -S error` no diagnostics
- [ ] All 12 tests have a numbered TAP line; T11/T12 emit SKIP correctly per host
- [ ] On Linux host: passed=11 + 1 SKIP (T11), failed=0
- [ ] On macOS host: passed=11 + 1 SKIP (T12), failed=0
- [ ] T7 (Debian branch) actually catches the pre-fix `linux/ubuntu` hardcode if reverted (positive verification)
- [ ] T10 actually fails if PR #25's Linux guard is reverted (sourcing install.sh under bash 3.2 would throw `neovim: unbound variable`, rc≠0) — verified manually by adversarial revert
- [ ] No `install.sh` modifications in this PR
- [ ] Single SSH-signed commit
- [ ] Spec promote: `active/2026-05-10-test-install-os.md` → `done/` in this same commit (single-task PR, no follow-up bookkeeping)

## Risk

- **Low.** New test file only; no production code changes. Test failures only block this PR's own CI, not master. Worst case: a test is over-fitted to the current install.sh implementation and breaks on a future refactor — addressable by adjusting the test, not behaviour.

## Future work (NOT this PR)

- **PR #2**: `.github/workflows/test.yml` matrix runs `tests/test-{zsh-init,install-projects,install-secrets,install-os}.sh` on `ubuntu-22.04 + macos-14`. Depends on this PR landing first.
- **Follow-up #3** (optional): container matrix (Debian 12, Arch) for `--dry-run` smoke testing of unsupported distro.
- **Follow-up #4** (optional): migrate `test-install-projects.sh:191` awk-slice to clean `( source install.sh; ... )` now that F7 guard exists.
