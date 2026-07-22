# Inline Comment Posting Rules

Three mandatory pre-flight gates before posting any inline comment to a GitHub PR.
All three gates must pass. Fail any gate → skip the comment (do not post).

---

## Gate 1: Line Must Fall Inside a Diff Hunk

Before posting, verify the target line is inside the PR diff.

```bash
# Fetch PR file diff
gh api repos/{owner}/{repo}/pulls/{pr_number}/files \
  --jq '.[] | select(.filename == "PATH/TO/FILE") | .patch'
```

Parse the `@@ -old_start,old_count +new_start,new_count @@` headers to compute
which line numbers are in the diff. The comment's `line` parameter must fall
within a hunk. If the line is not in any hunk, **drop the comment**.

**Why:** GitHub's API rejects comments on lines outside the diff with a 422 error,
and `gh` CLI surfaces this as an unhelpful "unprocessable entity" with no context.

---

## Gate 2: Line Must Be an Added (+) Line

The target line must be a `+` line (newly added), never a context line (` `)
or a deletion (`-`).

Inspect the patch:
- Lines starting with `+` (excluding `+++` header) → **allowed**
- Lines starting with ` ` (context) → **drop**
- Lines starting with `-` → **drop**

**Why:** Commenting on a deleted line or context line is confusing to the author
(the line may not exist in the new file at all) and often fails or lands on the
wrong line in the GitHub UI.

---

## Gate 3: Use the Correct Endpoint and Parameters

Always use `pulls/{n}/comments` (review comments), never `issues/{n}/comments`
(general PR comments). The latter doesn't support line anchoring.

### Required fields

```json
{
  "body": "...",
  "commit_id": "<LATEST_SHA>",
  "path": "path/to/file.ext",
  "line": <1-based line number in new file>,
  "side": "RIGHT"
}
```

Fetch the latest commit SHA:
```bash
gh api repos/{owner}/{repo}/pulls/{pr_number} --jq '.head.sha'
```

### MCP-first guidance

If `mcp__github_inline_comment__create_inline_comment` is available in the
session, **always prefer MCP** over direct `gh api` calls — it handles
`commit_id` and `side` automatically and validates hunks before posting.

Check availability:
```
mcp__github_inline_comment__create_inline_comment(
  owner=..., repo=..., pull_number=...,
  path=..., line=..., body=...
)
```

Only fall back to `gh api repos/{owner}/{repo}/pulls/{pr_number}/comments`
if MCP is unavailable.

### Never use

- `issues/{n}/comments` — does not support line anchoring
- Omitting `commit_id` — causes "commit not part of PR" errors
- `side: "LEFT"` for new code — LEFT refers to the base (deleted lines)

---

## Summary Checklist

Before every inline comment POST:

- [ ] Line falls inside a `@@` hunk from `pulls/{n}/files`
- [ ] Patch line starts with `+` (not ` ` or `-`)
- [ ] Using `pulls/{n}/comments` with `commit_id` = latest SHA and `side="RIGHT"`
- [ ] Prefer MCP tool when available

---

## Comment Body Templates

Keep comment bodies brief, cite/link relevant code, and use a severity emoji.

### Line-specific review comment

```markdown
🔴/🟠/🟡/🟢 [Critical/High/Medium/Low]: [Brief description]

[Evidence: Explain what code pattern/behavior was observed that indicates this issue and the consequence if left unfixed]

[If applicable, provide code suggestion]:
```suggestion
[code here]
```
```

### Example: Bug Issue

```markdown
🟠 High: Potential null pointer dereference

Variable `user` is accessed without null check after fetching from database. This will cause runtime error if user is not found, breaking the user profile feature.

```suggestion
if (!user) {
  throw new Error('User not found');
}
```
```

### Example: Security Issue

```markdown
🔴 Critical: SQL Injection vulnerability

User input is directly concatenated into SQL query without sanitization. Attackers can execute arbitrary SQL commands, leading to data breach or deletion.

Use parameterized queries instead:
```suggestion
db.query('SELECT * FROM users WHERE id = ?', [userId])
```
```
