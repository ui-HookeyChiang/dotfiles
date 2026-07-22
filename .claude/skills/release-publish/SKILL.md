---
name: release-announce
description: Publish release notes to multiple channels — github-release (authoritative GitHub Release), github-wiki (GitHub Wiki pages), Confluence wiki hierarchy. Triggers on "announce release", "publish release", "post release note".
argument-hint: "[channels] [version] [--dry-run]"
test-devices: local
landing-group: release
---

# release-announce

Publish release notes to channels: **github-release** (GitHub Release via `gh release create`), **github-wiki** (Wiki pages), **confluence** (wiki hierarchy).

Runs after `release-note` generates markdown. Distributes to specified channels.

## Usage

```bash
/release-announce github-release,github-wiki,confluence v0.3.0
/release-announce confluence
/release-announce --dry-run github-release
/release-announce github-wiki v1.0.0
```

Natural language also works:
```bash
/release-announce publish the release to confluence and github-release
/release-announce announce v0.4.0 on all channels
/release-announce post the release note to the wiki
```

### Arguments

| Argument | Description |
|----------|-------------|
| `[channels]` | Comma-separated list: `github-release`, `github-wiki`, `confluence`. Default: `github-release,github-wiki`. Deprecated aliases: `repo` and `github` → map to `github-release` with a `[DEPRECATED]` warning. |
| `[version]` | Version tag (e.g., `v0.3.0`). Default: latest git tag |
| `--dry-run` | Show what would be published without doing it |

---

## Instructions

Publish release-note markdown to requested channels.

### Step 0: Gather Inputs

1. **Release note markdown** (`$RELEASE_MD`): from `release-note` output, user-provided, or fetched: `RELEASE_MD=$(gh release view vX.Y.Z --json body -q .body)`. Step 1 asserts non-empty.
2. **Version**: parse from argument, or detect from latest git tag:
   ```bash
   VERSION=$(git describe --tags --match 'v*' --abbrev=0)
   # e.g., v0.3.0
   MAJOR=$(echo "$VERSION" | sed 's/^v//' | cut -d. -f1)
   MINOR=$(echo "$VERSION" | sed 's/^v//' | cut -d. -f2)
   PATCH=$(echo "$VERSION" | sed 's/^v//' | cut -d. -f3)
   MAJOR_MINOR="${MAJOR}.${MINOR}"
   ```
3. **Bump type detection**: compare current to previous tag (drives prepend vs new page):
   ```bash
   PREV_VERSION=$(git describe --tags --match 'v*' --abbrev=0 "${VERSION}^")
   PREV_MAJOR=$(echo "$PREV_VERSION" | sed 's/^v//' | cut -d. -f1)
   PREV_MINOR=$(echo "$PREV_VERSION" | sed 's/^v//' | cut -d. -f2)

   if [ "$MAJOR" -ne "$PREV_MAJOR" ]; then
     BUMP_TYPE="major"
   elif [ "$MINOR" -ne "$PREV_MINOR" ]; then
     BUMP_TYPE="minor"
   else
     BUMP_TYPE="fix"
   fi
   ```
4. **Channels**: parse from argument or default to `github-release,github-wiki`.

5. **Deprecated alias handling**: `repo`/`github` → rewrite to `github-release` with warning:
   ```bash
   # CHANNELS is a comma-separated list parsed from the argument
   case ",$CHANNELS," in
     *,repo,*|*,github,*)
       echo "[DEPRECATED] 'repo' channel renamed to 'github-release'. Use 'github-release' instead." >&2
       CHANNELS=$(echo "$CHANNELS" | sed -E 's/(^|,)(repo|github)(,|$)/\1github-release\3/g')
       ;;
   esac
   ```
   Alias supported one release cycle for backwards compat.

### Step 1: Validate

Assert release-note markdown present and non-empty — targets are irreversible, empty body must abort before confirm. Empty IS reachable (standalone usage, manual handoff, blank `gh release view` body). Guard up front:
```bash
# $RELEASE_MD = the markdown gathered in Step 0.1 (release-note output, user-provided,
# or `gh release view` body). Empty/whitespace-only → STOP, do not reach publish.
if [ -z "$(printf '%s' "$RELEASE_MD" | tr -d '[:space:]')" ]; then
  echo "[ABORT] no release-note markdown — run release-note first, or pass the body." >&2
  exit 1
fi
```

Then confirm with the user:
```
Publishing v0.3.0 to: github-release, github-wiki, confluence
Bump type: minor (0.2 -> 0.3)

Proceed? [y/N]
```

If `--dry-run` is set, show the plan and stop without executing.

---

## Channels

Each channel follows its reference recipe. All share Step 0 inputs (`$VERSION`, `$MAJOR`/`$MINOR`, `$MAJOR_MINOR`, `$BUMP_TYPE`) and release markdown.

| Channel | Publishes to | Auth | Bump-type behavior | Key gotcha | Recipe |
|---------|--------------|------|--------------------|------------|--------|
| `github-release` | GitHub Release (authoritative, tag-bound) | `gh auth` token (repo scope) | n/a — one release per tag | No repo-side copy kept; landing reads the Release API directly | [references/channel-github-release.md](references/channel-github-release.md) |
| `github-wiki` | `<repo>.wiki.git` flat page set + `Home.md` index | `gh auth` token (repo scope) | fix → prepend to `Release-Note-M.N.md`; minor/major → new file | `.wiki.git` is lazy-created — does NOT exist until first page made via Web UI; verify via `git ls-remote`, NOT curl | [references/channel-github-wiki.md](references/channel-github-wiki.md) |
| `confluence` | Confluence wiki hierarchy under "Release Note" | Atlassian creds in `~/.config/ubiquiti/jira-credentials` | fix → prepend to `M.N` page; minor/major → new `M.N` subpage | Caller must pass `CONFLUENCE_PARENT_ID` + `CONFLUENCE_SPACE`; CQL can't find draft pages so store page IDs; body is XHTML not markdown | [references/channel-confluence.md](references/channel-confluence.md) |

---

## Output

After publishing to each channel, report the results:

```
Published v0.3.0:
  github-release: GitHub Release: https://github.com/ORG/REPO/releases/tag/v0.3.0
  github-wiki:    Updated Release-Note-0.3.md (prepended — fix bump)
                  Home.md regenerated
                  https://github.com/ORG/REPO/wiki/Release-Note-0.3
  confluence:     Updated page "0.3" (prepended — fix bump)
                  https://ubiquiti.atlassian.net/wiki/spaces/$CONFLUENCE_SPACE/pages/XXXXXXX
```

On `--dry-run`, show the plan without executing:

```
[DRY RUN] Would publish v0.3.0 to:
  github-release: gh release create v0.3.0 from tempfile
  github-wiki:    prepend to existing Release-Note-0.3.md (fix bump), regenerate Home.md, push to wiki
  confluence:     prepend to existing page "0.3" (fix bump, page ID XXXXXXX)
```

---

## Error Handling

| Code | Cause | Fix |
|------|-------|-----|
| 401 | Confluence credentials wrong or expired | Refresh `~/.config/ubiquiti/jira-credentials` |
| 404 | Page not found | Verify page ID; "Release Note" parent may need to be created |
| 409 | Version conflict on update | For published pages: re-fetch version and increment. For draft pages: always use `version: 1` |
| `gh` not found | GitHub CLI not installed | `apt install gh` or `brew install gh`, then `gh auth login` |
| No git tag | No version tags in repo | Run `/semver-release` first to create a version tag |
| Wiki not initialized | `ls-remote` returns "Repository not found" but `has_wiki=true` | Create the first page via Web UI: https://github.com/&lt;owner&gt;/&lt;repo&gt;/wiki |
| Wiki disabled | `has_wiki=false` | Enable wiki in repo Settings → Features → Wikis, or drop `github-wiki` from channel list |
| Wiki push rejected | Concurrent wiki update | `git pull --rebase origin HEAD` in the wiki clone, then retry |
| `[DEPRECATED] 'repo' channel...` | User passed legacy `repo` / `github` channel name | Switch to `github-release`; the alias still works for one release cycle |

## Important Notes

- Publishes only — does NOT generate notes. Use `release-note` first.
- Credentials: `~/.config/ubiquiti/jira-credentials` (shared with Jira/Confluence)
- **Store page IDs** — new version pages (minor/major): record ID. Patch bumps need it (CQL can't find drafts).
- Confluence: **Storage Format** (XHTML), not markdown. Convert before posting.
- `repo`/`github` deprecated aliases for `github-release` (one cycle, then removed).
- GitHub Wiki: raw markdown, no conversion needed.
- `.wiki.git` is lazy-initialized — `hasWikiEnabled=true` ≠ exists. First page via Web UI; auto-created wikis use branch `master`.
- Default channels: `github-release,github-wiki`
- Never print credentials
