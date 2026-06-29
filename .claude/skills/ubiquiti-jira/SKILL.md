# Skill: ubiquiti-jira

# ubiquiti-jira

UOF project Jira workflow automation — post-PR-merge transitions, PR title
naming, fixVersion, and QA comment. Encodes the UOF state machine, not
general Jira API (that's the `jira` skill). Use when user says "post-merge",
"update jira after merge", "transition UOF ticket", "set fixVersion",
"rename PR title [UOF-...]", or any post-merge Jira housekeeping for
Ubiquiti firmware tickets.

## Usage

```bash
/uof-jira post-merge UOF-4965 --pr 10288
/uof-jira post-merge UOF-4965              # auto-detect PR from branch
/uof-jira title UOF-4965 10288 "sysid: reserve UID 970 for unifi-drive-admin"
```

## Step 0: Load Credentials

Always source Jira credentials first (same as `jira` skill):

```bash
source ~/.config/ubiquiti/jira-credentials
# $JIRA_EMAIL and $JIRA_TOKEN available
```

## Operations

### 1. Post-Merge Workflow (`post-merge`)

After a PR merges, transition the ticket through the UOF state machine and
update metadata. The full sequence:

```
1. Get current status        → GET /issue/<KEY>?fields=status,fixVersions
2. Transition to target      → walk the state machine (see reference)
3. Set fixVersion             → from debbox conf/arch/version on merge branch
4. Add verification comment  → PR link + test results summary
```

**Transition logic** — walk from current status to `Ready to QA`:

| Current Status | Transitions needed | IDs |
|---|---|---|
| Backlog | Backlog → 待辦事項 (91) → RD In Progress (31) → Ready to QA (111) | 3 steps |
| 待辦事項 | → RD In Progress (31) → Ready to QA (111) | 2 steps |
| RD In Progress | → Ready to QA (111) | 1 step |
| Ready to QA | already there | 0 steps |
| Block | → Ready to QA (211, direct) | 1 step |
| Need more info | → RD In Progress (3, global) → Ready to QA (111) | 2 steps |

**IMPORTANT**: transition IDs may change. Always **discover at runtime** via
`GET /issue/<KEY>/transitions` — the table above is a reference, not hardcoded
constants. Match by transition **name**, not ID.

**fixVersion** — resolve from the merge target branch:

```bash
# On debbox: read conf/arch/version from the merge branch
VERSION=$(git show origin/master:conf/arch/version 2>/dev/null \
  | grep PRODUCT_VERSION | cut -d= -f2)
# master → "6.0.0", stable/5.1 → "5.1.21", etc.
```

For non-debbox repos, prompt the user for the fixVersion or skip.

**Verification comment** — ADF format (use `jira` skill's `md2adf.py`):

```
PR merged: ubiquiti/debbox#<NUMBER> (<PR URL>)
Verified on <device>: <summary of test results>
```

### 2. PR Title Naming (`title`)

Rename a PR to match the Ubiquiti convention. Uses `gh api PATCH`
(**never** `gh pr edit --title` — it silently capitalizes the first letter).

**Format**: `[PROJECT-XXXX] scope: description`

The PROJECT prefix comes from the Jira ticket key (UOF, DEBFACT, DEBBOX, etc.),
not from the repo.

```bash
# Extract project prefix from ticket key
PROJECT=$(echo "UOF-4965" | cut -d- -f1)
# → [UOF-4965] sysid: reserve UID 970 for unifi-drive-admin

gh api "repos/{owner}/{repo}/pulls/{number}" -X PATCH \
  -f title="[${KEY}] ${SCOPE}: ${DESCRIPTION}"
```

**Scope** is the debbox subsystem or package name:
- `sysid`, `kernel`, `conf`, `target`, `package` for debbox
- `package: <pkg>` for debfactory
- freeform for other repos

### 3. Fix Version Only (`fixversion`)

Set fixVersion without transitioning. Use `add` (not `set`) to preserve
existing fixVersions (backport tickets have multiple):

```bash
curl -s -u "$JIRA_EMAIL:$JIRA_TOKEN" -X PUT \
  "https://ubiquiti.atlassian.net/rest/api/3/issue/<KEY>" \
  -H "Content-Type: application/json" \
  -d '{"update":{"fixVersions":[{"add":{"name":"<VERSION>"}}]}}'
```

## Error Handling

| Code | Cause | Fix |
|------|-------|-----|
| 401 | Credentials expired | Re-source `~/.config/ubiquiti/jira-credentials` |
| 404 | Ticket not found | Verify ticket key |
| 400 | Transition not available from current status | Check current status, walk the state machine |
| 400 | fixVersion not found | Check `GET /project/UOF/versions` for valid version names |

## Important Notes

- **Never use `gh pr edit --title`** — it silently capitalizes; always use `gh api PATCH`
- **Transition IDs are runtime-discovered** — always GET /transitions first, match by name
- **fixVersion = debbox PRODUCT_VERSION** — read from `conf/arch/version` on the merge branch
- **ADF required** for comments — use `md2adf.py` from the `jira` skill for long content
- This skill is for **UOF project workflow** — for general Jira API operations, use the `jira` skill

## See Also

- `jira` — general Jira REST API operations (CRUD, search, ADF format)
- `stacking-dev` — Phase 4 pre-merge Jira (PR title prefix, description backfill)
- `ubiquiti-debbox-fw-build` — firmware version and build system
