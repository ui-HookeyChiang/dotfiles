---
name: host-work-journal
landing-group: workflow
argument-hint: "[--start-date YYYY-MM-DD] [--end-date YYYY-MM-DD] [--detailed] [--skip-covered]"
description: Collect host activity (git, shell, Claude, OpenCode, test artifacts) into structured JSON. Use when the user asks for a work report, activity summary, journal entry, weekly report, or wants to review what was done over a date range. Portable — outputs JSON to ~/; downstream pipeline is repo-specific.
disable-model-invocation: true
---

# Host Work Journal

Collect work activity from the current host into structured JSON. This is the **portable collector** — it gathers data and writes a JSON file. Downstream composition (Markdown reports, SAR cards, milestone integration) is handled by repo-specific skills.

## Quick Start

```bash
SKILL_DIR=~/.claude/skills/host-work-journal

# Default: last 7 days
python3 $SKILL_DIR/scripts/collect-weekly-report.py -v

# Custom date range
python3 $SKILL_DIR/scripts/collect-weekly-report.py \
  --start-date 2026-02-01 --end-date 2026-02-28 -v

# With detailed Claude session analysis
python3 $SKILL_DIR/scripts/collect-weekly-report.py \
  --start-date 2026-02-01 --end-date 2026-02-28 --detailed -v

# Skip dates already covered by existing reports (needs --journal-root)
python3 $SKILL_DIR/scripts/collect-weekly-report.py \
  --journal-root ~/my-project/journal --skip-covered -v
```

Output: `~/work-report-data_<host>_<start>-to-<end>.json`

## Arguments

| Flag | Default | Purpose |
|------|---------|---------|
| `--start-date` | 7 days ago | Start of collection range (YYYY-MM-DD or ISO 8601) |
| `--end-date` | today | End of collection range |
| `--output` | `~/work-report-data_<host>_<start>-to-<end>.json` | Custom output path |
| `--author` | auto-detect from git config | Git author name(s), repeatable |
| `--no-fetch` | false | Skip `git fetch` (offline mode) |
| `--detailed` | false | Parse per-session .jsonl for tool/token/file details |
| `--skip-covered` | false | Deduplicate against existing reports in journal dirs |
| `--journal-root` | `~/Awesome-CV/journal` | Root dir containing `raw/` and `integrated/` for dedup |
| `--dry-run` | false | Print summary without writing output |
| `-v` / `--verbose` | false | Verbose logging |

## Data Sources

The collector gathers from all sources in parallel:

| Source | What |
|--------|------|
| Git repos | Commits, PRs, line stats (all repos under ~) + SAR-categorized commits (target repos) |
| Shell history | Command frequency, SSH targets, SCP transfers |
| Claude Code | Sessions, prompts by project/topic, token usage |
| OpenCode | Sessions, prompts by project/topic, cost, tool usage |
| Test artifacts | fio sessions, device configs, result counts |
| Infrastructure | Managed devices from SSH config |

## Output JSON Structure

```json
{
  "metadata": { "hostname": "...", "start_date": "...", "end_date": "..." },
  "git": { "<repo>": { "commits": [...], "stats": {...} } },
  "git_sar": { "<category>": [...] },
  "shell": { "commands": {...}, "ssh_targets": [...] },
  "claude": { "sessions": [...] },
  "opencode": { "sessions": [...] },
  "tests": { "fio": [...] },
  "infra": { "devices": [...] },
  "initiatives": { "cross_repo": [...], "sha_dedup_stats": {...} }
}
```

The `initiatives` key contains cross-repo commit groups detected by Jaccard subject similarity, plus SHA dedup stats. The `git_sar` key contains commits from target repos, categorized by topic keywords. This feeds downstream SAR extraction workflows.

## Deduplication (--skip-covered)

When `--skip-covered` is passed, the script scans `<journal-root>/raw/` and `<journal-root>/integrated/` for `work-report_<host>_*` files, computes uncovered date gaps, and collects only for those gaps. Reports that were collected, processed, and moved to `integrated/` are still recognized as covered.

Requires `--journal-root` to point to the correct journal directory for the target project.

## Report Generation Prompt

After collecting JSON, use this prompt template to generate a knowledge-density weekly report:

### Phase 1: Initiative Discovery

1. Read `initiatives.cross_repo` from the JSON first — pre-grouped and authoritative.
2. If absent, fall back to scanning all commits across repos and grouping by subject similarity (Jaccard on tokenized subjects; threshold ~0.5).
3. Deduplicate commits sharing identical SHAs across repos (worktree branches).
4. Group related commits/PRs into **topic-initiatives** (e.g. "Linux Kernel: btrfs ENVR Backport", "Org-wide CI Modernization"). One initiative may span multiple repos. Standalone items that don't cluster remain as single entries.

### Phase 2: Knowledge Density Scoring

Score every topic-initiative (KD = highest item in group):

| KD | Meaning |
|----|---------|
| 1 | Mechanical: version bump, config tweak, alias change |
| 2 | Applied a known pattern to a new context |
| 3 | Non-trivial investigation or debugging |
| 4 | Produced a reusable artifact: skill, tool, framework, ADR, org-wide template |
| 5 | Novel insight that changed approach or architecture |

Justify KD 4-5 with one concrete reason from commit/session data.

### Phase 3: Report

Sort by topic-initiative, KD descending within. Each initiative gets a header with `[KD{n}]` tag. List constituent items as bullets under the header. Traditional Chinese prose, English technical terms.

```
### {Topic}: {Initiative Name} [KD{n}]
- item 1
- item 2
```

### Phase 4: Ticket Appendix

Extract Jira ticket references from PR titles (regex `[A-Z]+-\d+` on `[UOF-1234]` prefix pattern). No Jira API needed — PR titles from GitHub are sufficient.

| Ticket | Summary | fixVersion | PRs |
|--------|---------|------------|-----|

fixVersion: infer from debbox `conf/arch/version` PRODUCT_VERSION if PRs merged to debbox/debbox-kernel. Otherwise "pending".

### Appendix

- **Average KD** (mean, one decimal, by initiative count)
- **Histogram**: count per KD level (1-5)
- **SAR candidates**: KD ≥ 4
- **Week-over-week trend**: if prior week data available, compare average KD, item count, SAR count

## Integration with Downstream Pipelines

This skill only produces the JSON. To compose Markdown reports and integrate into a career documentation pipeline, use the repo-specific skill (e.g., `Awesome-CV/.claude/skills/host-work-journal` which adds Phase 2 composition, frontmatter templates, and SAR card generation).
