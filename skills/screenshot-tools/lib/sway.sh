#!/usr/bin/env bash

sway_require_jq() {
  have jq || fail_json "jq is required for sway backend" "sway-grim" "$MODE"
}

sway_windows_json() {
  sway_require_jq
  swaymsg -t get_tree | jq -c '[.. | objects
    | select((.type? == "con" or .type? == "floating_con") and (.pid? != null) and (.rect? != null) and ((.visible? // true) == true))
    | {
        id: .id,
        title: (.name // ""),
        app_id: (.app_id // ""),
        shell: (.shell // ""),
        focused: (.focused // false),
        pid: .pid,
        workspace: (.workspace // null),
        geometry: {x: .rect.x, y: .rect.y, width: .rect.width, height: .rect.height}
      }
  ]'
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
  local q_lower
  q_lower="$(printf '%s' "$query" | tr '[:upper:]' '[:lower:]')"
  swaymsg -t get_tree | jq -c --arg q "$q_lower" '[.. | objects
    | select((.type? == "con" or .type? == "floating_con") and (.pid? != null) and (.rect? != null) and ((.visible? // true) == true))
    | {
        id: .id,
        title: (.name // ""),
        app_id: (.app_id // ""),
        focused: (.focused // false),
        pid: .pid,
        geometry: {x: .rect.x, y: .rect.y, width: .rect.width, height: .rect.height}
      }
    | . + {
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
  ] | sort_by(-.score, .title, .app_id)'
}

sway_window_geometry_by_id() {
  local window_id="$1"
  sway_require_jq
  swaymsg -t get_tree | jq -c --argjson id "$window_id" 'first(.. | objects
    | select((.type? == "con" or .type? == "floating_con") and (.id? == $id) and (.rect? != null))
    | {
        x: .rect.x,
        y: .rect.y,
        width: .rect.width,
        height: .rect.height,
        title: (.name // ""),
        app_id: (.app_id // ""),
        id: .id,
        pid: .pid
      }
  )'
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

sway_capture() {
  local path region geom matches top second query_details extra
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
      [[ "$top" != "null" ]] || fail_json "No sway window matched: $WINDOW_QUERY" "sway-grim" "window"
      if [[ "$second" != "null" ]]; then
        if [[ "$(jq -r '.[0].base_score' <<<"$matches")" == "$(jq -r '.[1].base_score' <<<"$matches")" ]]; then
          fail_json "Ambiguous window query: $WINDOW_QUERY" "sway-grim" "window" "$(jq -c --arg q "$WINDOW_QUERY" '{query:$q, matches:.}' <<<"$matches")"
        fi
      fi
      path="$(mk_png_path "$OUTPUT")"
      geom="$(jq -c '.[0].geometry + {title: .[0].title, app_id: .[0].app_id, id: .[0].id, pid: .[0].pid}' <<<"$matches")"
      extra="$(jq -c '.[0] | {match:{id, title, app_id, pid, score, base_score}}' <<<"$matches")"
      grim -g "$(geom_to_grim "$geom")" "$path"
      emit_success "sway-grim" "window" "$path" "$geom" "$extra"
      ;;
    window-id)
      [[ -n "$WINDOW_ID" ]] || fail_json "window-id mode requires a window id" "sway-grim" "window-id"
      [[ "$WINDOW_ID" =~ ^[0-9]+$ ]] || fail_json "window-id must be numeric: $WINDOW_ID" "sway-grim" "window-id"
      path="$(mk_png_path "$OUTPUT")"
      geom="$(sway_window_geometry_by_id "$WINDOW_ID")"
      [[ "$geom" != "null" ]] || fail_json "No sway window matched id: $WINDOW_ID" "sway-grim" "window-id"
      extra="$(jq -c '{match:{id, title, app_id, pid}}' <<<"$geom")"
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
