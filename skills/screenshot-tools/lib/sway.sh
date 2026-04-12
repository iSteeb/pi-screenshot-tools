#!/usr/bin/env bash

sway_require_jq() {
  have jq || fail_json "jq is required for sway backend" "sway-grim" "$MODE"
}

sway_windows_json() {
  sway_require_jq
  local tree_json workspaces_json
  tree_json="$(swaymsg -t get_tree)"
  workspaces_json="$(swaymsg -t get_workspaces)"
  jq -cn --argjson tree "$tree_json" --argjson workspaces "$workspaces_json" '
    def collect_windows($node; $workspace):
      if (($node.type? == "con" or $node.type? == "floating_con") and ($node.pid? != null) and ($node.rect? != null)) then
        [{
          id: $node.id,
          title: ($node.name // ""),
          app_id: ($node.app_id // ""),
          shell: ($node.shell // ""),
          focused: ($node.focused // false),
          pid: $node.pid,
          workspace: $workspace,
          geometry: {x: $node.rect.x, y: $node.rect.y, width: $node.rect.width, height: $node.rect.height}
        }]
      else
        [
          (($node.nodes // []) + ($node.floating_nodes // []))[]? as $child
          | collect_windows($child; if $child.type? == "workspace" then ($child.name // $workspace) else $workspace end)
        ] | add // []
      end;

    ($workspaces | map({key: .name, value: (.visible // false)}) | from_entries) as $workspace_visible
    | collect_windows($tree; null)
    | map(. + {visible: ($workspace_visible[.workspace] // false)})
    | sort_by(.workspace, .title, .app_id, .id)
  '
}

sway_visible_windows_json() {
  jq -c 'map(select((.visible // false) == true))' <<<"$(sway_windows_json)"
}

sway_outputs_json() {
  sway_require_jq
  swaymsg -t get_outputs | jq -c '[.[] | select(.active == true) | {
    name: .name,
    make: (.make // ""),
    model: (.model // ""),
    serial: (.serial // ""),
    scale: (.scale // 1),
    focused: (.focused // false),
    current_workspace: (.current_workspace // null),
    geometry: {x: .rect.x, y: .rect.y, width: .rect.width, height: .rect.height}
  }]'
}

sway_workspaces_json() {
  sway_require_jq
  swaymsg -t get_workspaces | jq -c '[.[] | {
    id: .id,
    num: .num,
    name: .name,
    focused: .focused,
    visible: .visible,
    urgent: .urgent,
    output: .output,
    geometry: {x: .rect.x, y: .rect.y, width: .rect.width, height: .rect.height}
  }]'
}

sway_active_window_geometry() {
  sway_require_jq
  swaymsg -t get_tree | jq -c 'last(.. | objects
    | select((.type? == "con" or .type? == "floating_con") and (.focused? == true) and (.rect? != null))
    | {
        id: .id,
        title: (.name // ""),
        app_id: (.app_id // ""),
        pid: .pid,
        geometry: {x: .rect.x, y: .rect.y, width: .rect.width, height: .rect.height}
      }
  ) | .geometry + {title, app_id, id, pid}'
}

sway_ranked_window_matches() {
  local query="$1"
  sway_require_jq
  local q_lower windows_json
  q_lower="$(printf '%s' "$query" | tr '[:upper:]' '[:lower:]')"
  windows_json="$(sway_visible_windows_json)"
  jq -c --arg q "$q_lower" '
    map(
      . + {
        title_lc: (.title | ascii_downcase),
        app_id_lc: (.app_id | ascii_downcase)
      }
      | . + {
          base_score: (
            (if .title_lc == $q then 100 else 0 end) +
            (if .app_id_lc == $q then 95 else 0 end) +
            (if (.title_lc | startswith($q)) and (.title_lc != $q) then 70 else 0 end) +
            (if (.app_id_lc | startswith($q)) and (.app_id_lc != $q) then 65 else 0 end) +
            (if (.title_lc | contains($q)) and (.title_lc != $q) and ((.title_lc | startswith($q)) | not) then 40 else 0 end) +
            (if (.app_id_lc | contains($q)) and (.app_id_lc != $q) and ((.app_id_lc | startswith($q)) | not) then 35 else 0 end)
          )
        }
      | . + { score: (.base_score + (if .focused then 1 else 0 end)) }
      | select(.base_score > 0)
      | del(.title_lc, .app_id_lc)
    ) | sort_by(-.score, .title, .app_id)
  ' <<<"$windows_json"
}

sway_window_geometry_by_id() {
  local window_id="$1"
  sway_require_jq
  jq -c --argjson id "$window_id" 'first(.[] | select(.id == $id) | (.geometry + {
    title,
    app_id,
    id,
    pid,
    workspace,
    visible
  }))' <<<"$(sway_windows_json)"
}

sway_output_geometry() {
  local out_name="$1"
  sway_require_jq
  swaymsg -t get_outputs | jq -c --arg name "$out_name" 'first(.[] | select(.name == $name and .active == true) | {x: .rect.x, y: .rect.y, width: .rect.width, height: .rect.height, name: .name})'
}

sway_workspace_geometry() {
  local workspace_query="$1"
  sway_require_jq
  if [[ "$workspace_query" == "current" ]]; then
    swaymsg -t get_workspaces | jq -c 'first(.[] | select(.focused == true) | {x: .rect.x, y: .rect.y, width: .rect.width, height: .rect.height, name: .name, output: .output})'
  else
    swaymsg -t get_workspaces | jq -c --arg q "$workspace_query" 'first(.[] | select((.name == $q) or ((.num|tostring) == $q)) | {x: .rect.x, y: .rect.y, width: .rect.width, height: .rect.height, name: .name, output: .output})'
  fi
}

sway_require_window_visible_for_capture() {
  local mode="$1"
  local geom_json="$2"
  local workspace visible details
  workspace="$(jq -r '.workspace // empty' <<<"$geom_json")"
  visible="$(jq -r '.visible // false' <<<"$geom_json")"
  if [[ "$visible" != "true" ]]; then
    details="$(jq -cn --arg reason "window-not-visible" --arg capture_method "screen-region" --arg workspace "$workspace" --argjson match "$geom_json" '{reason:$reason, capture_method:$capture_method, workspace:($workspace | select(length > 0)), match:$match}')"
    fail_json "Cannot capture window because it is not visible on the current desktop; this backend captures screen regions, not hidden window surfaces" "sway-grim" "$mode" "$details"
  fi
}

sway_capture() {
  local path region geom matches top second extra
  case "$MODE" in
    full)
      path="$(mk_png_path "$OUTPUT")"
      grim "$path"
      emit_success "sway-grim" "full" "$path"
      ;;
    region)
      have slurp || fail_json "slurp is required for interactive region capture on sway" "sway-grim" "region"
      path="$(mk_png_path "$OUTPUT")"
      region="$(slurp)" || fail_json "Region selection cancelled" "sway-grim" "region"
      grim -g "$region" "$path"
      emit_success "sway-grim" "region" "$path" "$(parse_slurp_geometry "$region")"
      ;;
    active-window)
      path="$(mk_png_path "$OUTPUT")"
      geom="$(sway_active_window_geometry)"
      capture_grim_geometry "sway-grim" "active-window" "$geom" "$path"
      ;;
    window)
      [[ -n "$WINDOW_QUERY" ]] || fail_json "window mode requires a title or app_id fragment" "sway-grim" "window"
      matches="$(sway_ranked_window_matches "$WINDOW_QUERY")"
      top="$(jq '.[0] // null' <<<"$matches")"
      second="$(jq '.[1] // null' <<<"$matches")"
      [[ "$top" != "null" ]] || fail_json "No visible sway window matched: $WINDOW_QUERY" "sway-grim" "window"
      if [[ "$second" != "null" ]]; then
        if [[ "$(jq -r '.[0].base_score' <<<"$matches")" == "$(jq -r '.[1].base_score' <<<"$matches")" ]]; then
          fail_json "Ambiguous window query: $WINDOW_QUERY" "sway-grim" "window" "$(jq -c --arg q "$WINDOW_QUERY" '{query:$q, matches:.}' <<<"$matches")"
        fi
      fi
      path="$(mk_png_path "$OUTPUT")"
      geom="$(jq -c '.[0].geometry + {title: .[0].title, app_id: .[0].app_id, id: .[0].id, pid: .[0].pid, workspace: .[0].workspace, visible: .[0].visible}' <<<"$matches")"
      extra="$(jq -c '.[0] | {capture_method:"screen-region", match:{id, title, app_id, pid, workspace, visible, score, base_score}}' <<<"$matches")"
      grim -g "$(geom_to_grim "$geom")" "$path"
      emit_success "sway-grim" "window" "$path" "$geom" "$extra"
      ;;
    window-id)
      [[ -n "$WINDOW_ID" ]] || fail_json "window-id mode requires a window id" "sway-grim" "window-id"
      [[ "$WINDOW_ID" =~ ^[0-9]+$ ]] || fail_json "window-id must be numeric: $WINDOW_ID" "sway-grim" "window-id"
      path="$(mk_png_path "$OUTPUT")"
      geom="$(sway_window_geometry_by_id "$WINDOW_ID")"
      [[ "$geom" != "null" ]] || fail_json "No sway window matched id: $WINDOW_ID" "sway-grim" "window-id"
      sway_require_window_visible_for_capture "window-id" "$geom"
      extra="$(jq -c '{capture_method:"screen-region", match:{id, title, app_id, pid, workspace, visible}}' <<<"$geom")"
      grim -g "$(geom_to_grim "$geom")" "$path"
      emit_success "sway-grim" "window-id" "$path" "$geom" "$extra"
      ;;
    output)
      [[ -n "$OUTPUT_NAME" ]] || fail_json "output mode requires an output name" "sway-grim" "output"
      path="$(mk_png_path "$OUTPUT")"
      geom="$(sway_output_geometry "$OUTPUT_NAME")"
      [[ "$geom" != "null" ]] || fail_json "No active sway output matched: $OUTPUT_NAME" "sway-grim" "output"
      capture_grim_geometry "sway-grim" "output" "$geom" "$path"
      ;;
    workspace)
      [[ -n "$WORKSPACE_QUERY" ]] || WORKSPACE_QUERY="current"
      path="$(mk_png_path "$OUTPUT")"
      geom="$(sway_workspace_geometry "$WORKSPACE_QUERY")"
      [[ "$geom" != "null" ]] || fail_json "No sway workspace matched: $WORKSPACE_QUERY" "sway-grim" "workspace"
      capture_grim_geometry "sway-grim" "workspace" "$geom" "$path"
      ;;
    list-windows)
      jq -cn --arg backend "sway-grim" --arg mode "list-windows" --argjson windows "$(sway_windows_json)" '{ok:true, backend:$backend, mode:$mode, windows:$windows}'
      ;;
    list-outputs)
      jq -cn --arg backend "sway-grim" --arg mode "list-outputs" --argjson outputs "$(sway_outputs_json)" '{ok:true, backend:$backend, mode:$mode, outputs:$outputs}'
      ;;
    list-workspaces)
      jq -cn --arg backend "sway-grim" --arg mode "list-workspaces" --argjson workspaces "$(sway_workspaces_json)" '{ok:true, backend:$backend, mode:$mode, workspaces:$workspaces}'
      ;;
    *)
      fail_json "Unsupported mode for sway: $MODE" "sway-grim" "$MODE"
      ;;
  esac
}
