#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$BASE_DIR/lib/common.sh"
# shellcheck source=/dev/null
source "$BASE_DIR/lib/sway.sh"
# shellcheck source=/dev/null
source "$BASE_DIR/lib/hyprland.sh"
# shellcheck source=/dev/null
source "$BASE_DIR/lib/gnome-wayland.sh"
# shellcheck source=/dev/null
source "$BASE_DIR/lib/x11.sh"

MODE="${1:-}"
shift || true

OUTPUT=""
WINDOW_QUERY=""
OUTPUT_NAME=""
WORKSPACE_QUERY=""

usage() {
  cat <<'EOF'
Usage:
  capture.sh full [--output PATH]
  capture.sh region [--output PATH]
  capture.sh active-window [--output PATH]
  capture.sh window <title-or-appid-fragment> [--output PATH]
  capture.sh output <output-name> [--output PATH]
  capture.sh workspace [current|name|number] [--output PATH]
  capture.sh list-windows
  capture.sh list-outputs
  capture.sh list-workspaces
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --output)
        OUTPUT="${2:?missing path after --output}"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        case "$MODE" in
          window)
            if [[ -z "$WINDOW_QUERY" ]]; then
              WINDOW_QUERY="$1"
            else
              WINDOW_QUERY+=" $1"
            fi
            ;;
          output)
            if [[ -z "$OUTPUT_NAME" ]]; then
              OUTPUT_NAME="$1"
            else
              OUTPUT_NAME+=" $1"
            fi
            ;;
          workspace)
            if [[ -z "$WORKSPACE_QUERY" ]]; then
              WORKSPACE_QUERY="$1"
            else
              WORKSPACE_QUERY+=" $1"
            fi
            ;;
          *)
            fail_json "Unexpected argument: $1" "unknown" "$MODE"
            ;;
        esac
        shift
        ;;
    esac
  done
}

backend_detect() {
  if [[ -n "${SWAYSOCK:-}" ]] && have swaymsg && have grim; then
    printf 'sway-grim\n'
  elif [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] && have hyprctl && have grim; then
    printf 'hyprland-grim\n'
  elif [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]] && have gnome-screenshot; then
    printf 'gnome-wayland\n'
  elif [[ -n "${DISPLAY:-}" ]]; then
    printf 'x11\n'
  else
    printf 'unknown\n'
  fi
}

main() {
  [[ -n "$MODE" ]] || { usage; exit 1; }
  parse_args "$@"

  local backend
  backend="$(backend_detect)"

  case "$backend" in
    sway-grim)
      sway_capture
      ;;
    hyprland-grim)
      hypr_capture
      ;;
    gnome-wayland)
      gnome_wayland_capture
      ;;
    x11)
      x11_capture
      ;;
    *)
      fail_json "Could not determine a supported screenshot backend for this session" "$backend" "$MODE"
      ;;
  esac
}

main "$@"
