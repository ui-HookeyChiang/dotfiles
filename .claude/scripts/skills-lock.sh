#!/usr/bin/env bash
# Maintain skills-lock.json. T1 intentionally regenerates from the installed
# tree; later install/upgrade flows should feed this same hash function from
# pinned upstream content.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

LOCK_FILE="${SKILLS_LOCK_FILE:-$REPO_ROOT/skills-lock.json}"
SKILLS_ROOT="${SKILLS_LOCK_SKILLS_ROOT:-$HOME/.agents/skills}"
SKILLS_CLI_VERSION="${SKILLS_LOCK_SKILLS_CLI_VERSION:-1.5.20}"

MATTPOCOCK_SOURCE="mattpocock/skills"
MATTPOCOCK_REF="HEAD"
MATTPOCOCK_SOURCE_REF="ed37663cc5fbef691ddfecd080dff42f7e7e350d"
MATTPOCOCK_SKILLS="${SKILLS_LOCK_MATTPOCOCK_SKILLS:-improve-codebase-architecture grill-with-docs grilling to-spec to-tickets wayfinder triage setup-matt-pocock-skills handoff writing-great-skills ask-matt domain-modeling tdd resolving-merge-conflicts codebase-design diagnosing-bugs prototype research}"

DARWIN_SOURCE="alchaincyf/darwin-skill"
DARWIN_REF="HEAD"
DARWIN_SOURCE_REF="2fbaf4171e453d5c66fc8109a296ae89c4772bc3"
DARWIN_SKILLS="${SKILLS_LOCK_DARWIN_SKILLS:-darwin-skill}"

RTK_SOURCE="rtk-ai/rtk"
RTK_REF="v0.44.0"
RTK_TAG="v0.44.0"
RTK_SOURCE_REF="3fc407027589acef9579df5b2ad10b0f3042e030"

usage() {
  cat <<'EOF'
Usage: scripts/skills-lock.sh <regen|verify|hash-tree DIR>

Environment:
  SKILLS_LOCK_FILE                Lock path (default: ./skills-lock.json)
  SKILLS_LOCK_SKILLS_ROOT         Installed skills root (default: ~/.agents/skills)
  SKILLS_LOCK_SKILLS_CLI_VERSION  Exact skills npm CLI version to record
EOF
}

require_bin() {
  local bin="$1"
  command -v "$bin" >/dev/null 2>&1 || {
    echo "missing required binary: $bin" >&2
    exit 2
  }
}

tree_hash() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    echo "missing skill directory: $dir" >&2
    exit 1
  fi

  (
    cd "$dir"
    LC_ALL=C find . -type f -print0 \
      | LC_ALL=C sort -z \
      | while IFS= read -r -d '' file; do
          local rel="${file#./}"
          local file_hash
          file_hash="$(sha256sum "$rel" | awk '{print $1}')"
          printf '%s  %s\n' "$file_hash" "$rel"
        done
  ) | sha256sum | awk '{print "sha256:" $1}'
}

json_array_from_words() {
  local words="$1"
  # Skill names are package ids, so whitespace splitting is intentional here.
  # shellcheck disable=SC2086
  printf '%s\n' $words | jq -R . | jq -s .
}

add_skill_hashes() {
  local source="$1"
  local skill_names="$2"
  local path_mode="$3"
  local skills_json="$4"

  for skill in $skill_names; do
    local skill_path="$skill"
    if [[ "$path_mode" == "repo-root" ]]; then
      skill_path="."
    elif [[ "$source" == "$MATTPOCOCK_SOURCE" ]]; then
      case "$skill" in
        handoff|writing-great-skills|grilling|teach) skill_path="skills/productivity/$skill" ;;
        *) skill_path="skills/engineering/$skill" ;;
      esac
    fi

    local hash
    hash="$(tree_hash "$SKILLS_ROOT/$skill")" || hash=""
    if [[ ! "$hash" =~ ^sha256:[0-9a-f]{64}$ ]]; then
      echo "refusing to write invalid treeHash for $skill (got: '$hash')" >&2
      exit 1
    fi
    skills_json="$(
      jq \
        --arg name "$skill" \
        --arg source "$source" \
        --arg skillPath "$skill_path" \
        --arg treeHash "$hash" \
        '. + {($name): {source: $source, skillPath: $skillPath, treeHash: $treeHash}}' \
        <<<"$skills_json"
    )"
  done

  printf '%s\n' "$skills_json"
}

regen() {
  require_bin jq
  require_bin sha256sum
  require_bin find
  require_bin sort

  local skills_json='{}'
  skills_json="$(add_skill_hashes "$MATTPOCOCK_SOURCE" "$MATTPOCOCK_SKILLS" "skill-name" "$skills_json")"
  skills_json="$(add_skill_hashes "$DARWIN_SOURCE" "$DARWIN_SKILLS" "repo-root" "$skills_json")"

  local mattpocock_skills_json darwin_skills_json
  mattpocock_skills_json="$(json_array_from_words "$MATTPOCOCK_SKILLS")"
  darwin_skills_json="$(json_array_from_words "$DARWIN_SKILLS")"

  jq -n \
    --arg skillsCliVersion "$SKILLS_CLI_VERSION" \
    --arg mattpocockSource "$MATTPOCOCK_SOURCE" \
    --arg mattpocockRef "$MATTPOCOCK_REF" \
    --arg mattpocockSourceRef "$MATTPOCOCK_SOURCE_REF" \
    --argjson mattpocockSkills "$mattpocock_skills_json" \
    --arg darwinSource "$DARWIN_SOURCE" \
    --arg darwinRef "$DARWIN_REF" \
    --arg darwinSourceRef "$DARWIN_SOURCE_REF" \
    --argjson darwinSkills "$darwin_skills_json" \
    --arg rtkSource "$RTK_SOURCE" \
    --arg rtkRef "$RTK_REF" \
    --arg rtkTag "$RTK_TAG" \
    --arg rtkSourceRef "$RTK_SOURCE_REF" \
    --argjson skills "$skills_json" \
    '{
      schemaVersion: 2,
      skillsCli: {
        package: "skills",
        version: $skillsCliVersion
      },
      sources: {
        ($mattpocockSource): {
          ref: $mattpocockRef,
          sourceRef: $mattpocockSourceRef,
          skills: $mattpocockSkills
        },
        ($darwinSource): {
          ref: $darwinRef,
          sourceRef: $darwinSourceRef,
          skills: $darwinSkills
        },
        ($rtkSource): {
          ref: $rtkRef,
          tag: $rtkTag,
          sourceRef: $rtkSourceRef
        }
      },
      skills: $skills
    }' >"$LOCK_FILE"

  echo "wrote $LOCK_FILE"
}

validate_lock_schema() {
  jq -e '
    .schemaVersion == 2
    and .skillsCli.package == "skills"
    and (.skillsCli.version | type == "string" and length > 0)
    and (.sources | type == "object")
    and (.skills | type == "object")
    and all(.sources[]; (.sourceRef | test("^[0-9a-f]{40}$")))
    and all(.skills[]; (.source | type == "string") and (.skillPath | type == "string") and (.treeHash | test("^sha256:[0-9a-f]{64}$")))
  ' "$LOCK_FILE" >/dev/null
}

verify() {
  require_bin jq
  require_bin sha256sum
  require_bin find
  require_bin sort

  if [[ ! -f "$LOCK_FILE" ]]; then
    echo "missing lock file: $LOCK_FILE" >&2
    exit 1
  fi

  validate_lock_schema || {
    echo "invalid skills lock schema: $LOCK_FILE" >&2
    exit 1
  }

  local failures=0
  while IFS= read -r skill; do
    local expected actual
    expected="$(jq -r --arg skill "$skill" '.skills[$skill].treeHash' "$LOCK_FILE")"
    actual="$(tree_hash "$SKILLS_ROOT/$skill")"

    if [[ "$actual" == "$expected" ]]; then
      echo "OK $skill"
    else
      echo "DRIFT $skill expected=$expected actual=$actual" >&2
      failures=$((failures + 1))
    fi
  done < <(jq -r '.skills | keys[]' "$LOCK_FILE")

  if [[ "$failures" -gt 0 ]]; then
    exit 1
  fi
}

case "${1:-}" in
  regen) regen ;;
  verify) verify ;;
  hash-tree)
    require_bin sha256sum
    require_bin find
    require_bin sort
    tree_hash "${2:?usage: scripts/skills-lock.sh hash-tree DIR}"
    ;;
  -h|--help) usage ;;
  *) usage >&2; exit 2 ;;
esac
