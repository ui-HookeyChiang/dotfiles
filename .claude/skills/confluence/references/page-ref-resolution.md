# Page reference resolution & credential setup

## Page reference resolution

Any argument accepting a page reference (URL, title, or ID) must be resolved to a
numeric page ID before calling the API. `--space` is needed only when the
reference is a title (URLs and raw IDs carry/are the ID already).

```bash
resolve_page_ref() {
  local ref="$1"
  local space="$2"  # optional, only needed for title lookup

  # Pattern 1: .../wiki/spaces/XX/overview?homepageId=<ID>
  if echo "$ref" | grep -qE 'wiki/spaces/[^/]+/overview\?homepageId='; then
    echo "$ref" | grep -oP 'homepageId=\K[0-9]+'
    return
  fi

  # Pattern 2: .../wiki/spaces/XX/pages/edit-v2/<ID>
  if echo "$ref" | grep -qE 'wiki/spaces/[^/]+/pages/edit-v2/[0-9]+'; then
    echo "$ref" | grep -oP 'pages/edit-v2/\K[0-9]+'
    return
  fi

  # Pattern 3: .../wiki/spaces/XX/pages/<ID>/Page+Title
  if echo "$ref" | grep -qE 'wiki/spaces/[^/]+/pages/[0-9]+/'; then
    echo "$ref" | grep -oP 'pages/\K[0-9]+'
    return
  fi

  # Pattern 4: .../wiki/spaces/XX/pages/<ID>
  if echo "$ref" | grep -qE 'wiki/spaces/[^/]+/pages/[0-9]+$'; then
    echo "$ref" | grep -oP 'pages/\K[0-9]+'
    return
  fi

  # Raw numeric ID
  if echo "$ref" | grep -qE '^[0-9]+$'; then
    echo "$ref"
    return
  fi

  # Title lookup via CQL (requires --space)
  if [ -z "$space" ]; then
    echo "ERROR: --space is required when using a title to identify a page" >&2
    return 1
  fi
  local result
  result=$(curl -s -u "$JIRA_EMAIL:$JIRA_TOKEN" \
    -G --data-urlencode "cql=type=page AND space=\"$space\" AND title=\"$ref\"" \
    "https://ubiquiti.atlassian.net/wiki/rest/api/content/search")
  local page_id
  page_id=$(echo "$result" | jq -r '.results[0].id // empty')
  if [ -z "$page_id" ]; then
    echo "ERROR: No page found with title \"$ref\" in space $space" >&2
    return 1
  fi
  echo "$page_id"
}
```

To extract the space key from a URL:

```bash
extract_space_from_url() {
  local ref="$1"
  if echo "$ref" | grep -qE 'wiki/spaces/[^/]+'; then
    echo "$ref" | grep -oP 'wiki/spaces/\K[^/]+'
  fi
}
```

To derive the space key from a page ID (when `--space` is not provided):

```bash
get_space_from_page() {
  local page_id="$1"
  curl -s -u "$JIRA_EMAIL:$JIRA_TOKEN" \
    "https://ubiquiti.atlassian.net/wiki/rest/api/content/$page_id?expand=space" \
    | jq -r '.space.key'
}
```

---

## credential-migration

First-time setup for `~/.config/ubiquiti/jira-credentials`. The happy path
(`source` + missing-creds check) lives inline in SKILL.md Step 0; this is the
full migration + template logic to run when the file is absent or incomplete.
It first tries to migrate from legacy paths, then falls back to writing a
template the user must edit.

```bash
if [ ! -f ~/.config/ubiquiti/jira-credentials ] || ! grep -q JIRA_EMAIL ~/.config/ubiquiti/jira-credentials 2>/dev/null; then
  # Migrate from legacy paths if they exist
  for legacy in ~/.ubiquiti/jira-credentials ~/.private/jira-credentials; do
    if [ -f "$legacy" ] && grep -q JIRA_EMAIL "$legacy" 2>/dev/null; then
      mkdir -p ~/.config/ubiquiti
      cp "$legacy" ~/.config/ubiquiti/jira-credentials
      chmod 600 ~/.config/ubiquiti/jira-credentials
      echo "Migrated credentials from $legacy to ~/.config/ubiquiti/jira-credentials"
      break
    fi
  done
fi

if [ ! -f ~/.config/ubiquiti/jira-credentials ] || ! grep -q JIRA_EMAIL ~/.config/ubiquiti/jira-credentials 2>/dev/null; then
  mkdir -p ~/.config/ubiquiti
  cat > ~/.config/ubiquiti/jira-credentials << 'TMPL'
# Atlassian credentials (shared by Jira and Confluence skills)
# Get API token from https://id.atlassian.com/manage-profile/security/api-tokens
export JIRA_EMAIL="YOUR_EMAIL@ui.com"
export JIRA_TOKEN="YOUR_API_TOKEN"
TMPL
  chmod 600 ~/.config/ubiquiti/jira-credentials
  echo "Created ~/.config/ubiquiti/jira-credentials template. Please edit it with your real credentials, then retry."
  echo "  Run: vi ~/.config/ubiquiti/jira-credentials"
fi
```

After creating the template, tell the user to fill in their real email and API
token, then retry the command. Do NOT proceed with placeholder values.
