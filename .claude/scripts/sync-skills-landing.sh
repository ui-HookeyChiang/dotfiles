#!/usr/bin/env bash
# sync-skills-landing.sh — single generator for README.md and wiki Home.md.
#
# Walks every `<skill>/SKILL.md` at the repo root, parses name/description/
# landing-group from YAML frontmatter, and renders the skills-landing template
# into README.md and wiki-Home.md.generated.
#
# Usage:
#   scripts/sync-skills-landing.sh              # regen both outputs
#   scripts/sync-skills-landing.sh --check      # exit 1 if regen would change
#   scripts/sync-skills-landing.sh --readme-only
#   scripts/sync-skills-landing.sh --wiki-only
#
# No external deps beyond awk/sed/grep.

set -euo pipefail

# -----------------------------------------------------------------------------
# Locate repo root
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE="$SCRIPT_DIR/templates/skills-landing.md.tmpl"
README="$REPO_ROOT/README.md"
WIKI_OUT="$REPO_ROOT/wiki-Home.md.generated"
MARKER="<!-- END AUTO-GENERATED LANDING -->"

VALID_GROUPS="test build deploy debug workflow release atlassian"

# Directories to exclude from skill discovery
EXCLUDE_DIRS=".worktrees node_modules pua docs releases scripts spec codeeee _shared _evals debian .git .github ajatt-khatzumoto-perspective kaufmann-perspective krashen-perspective language-learning-council"

# -----------------------------------------------------------------------------
# Usage
# -----------------------------------------------------------------------------
usage() {
  cat <<'USAGE'
Usage: sync-skills-landing.sh [--check|--readme-only|--wiki-only|--help]

Generates README.md and wiki-Home.md.generated from */SKILL.md frontmatter.
Requires each SKILL.md to have a `landing-group:` field (one of:
test, build, deploy, debug, workflow, release, atlassian).

Modes:
  (no args)        Regenerate both README.md and wiki-Home.md.generated
  --check          Exit non-zero if regeneration would change any file (CI use)
  --readme-only    Only regenerate README.md
  --wiki-only      Only regenerate wiki-Home.md.generated
  --help, -h       Print this usage and exit
USAGE
}

# -----------------------------------------------------------------------------
# Parse args
# -----------------------------------------------------------------------------
MODE="both"
CHECK_MODE=0
for arg in "$@"; do
  case "$arg" in
    --readme-only) MODE="readme" ;;
    --wiki-only)   MODE="wiki" ;;
    --check)       CHECK_MODE=1 ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown arg: $arg" >&2
      usage >&2
      exit 2
      ;;
  esac
done

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

# Is directory in EXCLUDE_DIRS list?
is_excluded() {
  local dir="$1"
  for ex in $EXCLUDE_DIRS; do
    [ "$dir" = "$ex" ] && return 0
  done
  return 1
}

# Find all skill directories (i.e. dirs at REPO_ROOT with a SKILL.md inside).
find_skill_dirs() {
  cd "$REPO_ROOT"
  for d in */; do
    d="${d%/}"
    is_excluded "$d" && continue
    [ -f "$d/SKILL.md" ] || continue
    echo "$d"
  done | sort
}

# Read a frontmatter field value for a given SKILL.md.
# Handles plain (`key: value`), quoted (`key: "value"`), and folded
# (`key: >-` followed by indented lines) styles.
# Prints a single-line value on stdout. Returns 1 if the field is missing.
read_frontmatter_field() {
  local file="$1"
  local field="$2"
  awk -v field="$field" '
    BEGIN { in_fm = 0; fm_count = 0; in_field = 0; buf = "" }
    /^---[[:space:]]*$/ {
      fm_count++
      if (fm_count == 1) { in_fm = 1; next }
      if (fm_count == 2) { in_fm = 0; exit }
    }
    !in_fm { next }
    {
      if (in_field) {
        # Continuation of folded or literal block
        if ($0 ~ /^[[:space:]]/) {
          # Strip leading whitespace
          line = $0
          sub(/^[[:space:]]+/, "", line)
          if (buf == "") buf = line
          else           buf = buf " " line
          next
        } else {
          in_field = 0
          # fall through — current line might start a new field, continue
        }
      }
      # Check for target field
      # Match "field: ..." with optional whitespace
      pat = "^" field "[[:space:]]*:"
      if ($0 ~ pat) {
        rest = $0
        sub(pat, "", rest)
        sub(/^[[:space:]]+/, "", rest)
        # Folded scalar (>- / >) or literal scalar (|- / |) — both join
        # continuation lines the same way for our purposes (single-line output).
        if (rest == ">-" || rest == ">" || rest == "|-" || rest == "|") {
          in_field = 1
          buf = ""
          next
        }
        # Inline value: strip surrounding quotes if present
        if (rest ~ /^".*"[[:space:]]*$/) {
          sub(/^"/, "", rest); sub(/"[[:space:]]*$/, "", rest)
        } else if (rest ~ /^'\''.*'\''[[:space:]]*$/) {
          sub(/^'\''/, "", rest); sub(/'\''[[:space:]]*$/, "", rest)
        }
        buf = rest
        # Print immediately
        print buf
        found = 1
        exit
      }
    }
    END {
      if (!found && buf != "") print buf
      else if (!found) exit 1
    }
  ' "$file"
}

# Take full description text; return just the first sentence / useful snippet.
# Cuts at first of: ". Use when ", ". Triggers on ", ". Covers", ". TRIGGER", ".\s"
# Keeps the result under ~180 chars.
summarize_description() {
  local desc="$1"
  # Decode a few common YAML double-quoted \u escapes (→, —, …) so they render as real chars
  desc=$(printf '%s' "$desc" | sed \
    -e 's/\\u2192/→/g' \
    -e 's/\\u2014/—/g' \
    -e 's/\\u2013/–/g' \
    -e 's/\\u2026/…/g' \
    -e 's/\\u201c/"/g' \
    -e 's/\\u201d/"/g' \
    -e 's/\\u2018/'\''/g' \
    -e 's/\\u2019/'\''/g')
  # Cut at markers that introduce "use when / triggers / keywords" dumps
  desc=$(printf '%s' "$desc" | awk '{
    # Try multiple split points, pick the earliest non-zero position
    best = length($0) + 1
    for (i = 0; i < 10; i++) {
      if (i == 0) m = ". Use when "
      else if (i == 1) m = ". Use this skill"
      else if (i == 2) m = ". Use whenever"
      else if (i == 3) m = ". Triggers"
      else if (i == 4) m = ". TRIGGER"
      else if (i == 5) m = ". Covers"
      else if (i == 6) m = ". Keywords"
      else if (i == 7) m = ". When to use"
      else if (i == 8) m = ". Runs "
      else m = ". Also use"
      p = index($0, m)
      if (p > 0 && p < best) best = p
    }
    if (best <= length($0)) $0 = substr($0, 1, best - 1) "."
    # If still long, cut at first period + space
    if (length($0) > 200) {
      p = index($0, ". ")
      if (p > 0) $0 = substr($0, 1, p)
    }
    print
  }')
  # Hard cap
  if [ "${#desc}" -gt 220 ]; then
    desc="${desc:0:217}..."
  fi
  printf '%s' "$desc"
}

# -----------------------------------------------------------------------------
# Collect skills
# -----------------------------------------------------------------------------

# Build per-group table rows into temp files
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

for g in $VALID_GROUPS; do
  : > "$WORK/group-$g"
done

SKILL_COUNT=0
MISSING=""
INVALID=""

while IFS= read -r dir; do
  file="$REPO_ROOT/$dir/SKILL.md"
  [ -f "$file" ] || continue

  name=$(read_frontmatter_field "$file" "name" 2>/dev/null || true)
  [ -z "$name" ] && name="$dir"

  group=$(read_frontmatter_field "$file" "landing-group" 2>/dev/null || true)
  if [ -z "$group" ]; then
    MISSING="$MISSING $name"
    continue
  fi

  # Validate group
  valid=0
  for vg in $VALID_GROUPS; do
    [ "$group" = "$vg" ] && valid=1 && break
  done
  if [ "$valid" = "0" ]; then
    INVALID="$INVALID $name=$group"
    continue
  fi

  desc=$(read_frontmatter_field "$file" "description" 2>/dev/null || true)
  short=$(summarize_description "$desc")
  [ -z "$short" ] && short="$name"

  # Escape pipe chars for markdown table
  short_escaped=$(printf '%s' "$short" | sed 's/|/\\|/g')

  SKILL_COUNT=$((SKILL_COUNT + 1))
  printf '| %s | [`%s`](%s) |\n' "$short_escaped" "$name" "$name" >> "$WORK/group-$group"
done < <(find_skill_dirs)

# Fail on missing / invalid
if [ -n "$MISSING" ]; then
  echo "error: skill(s) missing 'landing-group' in frontmatter:$MISSING" >&2
  echo "       valid groups: $VALID_GROUPS" >&2
  exit 3
fi
if [ -n "$INVALID" ]; then
  echo "error: skill(s) have unknown landing-group:$INVALID" >&2
  echo "       valid groups: $VALID_GROUPS" >&2
  exit 3
fi

# Sort each group's rows alphabetically by skill name for stable output
for g in $VALID_GROUPS; do
  if [ -s "$WORK/group-$g" ]; then
    sort "$WORK/group-$g" > "$WORK/group-$g.sorted"
    mv "$WORK/group-$g.sorted" "$WORK/group-$g"
  fi
done

# -----------------------------------------------------------------------------
# Build release index
# -----------------------------------------------------------------------------
# Reads from GitHub Release API (authoritative store). Dual-target:
#   readme  — per-patch bullets linking to GitHub Release page URLs
#   wiki    — major.minor bullets linking to Release-Note-X.Y wiki pages
# Graceful fallback to "_No releases published yet._" when gh is missing,
# unauthenticated, or returns no releases.
build_release_index() {
  local target="${1:-readme}"

  # Detect gh availability — graceful fallback
  if ! command -v gh >/dev/null 2>&1; then
    echo "_No releases published yet._"
    return
  fi

  # Fetch releases (JSON). If it fails (no auth, network, no releases), fall back.
  local releases_json
  releases_json=$(gh release list --limit 100 --json tagName,isLatest 2>/dev/null || echo "[]")
  if [ "$releases_json" = "[]" ] || [ -z "$releases_json" ]; then
    echo "_No releases published yet._"
    return
  fi

  # Extract tag names in order (gh returns newest-first already).
  # Each line: "<flag> <tagName>" where flag is "L" (latest) or "-".
  local tags
  tags=$(echo "$releases_json" | python3 -c '
import json, sys
data = json.load(sys.stdin)
for r in data:
    flag = "L" if r.get("isLatest") else "-"
    print(flag + " " + r["tagName"])
')

  if [ -z "$tags" ]; then
    echo "_No releases published yet._"
    return
  fi

  # Detect repo URL for README links (same pattern as github-wiki channel)
  local repo_url
  repo_url=$(gh repo view --json url -q .url 2>/dev/null || echo "")

  if [ "$target" = "wiki" ]; then
    # Group by major.minor, newest first; mark the overall latest's line.
    local latest_mm=""
    # first pass: find which major.minor has isLatest=L
    while IFS= read -r line; do
      flag="${line%% *}"
      tag="${line#* }"
      if [ "$flag" = "L" ]; then
        # strip leading v, then major.minor
        ver="${tag#v}"
        latest_mm=$(echo "$ver" | awk -F. '{printf "%s.%s", $1, $2}')
        break
      fi
    done <<< "$tags"

    # dedupe by major.minor, newest-first order preserved
    while IFS= read -r line; do
      tag="${line#* }"
      ver="${tag#v}"
      echo "$ver" | awk -F. '{printf "%s.%s\n", $1, $2}'
    done <<< "$tags" | awk '!seen[$0]++' | while IFS= read -r mm; do
      if [ "$mm" = "$latest_mm" ]; then
        printf -- "- [%s](Release-Note-%s) — latest\n" "$mm" "$mm"
      else
        printf -- "- [%s](Release-Note-%s)\n" "$mm" "$mm"
      fi
    done
  else
    # readme: per-patch links to the GitHub Release page
    while IFS= read -r line; do
      flag="${line%% *}"
      tag="${line#* }"
      if [ -n "$repo_url" ]; then
        url="$repo_url/releases/tag/$tag"
      else
        url="releases/tag/$tag"  # relative fallback
      fi
      if [ "$flag" = "L" ]; then
        printf -- "- [%s](%s) — latest\n" "$tag" "$url"
      else
        printf -- "- [%s](%s)\n" "$tag" "$url"
      fi
    done <<< "$tags"
  fi
}

# -----------------------------------------------------------------------------
# Render template
# -----------------------------------------------------------------------------
# Args: $1 = output path; $2 = release-index target (readme|wiki, default readme)
render_landing() {
  local out="$1"
  local release_target="${2:-readme}"

  # Build section tables per group
  for g in $VALID_GROUPS; do
    local section="| Task | Skill |"$'\n'"|------|-------|"
    if [ -s "$WORK/group-$g" ]; then
      section+=$'\n'
      section+="$(cat "$WORK/group-$g")"
    else
      section+=$'\n'"| _(no skills)_ | |"
    fi
    # Write section to file to substitute safely
    printf '%s\n' "$section" > "$WORK/section-$g.md"
  done

  # Release index (target-aware: readme = per-patch GH URLs, wiki = major.minor)
  build_release_index "$release_target" > "$WORK/release-index.md"

  # Use awk for safe placeholder substitution (file-level, no shell escaping hell)
  awk \
    -v skill_count="$SKILL_COUNT" \
    -v section_test_file="$WORK/section-test.md" \
    -v section_build_file="$WORK/section-build.md" \
    -v section_deploy_file="$WORK/section-deploy.md" \
    -v section_debug_file="$WORK/section-debug.md" \
    -v section_workflow_file="$WORK/section-workflow.md" \
    -v section_release_file="$WORK/section-release.md" \
    -v section_atlassian_file="$WORK/section-atlassian.md" \
    -v release_index_file="$WORK/release-index.md" '
    function slurp(path,   line, out) {
      out = ""
      while ((getline line < path) > 0) {
        if (out == "") out = line
        else           out = out "\n" line
      }
      close(path)
      return out
    }
    BEGIN {
      sections["{{SECTION:test}}"]      = slurp(section_test_file)
      sections["{{SECTION:build}}"]     = slurp(section_build_file)
      sections["{{SECTION:deploy}}"]    = slurp(section_deploy_file)
      sections["{{SECTION:debug}}"]     = slurp(section_debug_file)
      sections["{{SECTION:workflow}}"]  = slurp(section_workflow_file)
      sections["{{SECTION:release}}"]   = slurp(section_release_file)
      sections["{{SECTION:atlassian}}"] = slurp(section_atlassian_file)
      sections["{{RELEASE_INDEX}}"]     = slurp(release_index_file)
      sections["{{SKILL_COUNT}}"]       = skill_count
    }
    {
      line = $0
      for (key in sections) {
        p = index(line, key)
        while (p > 0) {
          line = substr(line, 1, p - 1) sections[key] substr(line, p + length(key))
          p = index(line, key)
        }
      }
      print line
    }
  ' "$TEMPLATE" > "$out"
}

# -----------------------------------------------------------------------------
# Build README with preserved tail
# -----------------------------------------------------------------------------
build_readme() {
  local out="$1"
  local landing_tmp="$WORK/landing.md"
  render_landing "$landing_tmp" "readme"

  local preserved_tail="$WORK/tail.md"
  : > "$preserved_tail"

  if [ -f "$README" ] && grep -qF "$MARKER" "$README"; then
    # Everything AFTER the marker line
    awk -v marker="$MARKER" '
      BEGIN { found = 0 }
      {
        if (!found && index($0, marker) > 0) { found = 1; next }
        if (found) print
      }
    ' "$README" > "$preserved_tail"
  fi

  {
    cat "$landing_tmp"
    printf '\n%s\n' "$MARKER"
    if [ -s "$preserved_tail" ]; then
      cat "$preserved_tail"
    else
      # First-time run: include default Adding-a-new-skill section
      cat <<'EOF_TAIL'

## Adding a New Skill

1. Use [`skill-writer`](skill-writer) to generate the skill structure.
2. Add `landing-group: <test|build|deploy|debug|workflow|release|atlassian>` to the new `<skill>/SKILL.md` frontmatter.
3. Run `scripts/sync-skills-landing.sh` to regenerate this file. CI will fail via `--check` if you forget.
4. Commit the regenerated README + updated SKILL.md in the same PR.
EOF_TAIL
    fi
  } > "$out"
}

# -----------------------------------------------------------------------------
# Main — regenerate (or check)
# -----------------------------------------------------------------------------
NEW_README="$WORK/README.new.md"
NEW_WIKI="$WORK/Home.new.md"

case "$MODE" in
  readme) build_readme "$NEW_README" ;;
  wiki)   render_landing "$NEW_WIKI" "wiki" ;;
  both)
    build_readme "$NEW_README"
    render_landing "$NEW_WIKI" "wiki"
    ;;
esac

if [ "$CHECK_MODE" = "1" ]; then
  diff_found=0
  if [ "$MODE" != "wiki" ]; then
    if [ ! -f "$README" ] || ! diff -q "$README" "$NEW_README" >/dev/null; then
      echo "diff: README.md is out of sync" >&2
      diff -u "$README" "$NEW_README" | head -40 >&2 || true
      diff_found=1
    fi
  fi
  if [ "$MODE" != "readme" ]; then
    if [ -f "$WIKI_OUT" ]; then
      if ! diff -q "$WIKI_OUT" "$NEW_WIKI" >/dev/null; then
        echo "diff: wiki-Home.md.generated is out of sync" >&2
        diff -u "$WIKI_OUT" "$NEW_WIKI" | head -40 >&2 || true
        diff_found=1
      fi
    fi
    # No wiki file = ok (user hasn't generated it yet); only fail if it exists and drifts
  fi
  exit "$diff_found"
fi

# Write outputs
if [ "$MODE" != "wiki" ]; then
  cp "$NEW_README" "$README"
  echo "wrote $README ($SKILL_COUNT skills)"
fi
if [ "$MODE" != "readme" ]; then
  cp "$NEW_WIKI" "$WIKI_OUT"
  echo "wrote $WIKI_OUT ($SKILL_COUNT skills)"
fi
