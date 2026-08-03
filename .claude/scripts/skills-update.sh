#!/usr/bin/env bash
# Gated upgrade flow for pinned upstream skills.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOCK_SCRIPT="$SCRIPT_DIR/skills-lock.sh"
LOCK_FILE="${SKILLS_UPDATE_LOCK_FILE:-$REPO_ROOT/skills-lock.json}"
TICKET_DIR="${SKILLS_UPDATE_TICKET_DIR:-$REPO_ROOT/docs/ticket}"

MATTPOCOCK_SOURCE="mattpocock/skills"
DARWIN_SOURCE="alchaincyf/darwin-skill"
RTK_SOURCE="rtk-ai/rtk"

require_bin() {
  local bin="$1"
  command -v "$bin" >/dev/null 2>&1 || {
    echo "missing required binary: $bin" >&2
    exit 2
  }
}

source_ref_env_name() {
  case "$1" in
    "$MATTPOCOCK_SOURCE") printf '%s\n' "SKILLS_UPDATE_MATTPOCOCK_SOURCE_REF" ;;
    "$DARWIN_SOURCE") printf '%s\n' "SKILLS_UPDATE_DARWIN_SOURCE_REF" ;;
    "$RTK_SOURCE") printf '%s\n' "SKILLS_UPDATE_RTK_SOURCE_REF" ;;
    *) echo "unknown source: $1" >&2; exit 2 ;;
  esac
}

source_dir_env_name() {
  case "$1" in
    "$MATTPOCOCK_SOURCE") printf '%s\n' "SKILLS_UPDATE_MATTPOCOCK_SOURCE_DIR" ;;
    "$DARWIN_SOURCE") printf '%s\n' "SKILLS_UPDATE_DARWIN_SOURCE_DIR" ;;
    *) echo "unknown source dir: $1" >&2; exit 2 ;;
  esac
}

env_value() {
  local name="$1"
  printf '%s\n' "${!name:-}"
}

github_ref_sha() {
  local source="$1" ref="$2" env_name env_ref
  env_name="$(source_ref_env_name "$source")"
  env_ref="$(env_value "$env_name")"
  if [[ -n "$env_ref" ]]; then
    printf '%s\n' "$env_ref"
    return
  fi

  git ls-remote "https://github.com/${source}.git" "$ref" | awk 'NR == 1 {print $1}'
}

latest_rtk_tag() {
  if [[ -n "${SKILLS_UPDATE_RTK_TAG:-}" ]]; then
    printf '%s\n' "$SKILLS_UPDATE_RTK_TAG"
    return
  fi

  curl -fsSL "https://api.github.com/repos/${RTK_SOURCE}/releases/latest" | jq -r '.tag_name'
}

prepare_source_tree() {
  local source="$1" ref="$2" dest="$3" env_name local_dir url
  env_name="$(source_dir_env_name "$source")"
  local_dir="$(env_value "$env_name")"

  mkdir -p "$dest"
  if [[ -n "$local_dir" ]]; then
    cp -R "$local_dir"/. "$dest"/
    return
  fi

  url="https://codeload.github.com/${source}/tar.gz/${ref}"
  curl -fsSL "$url" | tar -xz -C "$dest" --strip-components=1
}

hash_skill() {
  local skill_dir="$1" hash
  hash="$(bash "$LOCK_SCRIPT" hash-tree "$skill_dir")" || hash=""
  if [[ ! "$hash" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    echo "refusing to use invalid treeHash for $skill_dir (got: '$hash')" >&2
    return 1
  fi
  printf '%s\n' "$hash"
}

candidate_lock() {
  local current="$1" output="$2" matt_dir="$3" darwin_dir="$4" matt_ref="$5" darwin_ref="$6" rtk_tag="$7" rtk_ref="$8"
  cp "$current" "$output"

  jq \
    --arg matt "$MATTPOCOCK_SOURCE" \
    --arg mattRef "$matt_ref" \
    --arg darwin "$DARWIN_SOURCE" \
    --arg darwinRef "$darwin_ref" \
    --arg rtk "$RTK_SOURCE" \
    --arg rtkTag "$rtk_tag" \
    --arg rtkRef "$rtk_ref" \
    '.sources[$matt].sourceRef = $mattRef
     | .sources[$darwin].sourceRef = $darwinRef
     | .sources[$rtk].ref = $rtkTag
     | .sources[$rtk].tag = $rtkTag
     | .sources[$rtk].sourceRef = $rtkRef' \
    "$output" >"$output.tmp"
  mv "$output.tmp" "$output"

  while IFS=$'\t' read -r skill skill_path; do
    local hash
    hash="$(hash_skill "$matt_dir/$skill_path")"
    jq --arg skill "$skill" --arg hash "$hash" '.skills[$skill].treeHash = $hash' "$output" >"$output.tmp"
    mv "$output.tmp" "$output"
  done < <(jq -r --arg source "$MATTPOCOCK_SOURCE" '.skills | to_entries[] | select(.value.source == $source) | [.key, .value.skillPath] | @tsv' "$current")

  while IFS=$'\t' read -r skill skill_path; do
    local hash
    hash="$(hash_skill "$darwin_dir/$skill_path")"
    jq --arg skill "$skill" --arg hash "$hash" '.skills[$skill].treeHash = $hash' "$output" >"$output.tmp"
    mv "$output.tmp" "$output"
  done < <(jq -r --arg source "$DARWIN_SOURCE" '.skills | to_entries[] | select(.value.source == $source) | [.key, .value.skillPath] | @tsv' "$current")
}

changed_skills() {
  local current="$1" candidate="$2"
  jq -r --slurp '
    .[0] as $old
    | .[1] as $new
    | ($new.skills | keys[]) as $skill
    | select($old.skills[$skill].treeHash != $new.skills[$skill].treeHash)
    | $skill
  ' "$current" "$candidate"
}

changed_sources() {
  local current="$1" candidate="$2"
  jq -r --slurp '
    .[0] as $old
    | .[1] as $new
    | ($new.sources | keys[]) as $source
    | select($old.sources[$source].sourceRef != $new.sources[$source].sourceRef or $old.sources[$source].tag != $new.sources[$source].tag)
    | $source
  ' "$current" "$candidate"
}

candidate_skill_dir() {
  local candidate="$1" matt_dir="$2" darwin_dir="$3" skill="$4" source skill_path
  source="$(jq -r --arg skill "$skill" '.skills[$skill].source' "$candidate")"
  skill_path="$(jq -r --arg skill "$skill" '.skills[$skill].skillPath' "$candidate")"
  case "$source" in
    "$MATTPOCOCK_SOURCE") printf '%s/%s\n' "$matt_dir" "$skill_path" ;;
    "$DARWIN_SOURCE") printf '%s/%s\n' "$darwin_dir" "$skill_path" ;;
    *) echo "unsupported skill source for $skill: $source" >&2; return 1 ;;
  esac
}

run_skill_audit_gate() {
  local skill_dir="$1" audit_cmd rc

  [[ "${SKILLS_UPDATE_SKIP_AUDIT:-0}" == "1" ]] && return 0

  audit_cmd="${SKILLS_UPDATE_AUDIT_CMD:-$REPO_ROOT/skill-audit/scripts/run.sh}"
  if [[ ! -x "$audit_cmd" ]]; then
    echo "skill-audit not executable: $audit_cmd" >&2
    return 1
  fi

  set +e
  "$audit_cmd" "$skill_dir" >/tmp/skills-update-audit.out 2>/tmp/skills-update-audit.err
  rc=$?
  set -e

  case "$rc" in
    2) return 0 ;;
    0)
      echo "skill-audit found problems in $skill_dir" >&2
      cat /tmp/skills-update-audit.out >&2
      return 1
      ;;
    *)
      echo "skill-audit failed for $skill_dir" >&2
      cat /tmp/skills-update-audit.err >&2
      return 1
      ;;
  esac
}

reverse_dependency_gate() {
  local skill="$1" skill_dir="$2" failures=0

  mapfile -t refs < <(
    rg -l --fixed-strings "$skill" "$REPO_ROOT" \
      --glob '!.git/**' \
      --glob '!.worktree/**' \
      --glob '!.worktrees/**' \
      --glob '!docs/dogfoods/**' \
      --glob '!skills-lock.json' \
      --glob '*.{md,sh,py,json,yaml,yml,ts}' 2>/dev/null || true
  )

  [[ "${#refs[@]}" -eq 0 ]] && return 0
  [[ -f "$skill_dir/SKILL.md" ]] || {
    echo "reverse-dependency gate: $skill is referenced but candidate has no SKILL.md" >&2
    return 1
  }

  for ref in "${refs[@]}"; do
    while IFS= read -r mention; do
      [[ -z "$mention" ]] && continue
      local rel="${mention#"$skill/"}"
      if [[ ! -e "$skill_dir/$rel" ]]; then
        echo "reverse-dependency gate: $ref references missing candidate path $mention" >&2
        failures=$((failures + 1))
      fi
    done < <(rg -o --no-line-number "${skill}/[A-Za-z0-9._/-]+" "$ref" 2>/dev/null | sort -u || true)
  done

  [[ "$failures" -eq 0 ]]
}

write_blocker_ticket() {
  local changed_file="$1" reason="$2" ticket
  mkdir -p "$TICKET_DIR"
  ticket="$TICKET_DIR/$(date -u +%Y-%m-%d)-skills-update-blocked-$(date -u +%H%M%S).md"
  {
    echo "# skills-update blocked"
    echo
    echo "Status: needs-triage"
    echo "Date: $(date -u +%Y-%m-%d)"
    echo
    echo "## Reason"
    echo
    echo "$reason"
    echo
    echo "## Changed skills"
    echo
    if [[ -s "$changed_file" ]]; then
      sed 's/^/- /' "$changed_file"
    else
      echo "- (none)"
    fi
  } >"$ticket"
  echo "wrote blocker ticket: $ticket" >&2
}

gate_changed_skills() {
  local candidate="$1" matt_dir="$2" darwin_dir="$3" changed_file="$4" skill skill_dir
  while IFS= read -r skill; do
    [[ -n "$skill" ]] || continue
    skill_dir="$(candidate_skill_dir "$candidate" "$matt_dir" "$darwin_dir" "$skill")"
    run_skill_audit_gate "$skill_dir" || return 1
    reverse_dependency_gate "$skill" "$skill_dir" || return 1
  done < "$changed_file"
}

commit_and_open_pr() {
  [[ "${SKILLS_UPDATE_COMMIT_PR:-1}" == "1" ]] || return 0

  require_bin git
  if [[ "$(git -C "$REPO_ROOT" branch --show-current)" == "main" ]]; then
    git -C "$REPO_ROOT" switch -c "skills-update-$(date -u +%Y%m%d-%H%M%S)"
  fi

  git -C "$REPO_ROOT" add "$LOCK_FILE"
  git -C "$REPO_ROOT" commit -m "$(cat <<'EOF'
Update pinned upstream skills

EOF
)"

  if command -v gh >/dev/null 2>&1; then
    git -C "$REPO_ROOT" push -u origin HEAD
    gh pr create --repo ubiquiti/prompt-hub --title "Update pinned upstream skills" --body "$(cat <<'EOF'
## Summary
- Update `skills-lock.json` to the latest gated upstream skill refs.

## Test plan
- `make skills-lock-verify`

EOF
)"
  else
    echo "gh not found; committed locally but did not open PR" >&2
  fi
}

usage() {
  cat <<'EOF'
Usage: scripts/skills-update.sh

Gated upgrade flow for pinned upstream skills. Takes no arguments;
configuration is env-var driven (SKILLS_UPDATE_*).
EOF
}

main() {
  if [[ $# -gt 0 ]]; then
    case "$1" in
      -h|--help) usage; exit 0 ;;
      *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
  fi

  require_bin jq
  require_bin git
  require_bin curl
  require_bin tar
  require_bin rg

  [[ -f "$LOCK_FILE" ]] || { echo "missing lock file: $LOCK_FILE" >&2; exit 1; }

  local tmp matt_dir darwin_dir candidate changed_file sources_file
  local matt_ref darwin_ref rtk_tag rtk_ref
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" EXIT

  matt_ref="$(github_ref_sha "$MATTPOCOCK_SOURCE" HEAD)"
  darwin_ref="$(github_ref_sha "$DARWIN_SOURCE" HEAD)"
  rtk_tag="$(latest_rtk_tag)"
  rtk_ref="$(github_ref_sha "$RTK_SOURCE" "refs/tags/${rtk_tag}^{}")"
  [[ -n "$rtk_ref" ]] || rtk_ref="$(github_ref_sha "$RTK_SOURCE" "refs/tags/${rtk_tag}")"

  matt_dir="$tmp/mattpocock"
  darwin_dir="$tmp/darwin"
  candidate="$tmp/skills-lock.candidate.json"
  changed_file="$tmp/changed-skills.txt"
  sources_file="$tmp/changed-sources.txt"

  prepare_source_tree "$MATTPOCOCK_SOURCE" "$matt_ref" "$matt_dir"
  prepare_source_tree "$DARWIN_SOURCE" "$darwin_ref" "$darwin_dir"
  candidate_lock "$LOCK_FILE" "$candidate" "$matt_dir" "$darwin_dir" "$matt_ref" "$darwin_ref" "$rtk_tag" "$rtk_ref"

  changed_skills "$LOCK_FILE" "$candidate" >"$changed_file"
  changed_sources "$LOCK_FILE" "$candidate" >"$sources_file"

  if cmp -s "$LOCK_FILE" "$candidate"; then
    echo "skills-update: upstream unchanged; no lock changes"
    return 0
  fi

  echo "skills-update: changed sources"
  sed 's/^/  - /' "$sources_file"
  echo "skills-update: changed skills"
  if [[ -s "$changed_file" ]]; then
    sed 's/^/  - /' "$changed_file"
  else
    echo "  - (none)"
  fi

  if ! gate_changed_skills "$candidate" "$matt_dir" "$darwin_dir" "$changed_file"; then
    write_blocker_ticket "$changed_file" "One or more changed upstream skills failed the update gate. Lock and installed state were not mutated."
    return 1
  fi

  cp "$candidate" "$LOCK_FILE"

  local install_cmd verify_cmd
  install_cmd="${SKILLS_UPDATE_INSTALL_CMD:-$REPO_ROOT/install.sh --skip-bins}"
  verify_cmd="${SKILLS_UPDATE_VERIFY_CMD:-make -C \"$REPO_ROOT\" skills-lock-verify}"
  bash -c "$install_cmd"
  bash -c "$verify_cmd"
  commit_and_open_pr
}

main "$@"
