# Writing long descriptions and comments: use `md2adf.py`

Anything longer than a single paragraph (Jira ticket descriptions, comments
with code blocks, multi-section runbooks) **must** be converted from markdown to
real ADF nodes — `heading`, `codeBlock`, `bulletList`, `orderedList`, `table` —
before PUT/POST. If you instead split markdown by newlines and stuff every line
into a `paragraph` node, Jira renders raw characters: the user sees literal
`## Why`, literal triple-backticks, literal `| a | b |`. This is the most common
Jira-via-API regression — do not repeat it.

The skill ships a converter. Pipe markdown in, get ADF JSON out:

```bash
SKILL_DIR=~/.claude/skills/jira

# Build ADF from a markdown file
ADF=$(python3 "$SKILL_DIR/scripts/md2adf.py" < /path/to/desc.md)

# Use it as the description field of a create/update payload
PAYLOAD=$(jq -nc --argjson adf "$ADF" '{fields: {description: $adf}}')

curl -sS -u "$JIRA_EMAIL:$JIRA_TOKEN" -H "Content-Type: application/json" \
  -X PUT "https://ubiquiti.atlassian.net/rest/api/3/issue/UOF-1234" -d "$PAYLOAD"
```

For a `comment` payload, set the body to the same ADF:
`jq -nc --argjson adf "$ADF" '{body: $adf}'`.

## Supported markdown subset

| Markdown | ADF node |
|---|---|
| `## H2`, `### H3` (`#` × 1-6) | `heading` with `attrs.level` |
| ` ```bash ... ``` ` | `codeBlock` with `attrs.language` |
| `- item` / `* item` | `bulletList` / `listItem` |
| `1. item` | `orderedList` / `listItem` |
| `\| a \| b \|` plus `\|---\|---\|` | `table` with `tableHeader` / `tableCell` |
| `` `code` `` | inline `code` mark |
| `**bold**` | `strong` mark |
| blank line | paragraph separator |

## Verify the output before PUT

Check that node types are not all `paragraph`:

```bash
python3 "$SKILL_DIR/scripts/md2adf.py" < desc.md | \
  jq '[.content[].type] | group_by(.) | map({type:.[0], count:length})'
```

You should see a mix of `heading`, `codeBlock`, `bulletList`, `paragraph`, etc.
If everything is `paragraph`, the markdown was treated as plain text —
re-inspect for missing newlines around fenced code blocks or table headers.

## Regression suite

The converter has a regression suite at `scripts/md2adf-test.sh` (covers heading
levels, codeBlock language, bullet/ordered lists, tables, inline code, bold, doc
envelope). Run it before merging changes to the converter.
