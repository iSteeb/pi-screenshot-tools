#!/usr/bin/env bash

hypr_require_jq() {
  have jq || fail_json "jq is required for hyprland backend" "hyprland-grim" "$MODE"
}

hypr_windows_json() {
  hypr_require_jq
  local clients_json monitors_json
  clients_json="$(hyprctl clients -j)"
  monitors_json="$(hyprctl monitors -j)"
  jq -cn --argjson clients "$clients_json" --argjson monitors "$monitors_json" '
    ($monitors | map(.activeWorkspace.name) | map(select(. != null and . != "")) | unique) as $visible_workspaces
    | $clients
    | map({
        address,
        title: (.title // ""),
        app_id: (.class // ""),
        focused: (.focusHistoryID == 0),
        visible: ($visible_workspaces | index(.workspace.name) != null),
        pid,
        workspace: (.workspace.name // null),
        monitor: (.monitor // null),
        geometry: {x: .at[0], y: .at[1], width: .size[0], height: .size[1]}
      })
    | sort_by(.workspace, .title, .app_id, .address)
  '
}

hypr_visible_windows_json() {
  jq -c 'map(select((.visible // false) == true))' <<<"$(hypr_windows_json)"
}

hypr_outputs_json() {
  hypr_require_jq
  hyprctl monitors -j | jq -c '[.[] | {
    name,
    focused,
    description: (.description // ""),
    scale,
    current_workspace: (.activeWorkspace.name // null),
    geometry: {x, y, width, height}
  }]'
}

hypr_workspaces_json() {
  hypr_require_jq
  hyprctl workspaces -j | jq -c '[.[] | {
    id,
    name,
    monitor,
    monitorID,
    windows,
    hasfullscreen,
    lastwindow,
    geometry: {x, y, width, height}
  }]'
}

hypr_active_window_geometry() {
  hypr_require_jq
  hyprctl activewindow -j | jq -c '{x: .at[0], y: .at[1], width: .size[0], height: .size[1], title: (.title // ""), app_id: (.class // ""), pid, address}'
}

hypr_ranked_window_matches() {
  local query="$1"
  hypr_require_jq
  local q_lower windows_json
  q_lower="$(printf '%s' "$query" | tr '[:upper:]' '[:lower:]')"
  windows_json="$(hypr_visible_windows_json)"
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

hypr_window_geometry_by_id() {
  local window_id="$1"
  hypr_require_jq
  jq -c --arg q "$window_id" 'first(.[] | select((.address // "") == $q or ((.pid|tostring) == $q)) | (.geometry + {
    title,
    app_id,
    pid,
    address,
    workspace,
    monitor,
    visible
  }))' <<<"$(hypr_windows_json)"
}

hypr_output_geometry() {
  local out_name="$1"
  hypr_require_jq
  hyprctl monitors -j | jq -c --arg name "$out_name" 'first(.[] | select(.name == $name) | {x, y, width, height, name})'
}

hypr_workspace_geometry() {
  local workspace_query="$1"
  hypr_require_jq
  if [[ "$workspace_query" == "current" ]]; then
    hyprctl monitors -j | jq -c 'first(.[] | select(.focused == true) | {x, y, width, height, name: .activeWorkspace.name, monitor: .name})'
  else
    hyprctl workspaces -j | jq -c --arg q "$workspace_query" 'first(.[] | select((.name == $q) or ((.id|tostring) == $q)) | {x, y, width, height, name, monitor})'
  fi
}

hypr_require_window_visible_for_capture() {
  local mode="$1"
  local geom_json="$2"
  local workspace monitor visible details
  workspace="$(jq -r '.workspace // empty' <<<"$geom_json")"
  monitor="$(jq -r '.monitor // empty' <<<"$geom_json")"
  visible="$(jq -r '.visible // false' <<<"$geom_json")"
  if [[ "$visible" != "true" ]]; then
    details="$(jq -cn --arg reason "window-not-visible" --arg capture_method "screen-region" --arg workspace "$workspace" --arg monitor "$monitor" --argjson match "$geom_json" '{reason:$reason, capture_method:$capture_method, workspace:($workspace | select(length > 0)), monitor:($monitor | select(length > 0)), match:$match}')"
    fail_json "Cannot capture window because it is not visible on any current monitor; this backend captures screen regions, not hidden window surfaces" "hyprland-grim" "$mode" "$details"
  fi
}

hypr_capture() {
  local path region geom matches second extra
  case "$MODE" in
    full)
      path="$(mk_png_path "$OUTPUT")"
      grim "$path"
      emit_success "hyprland-grim" "full" "$path"
      ;;
    region)
      have slurp || fail_json "slurp is required for interactive region capture on Hyprland" "hyprland-grim" "region"
      path="$(mk_png_path "$OUTPUT")"
      region="$(slurp)" || fail_json "Region selection cancelled" "hyprland-grim" "region"
      grim -g "$region" "$path"
      emit_success "hyprland-grim" "region" "$path" "$(parse_slurp_geometry "$region")"
      ;;
    active-window)
      path="$(mk_png_path "$OUTPUT")"
      geom="$(hypr_active_window_geometry)"
      capture_grim_geometry "hyprland-grim" "active-window" "$geom" "$path"
      ;;
    window)
      [[ -n "$WINDOW_QUERY" ]] || fail_json "window mode requires a title or class fragment" "hyprland-grim" "window"
      matches="$(hypr_ranked_window_matches "$WINDOW_QUERY")"
      [[ "$(jq 'length' <<<"$matches")" -gt 0 ]] || fail_json "No visible Hyprland window matched: $WINDOW_QUERY" "hyprland-grim" "window"
      second="$(jq '.[1] // null' <<<"$matches")"
      if [[ "$second" != "null" && "$(jq -r '.[0].base_score' <<<"$matches")" == "$(jq -r '.[1].base_score' <<<"$matches")" ]]; then
        fail_json "Ambiguous window query: $WINDOW_QUERY" "hyprland-grim" "window" "$(jq -c --arg q "$WINDOW_QUERY" '{query:$q, matches:.}' <<<"$matches")"
      fi
      path="$(mk_png_path "$OUTPUT")"
      geom="$(jq -c '.[0].geometry + {title: .[0].title, app_id: .[0].app_id, pid: .[0].pid, address: .[0].address, workspace: .[0].workspace, monitor: .[0].monitor, visible: .[0].visible}' <<<"$matches")"
      extra="$(jq -c '.[0] | {capture_method:"screen-region", match:{address, title, app_id, pid, workspace, monitor, visible, score, base_score}}' <<<"$matches")"
      grim -g "$(geom_to_grim "$geom")" "$path"
      emit_success "hyprland-grim" "window" "$path" "$geom" "$extra"
      ;;
    window-id)
      [[ -n "$WINDOW_ID" ]] || fail_json "window-id mode requires a window id" "hyprland-grim" "window-id"
      path="$(mk_png_path "$OUTPUT")"
      geom="$(hypr_window_geometry_by_id "$WINDOW_ID")"
      [[ "$geom" != "null" ]] || fail_json "No Hyprland window matched id: $WINDOW_ID" "hyprland-grim" "window-id"
      hypr_require_window_visible_for_capture "window-id" "$geom"
      extra="$(jq -c '{capture_method:"screen-region", match:{address, title, app_id, pid, workspace, monitor, visible}}' <<<"$geom")"
      grim -g "$(geom_to_grim "$geom")" "$path"
      emit_success "hyprland-grim" "window-id" "$path" "$geom" "$extra"
      ;;
    output)
      [[ -n "$OUTPUT_NAME" ]] || fail_json "output mode requires an output name" "hyprland-grim" "output"
      path="$(mk_png_path "$OUTPUT")"
      geom="$(hypr_output_geometry "$OUTPUT_NAME")"
      [[ "$geom" != "null" ]] || fail_json "No Hyprland output matched: $OUTPUT_NAME" "hyprland-grim" "output"
      capture_grim_geometry "hyprland-grim" "output" "$geom" "$path"
      ;;
    workspace)
      [[ -n "$WORKSPACE_QUERY" ]] || WORKSPACE_QUERY="current"
      path="$(mk_png_path "$OUTPUT")"
      geom="$(hypr_workspace_geometry "$WORKSPACE_QUERY")"
      [[ "$geom" != "null" ]] || fail_json "No Hyprland workspace matched: $WORKSPACE_QUERY" "hyprland-grim" "workspace"
      capture_grim_geometry "hyprland-grim" "workspace" "$geom" "$path"
      ;;
    list-windows)
      jq -cn --arg backend "hyprland-grim" --arg mode "list-windows" --argjson windows "$(hypr_windows_json)" '{ok:true, backend:$backend, mode:$mode, windows:$windows}'
      ;;
    list-outputs)
      jq -cn --arg backend "hyprland-grim" --arg mode "list-outputs" --argjson outputs "$(hypr_outputs_json)" '{ok:true, backend:$backend, mode:$mode, outputs:$outputs}'
      ;;
    list-workspaces)
      jq -cn --arg backend "hyprland-grim" --arg mode "list-workspaces" --argjson workspaces "$(hypr_workspaces_json)" '{ok:true, backend:$backend, mode:$mode, workspaces:$workspaces}'
      ;;
    *)
      fail_json "Unsupported mode for Hyprland: $MODE" "hyprland-grim" "$MODE"
      ;;
  esac
}
