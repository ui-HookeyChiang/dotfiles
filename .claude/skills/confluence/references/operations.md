# Confluence operation recipes

Full curl + jq recipes for the 8 operations. The base URL is set once and reused:

```bash
BASE=https://ubiquiti.atlassian.net/wiki/rest/api
```

All recipes assume credentials are loaded (`source ~/.config/ubiquiti/jira-credentials`)
and, where a page reference is taken, that the helper functions from
`page-ref-resolution.md` are in scope.

---

## first-time-setup

If `~/.config/ubiquiti/jira-credentials` does not exist or is missing
`JIRA_EMAIL`/`JIRA_TOKEN`, run the setup automatically. This first tries to
migrate credentials from legacy paths, then falls back to writing a template.
The full migration + template logic lives in
`page-ref-resolution.md#credential-migration`. After creating the template,
tell the user to fill in their real email and API token, then retry. Do NOT
proceed with placeholder values.

---

## search

```bash
source ~/.config/ubiquiti/jira-credentials
BASE=https://ubiquiti.atlassian.net/wiki/rest/api

# Basic search within a space
curl -s -u "$JIRA_EMAIL:$JIRA_TOKEN" \
  -G --data-urlencode "cql=type=page AND space=<SPACE> AND title~\"<QUERY>\"" \
  --data-urlencode "expand=space" \
  "$BASE/content/search" \
  | jq -r '.results[] | "\(.id)\t\(.title)\thttps://ubiquiti.atlassian.net/wiki/spaces/\(.space.key)/pages/\(.id)"'

# Search across all spaces
curl -s -u "$JIRA_EMAIL:$JIRA_TOKEN" \
  -G --data-urlencode "cql=type=page AND title~\"<QUERY>\"" \
  --data-urlencode "expand=space" \
  "$BASE/content/search" \
  | jq -r '.results[] | "\(.id)\t\(.space.key)\t\(.title)\thttps://ubiquiti.atlassian.net/wiki/spaces/\(.space.key)/pages/\(.id)"'
```

CQL tips:
- `title~"Firmware"` — fuzzy title match (contains)
- `title="Exact Title"` — exact title match
- `text~"keyword"` — full-text body search
- `label="my-label"` — pages with a specific label
- `ancestor=<PAGE_ID>` — pages under a parent (recursive)

---

## read

```bash
source ~/.config/ubiquiti/jira-credentials
BASE=https://ubiquiti.atlassian.net/wiki/rest/api
PAGE_ID=$(resolve_page_ref "<PAGE_REF>" "<SPACE>")

curl -s -u "$JIRA_EMAIL:$JIRA_TOKEN" \
  "$BASE/content/$PAGE_ID?expand=body.storage,version,ancestors,space" \
  | jq '{
    id: .id,
    title: .title,
    space: .space.key,
    url: "https://ubiquiti.atlassian.net/wiki/spaces/\(.space.key)/pages/\(.id)",
    version: .version.number,
    ancestors: [.ancestors[] | {id: .id, title: .title}],
    body: .body.storage.value
  }'
```

To convert the storage-format body to readable text, see
`storage-format.md#strip-html`. For drafts, add `?status=draft` to the request.

---

## tree

```bash
source ~/.config/ubiquiti/jira-credentials
BASE=https://ubiquiti.atlassian.net/wiki/rest/api
PAGE_ID=$(resolve_page_ref "<PAGE_REF>" "<SPACE>")

curl -s -u "$JIRA_EMAIL:$JIRA_TOKEN" \
  "$BASE/content/$PAGE_ID/child/page?expand=space&limit=100" \
  | jq -r '.results[] | "\(.id)\t\(.title)\thttps://ubiquiti.atlassian.net/wiki/spaces/\(.space.key)/pages/\(.id)"'
```

To get the page title as a tree header:

```bash
PARENT_TITLE=$(curl -s -u "$JIRA_EMAIL:$JIRA_TOKEN" \
  "$BASE/content/$PAGE_ID" \
  | jq -r '.title')
echo "Children of: $PARENT_TITLE ($PAGE_ID)"
```

---

## create

Creates a **published** (`status: current`) page. `--space` is derived from the
parent when not provided (`get_space_from_page`, see `page-ref-resolution.md`).

```bash
source ~/.config/ubiquiti/jira-credentials
BASE=https://ubiquiti.atlassian.net/wiki/rest/api
PARENT_ID=$(resolve_page_ref "<PARENT_REF>" "<SPACE>")

# Derive space key from parent if not provided
SPACE_KEY="${SPACE:-$(get_space_from_page "$PARENT_ID")}"

curl -s -u "$JIRA_EMAIL:$JIRA_TOKEN" \
  -X POST \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  "$BASE/content" \
  -d '{
    "type": "page",
    "title": "<PAGE_TITLE>",
    "status": "current",
    "space": {"key": "'"$SPACE_KEY"'"},
    "ancestors": [{"id": "'"$PARENT_ID"'"}],
    "body": {
      "storage": {
        "value": "<p>Page content here</p>",
        "representation": "storage"
      }
    }
  }' | jq '{id: .id, title: .title, url: "https://ubiquiti.atlassian.net/wiki/spaces/\(.space.key)/pages/\(.id)", status: .status}'
```

For user-provided plain text, wrap each paragraph in `<p>` tags. For richer
content, use Confluence Storage Format — see `storage-format.md`.

---

## draft

Creates a page with `status: draft`. Drafts are not visible to others until
published; use `publish` to make them visible. `--space` is derived from the
parent when not provided.

```bash
source ~/.config/ubiquiti/jira-credentials
BASE=https://ubiquiti.atlassian.net/wiki/rest/api
PARENT_ID=$(resolve_page_ref "<PARENT_REF>" "<SPACE>")
SPACE_KEY="${SPACE:-$(get_space_from_page "$PARENT_ID")}"

curl -s -u "$JIRA_EMAIL:$JIRA_TOKEN" \
  -X POST \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  "$BASE/content" \
  -d '{
    "type": "page",
    "title": "<PAGE_TITLE>",
    "status": "draft",
    "space": {"key": "'"$SPACE_KEY"'"},
    "ancestors": [{"id": "'"$PARENT_ID"'"}],
    "body": {
      "storage": {
        "value": "<p>Draft content here</p>",
        "representation": "storage"
      }
    }
  }' | jq '{id: .id, title: .title, url: "https://ubiquiti.atlassian.net/wiki/spaces/\(.space.key)/pages/\(.id)", status: .status}'
```

---

## update

Version rule (the single source of truth): updating a **published** page
requires fetching the current version number and incrementing it by 1. For
**draft** pages, always use `version: 1` — Confluence Cloud does not support
draft versioning. The same rule applies to `publish`.

```bash
source ~/.config/ubiquiti/jira-credentials
BASE=https://ubiquiti.atlassian.net/wiki/rest/api
PAGE_ID=$(resolve_page_ref "<PAGE_REF>" "<SPACE>")

# Fetch current version, title, and status
CURRENT=$(curl -s -u "$JIRA_EMAIL:$JIRA_TOKEN" \
  "$BASE/content/$PAGE_ID?expand=version,space")
CURRENT_VERSION=$(echo "$CURRENT" | jq -r '.version.number')
CURRENT_TITLE=$(echo "$CURRENT" | jq -r '.title')
CURRENT_STATUS=$(echo "$CURRENT" | jq -r '.status')
SPACE_KEY=$(echo "$CURRENT" | jq -r '.space.key')

# Draft pages: always version 1; published pages: increment
if [ "$CURRENT_STATUS" = "draft" ]; then
  NEXT_VERSION=1
else
  NEXT_VERSION=$((CURRENT_VERSION + 1))
fi

curl -s -u "$JIRA_EMAIL:$JIRA_TOKEN" \
  -X PUT \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  "$BASE/content/$PAGE_ID" \
  -d '{
    "type": "page",
    "title": "'"$CURRENT_TITLE"'",
    "status": "'"$CURRENT_STATUS"'",
    "space": {"key": "'"$SPACE_KEY"'"},
    "version": {"number": '"$NEXT_VERSION"'},
    "body": {
      "storage": {
        "value": "<p>Updated content here</p>",
        "representation": "storage"
      }
    }
  }' | jq '{id: .id, title: .title, version: .version.number, url: "https://ubiquiti.atlassian.net/wiki/spaces/\(.space.key)/pages/\(.id)"}'
```

To append content instead of replacing, fetch the current body first:

```bash
CURRENT_BODY=$(curl -s -u "$JIRA_EMAIL:$JIRA_TOKEN" \
  "$BASE/content/$PAGE_ID?expand=body.storage" \
  | jq -r '.body.storage.value')
# Append new content
NEW_BODY="${CURRENT_BODY}<p>Appended content</p>"
```

---

## publish

Convert a draft page to a published (current) page. Drafts always use
`version: 1` (see the version rule under `update`).

```bash
source ~/.config/ubiquiti/jira-credentials
BASE=https://ubiquiti.atlassian.net/wiki/rest/api
PAGE_ID=$(resolve_page_ref "<PAGE_REF>" "<SPACE>")

# Fetch draft content
CURRENT=$(curl -s -u "$JIRA_EMAIL:$JIRA_TOKEN" \
  "$BASE/content/$PAGE_ID?expand=body.storage,space&status=draft")
CURRENT_TITLE=$(echo "$CURRENT" | jq -r '.title')
CURRENT_BODY=$(echo "$CURRENT" | jq -r '.body.storage.value')
SPACE_KEY=$(echo "$CURRENT" | jq -r '.space.key')

curl -s -u "$JIRA_EMAIL:$JIRA_TOKEN" \
  -X PUT \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  "$BASE/content/$PAGE_ID" \
  -d "{
    \"type\": \"page\",
    \"title\": \"$CURRENT_TITLE\",
    \"status\": \"current\",
    \"space\": {\"key\": \"$SPACE_KEY\"},
    \"version\": {\"number\": 1},
    \"body\": {
      \"storage\": {
        \"value\": $(echo "$CURRENT_BODY" | jq -Rs .),
        \"representation\": \"storage\"
      }
    }
  }" | jq '{id: .id, title: .title, status: .status, version: .version.number, url: "https://ubiquiti.atlassian.net/wiki/spaces/\(.space.key)/pages/\(.id)"}'
```

---

## comment

Comments are created via `POST /content` with `type: "comment"` and a
`container` field referencing the parent page (the `/child/comment`
sub-resource does not accept POST).

```bash
source ~/.config/ubiquiti/jira-credentials
BASE=https://ubiquiti.atlassian.net/wiki/rest/api
PAGE_ID=$(resolve_page_ref "<PAGE_REF>" "<SPACE>")

curl -s -u "$JIRA_EMAIL:$JIRA_TOKEN" \
  -X POST \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  "$BASE/content" \
  -d '{
    "type": "comment",
    "container": {"id": "'"$PAGE_ID"'", "type": "page", "status": "current"},
    "body": {
      "storage": {
        "value": "<p>Comment text here</p>",
        "representation": "storage"
      }
    }
  }' | jq '{id: .id, type: .type, created: .version.when}'
```

For multi-paragraph comments, concatenate `<p>` blocks. For mentions, see
`storage-format.md#mentions`.
