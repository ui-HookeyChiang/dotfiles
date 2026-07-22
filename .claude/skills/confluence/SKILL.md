---
name: confluence
description: Interact with Confluence wiki via REST API — search, read, create, update, draft, publish pages, manage subpages, and add comments. For UOF post-merge workflow, use ubiquiti-jira.
argument-hint: "<search|read|tree|create|draft|update|publish|comment> [page-ref] [args]"
landing-group: atlassian
---

# confluence

Confluence assistant (ubiquiti.atlassian.net/wiki). Load credentials first, then `curl` the REST API. Full recipes in `references/operations.md`.

## Usage

```bash
/confluence search "Firmware" --space UDX
/confluence read https://ubiquiti.atlassian.net/wiki/spaces/UDX/pages/1849984059/UniFi+Dream+X+Home
/confluence tree 1849984059
/confluence create "My New Page" --parent 1849984059 --space UDX
/confluence draft "WIP Notes" --parent 1849984059 --space UDX
/confluence update 1849984059 "Updated content here"
/confluence publish 2000000001
/confluence comment 1849984059 "This looks good"
```

Natural language also works:
```bash
/confluence find pages about NPI in UDX space
/confluence show me the children of the UDX home page
/confluence create a draft under the Firmware page in UDX
/confluence publish my draft page
```

## Step 0: Load Credentials

Always run this before any API call:

```bash
source ~/.config/ubiquiti/jira-credentials
# Credentials now available as $JIRA_EMAIL and $JIRA_TOKEN
# Base URL: https://ubiquiti.atlassian.net/wiki/rest/api
```

If missing or incomplete, run first-time setup per `references/operations.md#first-time-setup` (migration logic in `references/page-ref-resolution.md#credential-migration`). Tell user to fill real values and retry. Do NOT proceed with placeholders.

## Operations

Resolve page reference to numeric ID first, then run the recipe from `references/operations.md`.

| Operation | What it does | Key gotcha | Recipe |
|-----------|--------------|------------|--------|
| search | Find pages by CQL (title/text/label/ancestor) | `--space` narrows to one space; omit for all-spaces | [operations.md#search](references/operations.md#search) |
| read | Fetch a page's body, version, ancestors | Drafts need `?status=draft` on the request | [operations.md#read](references/operations.md#read) |
| tree | List child pages of a page | Returns immediate children only (`limit=100`) | [operations.md#tree](references/operations.md#tree) |
| create | Create a published page (`status: current`) | `--space` derived from parent when omitted | [operations.md#create](references/operations.md#create) |
| draft | Create a draft page (`status: draft`) | Not visible until published; `--space` from parent | [operations.md#draft](references/operations.md#draft) |
| update | Replace/append page body | Published pages increment version; drafts always `version: 1` | [operations.md#update](references/operations.md#update) |
| publish | Convert a draft to current | Draft→current, version stays `1` | [operations.md#publish](references/operations.md#publish) |
| comment | Add a comment to a page | `POST /content` `type=comment` with `container` (NOT `/child/comment`) | [operations.md#comment](references/operations.md#comment) |

**Version rule:** published page update → fetch current version, increment by 1. Drafts always `version: 1` (no draft versioning). Applies to `update` and `publish`.

## Page Reference Resolution

Resolve any URL/title/ID to a numeric page ID before API calls. URLs and raw IDs resolve directly; **title** lookup needs `--space`. Helpers (`resolve_page_ref` / `extract_space_from_url` / `get_space_from_page`) in `references/page-ref-resolution.md`.

## Output Handling

- Pipe responses through `jq`
- Success: show page ID, title, URL: `https://ubiquiti.atlassian.net/wiki/spaces/{SPACE}/pages/{ID}`
- Error: show full error message
- Never print credentials

## Error Handling

| Code | Cause | Fix |
|------|-------|-----|
| 401 | Credentials wrong or expired | Remind user to refresh `~/.config/ubiquiti/jira-credentials` |
| 404 | Page not found | Verify page ID or URL; for drafts, add `?status=draft` to the request |
| 409 | Version conflict on update | Re-fetch current version number and retry with incremented version |

## Important Notes

- Credentials: `~/.config/ubiquiti/jira-credentials` (shared with Jira skill)
- **Storage Format** (XHTML), NOT ADF — see `references/storage-format.md`
- Page URLs: `https://ubiquiti.atlassian.net/wiki/spaces/{SPACE}/pages/{ID}`
- Drafts: add `?status=draft` to fetch
- `--space` required only for title lookups
