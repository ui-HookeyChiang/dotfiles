# GitHub Mode — Post Inline Comments

This document is the GitHub-mode procedure for code-review. It runs only when
MCP `mcp__github_inline_comment__create_inline_comment` or `gh api` is available.

---

## GitHub mode (post inline comments)

> **Gate A** (bot dedup) and **Gate C** (concurrency) are **workflow-owned** —
> handled by the CI workflow step / concurrency group, not the agent.
> See `setup-github-code-review/template.yml`.

### Phase 3.5 Layer A: Pre-Flight Line Validation

For each candidate comment, verify using [`inline-comment-rules.md`](inline-comment-rules.md):

1. **Gate 1 — Hunk check**: Fetch `gh api repos/{owner}/{repo}/pulls/{pr_number}/files` and parse `@@` hunk headers. The comment's target line must fall inside a hunk. If not → **drop**.
2. **Gate 2 — Added-line check**: The target line in the patch must start with `+` (not ` ` context or `-` deleted). If not → **drop**.
3. **Gate 3 — Endpoint check**: Confirm you will use `pulls/{n}/comments` with `commit_id=<latest_sha>` and `side="RIGHT"`. Prefer MCP tool `mcp__github_inline_comment__create_inline_comment` when available. Never use `issues/{n}/comments`.

### Q5: Dedup against posted comments

See [`senior-engineer-filter.md`](senior-engineer-filter.md) for the full dedup formula, PASS 1/PASS 2 logic, and API calls.

### Noise Budget Enforcement

Cap total comments per `senior-engineer-filter.md` noise budget table. Sort survivors by Impact Score descending; post top-N only.

### Post Inline Comments

Only when filters produced survivors. **Zero findings → skip posting, but Phase 4 still runs.**

a. **Preferred**: `mcp__github_inline_comment__create_inline_comment` per issue.

b. **Fallback** (direct API):
   - Check if `git:attach-review-to-pr` command exists.
   - **Multiple issues**: `gh api repos/{owner}/{repo}/pulls/{pr_number}/reviews` with line comments.
   - **Single issue**: `gh api repos/{owner}/{repo}/pulls/{pr_number}/comments`.

Comments: brief, use emojis, link/cite relevant code and URLs.

### Phase 4: Post-review state cleanup (dual-layer)

**MANDATORY — runs after every review pass, regardless of finding count.**

Two-layer guarantee:
1. **Agent (best-effort):** After posting (or deciding zero findings), resolve
   outdated bot-owned threads via GraphQL `resolveReviewThread`. This is
   best-effort — the agent may skip it if it doesn't read this file.
2. **Workflow step (safety net):** A dedicated workflow step runs the same
   resolve logic AFTER Claude completes. Idempotent — resolving an
   already-resolved thread is a no-op.

**Auto-resolve filter** — all four conditions must be true:
1. `isOutdated == true`
2. `isResolved == false`
3. First comment author is the bot (GraphQL `author.login` without `[bot]` suffix)
4. No human commented in the thread

**Agent resolve commands:**

```bash
# Step 1 — Fetch review threads
gh api graphql -f query='
query($owner: String!, $repo: String!, $pr: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $pr) {
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          isOutdated
          comments(first: 100) {
            nodes { author { login } }
          }
        }
      }
    }
  }
}' -F owner=<OWNER> -F repo=<REPO> -F pr=<PR_NUMBER>

# Step 2 — Resolve filtered threads
# For each thread passing all 4 conditions:
for thread_id in <THREAD_IDS>; do
  gh api graphql -f query="mutation { resolveReviewThread(input: {threadId: \"$thread_id\"}) { thread { isResolved } } }"
done

# Step 3 — Emit contract log line
echo "Layer C: resolved $RESOLVED threads"
```

<!-- NOTE: bot login values (e.g. "uos-fw-pr-assistant", "claude") are
     org-specific. Adapt for your deployment. GraphQL author.login does NOT
     include the [bot] suffix; REST user.login DOES — don't mix them. -->

**Stale review dismissal:** Dismiss bot's own `CHANGES_REQUESTED` reviews when
all associated threads are resolved or outdated. (Workflow step handles this.)

> **Back-compat contract:** Emit "Layer C: resolved N threads" — caller
> workflows grep this exact string. Do NOT rename.

---

#### Examples of false positives

See [`senior-engineer-filter.md`](senior-engineer-filter.md) auto-drop list.

## Comment Templates

Templates in [`inline-comment-rules.md`](inline-comment-rules.md). Keep brief, cite code, use severity emoji (🔴/🟠/🟡/🟢).
