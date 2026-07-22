# Jira operation recipes

Full curl + jq/python recipes for the 5 operations. Each recipe is self-contained:
it sources credentials and sets the base URL once, then reuses `$BASE`:

```bash
source ~/.config/ubiquiti/jira-credentials
BASE=https://ubiquiti.atlassian.net/rest/api/3
```

All recipes assume the credentials file exists (see SKILL.md Step 0). Replace
`<TICKET>` with an issue key like `UOF-4399`.

---

## comment

The `body` must be an ADF **doc** node — a plain string is rejected.

```bash
source ~/.config/ubiquiti/jira-credentials
BASE=https://ubiquiti.atlassian.net/rest/api/3
curl -s -u "$JIRA_EMAIL:$JIRA_TOKEN" \
  -X POST \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  "$BASE/issue/<TICKET>/comment" \
  -d '{
    "body": {
      "type": "doc",
      "version": 1,
      "content": [
        {
          "type": "paragraph",
          "content": [{"type": "text", "text": "<YOUR MESSAGE>"}]
        }
      ]
    }
  }'
```

For multi-paragraph comments, add more paragraph objects to the `content` array.
For bullet lists:
```json
{
  "type": "bulletList",
  "content": [
    {
      "type": "listItem",
      "content": [{"type": "paragraph", "content": [{"type": "text", "text": "Item 1"}]}]
    }
  ]
}
```

For comments longer than a single paragraph (code blocks, multi-section), build
the ADF body with `md2adf.py` instead of hand-writing nodes — see
`adf-format.md`. Set the body to the same ADF: `jq -nc --argjson adf "$ADF" '{body: $adf}'`.

---

## get

The `fields=` query param controls which fields are returned.

```bash
source ~/.config/ubiquiti/jira-credentials
BASE=https://ubiquiti.atlassian.net/rest/api/3
curl -s -u "$JIRA_EMAIL:$JIRA_TOKEN" \
  -H "Accept: application/json" \
  "$BASE/issue/<TICKET>?fields=summary,status,assignee,description,parent,subtasks,issuetype" \
  | python3 -m json.tool
```

---

## create

First, get the project's issuetype IDs:
```bash
source ~/.config/ubiquiti/jira-credentials
BASE=https://ubiquiti.atlassian.net/rest/api/3
curl -s -u "$JIRA_EMAIL:$JIRA_TOKEN" \
  -H "Accept: application/json" \
  "$BASE/project/UOF" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for it in data.get('issueTypes', []):
    print(it['id'], it['name'])
"
```

Then create. For anything longer than a one-line description, convert markdown
to ADF via `md2adf.py` (see `adf-format.md`) — do NOT inline a single
`paragraph` for a multi-section ticket:

```bash
source ~/.config/ubiquiti/jira-credentials
BASE=https://ubiquiti.atlassian.net/rest/api/3
SKILL_DIR=~/.claude/skills/jira

# Build ADF from a prepared markdown file (heading/codeBlock/table/list aware)
ADF=$(python3 "$SKILL_DIR/scripts/md2adf.py" < /path/to/desc.md)

PAYLOAD=$(jq -nc --argjson adf "$ADF" '{
  fields: {
    project: {key: "UOF"},
    issuetype: {name: "Sub-task"},
    parent: {key: "<PARENT_TICKET>"},
    summary: "<TICKET TITLE>",
    description: $adf
  }
}')

curl -sS -u "$JIRA_EMAIL:$JIRA_TOKEN" -H "Content-Type: application/json" \
  -X POST "$BASE/issue" -d "$PAYLOAD"
```

Common issue types: `Story`, `Task`, `Sub-task`, `Bug`

---

## search

JQL search uses `POST /search/jql` — ADF is not involved. (The legacy
`POST /issue/search` was removed by Atlassian in May 2025; it now returns
410/405.) Response carries `issues[]` plus `nextPageToken`/`isLast` for
pagination; the `.issues[].key` / `.fields` shape is unchanged.

```bash
source ~/.config/ubiquiti/jira-credentials
BASE=https://ubiquiti.atlassian.net/rest/api/3
curl -s -u "$JIRA_EMAIL:$JIRA_TOKEN" \
  -X POST \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  "$BASE/search/jql" \
  -d '{
    "jql": "<JQL QUERY>",
    "fields": ["summary", "status", "issuetype", "parent"],
    "maxResults": 20
  }' | python3 -c "
import sys, json
data = json.load(sys.stdin)
for issue in data.get('issues', []):
    print(issue['key'], issue['fields']['summary'], '-', issue['fields']['status']['name'])
"
```

Common JQL examples:
- `project=UOF AND parent=UOF-4300 ORDER BY created ASC` — child tasks of a ticket
- `project=UOF AND summary ~ \"EFG Neo\" ORDER BY created DESC` — search by title
- `project=UOF AND assignee=currentUser() AND status != Done` — my open tickets

---

## transition

**IMPORTANT: Different issue types have different workflows.** Always `GET /transitions`
first — never hardcode transition IDs across issue types.

### UOF Project Workflow Reference

#### Task (任務)

| ID | Name | Typical use |
|----|------|-------------|
| 2 | monitoring | Parked / watching |
| 3 | RD In Progress | Active development |
| 21 | Need more info | Blocked on info |
| 111 | Dev Completed | Code done, awaiting QA |
| 121 | RD Completed & Close | Done (final state) |
| 131 | Block by something | Blocked |
| 141 | PR release | Released |

#### Epic (大型工作)

| ID | Name | Status category | Trap |
|----|------|-----------------|------|
| 11 | To Do | To Do | — |
| 21 | In Progress | In Progress | — |
| 31 | Done | 完成 | **Lands on "No need to fix" status, NOT "Done"** |
| 41 | SQA TESTING | In Progress | — |
| 71 | RD developing | In Progress | — |

**Epic trap:** Transition `31` ("Done") results in status name "No need to fix" even though
`statusCategory` is "完成" (Done). This is a workflow design quirk — the Epic has no
"RD Completed & Close" equivalent. Use `31` for closing Epics but expect the status
name to show "No need to fix".

### Recipe

First get available transitions:
```bash
source ~/.config/ubiquiti/jira-credentials
BASE=https://ubiquiti.atlassian.net/rest/api/3
curl -s -u "$JIRA_EMAIL:$JIRA_TOKEN" \
  -H "Accept: application/json" \
  "$BASE/issue/<TICKET>/transitions" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
for t in data.get('transitions', []):
    print(t['id'], t['name'])
"
```

Then transition:
```bash
source ~/.config/ubiquiti/jira-credentials
BASE=https://ubiquiti.atlassian.net/rest/api/3
curl -s -u "$JIRA_EMAIL:$JIRA_TOKEN" \
  -X POST \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  "$BASE/issue/<TICKET>/transitions" \
  -d '{"transition": {"id": "<TRANSITION_ID>"}}'
```
