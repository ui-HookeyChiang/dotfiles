---
name: setup-github-code-review
description: Deploy or re-sync the Claude PR review workflow on a Ubiquiti repo.
argument-hint: "<repo-name>"
landing-group: workflow
disable-model-invocation: true
---

# Setup Claude PR Review Workflow

NOT for reviewing a PR (use `code-review`). NOT for editing the template logic
itself (edit `template.yml` directly, then use this skill to propagate).

Three branches:
- **Onboard** — new repo, no workflow yet → Steps 1–10.
- **Re-sync** — workflow exists, propagate template updates → Steps 1, 2, 5.
- **Bump** — prompt-hub skill SHA changed, push to all repos → Bump section only.

## Steps

### 1. Resolve repo

```bash
REPO="${ARGUMENTS:-}"
```

If empty, ask. Verify exists:
```bash
gh api "repos/ubiquiti/$REPO" --jq '{default_branch, language, private}'
```

Done when: API returns valid JSON with `default_branch`.

### 2. Detect mode

```bash
gh api "repos/ubiquiti/$REPO/contents/.github/workflows/claude-pr-review.yml" --jq '.sha' 2>/dev/null
```

- **Exists** → re-sync. Jump to Step 5 (`render.py --push` with existing branch name from the workflow file).
- **Missing** → onboard. Continue to Step 3.

### 3. Gather config

Determine:
- `default_branch` — from Step 1
- `directive_path` — `.github/claude/<repo-name>-directive.md`
- `domain_desc` — infer from language + README top 20 lines. If uncertain, ask user.
- `paths_ignore_extra` — `gh api repos/ubiquiti/$REPO/contents --jq '.[].name'`; add `doc/**` / `docs/**` if those dirs exist.

Done when: all 4 values resolved (no placeholders).

### 4. Add to repos.yaml

Append to `setup-github-code-review/repos.yaml`. Validate:
```bash
python3 -c "import yaml; yaml.safe_load(open('setup-github-code-review/repos.yaml'))"
```

Done when: YAML validates.

### 5. Render and push

```bash
python3 setup-github-code-review/render.py --push --branch chore/add-claude-pr-review $REPO
```

Done when: script prints `PUSHED`.

### 6. Create directive

Push `.github/claude/<repo-name>-directive.md` to the same branch on the target repo. Content: 3-5 bullet domain focus inferred from repo language/structure.

Done when: file exists on the target branch at `.github/claude/<repo-name>-directive.md`.

### 7. Create PR

```bash
gh pr create --repo "ubiquiti/$REPO" \
  --base <default_branch> \
  --head chore/add-claude-pr-review \
  --title "chore(ci): add Claude PR review workflow"
```

Done when: PR URL returned.

### 8. Provision secrets

Check and provision required secrets for the target repo.

#### 8a. GitHub App — `uos-fw-pr-assistant`

The workflow authenticates as the `uos-fw-pr-assistant` internal GitHub App.
Two org-level items must be accessible to the target repo:

| Type | Name |
|------|------|
| Org variable | `UOS_FW_PR_ASSISTANT_APP_ID` |
| Org secret | `UOS_FW_PR_ASSISTANT_APP_PRIVATE_KEY` |

```bash
gh api repos/ubiquiti/$REPO/actions/organization-variables --jq '.variables[].name' | grep -q UOS_FW_PR_ASSISTANT_APP_ID
gh api repos/ubiquiti/$REPO/actions/organization-secrets --jq '.secrets[].name' | grep -q UOS_FW_PR_ASSISTANT_APP_PRIVATE_KEY
```

If both present → skip to 8b.

If missing → the App is not installed on this repo. Print the following IT
request for the user to copy:

```
Subject: Install uos-fw-pr-assistant GitHub App on ubiquiti/$REPO

Please install the internal GitHub App "uos-fw-pr-assistant" on the
repository ubiquiti/$REPO.

This grants the repo access to the org-level variable
UOS_FW_PR_ASSISTANT_APP_ID and secret UOS_FW_PR_ASSISTANT_APP_PRIVATE_KEY,
which are required by the Claude PR review workflow.

Path: github.com/organizations/ubiquiti/settings/installations
      → uos-fw-pr-assistant → Repository access → add ubiquiti/$REPO
```

**Wait for IT confirmation before continuing** — Steps 7 and 9 will fail
without the App token. 8b and 8c can proceed in parallel.

Done when: both grep commands exit 0.

#### 8b. ANTHROPIC_API_KEY

```bash
if ! gh api repos/ubiquiti/$REPO/actions/secrets --jq '.secrets[].name' | grep -q ANTHROPIC_API_KEY; then
  echo "MISSING: ANTHROPIC_API_KEY — ask user to provide, then:"
  echo "  gh secret set ANTHROPIC_API_KEY --repo ubiquiti/$REPO"
fi
```

Done when: `ANTHROPIC_API_KEY` appears in repo secrets.

#### 8c. PROMPT_HUB_DEPLOY_KEY

Each consumer repo gets its own ed25519 deploy key pair — public half on
prompt-hub, private half as the repo's `PROMPT_HUB_DEPLOY_KEY` secret.

```bash
if gh api repos/ubiquiti/$REPO/actions/secrets --jq '.secrets[].name' | grep -q PROMPT_HUB_DEPLOY_KEY; then
  echo "PROMPT_HUB_DEPLOY_KEY already exists — skipping."
else
  KEYFILE=$(mktemp -u /tmp/deploy-key-XXXXXX)
  ssh-keygen -t ed25519 -f "$KEYFILE" -N "" -C "claude-pr-review-$REPO"

  gh api repos/ubiquiti/prompt-hub/keys \
    -f title="claude-pr-review-$REPO" \
    -f key="$(cat ${KEYFILE}.pub)" \
    -F read_only=true

  gh secret set PROMPT_HUB_DEPLOY_KEY --repo "ubiquiti/$REPO" < "$KEYFILE"

  rm -f "$KEYFILE" "${KEYFILE}.pub"
fi
```

Done when: `PROMPT_HUB_DEPLOY_KEY` appears in repo secrets.

### 9. Verify trigger

```bash
sleep 15 && gh pr checks <PR> --repo "ubiquiti/$REPO"
```

Done when: `review` job appears in the checks output.

### 10. Commit repos.yaml to prompt-hub

Stage and commit the `repos.yaml` update on the current prompt-hub branch.

Done when: committed and pushed.

## Bump prompt-hub skill SHA

When code-review skill changes land on prompt-hub main:

```bash
python3 setup-github-code-review/render.py --push --branch chore/bump-prompt-hub-skill-sha
```

This auto-resolves `origin/main` HEAD as the prompt-hub ref, renders all
workflows, and pushes to all repos in `repos.yaml`. To pin a specific SHA:

```bash
python3 setup-github-code-review/render.py --push --ref <SHA>
```

Done when: all repos print `PUSHED`.
