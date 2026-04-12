#!/usr/bin/env bash

x11_outputs_json() {
  if have xrandr; then
    xrandr --query | awk '/ connected/{print $1}' | jq -Rsc 'split("\n")[:-1] | map({name: ., geometry: null})'
  else
    printf '[]\n'
  fi
}

x11_capture() {
  local path win_id geom
  case "$MODE" in
    full)
      path="$(mk_png_path "$OUTPUT")"
      if have gnome-screenshot; then
        gnome-screenshot -f "$path"
      else
        fail_json "No full-screen capture backend available on X11" "x11" "full"
      fi
      emit_success "x11" "full" "$path"
      ;;
    active-window)
      path="$(mk_png_path "$OUTPUT")"
      if have xdotool && have xwininfo && have import; then
        win_id="$(xdotool getactivewindow)"
        import -window "$win_id" "$path"
        geom="$(xwininfo -id "$win_id" | awk '
          /Absolute upper-left X:/ {x=$4}
          /Absolute upper-left Y:/ {y=$4}
          /Width:/ {w=$2}
          /Height:/ {h=$2}
          END {printf("{\"x\":%s,\"y\":%s,\"width\":%s,\"height\":%s}", x, y, w, h)}')"
        emit_success "x11" "active-window" "$path" "$geom"
      elif have gnome-screenshot; then
        gnome-screenshot -w -f "$path"
        emit_success "x11" "active-window" "$path"
      else
        fail_json "No active-window capture backend available on X11" "x11" "active-window"
      fi
      ;;
    region)
      path="$(mk_png_path "$OUTPUT")"
      if have gnome-screenshot; then
        gnome-screenshot -a -f "$path"
        emit_success "x11" "region" "$path"
      else
        fail_json "No region capture backend available on X11" "x11" "region"
      fi
      ;;
    list-outputs)
      jq -cn --arg backend "x11" --arg mode "list-outputs" --argjson outputs "$(x11_outputs_json)" '{ok:true, backend:$backend, mode:$mode, outputs:$outputs}'
      ;;
    *)
      fail_json "Mode not implemented for X11 backend: $MODE" "x11" "$MODE"
      ;;
  esac
}
