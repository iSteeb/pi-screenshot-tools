#!/usr/bin/env bash

have() {
  command -v "$1" >/dev/null 2>&1
}

json_escape() {
  printf '%s' "${1:-}" | jq -Rsa .
}

fail_json() {
  local msg="$1"
  local backend="${2:-unknown}"
  local mode="${3:-unknown}"
  local details="${4:-null}"
  printf '{"ok":false,"backend":%s,"mode":%s,"error":%s,"details":%s}\n' \
    "$(json_escape "$backend")" \
    "$(json_escape "$mode")" \
    "$(json_escape "$msg")" \
    "$details"
  exit 1
}

mk_png_path() {
  local output_path="${1:-}"
  if [[ -n "$output_path" ]]; then
    mkdir -p "$(dirname "$output_path")"
    printf '%s\n' "$output_path"
  else
    mktemp --suffix=.png "${TMPDIR:-/tmp}/pi-screenshot-XXXXXX"
  fi
}

geom_to_grim() {
  jq -r '"\(.x),\(.y) \(.width)x\(.height)"' <<<"$1"
}

parse_slurp_geometry() {
  jq -cn --arg r "$1" '
    ($r | capture("(?<x>-?[0-9]+),(?<y>-?[0-9]+) (?<width>[0-9]+)x(?<height>[0-9]+)"))
    | {x: (.x|tonumber), y: (.y|tonumber), width: (.width|tonumber), height: (.height|tonumber)}
  '
}

png_metadata_json() {
  local path="$1"
  python3 - "$path" <<'PY'
import json, os, struct, sys
path = sys.argv[1]
size = os.path.getsize(path)
width = height = None
with open(path, 'rb') as f:
    sig = f.read(8)
    if sig == b'\x89PNG\r\n\x1a\n':
        _len = f.read(4)
        chunk = f.read(4)
        if chunk == b'IHDR':
            width, height = struct.unpack('>II', f.read(8))
print(json.dumps({"width": width, "height": height, "bytes": size}))
PY
}

emit_success() {
  local backend="$1"
  local mode="$2"
  local path="$3"
  local geometry_json="${4:-null}"
  local extra_json
  if [[ $# -ge 5 ]]; then
    extra_json="$5"
  else
    extra_json='{}'
  fi
  local image_json="null"
  if [[ -n "$path" && -f "$path" ]]; then
    image_json="$(png_metadata_json "$path")"
  fi
  jq -cn \
    --arg backend "$backend" \
    --arg mode "$mode" \
    --arg path "$path" \
    --argjson geometry "$geometry_json" \
    --argjson image "$image_json" \
    --argjson extra "$extra_json" \
    '{ok:true, backend:$backend, mode:$mode, path:$path, geometry:$geometry, image:$image} + $extra'
}

capture_grim_geometry() {
  local backend="$1"
  local mode="$2"
  local geom_json="$3"
  local path="$4"
  [[ -n "$geom_json" && "$geom_json" != "null" ]] || fail_json "No geometry resolved" "$backend" "$mode"
  grim -g "$(geom_to_grim "$geom_json")" "$path"
  emit_success "$backend" "$mode" "$path" "$geom_json"
}
