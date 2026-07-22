# Channel: github-wiki

Publish the release note to a GitHub Wiki page hierarchy. Mirrors the Confluence channel's bump-type logic but targets the `<repo>.wiki.git` repo instead of Confluence REST.

## Page hierarchy

GitHub Wiki is flat (no nested pages), but supports markdown links between files. Layout:

```
Home.md                 <- auto-generated index
Release-Note-0.1.md     <- per-major.minor page
Release-Note-0.2.md
Release-Note-1.0.md
```

GitHub Wiki convention: `-` in a filename renders as a space in the page title, so `Release-Note-0.3.md` shows up as "Release Note 0.3".

## Bump-type logic

| Bump | Action |
|------|--------|
| **fix/patch** (0.3.1) | Prepend new release note to existing `Release-Note-0.3.md` (newest first, `---` separator) |
| **minor** (0.4.0) | Create new `Release-Note-0.4.md` |
| **major** (1.0.0) | Create new `Release-Note-1.0.md` |

After every publish, regenerate `Home.md` with all `Release-Note-*.md` pages sorted by version descending.

## Credentials / auth

GitHub Wiki push uses the same `gh auth` token as the main repo (wiki is part of the `repo` scope). Verify with:

```bash
gh auth status
```

## Step W0: Detect wiki URL

```bash
REPO_URL=$(gh repo view --json url -q .url)
OWNER_REPO=$(echo "$REPO_URL" | sed 's|https://github.com/||')
WIKI_URL="https://github.com/${OWNER_REPO}.wiki.git"
```

## Step W1: Clone wiki (must be initialized first — see error handling)

**Prerequisite: wiki must be initialized.** GitHub Wiki's `.wiki.git` repo is lazy-created — it does NOT exist until the first page is created via the Web UI, even if `hasWikiEnabled=true`. If you see the "GitHub Wiki repo does not exist" error, follow the instructions to create the first page, then re-run.

```bash
# Step W1: Clone wiki (must be initialized first — see error handling)
TMPDIR=$(mktemp -d)
if ! git ls-remote "$WIKI_URL" &>/dev/null; then
  cat >&2 <<ERR
ERROR: GitHub Wiki repo does not exist at $WIKI_URL
The wiki is lazy-initialized by GitHub: it only exists after the first page is created via the UI.
To fix:
  1. Open https://github.com/${OWNER_REPO}/wiki in a browser
  2. Click "Create the first page" and save any content
  3. Re-run this command
ERR
  exit 1
fi

git clone "$WIKI_URL" "$TMPDIR/wiki"
cd "$TMPDIR/wiki"

# Defensive check: ls-remote succeeded but clone is empty (rare — broken wiki state)
if ! git rev-parse HEAD &>/dev/null; then
  cat >&2 <<ERR
ERROR: Wiki clone succeeded but has no commits. The wiki is in a broken state.
Go to https://github.com/${OWNER_REPO}/wiki and create a page to fix it.
ERR
  exit 1
fi
```

## Step W2: Compute target filename

GitHub Wiki convention: `-` in filename renders as space in page title.

```bash
WIKI_FILE="Release-Note-${MAJOR}.${MINOR}.md"
```

## Step W3: Apply bump-type logic (mirrors Confluence)

- **fix/patch**: prepend new release note to existing file with `---` separator
- **minor/major**: create new file with release note content

```bash
if [ "$BUMP_TYPE" = "fix" ] && [ -f "$WIKI_FILE" ]; then
  EXISTING=$(cat "$WIKI_FILE")
  printf '%s\n\n---\n\n%s\n' "$RELEASE_NOTE" "$EXISTING" > "$WIKI_FILE"
else
  printf '%s\n' "$RELEASE_NOTE" > "$WIKI_FILE"
fi
```

## Step W4: Regenerate Home.md

Auto-generate the index from all `Release-Note-*.md` files, sorted by version descending.

```bash
{
  echo "# Release Notes"
  echo
  for f in $(ls Release-Note-*.md 2>/dev/null | sed 's/^Release-Note-//;s/\.md$//' | sort -rV); do
    page_name="Release-Note-${f}"
    echo "- [${f}](${page_name})"
  done
} > Home.md
```

## Step W5: Commit + push

`git push origin HEAD` follows whatever branch `git clone` checked out, so this works regardless of whether the wiki's default branch is `master` or `main`. (Note: auto-created GitHub Wikis default to `master`, not `main`.)

```bash
git add "$WIKI_FILE" Home.md
git commit -m "Release notes for ${VERSION}"
git push origin HEAD
echo "Published: https://github.com/${OWNER_REPO}/wiki/Release-Note-${MAJOR}.${MINOR}"
```

## Verifying the publish

The authoritative check is the wiki remote's HEAD — inspect it directly with `git ls-remote`:

    git ls-remote "$WIKI_URL" HEAD

If the returned commit matches the one you just pushed, the publish succeeded. **Do NOT rely on curl to the wiki page URL** — for private-repo wikis, unauthenticated requests (even with a Bearer token) return 404 because page rendering requires a GitHub session cookie.

## Error handling (github-wiki)

- **Wiki not initialized** — `git ls-remote` returns "Repository not found" even though `has_wiki=true`. Create the first page via the Web UI at `https://github.com/<owner>/<repo>/wiki`, then re-run.
- **Wiki disabled on repo** — `has_wiki=false`. Enable wiki in repo Settings → Features → Wikis, or drop `github-wiki` from the channel list.
- **Push rejected (concurrent update)** — `git pull --rebase origin HEAD` then retry once.
