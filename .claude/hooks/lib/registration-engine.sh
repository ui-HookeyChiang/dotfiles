#!/usr/bin/env bash
# Shared helpers for hook registration adapters.

REGISTRATION_APPLY=0
REGISTRATION_DRY_RUN=0

registration_configure() {
  REGISTRATION_APPLY="$1"
  REGISTRATION_DRY_RUN="$2"
}

registration_emit_dry_run() {
  local message="$1"
  [ "$REGISTRATION_APPLY" -eq 1 ] && [ "$REGISTRATION_DRY_RUN" -eq 1 ] || return 1
  echo "$message"
}

registration_validate_json_file() {
  local file="$1" label="$2"
  if ! jq empty "$file" >/dev/null 2>&1 || [ ! -s "$file" ]; then
    echo "  WARN: validation failed for $label; skipping" >&2
    return 1
  fi
}

registration_write_json_file() {
  local target="$1" tmp="$2" label="$3" success="$4"

  registration_validate_json_file "$tmp" "$label" || {
    rm -f "$tmp"
    return 1
  }

  mkdir -p "$(dirname "$target")"
  [ ! -f "$target" ] || cp "$target" "${target}.bak"
  mv "$tmp" "$target"
  echo "$success"
}

registration_symlink() {
  local source="$1" target="$2" dry_message="$3" success="$4"

  if registration_emit_dry_run "$dry_message"; then
    return 0
  fi

  mkdir -p "$(dirname "$target")"
  if [ ! -e "$target" ]; then
    ln -sf "$source" "$target"
    echo "$success"
  fi
}

registration_render_manifest_hooks() {
  local manifest="$1" harness="$2"
  jq --arg harness "$harness" '
    def compact:
      with_entries(select(.value != null and .value != ""));
    def hook_obj($cfg):
      {
        type: "command",
        command: $cfg.command,
        statusMessage: $cfg.statusMessage,
        timeout: $cfg.timeout
      } | compact;
    def entry($cfg):
      if ($cfg.shape // "nested") == "flat" then
        {
          matcher: $cfg.matcher,
          command: $cfg.command,
          timeout: $cfg.timeout
        } | compact
      else
        {
          matcher: $cfg.matcher,
          hooks: [hook_obj($cfg)]
        } | compact
      end;
    reduce .hooks[] as $hook ({hooks: {}};
      if ($hook.harnesses[$harness]? | type) != "object" then
        .
      else
        ($hook.harnesses[$harness]) as $cfg
        | if (($cfg.event // "") == "") then
            .
          else
            .hooks[$cfg.event] //= []
            | .hooks[$cfg.event] += [entry($cfg)]
          end
      end
    )
    | if $harness == "cursor" then .version //= 1 else . end
  ' "$manifest"
}

registration_expand_home_json() {
  sed "s|\\\$HOME|$HOME|g"
}

registration_merge_hooks_json() {
  local existing="$1" template="$2" shape="$3"

  if [ "$shape" = "flat" ]; then
    jq -n \
      --argjson existing "$existing" \
      --argjson template "$template" '
        $existing
        | .version //= ($template.version // 1)
        | .hooks //= {}
        | reduce ($template.hooks | to_entries[]) as {$key, $value} (.;
            .hooks[$key] //= []
            | reduce $value[] as $entry (.;
                if ([.hooks[$key][]?.command] | any(. == $entry.command))
                then .
                else .hooks[$key] += [$entry]
                end
            )
        )
      '
  else
    jq -n \
      --argjson existing "$existing" \
      --argjson template "$template" '
        $existing
        | .hooks //= {}
        | reduce ($template.hooks | to_entries[]) as {$key, $value} (.;
            .hooks[$key] //= []
            | reduce $value[] as $entry (.;
                ($entry.matcher // "") as $matcher
                | if ([.hooks[$key][]?.hooks[]?.command] | any(. == ($entry.hooks[0].command)))
                and ([.hooks[$key][]? | select((.matcher // "") == $matcher) | .hooks[]?.command] | any(. == ($entry.hooks[0].command)))
                then .
                else .hooks[$key] += [$entry]
                end
            )
        )
      '
  fi
}

registration_count_missing_hooks() {
  local target="$1" template="$2" shape="$3"

  if [ ! -f "$target" ]; then
    jq '[.hooks[]?[]?] | length' <<< "$template"
    return
  fi

  if [ "$shape" = "flat" ]; then
    jq -n \
      --argjson existing "$(cat "$target")" \
      --argjson template "$template" '
        [
          $template.hooks
          | to_entries[]
          | . as {$key, $value}
          | $value[]
          | .command as $cmd
          | select(([($existing.hooks[$key] // [])[]?.command] | any(. == $cmd)) | not)
        ] | length
      '
  else
    jq -n \
      --argjson existing "$(cat "$target")" \
      --argjson template "$template" '
        [
          $template.hooks
          | to_entries[]
          | . as {$key, $value}
          | $value[]
          | .hooks[0].command as $cmd
          | (.matcher // "") as $matcher
          | select(([($existing.hooks[$key] // [])[]? | select((.matcher // "") == $matcher) | .hooks[]?.command] | any(. == $cmd)) | not)
        ] | length
      '
  fi
}

registration_manifest_hook_names() {
  local manifest="$1" harness="$2"
  jq -r --arg harness "$harness" '
    .hooks[]
    | select(.harnesses[$harness])
    | .name
  ' "$manifest" | sort -u
}
