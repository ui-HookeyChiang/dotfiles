---
name: jira
description: Interact with Jira via REST API — create, search, read, comment, and transition tickets. Supports JQL queries, ADF formatting, and sub-tasks. For UOF post-merge workflow (transitions, fixVersion), use ubiquiti-jira.
argument-hint: "<comment|create|get|search|transition> [ticket] [args]"
landing-group: atlassian
---

# jira

Jira assistant (ubiquiti.atlassian.net). Load credentials, then `curl` the REST API. Full recipes in `references/operations.md`.

## Usage

```bash
/jira comment UOF-4399 "DTS work still pending, GPIO chip 8 pin 14/15"
/jira create UOF-4300 "EFG Neo: support LCM firmware update"
/jira search "project=UOF AND summary ~ NPI"
/jira get UOF-4399
/jira transition UOF-4399 "In Progress"
```

Natural language also works:
```bash
/jira add comment to UOF-4399 saying the DTS is blocked
/jira create a subtask under UOF-4300 for EFG Neo fan support
/jira mark UOF-4399 as done
```

## Step 0: Load Credentials

Always run this before any API call:

```bash
source ~/.config/ubiquiti/jira-credentials
# Credentials now available as $JIRA_EMAIL and $JIRA_TOKEN
# Base URL: https://ubiquiti.atlassian.net/rest/api/3
```

If missing/incomplete, run first-time setup, tell user to fill real values and retry. Do NOT proceed with placeholders.

```bash
if [ ! -f ~/.config/ubiquiti/jira-credentials ] || ! grep -q JIRA_EMAIL ~/.config/ubiquiti/jira-credentials 2>/dev/null; then
  mkdir -p ~/.config/ubiquiti
  cat > ~/.config/ubiquiti/jira-credentials << 'TMPL'
# Jira credentials — get API token from https://id.atlassian.com/manage-profile/security/api-tokens
export JIRA_EMAIL="YOUR_EMAIL@ui.com"
export JIRA_TOKEN="YOUR_API_TOKEN"
TMPL
  chmod 600 ~/.config/ubiquiti/jira-credentials
  echo "Created ~/.config/ubiquiti/jira-credentials template. Please edit it with your real credentials, then retry."
  echo "  Run: vi ~/.config/ubiquiti/jira-credentials"
fi
```

## Operations

Pick operation, run recipe from `references/operations.md`.

| Operation | What it does | Key gotcha | Recipe |
|-----------|--------------|------------|--------|
| comment | Add a comment to a ticket | `body` must be an ADF **doc** node, not a plain string | [operations.md#comment](references/operations.md#comment) |
| get | Fetch a ticket's fields | `fields=` query param controls which fields come back | [operations.md#get](references/operations.md#get) |
| create | Create a ticket / sub-task | Needs issuetype id/name + project key; UOF summary naming: `[product] description` (see `ubiquiti-jira`); long description → `md2adf.py` (see `references/adf-format.md`) | [operations.md#create](references/operations.md#create) |
| search | JQL search for issues | `POST /search` with a JQL string; ADF not involved | [operations.md#search](references/operations.md#search) |
| transition | Change a ticket's status | TWO-STEP — `GET /transitions` for the id, then `POST` with that id | [operations.md#transition](references/operations.md#transition) |

**UOF naming & workflow:** `[product] description` convention and post-merge workflow in `ubiquiti-jira`. This skill = generic Jira API only.

**ADF required:** `description`, `comment`, `body` MUST be ADF nodes — plain strings rejected; markdown in a single `paragraph` renders literally. Longer than one paragraph → `scripts/md2adf.py`. Full reference in `references/adf-format.md`.

Phase-4 auto-fill: `/jira fill <KEY>` — see `references/jira-fill-integration.md`.

## Output Handling

- Pipe responses through `python3 -m json.tool`
- Success: show ticket key/URL or comment ID
- Error: show full error message
- URL format: `https://ubiquiti.atlassian.net/browse/<TICKET>`

## Error Handling

| Code | Cause | Fix |
|------|-------|-----|
| 401 | Credentials wrong or expired | Remind user to refresh `~/.config/ubiquiti/jira-credentials` |
| 404 | Ticket not found | Verify ticket key |
| 400 | Bad request | Show full response body to diagnose field issues |

## Important Notes

- ADF required for `description`/`comment`/`body` — plain strings rejected
- UOF post-merge workflow → `ubiquiti-jira`
- Credentials: `~/.config/ubiquiti/jira-credentials`
- Never print credentials
