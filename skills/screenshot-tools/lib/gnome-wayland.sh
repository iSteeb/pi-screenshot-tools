#!/usr/bin/env bash

gnome_wayland_capture() {
  local path
  case "$MODE" in
    full)
      path="$(mk_png_path "$OUTPUT")"
      gnome-screenshot -f "$path"
      emit_success "gnome-wayland" "full" "$path"
      ;;
    region)
      path="$(mk_png_path "$OUTPUT")"
      gnome-screenshot -a -f "$path"
      emit_success "gnome-wayland" "region" "$path"
      ;;
    active-window)
      fail_json "Direct active-window capture is not implemented for GNOME Wayland yet; use region mode as fallback" "gnome-wayland" "active-window"
      ;;
    window)
      fail_json "Named-window capture is not implemented for GNOME Wayland yet; use region mode as fallback" "gnome-wayland" "window"
      ;;
    output)
      fail_json "Output-specific capture is not implemented for GNOME Wayland yet" "gnome-wayland" "output"
      ;;
    workspace)
      fail_json "Workspace capture is not implemented for GNOME Wayland yet" "gnome-wayland" "workspace"
      ;;
    list-windows)
      fail_json "Window listing is not implemented for GNOME Wayland yet" "gnome-wayland" "list-windows"
      ;;
    list-outputs)
      fail_json "Output listing is not implemented for GNOME Wayland yet" "gnome-wayland" "list-outputs"
      ;;
    list-workspaces)
      fail_json "Workspace listing is not implemented for GNOME Wayland yet" "gnome-wayland" "list-workspaces"
      ;;
    *)
      fail_json "Unsupported mode for GNOME Wayland: $MODE" "gnome-wayland" "$MODE"
      ;;
  esac
}
