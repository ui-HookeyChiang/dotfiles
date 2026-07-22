# Phase-4 ticket auto-fill (`jira-cli.py fill`)

This is a narrow automation tool, **not** a general Jira CLI — for ad-hoc
comment/get/create/search/transition use the curl recipes in `operations.md`.

## What `fill` does

`scripts/jira-cli.py fill <KEY>` auto-fills an **empty** Jira ticket description
from the merged PR's body + commits, shaped against the
`_shared/references/qa-verify-template.md` schema (Prerequisites, Step 0
test-bundle staging, step-by-step verification, failure handling, cleanup). It
converts the assembled markdown to ADF (via `md2adf.py`) and PUTs it to the
ticket. External seams (`subprocess_run`, `http_get`, `http_put`, `call_llm`)
keep the flow mockable in unit tests.

Implements spec `docs/spec/archive/2026-05-12-jira-fill-from-pr.md`.

Invoke via the slash form:

```bash
/jira fill UOF-1234
```

Useful flags (from the `fill` subparser):
- `--auto` — programmatic mode, skip the preview prompt (requires `--yes`)
- `--yes` — non-interactive approval (required with `--auto`)
- `--edit` — open `$EDITOR` on the draft before POST
- `--regenerate` — regenerate the draft

## flow-dev Phase-4 integration

flow-dev's Phase 4 calls this tool **by absolute path**, so the script must
stay at `~/.claude/skills/jira/scripts/jira-cli.py`:

- `flow-dev/scripts/jira-fill.sh` — thin wrapper that `exec`s
  `python3 .../jira-cli.py fill "$KEY" "$@"`.

## `link` subcommand — stub

`jira-cli.py link <KEY>` is **out of scope** and raises `NotImplementedError`.
Phase-4 invokes it defensively (errors suppressed); do not rely on it.
