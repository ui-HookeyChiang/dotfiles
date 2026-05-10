---
kind: spec
status: done
created: 2026-05-10
slug: ci-test-matrix
---

# Design: GitHub Actions multi-OS test matrix

**Date:** 2026-05-10
**Status:** Done (brainstorming bypassed — see Background)
**Owner:** hookey.chiang@ui.com

## Background

The dotfiles repo accumulated 4 TAP-13 test files with strong OS-branch coverage (post PR #26):

- `tests/test-zsh-init.sh` — 9 OS-agnostic + 1 Linux-only test
- `tests/test-install-projects.sh` — 9 OS-agnostic tests
- `tests/test-install-secrets.sh` — Mostly macOS-only (Keychain) tests
- `tests/test-install-os.sh` — 12 install.sh OS-branch tests, 1 Linux-only + 1 macOS-only

But **none of these run on macOS**. Every test currently runs only on the developer's Linux host (or wherever they happen to invoke them). PR #25's macOS bash 3.2 guard never had its target OS exercised; PR #26's T10 (which verifies that guard) currently only proves "install.sh sources cleanly on Linux bash 5.2", a tautology.

A multi-OS CI matrix closes this gap. The repo currently has no `.github/workflows/` directory at all — this is the first CI workflow.

Brainstorming bypassed: scope is "wire 4 existing test files into a 2-OS matrix on GitHub Actions". One file, ~80 lines, no design tradeoffs. The user already approved the structure in chat.

## Goal

Add `.github/workflows/test.yml`. On every `pull_request` and `push: master`, run all 4 TAP test files plus static checks (`bash -n`, `shellcheck`) on `ubuntu-22.04` and `macos-14`. Fail the workflow if any step exits non-zero.

This is **PR #2** in the CI uplift series. PR #1 (PR #26) added `tests/test-install-os.sh`; this PR wires it (and the others) into CI.

## Locked parameters

### Workflow shape

| Aspect | Decision |
|--------|----------|
| **File path** | `.github/workflows/test.yml` (single file; if more workflows added later, prefix conventions can emerge) |
| **Name** | `tests` |
| **Triggers** | `pull_request` (any base) + `push: branches: [master]` |
| **Permissions** | `contents: read` only (no write — minimal supply-chain surface) |
| **Concurrency** | `group: tests-${{ github.ref }}, cancel-in-progress: true` (cancel stale runs on rapid pushes) |
| **Matrix** | `os: [ubuntu-22.04, macos-14]`; `fail-fast: false` (per-OS independence) |
| **Action versions** | `actions/checkout@v4` (tag, not SHA — accept the trade-off; revisit if supply-chain concern grows) |

### Per-OS dependencies

| OS | Install method | Packages |
|----|----------------|----------|
| `ubuntu-22.04` | `sudo apt-get update && sudo apt-get install -y` | `zsh bat shellcheck` |
| `macos-14` | `brew install --quiet` | `zsh bat shellcheck` |

**Bash version on each runner**:
- ubuntu-22.04 default `bash` is 5.x
- macos-14 default `bash` (`/bin/bash`) is 3.2.57 — **deliberately kept**: this is what verifies PR #25's guard works in real life. We do NOT `brew install bash` on macOS; we use Apple's stock 3.2 to drive `bash` invocations of test scripts.

Test scripts have shebangs `#!/usr/bin/env bash` so they pick up the first `bash` on PATH. macOS has Homebrew bash on PATH after `brew install` only if `bash` was explicitly installed — we don't, so test scripts run under `/usr/local/bin/bash` if present from a previous brew formula's deps, but most likely under `/bin/bash` 3.2.

**However**: test scripts themselves use bash-4 features (`mapfile`, `[[ ... =~ ... ]]`, etc.). To avoid the test scripts themselves choking on bash 3.2, **invoke each test via `bash -n` for syntax check on host bash, then run with the test runner's preferred bash**. Concretely: on macOS, install Homebrew bash for *running* the tests (the tests are dev-tooling and need bash 4+), but **install.sh itself must remain testable under stock bash 3.2** (which is what T10 in test-install-os.sh verifies — and that test runs under whichever bash invokes it).

Decision: **install Homebrew bash on macOS** so the test scripts can run, but **do not change install.sh's shebang or behaviour**. The macos-14 job thus has both `/bin/bash` (3.2) and `/usr/local/bin/bash` (5.x). T10 specifically uses `bash -c` to spawn a sub-bash; on macOS this picks the first `bash` on PATH (Homebrew's). To force T10 to use stock bash 3.2 on macOS, T10 would need an explicit path — out of scope here, follow-up improvement.

For this PR's scope: deliberately accept that T10 on macOS-14 CI runs under bash 5 (Homebrew), which makes T10 a tautology there too. Container/explicit-bash matrix is follow-up #3. **Pragmatic value of this PR**: catches OS-divergent failures in everything *else* (T6/T7/T8/T9 distro paths, T11 macOS Keychain path, test-install-secrets.sh, test-zsh-init.sh's mesg tty-guard).

### Step inventory

| # | Step | Command(s) |
|---|------|------------|
| 1 | Checkout | `actions/checkout@v4` (default settings) |
| 2 | Install deps (Linux) | `if: runner.os == 'Linux'` → `sudo apt-get update -qq && sudo apt-get install -y -qq zsh bat shellcheck` |
| 3 | Install deps (macOS) | `if: runner.os == 'macOS'` → `brew install --quiet zsh bat shellcheck bash` |
| 4 | Symlink batcat→bat (Linux) | `mkdir -p ~/.local/bin && ln -sf "$(command -v batcat)" ~/.local/bin/bat` (mirrors install.sh's runtime behaviour, lets `command -v bat` resolve in test-zsh-init T5) |
| 5 | bash -n syntax | `bash -n .ctags.sh .ai-commit.sh .ai-commit-msg.sh install.sh` |
| 6 | shellcheck (bash dialect) | `shellcheck -S error .ai-commit.sh .ai-commit-msg.sh install.sh` |
| 7 | shellcheck (sh dialect for .ctags.sh) | `shellcheck -s sh -S error .ctags.sh` |
| 8 | Run test-zsh-init.sh | `bash tests/test-zsh-init.sh` |
| 9 | Run test-install-projects.sh | `bash tests/test-install-projects.sh` |
| 10 | Run test-install-secrets.sh | `bash tests/test-install-secrets.sh` |
| 11 | Run test-install-os.sh | `bash tests/test-install-os.sh` |

Each step's exit code propagates; first non-zero fails the job. TAP output goes to stdout (Actions captures it).

### What's NOT in scope

- Container matrix (Debian 12, Arch, Fedora) — follow-up #3.
- Real `bash install.sh --dry-run` smoke against the runner — follow-up; risks state pollution + sudo timeouts.
- CodeQL / Dependabot / supply-chain pinning — separate workflow file (`security.yml`), follow-up.
- Caching brew/apt to speed up CI — follow-up if observed slow.
- Job-level timeout — accept default 6 hours; tests should run in <2 min.
- Slack/webhook notifications — follow-up if needed.
- Concurrency groups beyond ref-based — current shape sufficient.
- macOS T10 tightening (force stock bash 3.2 vs Homebrew) — known limitation, follow-up.

## Verification

This is a CI workflow file — its real verification is **the workflow successfully running on the PR itself**. Pre-merge checks:

```bash
# 1. YAML well-formed
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/test.yml'))"

# 2. actionlint (if available — install via `go install github.com/rhysd/actionlint/cmd/actionlint@latest`)
command -v actionlint && actionlint .github/workflows/test.yml || echo "SKIP actionlint"

# 3. Diff scope: only this new file + spec
git diff --name-only origin/master..HEAD
# Expect: .github/workflows/test.yml + docs/specs/(active|done)/2026-05-10-ci-test-matrix.md

# 4. After PR opens: GitHub Actions runs both OS jobs and both PASS.
#    Verify: gh pr checks <PR> shows green checkmarks for both ubuntu-22.04 and macos-14.
```

Adversarial: if any test was silently broken on macOS, this PR's CI run is the first time we'd find out — so a matrix `failure` on first PR-CI run is informative, not a setback.

## Acceptance criteria

- [ ] `python3 -c "yaml.safe_load(...)"` succeeds (well-formed YAML)
- [ ] Workflow file declares `permissions: contents: read` and `concurrency: { group, cancel-in-progress }` blocks
- [ ] Matrix has both `ubuntu-22.04` and `macos-14`; `fail-fast: false`
- [ ] All 4 test files run as separate steps (so failures attribute to specific test files in the Actions UI)
- [ ] Static checks (`bash -n` + `shellcheck`) run as separate steps from test files
- [ ] `bash -n` covers `.ctags.sh .ai-commit.sh .ai-commit-msg.sh install.sh`
- [ ] `shellcheck -s sh -S error` covers `.ctags.sh`; `shellcheck -S error` covers the bash files
- [ ] On the PR after push: both matrix jobs (ubuntu-22.04 + macos-14) complete; their outcomes are documented in the PR body's Verification section. If any job fails, the failure is investigated and either fixed (separate commit) or accepted as a known issue with explicit follow-up issue
- [ ] Spec promote: `active/` → `done/` in this same commit (single-task PR convention)
- [ ] Single SSH-signed commit
- [ ] No production code changes in this PR (other than the new workflow file + spec)

## Risk

- **Low.** Pure additive change. Workflow file failures only block this PR's CI, not master. If macOS-14 surfaces real test bugs, those are bugs that *should* fail — caught now is better than caught by a real macOS user installing the dotfiles.
- **Real macOS test exposure**: this is the first time `test-install-secrets.sh` runs on actual macOS. It might surface mock/Keychain assumptions that don't hold on real Keychain. If so, fix in a follow-up PR.

## Future work

- Follow-up #3: container matrix (Debian 12 image for `--dry-run` smoke; Arch for `unsupported distro` fail-loud).
- Follow-up #4: cache brew/apt downloads.
- Follow-up #5: tighten T10 on macOS to force stock bash 3.2 invocation.
- Follow-up #6: add `permissions:` block to all future workflows by default; consider `securitylab/permissions-action` audit.
