---
kind: spec
status: done
created: 2026-05-09
slug: install-projects-deploy
---

# Design: `--with-projects` flag for personal project deployment

**Date:** 2026-05-09
**Status:** Proposed (draft for review)
**Owner:** hookey.chiang@ui.com

## Goal

Add a single `--with-projects` opt-in flag to `install.sh` that clones and bootstraps three personal repos (`llm-wiki`, `stock-target-finder`, `telegram-claude-bridge`) on a fresh machine, idempotently, matching the existing `--with-*` module pattern.

## User-confirmed parameters (LOCKED — do not re-litigate)

These were decided in brainstorming and are inputs to this spec, not open questions.

1. **Repos (3)**
   - `https://github.com/ui-HookeyChiang/llm-wiki`
     Python; ships its own `install.sh`; `.gitmodules` (Awesome-CV, personal-wiki, meta-wiki).
   - `https://github.com/ui-HookeyChiang/stock-target-finder`
     Python; `pyproject.toml` + `uv.lock`; ships its own `install.sh`; no submodules; has `.python-version` + `.env.example`.
   - `https://github.com/ui-HookeyChiang/telegram-claude-bridge`
     TypeScript; `package.json`; no `install.sh`; no submodules; has `.env.example`.

2. **Clone path**
   Env var `$DOTFILES_PROJECTS_DIR`, default `$HOME`. Default lands repos at `~/llm-wiki`, `~/stock-target-finder`, `~/telegram-claude-bridge`.

3. **Depth**
   Clone → `git submodule update --init --recursive` (when `.gitmodules` present) → repo's own `install.sh` (when present) OR fallback dependency install (npm / uv) → done. Three concerns in that order, each guarded by a skip check.

## Design decisions (answers to the 7 open questions)

### 1. Function shape: dispatch table over a config array

**Decision:** Single `install_projects()` driver that loops over a config array. Per-repo divergence (`uv` vs `npm` vs nested `install.sh`) is encoded as fields in the array entry, not in separate functions.

**Rationale:**
- We have exactly 3 repos and they share 80% of the work (clone, submodule init, idempotency check, dry-run). DRY beats premature decomposition.
- The 20% that differs (post-clone install command) collapses into one field per entry. A small `case` inside the loop dispatches it.
- 3 separate `install_<repo>()` functions would triple the boilerplate (clone branch, submodule branch, skip-check branch) for no behavior gain.
- If a 4th repo gets added later with a wildly different stack, the dispatch table extends naturally; if it can't, that's the moment to split — not now.

**Shape sketch (pseudo-code, NOT bash):**
```
PROJECTS = [
  { name: "llm-wiki",                url: "...", install: "repo-script" },
  { name: "stock-target-finder",     url: "...", install: "repo-script" },
  { name: "telegram-claude-bridge",  url: "...", install: "npm" },
]
for p in PROJECTS:
    clone_or_skip(p)
    init_submodules_if_any(p)
    run_install_step(p)   # dispatches on p.install
```

### 2. Dependency install strategy: trust repo `install.sh` when present, fall back to package-manager defaults; auto-flip `--with-node` when needed

**Decision:**
- `llm-wiki`: run `bash install.sh` from inside the cloned dir. Trust it.
- `stock-target-finder`: run `bash install.sh` from inside the cloned dir. Trust it. **Do NOT** pre-install `uv` from `install.sh` — if the repo's own script needs `uv`, that's its responsibility to bootstrap (or its README's). We don't pollute the dotfiles installer with transitive language-tool concerns.
- `telegram-claude-bridge`: no `install.sh`, so fall back: `cd <repo> && npm install` if `package.json` exists.
- **`--with-projects` auto-enables `--with-node`** (user-confirmed 2026-05-09). When `WITH_PROJECTS=1`, `parse_flags()` (or just before `main()` runs the optional modules) sets `WITH_NODE=1` automatically and `install_node` runs first so `npm` is available by the time `install_projects` reaches `telegram-claude-bridge`.

**Rationale:**
- Each repo owns its own dep tree. Re-implementing that knowledge in `install.sh` is a maintenance trap (the repo's `install.sh` will drift; ours won't track it).
- Auto-flip beats warn-and-skip on UX: a fresh-machine bootstrap that prints "skip telegram-claude-bridge — Node missing" and exits 0 with 2/3 installed is a footgun for the user who set `--with-projects` precisely to skip thinking about prerequisites. Implicit dep ordering is fine here because the dependency is one-way (projects → node, never the reverse) and `--with-node` is already in the public API.
- Order in `main()`: ensure `install_node` runs **before** `install_projects` (it already does — node is listed before projects in the optional-modules block). The auto-flip happens at the end of `parse_flags` so the existing ordering Just Works.
- `install_projects()` still checks `command -v npm` defensively before the npm fallback (e.g., user passed `--no-symlink` style overrides or `install_node` failed silently). If npm missing despite `WITH_NODE=1`, print "ERROR: telegram-claude-bridge needs npm but node install appears to have failed" and per-repo fail-soft (decision 3).
- If a repo's `install.sh` requires sudo or interactive input, that's a property of the upstream repo. We document the assumption ("repo install.sh must be non-interactive") in the spec; if it later breaks, fix the repo, not the dotfiles.

### 3. Failure handling: fail-soft per repo, fail-fast on infra errors

**Decision:**
- Wrap each repo's clone+install block so that a failure in **one repo** prints `WARN: <repo> install failed (continuing)` and moves to the next.
- Infra failures upstream of the loop (e.g., `mkdir $DOTFILES_PROJECTS_DIR` denied, `git` missing) still fail-fast as `set -euo pipefail` dictates.

**Rationale:**
- Other `--with-*` modules install infra (Node, Go, Rust). One failure there cascades — if Node is broken, nothing else Node-dependent works. Fail-fast is correct.
- Personal projects are user-data. If `stock-target-finder` fails, that doesn't break `telegram-claude-bridge`. Aborting the whole installer would be hostile to the user, who'd then have to manually figure out which step ran and which didn't.
- Mechanism: set up a per-repo subshell with `( ... ) || { warn; continue; }`. The outer `set -e` still applies; the local failure is contained.
- Loop end-of-run prints a summary: `installed: 2/3, failed: stock-target-finder`. Non-zero exit code if anything failed, so CI / scripted callers can detect.

### 4. Branch / version locking: clone main; never auto-pull on re-run

**Decision:** First run: `git clone <url> <dir>`. Re-run when `<dir>/.git` already exists: skip the clone entirely. Do **not** `git pull --ff-only`.

**Rationale:**
- This is a **bootstrap** installer, not an updater. The `--with-node` analog doesn't auto-upgrade Node on re-run; it only installs if missing. Same model.
- Auto-pulling silently drags the user's local checkout forward, potentially clobbering local work-in-progress (even with `--ff-only`, it disrupts the working tree's expected state and triggers cascading submodule updates).
- If the user wants updates, they `cd ~/llm-wiki && git pull` themselves. That's clearer.
- We DO re-run `git submodule update --init --recursive` even on re-run (idempotent: no-op if already initialized; corrects partial inits).

### 5. `.env` handling: copy `.env.example → .env` with FIXME sentinels, print reminder

**Decision** (user-confirmed 2026-05-09):
- If `.env.example` exists and `.env` does **not** exist:
  1. `cp .env.example .env` (idempotent: skip the copy entirely if `.env` already exists — never overwrite the user's filled-in secrets).
  2. Rewrite each value field in the new `.env` to `FIXME-PLEASE-FILL` so empty/blank example values don't masquerade as real secrets.
  3. Print: `note: created <repo>/.env from .env.example — fill in FIXME-PLEASE-FILL values before first run`.
- If `.env` already exists, do **nothing** — print `note: <repo>/.env present, leaving as-is`.

**Rationale:**
- Onboarding flow is the priority: a fresh-clone user can immediately see exactly which keys need filling without having to grep `.env.example` themselves.
- The FIXME sentinel makes failures **loud and grep-able**: when the app blows up with `ValueError: API key 'FIXME-PLEASE-FILL'`, the error string itself tells the user where to look. That's better than a missing-file error that varies per stack (Python KeyError vs Node `process.env.X is undefined`).
- Idempotent skip-when-exists protects already-configured `.env` files from being clobbered on re-run (critical — secrets are user-data).
- Mechanism: a small awk pass that replaces everything after the first `=` on each non-comment, non-blank line with `FIXME-PLEASE-FILL`. Comments (`# ...`) and blank lines pass through.
- Out of scope: secret-store integration, prompting for values, encryption. The FIXME sentinel is the breadcrumb; the user fills it in.

### 6. `DOTFILES_PROJECTS_DIR` creation: `mkdir -p` it, fail-fast if mkdir fails

**Decision:**
- If `$DOTFILES_PROJECTS_DIR` doesn't exist, `mkdir -p "$DOTFILES_PROJECTS_DIR"`.
- If mkdir fails (permission, read-only FS), error and exit — this is an infra failure, fail-fast (per decision 3).

**Rationale:**
- The default is `$HOME`, which always exists. So this branch only fires for users who set a custom path like `~/code/personal/`.
- If they bothered to set the env var, they want the dir created. `mkdir -p` is cheap and safe.
- No prompt, no guess. If the path is invalid, the error message tells them.

### 7. Path conflict with the dotfiles repo itself: document, don't engineer around

**Decision:** No special handling. Document in spec + module note: "if you cloned dotfiles itself to `~/dotfiles`, that name is reserved by you, not by this script. None of the 3 project names collide with `dotfiles`."

**Rationale:**
- The 3 repo names are `llm-wiki`, `stock-target-finder`, `telegram-claude-bridge`. None equal `dotfiles` or any of the existing whitelist entries (`.zshrc`, `.config/nvim`, etc.).
- Future-proofing for a hypothetical 4th repo named `dotfiles` is YAGNI.
- If `$HOME/llm-wiki` happens to already exist as an unrelated dir (e.g., the user manually made one), the clone-skip check (decision 4) would treat it as "already there" and skip. That's the wrong behavior, but it's also vanishingly unlikely. We accept the risk; if it bites, we add a "is this actually a git repo with the expected remote?" check later.

## Implementation outline

Pseudo-code, **not** runnable bash. Final bash goes in Phase 2.

```
# Globals
WITH_PROJECTS=0
PROJECTS_DIR="${DOTFILES_PROJECTS_DIR:-$HOME}"

# Project config (table-driven)
PROJECT_NAMES=(llm-wiki stock-target-finder telegram-claude-bridge)
PROJECT_URLS=(
  https://github.com/ui-HookeyChiang/llm-wiki
  https://github.com/ui-HookeyChiang/stock-target-finder
  https://github.com/ui-HookeyChiang/telegram-claude-bridge
)
PROJECT_INSTALL=(repo-script repo-script npm)

# Flag parsing additions
--with-projects -> WITH_PROJECTS=1
--all           -> also flip WITH_PROJECTS=1
# Auto-flip --with-node when --with-projects is set, after parse_flags():
if (( WITH_PROJECTS && ! WITH_NODE )); then
  WITH_NODE=1
  note "--with-projects auto-enabled --with-node (telegram-claude-bridge needs npm)"
fi

# Main flow
install_projects():
  log "install_projects"
  if not exists $PROJECTS_DIR:
    note "creating $PROJECTS_DIR"
    run mkdir -p "$PROJECTS_DIR"

  failures=()
  for i in 0..2:
    name=${PROJECT_NAMES[i]}
    url=${PROJECT_URLS[i]}
    method=${PROJECT_INSTALL[i]}
    dst="$PROJECTS_DIR/$name"

    (
      install_one_project "$name" "$url" "$method" "$dst"
    ) || failures+=("$name")

  if ${#failures[@]} > 0:
    err "failed: ${failures[*]}"
    return 1
  note "installed all: ${PROJECT_NAMES[*]}"

install_one_project(name, url, method, dst):
  # 1. Clone (idempotent)
  if [[ -d "$dst/.git" ]]:
    note "skip clone $name (already cloned at $dst)"
  else:
    note "cloning $name -> $dst"
    run git clone "$url" "$dst"

  # 2. Submodules (idempotent: no-op if no .gitmodules, safe to re-run)
  if [[ -f "$dst/.gitmodules" ]]:
    run git -C "$dst" submodule update --init --recursive

  # 3. Install
  case method:
    repo-script:
      if [[ -x "$dst/install.sh" || -f "$dst/install.sh" ]]:
        note "running $name/install.sh"
        run bash -c "cd '$dst' && bash install.sh"
      else:
        err "$name expected install.sh but none found"; return 1

    npm:
      if ! command -v npm:
        note "skip $name (npm missing — try --with-node --with-projects)"
        return 0
      if [[ -d "$dst/node_modules" ]]:
        note "skip $name npm install (node_modules present)"
      else:
        note "running npm install in $name"
        run bash -c "cd '$dst' && npm install"

  # 4. .env seed (cp + FIXME sentinel)
  if [[ -f "$dst/.env.example" ]]:
    if [[ -f "$dst/.env" ]]:
      note "$name/.env present, leaving as-is"
    else:
      note "creating $name/.env from .env.example with FIXME sentinels"
      run cp "$dst/.env.example" "$dst/.env"
      # Rewrite each KEY=VALUE line so VALUE becomes FIXME-PLEASE-FILL.
      # Comments and blank lines pass through untouched.
      run awk -i inplace 'BEGIN{FS=OFS="="} /^[[:space:]]*#/ || /^[[:space:]]*$/ {print; next} NF>=2 {$2="FIXME-PLEASE-FILL"; print; next} {print}' "$dst/.env"
      note "fill in FIXME-PLEASE-FILL values in $name/.env before first run"
```

> **Note on awk -i inplace:** GNU awk feature. macOS ships BSD awk, which doesn't support `-i inplace`. Fallback: write to a temp file and `mv`. Real implementation will use the temp-file pattern for portability.

## Idempotency contract

For each of the 4 sub-steps per repo, what does re-run do?

| Step                  | First run                                | Re-run, clean state                   | Re-run, partial state                                                                                                                       |
|-----------------------|------------------------------------------|---------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------|
| Clone                 | `git clone` (creates `.git/`)            | `[[ -d $dst/.git ]]` → skip           | If user manually deleted `.git/` but kept files: skip is wrong, but matches our "trust the dir" stance. Document, accept.                   |
| Submodule init        | `git submodule update --init --recursive` | Same command — git no-ops if all initialized | If a submodule was partially initialized (e.g., interrupted clone), re-run completes it. This is exactly the recovery path git intends.     |
| Install (repo-script) | `bash install.sh`                        | Repo's `install.sh` should also be idempotent (their problem). We re-run unconditionally. | Same as clean. We delegate idempotency to the repo's `install.sh`.                                                              |
| Install (npm)         | `npm install`                            | `[[ -d node_modules ]]` → skip         | If `node_modules/` exists but is corrupt/incomplete, we skip and the user has to `rm -rf node_modules && ./install.sh --with-projects`. Document. |
| `.env` seed           | `cp .env.example .env` + rewrite values to `FIXME-PLEASE-FILL` | If `.env` already exists → skip (never clobber filled-in secrets) | If user partially filled in `.env`, we still skip — they own it now. If `.env` is empty / corrupt, user `rm .env && re-run`. |

**Net:** re-run on a clean machine = full install. Re-run on a fully installed machine = all skips, exit 0, ~1 second total.

## Failure modes

| What can go wrong                                | What happens                                                  | User recovery                                                              |
|--------------------------------------------------|---------------------------------------------------------------|----------------------------------------------------------------------------|
| `$DOTFILES_PROJECTS_DIR` not creatable           | `mkdir -p` fails, `set -e` aborts whole `install.sh`          | Fix permissions or pick a different `DOTFILES_PROJECTS_DIR`; re-run.       |
| `git clone` fails (network, auth, repo gone)     | Per-repo failure caught, marked in summary, continues to next | Investigate the specific repo; re-run `--with-projects` to retry just the failed ones (others skip cleanly). |
| Submodule `--init` fails (auth on private submodule) | Per-repo failure                                          | Configure SSH/HTTPS auth; re-run.                                          |
| Repo's `install.sh` fails                         | Per-repo failure                                              | Run repo's `install.sh` manually inside the clone; consult repo's README.  |
| Repo's `install.sh` is interactive                | Hangs the installer                                           | Document upfront: "repo install.sh must be non-interactive." If a repo violates this, fix the repo. Could add a timeout in v2. |
| `npm install` fails (no node, network, peer-dep) | If no node: skip with note. Else: per-repo failure.            | Re-run with `--with-node --with-projects`, or fix the network.             |
| Disk full mid-clone                              | `git clone` fails, per-repo failure                           | Free space, re-run.                                                        |
| User Ctrl-C mid-run                              | Partial clone left in `$dst`; re-run will hit "skip clone" branch even though clone is incomplete | Document: if interrupted, `rm -rf` the partial dir and re-run. Could add a `.git/index.lock` check in v2. |
| Existing non-git dir at `$dst`                    | Clone fails (`fatal: destination path exists and is not an empty directory`) | Per-repo failure with informative git error; user resolves the conflict. |

## Test plan

### Unit (dry-run)

```bash
# T1. Default path, all 3 repos planned, --dry-run prints expected commands
./install.sh --with-projects --dry-run | grep -E '(git clone|submodule update|npm install|install.sh)'
# Expect: 3 'git clone' lines, 1 submodule line (llm-wiki), 2 'install.sh' lines, 1 'npm install' line

# T2. Custom DOTFILES_PROJECTS_DIR
DOTFILES_PROJECTS_DIR=/tmp/proj-test ./install.sh --with-projects --dry-run | grep '/tmp/proj-test/'
# Expect: all 3 clone targets under /tmp/proj-test/

# T3. --all turns on --with-projects
./install.sh --all --dry-run | grep 'install_projects'
# Expect: install_projects step appears in plan

# T4. Without --with-projects, install_projects does NOT run
./install.sh --dry-run | grep 'install_projects'
# Expect: no match
```

### Integration (real clone, throwaway dir)

```bash
# T5. Fresh install into a tmp dir
DOTFILES_PROJECTS_DIR=$(mktemp -d) ./install.sh --with-projects --with-node
# Expect: exit 0, 3 dirs cloned, llm-wiki has Awesome-CV/ etc, telegram-claude-bridge has node_modules/

# T6. Idempotent re-run
DOTFILES_PROJECTS_DIR=<same dir as T5> ./install.sh --with-projects --with-node
# Expect: exit 0, all "skip" notes, no new clones, completes in ~1s

# T7. Per-repo fail-soft: corrupt one repo URL, verify others still install
# (Edit PROJECT_URLS[1] to a bogus URL temporarily)
./install.sh --with-projects --with-node
# Expect: exit non-zero, "failed: stock-target-finder" in summary, llm-wiki + telegram-claude-bridge still installed
```

### Edge cases

```bash
# T8a. --with-projects auto-enables --with-node
./install.sh --with-projects --dry-run 2>&1 | grep -E '(install_node|auto-enabled --with-node)'
# Expect: "auto-enabled --with-node" + install_node block appears in plan

# T8b. --with-projects --with-node explicit (already-on, no double-flip noise)
./install.sh --with-projects --with-node --dry-run 2>&1 | grep -c 'auto-enabled --with-node' | grep -q '^0$'
# Expect: 0 occurrences (already-set, no auto-flip note printed)

# T9a. .env seeded with FIXME sentinels (cp + rewrite)
tmp=$(mktemp -d)
DOTFILES_PROJECTS_DIR=$tmp ./install.sh --with-projects
test -f $tmp/stock-target-finder/.env       # exists
test -f $tmp/telegram-claude-bridge/.env    # exists
grep -q 'FIXME-PLEASE-FILL' $tmp/stock-target-finder/.env
grep -q 'FIXME-PLEASE-FILL' $tmp/telegram-claude-bridge/.env
# Expect: all 4 commands exit 0

# T9b. Re-run does NOT clobber an existing .env
echo 'SHIOAJI_API_KEY=already_filled_in' > $tmp/stock-target-finder/.env
DOTFILES_PROJECTS_DIR=$tmp ./install.sh --with-projects
grep -q 'already_filled_in' $tmp/stock-target-finder/.env
# Expect: exit 0; user-filled value preserved

# T10. Pre-existing non-git dir at clone target
mkdir -p $tmp/llm-wiki && touch $tmp/llm-wiki/foo
DOTFILES_PROJECTS_DIR=$tmp ./install.sh --with-projects
# Expect: per-repo failure for llm-wiki with clear git error; other 2 still install
```

## Out of scope

- **Ongoing repo updates.** Re-run does not pull. Users `cd && git pull` themselves. (Could be a future `--update-projects` flag.)
- **`.env` value filling / secrets management.** We seed `.env` from `.env.example` with `FIXME-PLEASE-FILL` sentinels and never overwrite an existing `.env`. We do not prompt for values, integrate with a secret store, or encrypt anything.
- **Auto-installing `uv` for `stock-target-finder`.** That's the upstream repo's `install.sh`'s problem, not ours.
(removed: `--with-projects` now auto-enables `--with-node`, see decision 2.)
- **Interactive `install.sh` upstream.** We assume non-interactive. If a repo's installer prompts, that's an upstream bug.
- **GitHub auth setup.** If the user can't `git clone` over HTTPS/SSH, that's a prerequisite, not a `install.sh` concern.
- **A 4th project.** When/if it arrives, extend `PROJECT_*` arrays. If it doesn't fit the dispatch table, that's the moment to refactor.
- **README + CLI help text updates.** Trivial to add in Phase 2; not a design concern.
- **Cleanup / uninstall.** Out of scope for the same reason as the original `install.sh` spec.

## Open questions for reviewer

**All resolved 2026-05-09** — no blocking questions.

Reviewer flips on the original 3-way:
- Decision 2: **auto-flip `--with-node`** (not warn-and-skip). UX wins over explicit-opt-in convention.
- Decision 4: **no auto-pull** (kept as-is). Bootstrap semantic, not updater.
- Decision 5: **`cp .env.example .env` with FIXME-PLEASE-FILL sentinels** (not "print reminder, don't copy"). Onboarding wins; idempotent skip-when-exists protects already-filled secrets.

## Implementation plan reference

Phase 2 (writing-plans → executing-plans) will produce the actual bash diff against `install.sh`. This spec is the design contract.
