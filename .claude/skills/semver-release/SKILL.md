---
name: semver-release
description: Bump semantic version (fix/patch/minor/major), update debian/changelog via gbp dch, create annotated git tag
argument-hint: "<fix|patch|minor|major|init> [profile]"
test-devices: local
landing-group: release
---

# Semantic Version Release

Bump versions, update `debian/changelog` via `gbp dch`, create annotated git tags. Works with semver + Debian packaging or plain git tags.

Optional **profile** auto-chains downstream steps after bump+tag.

**Requires:** `git-buildpackage` (`apt install git-buildpackage`)

## Usage

```
/semver-release <fix|patch|minor|major|init> [profile]
```

| Argument | Effect |
|----------|--------|
| `fix` | Bump patch version (e.g., 1.2.3 → 1.2.4) |
| `patch` | Bump patch version (e.g., 1.2.3 → 1.2.4) |
| `minor` | Bump minor version (e.g., 1.2.3 → 1.3.0) |
| `major` | Bump major version (e.g., 1.2.3 → 2.0.0) |
| `init` | Create `debian/changelog` — prompts for starting version (0.0.1, 0.1.0, or 1.0.0) |

### Profiles

| Profile | After bump+tag, auto-run: |
|---------|---------------------------|
| _(none)_ | `/release-publish github-release,github-wiki` |
| `skill` | `/release-publish github-release,github-wiki,confluence` |

Default: single `/release-publish` call — generates notes, presents for review, publishes to `github-release` + `github-wiki`. `skill` profile adds Confluence. `release-publish` folds former `release-note` + `release-announce` into one call with review gate.

**All bump types publish to `github-wiki`.** `minor`/`major` → new wiki page; `fix`/`patch` → prepend to existing.

**Adding profiles:** define in table above. Profiles are skill-level, not per-repo.

## Version Source Detection

Reads current version from first source found:

| Priority | Source | How it reads |
|----------|--------|-------------|
| 1 | `debian/changelog` | Parse `package (X.Y.Z)` from first line |
| 2 | Latest git tag `v*` | Extract version from `git describe --tags --match 'v*' --abbrev=0` |
| 3 | None found | Run `/semver-release init` to set up |

Git tag always created. If `debian/changelog` exists, both changelog and tag update (complementary).

## Flow

### 1. Detect current version

```bash
# debian/changelog
head -1 debian/changelog
# → package (1.2.3) unstable; urgency=medium

# Git tag (fallback)
git describe --tags --match 'v*' --abbrev=0
# → v1.2.3
```

### 2. Compute new version

| Current | fix/patch | minor | major |
|---------|-----------|-------|-------|
| 1.2.3 | 1.2.4 | 1.3.0 | 2.0.0 |
| 0.0.1 | 0.0.2 | 0.1.0 | 1.0.0 |

### 3. Update debian/changelog with gbp dch

If `debian/changelog` exists, use `gbp dch` to generate the changelog entry from git commits:

```bash
NEW_VERSION=X.Y.Z

gbp dch \
  --new-version="$NEW_VERSION" \
  --ignore-branch \
  --release \
  --since="$(git describe --tags --match 'v*' --abbrev=0)" \
  --multimaint-merge \
  --spawn-editor=never \
  --commit
```

**Flags explained:**
| Flag | Purpose |
|------|---------|
| `--new-version` | Set the target version |
| `--ignore-branch` | Allow release from any branch (not just `debian/*`) |
| `--release` | Mark the entry as released (not `UNRELEASED`) |
| `--since` | Generate entries from the last `v*` tag forward — NOT from the last changelog edit. (`--auto` would resume from the last commit that touched `debian/changelog`, silently dropping every commit between the tag and a later non-release changelog edit.) |
| `--multimaint-merge` | Merge entries from multiple committers |
| `--spawn-editor=never` | Non-interactive — no editor popup |
| `--commit` | Auto-commit the changelog update |

If no `debian/changelog` exists, skip this step — the tag is the only version record.

### 4. Release guards (run BEFORE push — abort on any failure)

Pushes bump commit + tag **directly to main** (no PR). Authorized by release exception in `~/.claude/CLAUDE.md` — limited to `debian/changelog`, `releases/`, `v*` tags; code via PR first. **Tag created AFTER commit pushes** (failed push must not leave local tag ahead).

Guards 1+2 run ONLY when `debian/changelog` exists (validates bump commit). Tag-only repo skips to step 5.

```bash
NEW_VERSION=X.Y.Z   # from step 2

if [ -f debian/changelog ]; then
  # Guard 1 — VERSION-MATCH: changelog head version == NEW_VERSION (catches source drift).
  CL_VERSION=$(head -1 debian/changelog | sed -E 's/^[^(]*\(([^)]+)\).*/\1/')
  [ "$CL_VERSION" = "$NEW_VERSION" ] || {
    echo "ABORT: changelog version ($CL_VERSION) != computed NEW_VERSION ($NEW_VERSION)" >&2; exit 1; }

  # Guard 2 — PATH-SCOPE: the bump commit may touch ONLY debian/changelog + releases/.
  OFFENDERS=$(git show --name-only --format= HEAD | grep -Ev '^(debian/changelog|releases/)' | grep -v '^$' || true)
  [ -z "$OFFENDERS" ] || {
    echo "ABORT: release commit touches non-release paths (code must go via PR):" >&2
    echo "$OFFENDERS" >&2; exit 1; }
fi
```

### 5. Confirm, then push-then-tag

Show summary, ask before pushing:

```
Release summary:
  Version: 1.2.3 → 1.2.4
  Source:  debian/changelog (+ git tag)
  Tag:    v1.2.4

Push commit to main, then tag and push tag? [y/N]
```

After explicit confirmation. **Guard 3 — PUSH-THEN-TAG**: push commit → confirm → tag pushed SHA → push tag:

```bash
git push origin HEAD || { echo "ABORT: commit push failed — no tag created" >&2; exit 1; }
git tag -a "v${NEW_VERSION}" -m "Release v${NEW_VERSION}"
git push origin "v${NEW_VERSION}"
```

## Init

`/semver-release init` creates `debian/changelog`. Ask starting version:

```
Pick a starting version:
  1) 0.0.1 — pre-release, just getting started
  2) 0.1.0 — initial development, API may change
  3) 1.0.0 — first stable release
```

Then create the file using `dch`:

```bash
PACKAGE=$(basename "$(git rev-parse --show-toplevel)")
VERSION=<chosen version>

dch --create --package "$PACKAGE" --newversion "$VERSION" "initial version"
dch --release ""

git add debian/changelog
git commit -m "chore: init debian/changelog at v${VERSION}"
git tag -a "v${VERSION}" -m "Release v${VERSION}"
```

**Requires:** `devscripts` (`apt install devscripts`)

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| No version found | No `debian/changelog` or `v*` tags | Run `/semver-release init` first |
| `gbp: command not found` | `git-buildpackage` not installed | `apt install git-buildpackage` |
| `dch: command not found` | `devscripts` not installed | `apt install devscripts` |
| Tag already exists | Version was already tagged | Check `git tag -l 'vX.Y.Z'` — bump again or delete the stale tag |
| `gbp dch` picks up too many / too few commits | Last tag missing/wrong, or a non-release commit touched `debian/changelog` after the tag (`--auto` would resume from there and drop commits) | Verify `git describe --tags --match 'v*' --abbrev=0` returns the expected tag; step 3's `--since=<tag>` pins the range to it regardless of later changelog edits |

## Profile Execution

After bump+tag pushed (step 5), continue release chain. Failure → stop and report; user re-runs manually.

### Default (no profile)

```
/semver-release minor
  → [1] bump 0.3.0 → 0.4.0, gbp dch, push, tag v0.4.0, push tag
  → [2] /release-publish github-release,github-wiki
        ├─ generate notes + present for review (gate)
        ├─ github-release: commit file, gh release
        └─ github-wiki:    publish to GitHub Wiki
```

1. **release-publish (generate + review)** — collect from debian/changelog + git log, generate structured markdown, present for user review (the gate)
2. **release-publish github-release** — commit `releases/vX.Y.Z.md` and create GitHub Release
3. **release-publish github-wiki** — publish to the repo's GitHub Wiki. `minor`/`major` creates a new wiki page for the `major.minor` line; `fix`/`patch` prepends the new entry to the existing page for that line. Runs for **all** bump types.

### Profile: `skill`

Default + Confluence publishing:

- `CONFLUENCE_PARENT_ID=4768563289` (Claude Code Skills Guide)
- `CONFLUENCE_SPACE=UDX`

```
/semver-release minor skill
  → [1] bump 0.3.0 → 0.4.0, gbp dch, push, tag v0.4.0, push tag
  → [2] /release-publish github-release,github-wiki,confluence
        ├─ generate notes + present for review (gate)
        ├─ github-release: commit file, gh release
        ├─ github-wiki:    publish to GitHub Wiki
        └─ confluence:     create/update Confluence wiki page
```

Adds confluence channel under `Release Note/<major.minor>/` hierarchy.
