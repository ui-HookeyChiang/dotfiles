# Channel: confluence

Publish the release note to a Confluence wiki page hierarchy. The caller must provide:

- **`CONFLUENCE_PARENT_ID`** — parent page ID under which "Release Note" subpages live
- **`CONFLUENCE_SPACE`** — Confluence space key

These are passed by the calling profile (e.g., semver-release `skill` profile sets them to the skill repo's wiki page). They are NOT hardcoded here.

## Page Hierarchy

```
<Parent Page>  [CONFLUENCE_PARENT_ID]
  +-- Release Note                [find or create]
        +-- 0.1                   <- major.minor subpage
        +-- 0.2
        +-- 0.3
        +-- 1.0
```

- **Intermediate page**: "Release Note" — find by title or create if missing
- **Version pages**: named by `major.minor` (e.g., `0.3`, `1.0`)

## Bump Type Logic

| Bump Type | Action |
|-----------|--------|
| **fix/patch** (e.g., 0.3.1) | Find existing `0.3` page, prepend new release note (newest first), update page |
| **minor** (e.g., 0.4.0) | Create new `0.4` subpage under "Release Note" parent |
| **major** (e.g., 1.0.0) | Create new `1.0` subpage under "Release Note" parent |

## Step C0: Load Credentials

Uses the same Atlassian credentials as the `jira` and `confluence` skills. See `confluence` skill for setup instructions if credentials are missing.

```bash
source ~/.config/ubiquiti/jira-credentials
# Provides $JIRA_EMAIL and $JIRA_TOKEN
```

## Step C1: Find or Create "Release Note" Intermediate Page

Search for the "Release Note" page under the parent:

```bash
# CONFLUENCE_PARENT_ID and CONFLUENCE_SPACE are provided by the calling profile
# e.g., skill profile sets: CONFLUENCE_PARENT_ID=4768563289 CONFLUENCE_SPACE=UDX

# Search for "Release Note" page under parent
RELEASE_NOTE_PAGE=$(curl -s -u "$JIRA_EMAIL:$JIRA_TOKEN" \
  -G --data-urlencode "cql=type=page AND space=$CONFLUENCE_SPACE AND title=\"Release Note\" AND ancestor=$CONFLUENCE_PARENT_ID" \
  "https://ubiquiti.atlassian.net/wiki/rest/api/content/search" \
  | jq -r '.results[0].id // empty')

# Create if it doesn't exist
if [ -z "$RELEASE_NOTE_PAGE" ]; then
  RELEASE_NOTE_PAGE=$(curl -s -u "$JIRA_EMAIL:$JIRA_TOKEN" \
    -X POST \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    "https://ubiquiti.atlassian.net/wiki/rest/api/content" \
    -d '{
      "type": "page",
      "title": "Release Note",
      "status": "current",
      "space": {"key": "'"$CONFLUENCE_SPACE"'"},
      "ancestors": [{"id": "'"$CONFLUENCE_PARENT_ID"'"}],
      "body": {
        "storage": {
          "value": "<p>Release notes organized by major.minor version.</p>",
          "representation": "storage"
        }
      }
    }' | jq -r '.id')
  echo "Created Release Note page: $RELEASE_NOTE_PAGE"
fi
```

## Step C2: Convert Markdown to XHTML

Confluence uses Storage Format (XHTML). Convert the release note markdown to XHTML before posting.

Conversion rules:

| Markdown | Confluence Storage Format (XHTML) |
|----------|----------------------------------|
| `# Heading 1` | `<h1>Heading 1</h1>` |
| `## Heading 2` | `<h2>Heading 2</h2>` |
| `### Heading 3` | `<h3>Heading 3</h3>` |
| `Paragraph text` | `<p>Paragraph text</p>` |
| `- list item` | `<ul><li>list item</li></ul>` |
| `1. ordered item` | `<ol><li>ordered item</li></ol>` |
| `**bold**` | `<strong>bold</strong>` |
| `*italic*` | `<em>italic</em>` |
| `` `code` `` | `<code>code</code>` |
| `> blockquote` | `<blockquote><p>blockquote</p></blockquote>` |
| `[text](url)` | `<a href="url">text</a>` |
| `---` | `<hr />` |

For fenced code blocks, use the Confluence code macro:
```xml
<ac:structured-macro ac:name="code">
  <ac:parameter ac:name="language">bash</ac:parameter>
  <ac:plain-text-body><![CDATA[code content here]]></ac:plain-text-body>
</ac:structured-macro>
```

For a horizontal separator between release notes on the same page:
```xml
<hr />
```

Use `jq -Rs .` to JSON-escape the XHTML body before embedding in API payloads:
```bash
XHTML_BODY="<h1>v0.3.0</h1><p>Release content...</p>"
# JSON-escape for API payload
ESCAPED_BODY=$(echo "$XHTML_BODY" | jq -Rs .)
```

## Step C3a: Fix/Patch Bump — Prepend to Existing Page

For fix/patch bumps, find the existing major.minor page and prepend the new content:

```bash
MAJOR_MINOR="0.3"  # from Step 0

# Find existing version page — try published first, then draft
VERSION_PAGE_ID=$(curl -s -u "$JIRA_EMAIL:$JIRA_TOKEN" \
  -G --data-urlencode "cql=type=page AND space=$CONFLUENCE_SPACE AND title=\"$MAJOR_MINOR\" AND ancestor=$RELEASE_NOTE_PAGE" \
  "https://ubiquiti.atlassian.net/wiki/rest/api/content/search" \
  | jq -r '.results[0].id // empty')

# CQL search does NOT find draft pages — if empty, check known page ID from prior creation
# or list children of the Release Note page
if [ -z "$VERSION_PAGE_ID" ]; then
  echo "WARN: CQL search found nothing (page may be a draft). Check stored page ID or list children."
  # Fallback: create a new page (treating as minor bump)
fi

# Fetch current page — try published first, then draft
RESPONSE=$(curl -s -w "\n%{http_code}" -u "$JIRA_EMAIL:$JIRA_TOKEN" \
  "https://ubiquiti.atlassian.net/wiki/rest/api/content/$VERSION_PAGE_ID?expand=body.storage,version")
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
CURRENT=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "404" ]; then
  # Page might be a draft — retry with ?status=draft
  RESPONSE=$(curl -s -w "\n%{http_code}" -u "$JIRA_EMAIL:$JIRA_TOKEN" \
    "https://ubiquiti.atlassian.net/wiki/rest/api/content/$VERSION_PAGE_ID?status=draft&expand=body.storage,version")
  HTTP_CODE=$(echo "$RESPONSE" | tail -1)
  CURRENT=$(echo "$RESPONSE" | sed '$d')
  if [ "$HTTP_CODE" = "404" ]; then
    echo "ERROR: Page $VERSION_PAGE_ID not found (neither published nor draft)"
    # Fall through to Step C3b (create new page)
  fi
fi
CURRENT_VERSION=$(echo "$CURRENT" | jq -r '.version.number')
CURRENT_BODY=$(echo "$CURRENT" | jq -r '.body.storage.value')
CURRENT_STATUS=$(echo "$CURRENT" | jq -r '.status')

# Version handling differs for draft vs published:
#   - Published pages: increment version number
#   - Draft pages: ALWAYS use version 1 (Confluence Cloud limitation)
if [ "$CURRENT_STATUS" = "draft" ]; then
  NEXT_VERSION=1
else
  NEXT_VERSION=$((CURRENT_VERSION + 1))
fi

# Prepend new release note (newest first), separated by <hr />
NEW_BODY="${XHTML_BODY}<hr />${CURRENT_BODY}"

# Update the page
curl -s -u "$JIRA_EMAIL:$JIRA_TOKEN" \
  -X PUT \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  "https://ubiquiti.atlassian.net/wiki/rest/api/content/$VERSION_PAGE_ID" \
  -d "{
    \"type\": \"page\",
    \"title\": \"$MAJOR_MINOR\",
    \"status\": \"$CURRENT_STATUS\",
    \"space\": {\"key\": \"$CONFLUENCE_SPACE\"},
    \"version\": {\"number\": $NEXT_VERSION},
    \"body\": {
      \"storage\": {
        \"value\": $(echo "$NEW_BODY" | jq -Rs .),
        \"representation\": \"storage\"
      }
    }
  }" | jq --arg space "$CONFLUENCE_SPACE" '{id, title, version: .version.number, url: "https://ubiquiti.atlassian.net/wiki/spaces/\($space)/pages/\(.id)"}'
```

**Draft page caveats:**
- CQL search (`/content/search`) does NOT return draft pages — you must know the page ID from initial creation or use `/content/{parent_id}/child/page` (which also excludes drafts)
- Draft pages always use `version: 1` on PUT — Confluence Cloud does not support draft versioning
- Always include `"status": "draft"` in PUT body to preserve draft status
- Always add `?status=draft` to GET requests for draft pages

## Step C3b: Minor/Major Bump — Create New Page

For minor or major bumps, create a new subpage under "Release Note":

```bash
MAJOR_MINOR="0.4"  # from Step 0

curl -s -u "$JIRA_EMAIL:$JIRA_TOKEN" \
  -X POST \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  "https://ubiquiti.atlassian.net/wiki/rest/api/content" \
  -d "{
    \"type\": \"page\",
    \"title\": \"$MAJOR_MINOR\",
    \"status\": \"current\",
    \"space\": {\"key\": \"$CONFLUENCE_SPACE\"},
    \"ancestors\": [{\"id\": \"$RELEASE_NOTE_PAGE\"}],
    \"body\": {
      \"storage\": {
        \"value\": $(echo "$XHTML_BODY" | jq -Rs .),
        \"representation\": \"storage\"
      }
    }
  }" | jq --arg space "$CONFLUENCE_SPACE" '{id, title, url: "https://ubiquiti.atlassian.net/wiki/spaces/\($space)/pages/\(.id)"}'
```

## Step C4: List Existing Version Pages (Optional)

To verify the hierarchy or list existing version pages:

```bash
# Get children of Release Note page
curl -s -u "$JIRA_EMAIL:$JIRA_TOKEN" \
  "https://ubiquiti.atlassian.net/wiki/rest/api/content/$RELEASE_NOTE_PAGE/child/page?limit=100" \
  | jq --arg space "$CONFLUENCE_SPACE" -r '.results[] | "\(.id)\t\(.title)\thttps://ubiquiti.atlassian.net/wiki/spaces/\($space)/pages/\(.id)"'
```
