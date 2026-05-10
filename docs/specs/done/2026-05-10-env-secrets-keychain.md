---
kind: spec
status: done
created: 2026-05-10
slug: env-secrets-keychain
---

# Design: `--with-secrets` flag for macOS Keychain-backed `.env` seeding

**Date:** 2026-05-10
**Status:** Proposed (draft for review)
**Owner:** hookey.chiang@ui.com

## Goal

Add a single `--with-secrets` opt-in flag to `install.sh` that, on a fresh Mac,
materializes per-project `.env` files from committed `.env.tpl` shell-evaluable
templates whose values resolve via `security find-generic-password`. Idempotent;
fail-soft per missing key; matches the existing `--with-*` module pattern (PR #17).

The end-state on a fresh machine, after `./install.sh --all` (or `--with-secrets`):

1. The user has previously populated the Keychain entries on **one** of their Macs
   (manually, via `security add-generic-password`). iCloud Keychain auto-syncs
   them across all the user's Macs.
2. `install.sh --with-secrets` clones the projects (auto-implied via
   `--with-projects`), evaluates each repo's committed `.env.tpl`, writes the
   resolved values to `.env` next to it, and prints a copy-pasteable bootstrap
   block listing any keys that were missing in the Keychain.

## USER-LOCKED parameters (do NOT re-litigate)

These were decided in brainstorming and are inputs to this spec, not open questions.

1. **Storage:** macOS Keychain via `security` CLI. Entries auto-sync via iCloud
   Keychain across the user's Macs (no manual sync step in this spec).
2. **Template format:** `.env.tpl` files committed to GitHub, content is
   shell-evaluable text:
   ```
   SINOPAC_API_KEY=$(security find-generic-password -s sinopac-api-key -w)
   SINOPAC_SECRET_KEY=$(security find-generic-password -s sinopac-secret -w)
   ```
   Resolved on `--with-secrets` to produce `.env`.
3. **Single user, macOS only.** No 1Password, no GPG fan-out, no team sharing.
4. **Trigger:** new `--with-secrets` flag, alongside existing `--with-projects`.
   Auto-implies `--with-projects` (no point seeding secrets without the projects).
5. **Per-project repos own their `.env.tpl`** — committed to `stock-target-finder`
   and `telegram-claude-bridge` themselves (not this dotfiles repo). The user is
   the maintainer of all 3 repos so the cross-repo PRs are not coordination cost.

## Design decisions

### S1. `.env.tpl` location: in each project repo

**Decision:** Commit `.env.tpl` to each project repo next to its `.env.example`
(i.e., `stock-target-finder/.env.tpl` and `telegram-claude-bridge/.env.tpl`).
**Not** centralized under `dotfiles/templates/`.

**Rationale:**
- Each repo's `.env.tpl` is a schema document for that repo's configuration.
  Putting it next to `.env.example` is the natural home — they document the same
  surface (which keys exist), just one with placeholder values and one with
  `$(security find-generic-password ...)` lookups.
- Centralizing in dotfiles couples this repo to the project repos' env schemas.
  When `stock-target-finder` adds a new key, the user would have to PR two repos
  (the project repo's `.env.example` AND the dotfiles `templates/` mirror) instead
  of one. The cost compounds with every schema change.
- The "2 cross-repo PRs to land this" cost is paid once. Schema drift is paid
  forever. Optimize for the recurring cost.
- `llm-wiki` doesn't have an `.env.example` and won't have an `.env.tpl` either —
  no behavior needed for it.

### S2. Keychain naming convention: `<repo>-<key-slug>`, account = `$USER`

**Decision:** Service field (`-s`) is `<repo-name>-<lowercase-key-slug>` where
`<key-slug>` is the env var name, lowercased, with underscores replaced by
hyphens. Account field (`-a`) is `$USER`.

Examples:
- `stock-target-finder-sinopac-api-key` (env var `SINOPAC_API_KEY`)
- `stock-target-finder-shioaji-secret` *(if ever renamed; today it's `SINOPAC_SECRET_KEY`)*
- `telegram-claude-bridge-telegram-bot-token` (env var `TELEGRAM_BOT_TOKEN`)

**Rationale:**
- Repo prefix prevents collision with arbitrary other Keychain entries the user
  may have (e.g., a generic `telegram-bot-token` entry could belong to anything).
- The slug shape is a pure mechanical transform from the env var name —
  predictable, no naming creativity per key.
- `$USER` for the account field matches macOS conventions for per-user secrets;
  iCloud Keychain syncs by user identity anyway, so this doesn't affect sync.
- Verbose, but the user only types these strings once during initial bootstrap;
  every subsequent use is automated. Verbosity at write-time, brevity at runtime.

### S3. Missing keychain entry handling: per-key fail-soft, write empty value, accumulate WARN

**Decision:** When `.env.tpl` is evaluated and `security find-generic-password`
returns non-zero (entry missing) for a single key:

1. Write `KEY=` (empty value) to `.env`.
2. Accumulate that key into a per-repo "missing" list.
3. After all keys for the repo are processed, print a WARN block listing each
   missing key with the exact `security add-generic-password` command to fix it.

The whole `.env` is still written (rest of keys resolve normally). `.env` is NOT
discarded due to a single missing key.

**Rationale:**
- Onboarding flow: the user sees on first run *exactly* which keys are missing
  and the *exact* CLI to fix each one. This is the breadcrumb pattern from PR #17
  (FIXME-PLEASE-FILL) extended with a copy-pasteable fix command.
- Discarding the whole `.env` on one missing key would punish the user for partial
  state — Keychain entries arrive incrementally as the user creates them, and a
  `.env` with 9/10 keys filled is more useful than a missing file.
- Empty value (`KEY=`) is safe: most apps treat missing-key and empty-string the
  same way; if any app crashes on empty string, that's still a faster, clearer
  failure than `KEY=$(security find-generic-password ...)` literal text leaking
  through (which would happen if eval fails silently).

### S4. Idempotency: pre-existing `.env` is sacred

**Decision:** Same contract as PR #17's `seed_env`: if `<repo>/.env` already
exists, do **nothing**. Print `note: <repo>/.env present, leaving as-is`.

To regenerate from `.env.tpl`, the user runs `rm <repo>/.env && ./install.sh
--with-secrets` (or just `rm` and re-run; same outcome).

**Rationale:**
- Symmetry with PR #17 (D5). The user may have hand-edited `.env` after the
  initial seed (e.g., flipped `SINOPAC_SIMULATION=true → false`); clobbering on
  re-run would lose that work.
- The "regenerate" gesture is `rm .env`. This is explicit, matches Unix
  convention, and is the same gesture the user would use to "reset" any config.
- No `--force-regenerate` flag — adds CLI surface for a one-line workaround.

### S5. Dry-run: do NOT call `security`, list expected entries

**Decision:** Under `--dry-run`, `--with-secrets` does NOT invoke
`security find-generic-password`. Instead, for each `.env.tpl` it would process,
print:

```
+ would inject from <repo>/.env.tpl using keychain entries: <s1>, <s2>, <s3>
```

Where `<s1>...` is the list of `-s <service>` values parsed (statically, by
regex) out of the `.env.tpl` file.

**Rationale:**
- Avoids accidentally caching real secret values into dry-run logs (which the
  user may paste into a debugging issue, screenshot, etc.).
- Avoids touching the Keychain at all in a dry-run, which keeps dry-run truly
  side-effect-free (matches PR #17's "trust the dispatch table" approach).
- Static regex parse of `-s <service>` is sufficient; we're not promising
  100% coverage of arbitrary template syntax, just the documented
  `$(security find-generic-password -s <service> -w)` shape.

### S6. Discovery: copy-pasteable bootstrap block on missing entries

**Decision:** Whenever `--with-secrets` finishes with one or more missing keys,
print at the end of the run (after all repos processed):

```
==> Missing keychain entries — add them to populate .env on next run:
security add-generic-password -s stock-target-finder-sinopac-api-key -a $USER -w 'YOUR_KEY_HERE'
security add-generic-password -s stock-target-finder-sinopac-secret-key -a $USER -w 'YOUR_SECRET_HERE'
security add-generic-password -s telegram-claude-bridge-telegram-bot-token -a $USER -w 'YOUR_TOKEN_HERE'
```

Each `.env.tpl` should have a leading comment line documenting the pattern, e.g.:

```
# Bootstrap: see README — populate via `security add-generic-password -s <key> -a $USER -w '<value>'`
# .env is auto-generated by dotfiles install.sh --with-secrets; edit at your own risk.
```

**Rationale:**
- The user's recovery path is "add the missing key, re-run install.sh". Giving
  them the exact CLI eliminates a lookup step.
- Printing once at the end of the run (not per-repo interleaved) keeps the WARN
  block easy to scan and easy to copy-paste in one go.
- The leading comment in `.env.tpl` is for future-self / other agents reading
  the file in isolation — it explains why the file exists and how to populate it.

### S7. No `--add-secret` shorthand: out of scope

**Decision:** `install.sh` will NOT grow an `--add-secret` flag, an interactive
prompt for entering keys, or any wrapper around `security add-generic-password`.
The user runs `security` directly using the bootstrap block from S6.

**Rationale:**
- Adding interactive flags bloats the installer and leaks secrets into shell
  history / `ps` listings (no good answer for stdin handling without a TUI).
- The `security add-generic-password` CLI is already simple, well-documented,
  and the user only runs it once per key per machine.
- Future: if this becomes friction, a separate `bin/dotfiles-add-secret` helper
  script (not in `install.sh`) could bundle prompt + `security add` + iCloud
  sync verification. That's a different spec.

### S8. `--with-secrets` auto-implies `--with-projects` (and transitively `--with-node`)

**Decision:** When `WITH_SECRETS=1`, `parse_flags()` sets `WITH_PROJECTS=1` if
not already set, with a `note: --with-secrets auto-enabled --with-projects (need
the projects to seed .env into)` log line. The existing PR #17 logic then
auto-enables `--with-node` from `WITH_PROJECTS`.

`--all` continues to set all `WITH_*` flags directly.

**Rationale:**
- Parallel to PR #17's `--with-projects → --with-node` auto-flip. UX wins over
  explicit-opt-in convention.
- Without the projects cloned, there's nowhere to put `.env` files. Running
  `--with-secrets` solo would be a no-op with confusing output ("looking for
  .env.tpl... not found, not found, not found").
- Order in `main()`: `install_projects` runs **before** `seed_secrets` (the new
  function) so the clones exist by the time we look for `.env.tpl`.

### S9. `.gitignore` for `.env.tpl` files

**Decision:** Verify each project repo's `.gitignore` includes `.env` but NOT
`.env.tpl`. (Confirmed via `gh api` 2026-05-10:
`stock-target-finder/.gitignore` has `.env` only;
`telegram-claude-bridge/.gitignore` has `.env` only.) Both repos can commit
`.env.tpl` without `.gitignore` changes.

If a future repo's `.gitignore` includes `.env*` (wildcard), the cross-repo PR
adding `.env.tpl` must also patch `.gitignore` to be `.env` (no wildcard) or add
`!.env.tpl` un-ignore. Document this caveat in the cross-repo PR template.

**Rationale:**
- `.env.tpl` is a schema document, not a secret — it's safe and intended to be
  committed. The `$(security find-generic-password ...)` literal is not a secret;
  the resolved value is.
- Catching this at commit time (not at install-time) prevents the failure mode
  where `.env.tpl` exists locally but isn't pushed to the user's other Mac.

### S10. Eval mechanism: per-line strict pattern match, no `eval` of full file

**Decision:** Read `.env.tpl` line-by-line. For each line:

1. **Comment / blank line** (`^\s*#` or `^\s*$`): pass through verbatim.
2. **`KEY=$(security find-generic-password -s <service> -w)`** match: parse out
   `<service>`, run `security find-generic-password -s '<service>' -a "$USER" -w`,
   capture stdout. If exit code 0 → write `KEY=<resolved>`. If non-zero → write
   `KEY=` and accumulate `<key>` into the missing list.
3. **`KEY=<literal>`** (no command substitution): pass through verbatim.
   This handles `DATABASE_URL=sqlite:///stock_finder.db` and similar non-secret
   defaults.
4. **Anything else** (unknown shape): pass through verbatim with a single WARN
   `note: <repo>/.env.tpl line N has unrecognized shape, passing through as-is`.
   Don't break the file; let the user fix the template.

**Rationale:**
- `eval "echo $(cat .env.tpl)"` is a footgun: any unquoted special character
  (backtick, `$VAR` reference, semicolon) breaks the world. We control the
  template format, but a typo in a future cross-repo PR shouldn't clobber `.env`.
- `bash -c '. .env.tpl; declare -p > .env'` is too magic and would happily run
  arbitrary code. Templates are committed to git but treating them as code (vs.
  data) is a footgun in the same shape.
- Per-line strict pattern match: predictable, debuggable, safe. Each line's
  failure is contained to that line.
- Account field `-a "$USER"` is hard-coded by the script (not parsed from the
  template), per S2. The template only specifies `-s <service>`. This keeps the
  template's surface area minimal and prevents drift between templates.

## Implementation outline

Pseudo-code, **not** runnable bash. Final bash goes in Phase 2.

```
# Globals (added to existing PR #17 set)
WITH_SECRETS=0

# Flag parsing additions (in parse_flags, alongside --with-projects)
--with-secrets -> WITH_SECRETS=1
--all          -> also flip WITH_SECRETS=1
# Auto-flip --with-projects when --with-secrets is set:
if (( WITH_SECRETS && ! WITH_PROJECTS )); then
  WITH_PROJECTS=1
  note "--with-secrets auto-enabled --with-projects (need projects to seed .env into)"
fi
# (existing PR #17 line then auto-flips WITH_NODE from WITH_PROJECTS)

# Main flow ordering (in main()):
#   install_node, install_projects, ..., seed_secrets — secrets last so projects exist.
(( WITH_SECRETS )) && seed_secrets || true

# Top-level driver
seed_secrets():
  log "seed_secrets"
  if OS != "macos":
    note "skip seed_secrets — Keychain is macOS-only"
    return 0

  global_missing=()  # (repo, key, service) tuples

  for i in 0..len(PROJECT_NAMES):
    name=${PROJECT_NAMES[i]}
    dst="$PROJECTS_DIR/$name"
    tpl="$dst/.env.tpl"
    env="$dst/.env"

    if not exists $tpl:
      note "skip $name (no .env.tpl)"
      continue

    if exists $env:
      note "$name/.env present, leaving as-is"
      continue

    if (( DRY_RUN )):
      services = parse_services($tpl)   # static regex parse of -s <service>
      note "+ would inject from $name/.env.tpl using keychain entries: ${services[@]}"
      continue

    seed_one_env $name $tpl $env
    # populates global_missing as a side effect

  if global_missing not empty:
    print_bootstrap_block global_missing

# Per-template processor
seed_one_env(name, tpl, env):
  tmp=$(mktemp "${env}.XXXXXX")
  local_missing=()

  while read line; do
    if line matches comment/blank: echo line >> tmp; continue
    if line matches KEY=$(security find-generic-password -s SERVICE -w):
      KEY=<extracted>
      SERVICE=<extracted>
      val=$(security find-generic-password -s "$SERVICE" -a "$USER" -w 2>/dev/null) || {
        echo "$KEY=" >> tmp
        local_missing+=("$SERVICE")
        global_missing+=("$name $KEY $SERVICE")
        continue
      }
      echo "$KEY=$val" >> tmp
      continue
    if line matches KEY=<literal>: echo line >> tmp; continue
    note "$name/.env.tpl line N has unrecognized shape, passing through as-is"
    echo line >> tmp
  done < $tpl

  mv $tmp $env
  chmod 600 $env  # secret hygiene; .env in $HOME, single-user
  if local_missing not empty:
    note "$name/.env created with ${#local_missing[@]} missing keychain entries (see end-of-run block)"
  else:
    note "$name/.env created from .env.tpl, all keychain entries resolved"

# End-of-run reporter
print_bootstrap_block(missing):
  err "missing keychain entries — add them to populate .env on next run:"
  for (repo, key, service) in missing:
    printf 'security add-generic-password -s %q -a %q -w %q\n' "$service" "$USER" 'YOUR_VALUE_HERE'
```

### `.env.tpl` example (lives in `stock-target-finder/.env.tpl`)

```
# Bootstrap: populate via `security add-generic-password -s <key> -a $USER -w '<value>'`
# This file is committed; values are resolved at install time by dotfiles install.sh --with-secrets.
DATABASE_URL=sqlite:///stock_finder.db

# Shioaji (永豐金) API
SINOPAC_API_KEY=$(security find-generic-password -s stock-target-finder-sinopac-api-key -w)
SINOPAC_SECRET_KEY=$(security find-generic-password -s stock-target-finder-sinopac-secret-key -w)
SINOPAC_PERSON_ID=$(security find-generic-password -s stock-target-finder-sinopac-person-id -w)
SINOPAC_CA_PATH=$(security find-generic-password -s stock-target-finder-sinopac-ca-path -w)
SINOPAC_CA_PASSWORD=$(security find-generic-password -s stock-target-finder-sinopac-ca-password -w)
SINOPAC_SIMULATION=true

# Notifications
LINE_NOTIFY_TOKEN=$(security find-generic-password -s stock-target-finder-line-notify-token -w)
TELEGRAM_BOT_TOKEN=$(security find-generic-password -s stock-target-finder-telegram-bot-token -w)
TELEGRAM_CHAT_ID=$(security find-generic-password -s stock-target-finder-telegram-chat-id -w)
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
EMAIL_USERNAME=$(security find-generic-password -s stock-target-finder-email-username -w)
EMAIL_PASSWORD=$(security find-generic-password -s stock-target-finder-email-password -w)
EMAIL_TO=$(security find-generic-password -s stock-target-finder-email-to -w)
```

> Note: `SINOPAC_SIMULATION=true` and `DATABASE_URL=sqlite:///stock_finder.db` are
> non-secret defaults — they pass through case 3 of S10 verbatim.

## Idempotency contract

| Step                          | First run                                              | Re-run, clean state                          | Re-run, partial state                                                                                                  |
|-------------------------------|--------------------------------------------------------|----------------------------------------------|------------------------------------------------------------------------------------------------------------------------|
| Detect `.env.tpl`             | If absent → skip with note                             | Same — skip                                  | If template was just added: process this run.                                                                           |
| Detect `.env` exists          | Absent → process template                              | Present → skip with `leaving as-is` note     | If user `rm`-ed `.env` between runs, re-process from template.                                                          |
| Resolve key (Keychain hit)    | Write `KEY=<value>` to `.env`                          | Skipped (because `.env` exists)              | Skipped same as clean.                                                                                                  |
| Resolve key (Keychain miss)   | Write `KEY=`, accumulate to missing list               | Skipped                                      | If user added the missing key after first run + `rm .env` + re-run, the key now resolves.                               |
| Write `.env` (per-repo)       | `chmod 600` + `mv tmp → .env` atomically               | Skipped                                      | If `mv` fails mid-run (disk full, etc.), tmp file remains as `.env.XXXXXX`; re-run cleans up next mktemp; document.    |
| End-of-run bootstrap block    | Printed if any keys missing across all repos           | Not printed (nothing to fix)                 | Reflects current Keychain state, not cumulative — always re-derived from this run's misses.                             |

**Net:** re-run on a clean machine = full seed. Re-run on a fully seeded machine
= all "leaving as-is" skips. Re-run after the user adds a missing Keychain entry
+ `rm <repo>/.env` = the one repo re-seeds with the new value.

## Failure modes

| What can go wrong                                          | What happens                                                                          | User recovery                                                                                                       |
|------------------------------------------------------------|---------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------|
| Run on Linux                                                | `seed_secrets` notes "Keychain is macOS-only" and returns 0                            | Use this flag only on macOS. Document.                                                                              |
| `.env.tpl` syntax doesn't match S10 patterns                | Per-line "unrecognized shape" WARN; line passed through verbatim to `.env`              | Inspect `<repo>/.env`, fix the `.env.tpl` syntax in the project repo, PR upstream, re-run.                          |
| Keychain entry missing for one key                          | `KEY=` written; missing list accumulates; bootstrap block printed at end of run        | Run the printed `security add-generic-password` line, `rm <repo>/.env`, re-run `install.sh --with-secrets`.         |
| Keychain entry exists but resolves to empty string          | `KEY=` written (treated same as missing); WARN listed in bootstrap block                | Same as missing.                                                                                                    |
| `security` CLI not on PATH                                  | Per-line `security` calls fail with exit code 127, all keys land on missing list       | macOS ships `/usr/bin/security`; if missing, the OS install is broken — fix that first.                              |
| iCloud Keychain not enabled / not synced yet                | Entries created on Mac A not visible on Mac B until sync completes                     | Wait for iCloud Keychain sync (typically <1 min); or manually re-add on the second Mac. Out of scope for this script. |
| User re-runs without `rm .env`                              | Existing `.env` skipped with note; no regeneration                                     | `rm <repo>/.env && ./install.sh --with-secrets` (documented).                                                       |
| `mv tmp → .env` fails mid-run (disk full)                   | Per-repo error; partial `.env.XXXXXX` orphan left behind                               | Free space, `rm <dst>/.env.*` orphans, re-run.                                                                      |
| `chmod 600` fails (FS doesn't support, etc.)                | Warn but proceed; `.env` written with default umask perms                              | Manual `chmod 600` if user cares; on macOS HFS+/APFS this never fires.                                              |
| `.env.tpl` exists but no project clone (manual delete)      | `seed_secrets` notes "skip $name (no clone dir)"; doesn't fail run                     | Re-run with `--with-projects` (auto-implied) to re-clone, then re-seed.                                              |
| Template references service name that doesn't exist anywhere | Empty value in `.env`; bootstrap line printed                                         | Decide: add the entry, or fix the `.env.tpl` to remove that line. PR upstream.                                      |

## Test plan

### Unit (dry-run, no network, no Keychain access)

```bash
# T1. --with-secrets in --help output
./install.sh --help | grep -- '--with-secrets'

# T2. --with-secrets auto-enables --with-projects (and transitively --with-node)
./install.sh --with-secrets --dry-run 2>&1 | grep -E 'auto-enabled --with-projects'
./install.sh --with-secrets --dry-run 2>&1 | grep -E 'auto-enabled --with-node'

# T3. --with-secrets --dry-run does NOT invoke `security`
# Run under a PATH that excludes /usr/bin/security; verify no error.
PATH=/usr/local/bin:/bin ./install.sh --with-secrets --dry-run 2>&1 | grep -v 'security:.*not found'

# T4. --with-secrets --dry-run lists expected keychain entries (static parse)
# Set up a fake DOTFILES_PROJECTS_DIR with an .env.tpl that has 3 keys.
tmp=$(mktemp -d)
mkdir -p $tmp/stock-target-finder
cat > $tmp/stock-target-finder/.env.tpl <<'TPL'
FOO=$(security find-generic-password -s stock-target-finder-foo -w)
BAR=$(security find-generic-password -s stock-target-finder-bar -w)
BAZ=literal
TPL
DOTFILES_PROJECTS_DIR=$tmp ./install.sh --with-secrets --dry-run 2>&1 | grep 'stock-target-finder-foo, stock-target-finder-bar'

# T5. --all enables --with-secrets
./install.sh --all --dry-run 2>&1 | grep -i 'seed_secrets'

# T6. Bare --dry-run does NOT run seed_secrets
./install.sh --dry-run 2>&1 | grep -v 'seed_secrets'
```

### Unit (real `security`, real Keychain, throwaway entries)

```bash
# T7. Pre-seed a throwaway entry, run, verify resolution
security add-generic-password -s test-env-tpl-foo -a $USER -w 'resolved-value'
trap "security delete-generic-password -s test-env-tpl-foo -a $USER" EXIT

tmp=$(mktemp -d)
mkdir -p $tmp/stock-target-finder
cat > $tmp/stock-target-finder/.env.tpl <<'TPL'
FOO=$(security find-generic-password -s test-env-tpl-foo -w)
TPL

DOTFILES_PROJECTS_DIR=$tmp ./install.sh --with-secrets
test "$(grep '^FOO=' $tmp/stock-target-finder/.env)" = "FOO=resolved-value"
test "$(stat -f '%Mp%Lp' $tmp/stock-target-finder/.env)" = "0600"  # macOS stat

# T8. Missing entry → KEY= and bootstrap block printed
tmp=$(mktemp -d)
mkdir -p $tmp/stock-target-finder
cat > $tmp/stock-target-finder/.env.tpl <<'TPL'
MISSING=$(security find-generic-password -s test-env-tpl-not-there-$$  -w)
TPL

out=$(DOTFILES_PROJECTS_DIR=$tmp ./install.sh --with-secrets 2>&1)
test "$(grep '^MISSING=' $tmp/stock-target-finder/.env)" = "MISSING="
echo "$out" | grep -q 'security add-generic-password -s test-env-tpl-not-there-'

# T9. Re-run on existing .env: no clobber
echo 'FOO=hand-edited' > $tmp/stock-target-finder/.env
DOTFILES_PROJECTS_DIR=$tmp ./install.sh --with-secrets
test "$(cat $tmp/stock-target-finder/.env)" = "FOO=hand-edited"

# T10. Comment + blank + literal pass through; non-secret defaults preserved
tmp=$(mktemp -d)
mkdir -p $tmp/stock-target-finder
cat > $tmp/stock-target-finder/.env.tpl <<'TPL'
# header comment

DATABASE_URL=sqlite:///stock_finder.db
SINOPAC_SIMULATION=true
TPL
DOTFILES_PROJECTS_DIR=$tmp ./install.sh --with-secrets
diff $tmp/stock-target-finder/.env.tpl $tmp/stock-target-finder/.env | grep -v '^---' | grep -v '^+++'
# Expect: identical content (no differences)
```

### Integration (full end-to-end on user's actual Mac)

```bash
# T11. Real cross-repo flow
# Pre-condition: stock-target-finder and telegram-claude-bridge each have .env.tpl
# committed; user has NOT yet added Keychain entries.
rm -rf ~/stock-target-finder ~/telegram-claude-bridge   # destructive — confirm with user first
./install.sh --with-secrets

# Expect:
#  - both repos cloned
#  - both .env created with KEY= for every secret-derived var
#  - bootstrap block printed listing every missing service name
#  - 0600 perms on .env files

# T12. Add one entry, partial resolution
security add-generic-password -s stock-target-finder-sinopac-api-key -a $USER -w 'fake-test-key'
rm ~/stock-target-finder/.env
./install.sh --with-secrets
grep '^SINOPAC_API_KEY=fake-test-key$' ~/stock-target-finder/.env
# bootstrap block should now be shorter by one line
```

## Out of scope

- **Linux support.** Keychain is macOS-only. Spec exits 0 with a note on Linux.
  If the user wants Linux, they file `--with-secrets-libsecret` as a future spec.
- **Reverse direction (`.env → Keychain` import).** Bootstrap is one-way: user
  adds to Keychain, install resolves. No "I have an existing `.env`, populate
  Keychain from it" subcommand.
- **Sync verification.** We assume iCloud Keychain works. If a key is missing
  on Mac B that exists on Mac A, the bootstrap block prints the same fix command
  the user would run on Mac A — they just have to wait for sync or re-add.
- **Encryption-at-rest of `.env`.** `.env` is plaintext on disk after seeding.
  `chmod 600` is the only protection. If the user wants encrypted `.env`,
  that's a different threat model.
- **Per-key Keychain ACLs.** All entries created with default ACL (any process
  the user runs can read). If we want Keychain Access prompt-on-read, that's
  a different `security add-generic-password -A` flag negotiation — out of scope.
- **Interactive secret entry.** No prompts in `install.sh`. User runs `security
  add-generic-password` directly.
- **`llm-wiki` integration.** No `.env.example` upstream, no `.env.tpl` planned.
  `seed_secrets` skips it cleanly via the "no `.env.tpl`" branch.
- **Cleanup of orphaned tmp files.** If `mv tmp → .env` fails mid-run, leftover
  `.env.XXXXXX` files persist. Document; don't engineer around.

## Open questions for reviewer

All resolved 2026-05-10. Listed below are 3 alternatives the reviewer might
want to flip before promoting this to `active/`. None are blocking.

1. **S2 — Keychain account field: `$USER` vs fixed `default`.** Picked `$USER`
   for convention. If the user wants their secrets to be portable to a different
   macOS account on the same Mac (e.g., a "personal" + "work" account), `default`
   would let entries resolve regardless of `$USER`. Flip if multi-account use is
   on the roadmap.
2. **S3 — Missing key behavior: empty value vs `FIXME-PLEASE-FILL` sentinel.**
   Picked empty for least-surprise (apps that handle missing-env gracefully will
   continue to do so). PR #17 uses `FIXME-PLEASE-FILL` for `.env.example` →
   `.env`. Flip to sentinel here if uniformity with PR #17 wins over the
   "empty = absent" convention.
3. **S10 — Eval mechanism: per-line strict pattern vs full-file `eval`.** Picked
   strict pattern for safety. If templates ever need richer shape (e.g., `KEY1=$(security ... -s a)$(security ... -s b)` concatenation, or shell parameter
   expansion), the strict matcher would have to grow. Flip to full-file `eval`
   only if a real use case demands it; today the simple case covers everything.

## Cross-repo coordination

This spec depends on cross-repo PRs landing in the project repos before
`--with-secrets` does anything useful. Order:

1. **`ui-HookeyChiang/stock-target-finder`** PR
   - Add `.env.tpl` next to `.env.example` with the 11 secret keys (per S2 naming).
   - Verify `.gitignore` already has `.env` only (no wildcard) — confirmed
     2026-05-10. No `.gitignore` change needed.
   - README mention: "secrets are sourced from macOS Keychain via dotfiles
     install.sh --with-secrets; see .env.tpl for the schema."

2. **`ui-HookeyChiang/telegram-claude-bridge`** PR
   - Add `.env.tpl` next to `.env.example` with `TELEGRAM_BOT_TOKEN` (the only
     hard secret) plus `ALLOWED_USER_IDS` (config, but personal). Optional vars
     stay commented out in `.env.tpl` mirroring `.env.example`.
   - Verify `.gitignore` (`.env` only, confirmed 2026-05-10). No change.
   - README mention as above.

3. **`ui-HookeyChiang/dotfiles`** PR (this spec → executing-plans)
   - Add `--with-secrets` flag, `seed_secrets()` function, dispatch in `main()`.
   - Update `--help` text.
   - Update `tests/test-install-secrets.sh` (TAP-13 mirror of
     `test-install-projects.sh`).
   - Update `README.md` to mention the flag.

The dotfiles PR can land first (the new function is a no-op when no `.env.tpl`
exists in the cloned repos — see S10 + idempotency table). Cross-repo PRs
1+2 then activate it.

## Implementation plan reference

Phase 2 (writing-plans → executing-plans) will produce the actual bash diff
against `install.sh` plus the two cross-repo `.env.tpl` files. This spec is
the design contract.
