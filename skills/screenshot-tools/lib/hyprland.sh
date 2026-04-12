#!/usr/bin/env bash

hypr_require_jq() {
  have jq || fail_json "jq is required for hyprland backend" "hyprland-grim" "$MODE"
}

hypr_windows_json() {
  hypr_require_jq
  hyprctl clients -j | jq -c '[.[] | {
    address,
    title: (.title // ""),
    app_id: (.class // ""),
    focused: (.focusHistoryID == 0),
    pid,
    workspace: (.workspace.name // null),
    geometry: {x: .at[0], y: .at[1], width: .size[0], height: .size[1]}
  }]'
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
  local q_lower
  q_lower="$(printf '%s' "$query" | tr '[:upper:]' '[:lower:]')"
  hyprctl clients -j | jq -c --arg q "$q_lower" '[.[]
    | {
        address,
        title: (.title // ""),
        app_id: (.class // ""),
        focused: (.focusHistoryID == 0),
        pid,
        geometry: {x: .at[0], y: .at[1], width: .size[0], height: .size[1]}
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
      [[ "$(jq 'length' <<<"$matches")" -gt 0 ]] || fail_json "No Hyprland window matched: $WINDOW_QUERY" "hyprland-grim" "window"
      second="$(jq '.[1] // null' <<<"$matches")"
      if [[ "$second" != "null" && "$(jq -r '.[0].base_score' <<<"$matches")" == "$(jq -r '.[1].base_score' <<<"$matches")" ]]; then
        fail_json "Ambiguous window query: $WINDOW_QUERY" "hyprland-grim" "window" "$(jq -c --arg q "$WINDOW_QUERY" '{query:$q, matches:.}' <<<"$matches")"
      fi
      path="$(mk_png_path "$OUTPUT")"
      geom="$(jq -c '.[0].geometry + {title: .[0].title, app_id: .[0].app_id, pid: .[0].pid, address: .[0].address}' <<<"$matches")"
      extra="$(jq -c '.[0] | {match:{address, title, app_id, pid, score, base_score}}' <<<"$matches")"
      grim -g "$(geom_to_grim "$geom")" "$path"
      emit_success "hyprland-grim" "window" "$path" "$geom" "$extra"
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
