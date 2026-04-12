---
name: screenshot-tools
description: Capture screenshots on Linux desktops for debugging, UI verification, and documentation. Use when you need full-screen, region, output/monitor, active-window, named-window, workspace, window-list, or output-list capture. Prefers compositor-native methods on Wayland and falls back cleanly on GNOME or X11.
---

# Screenshot Tools

Cross-desktop screenshot skill with a strong compositor-native implementation for **Sway/wlroots**, an implemented **Hyprland** backend, and adaptable fallbacks for **GNOME Wayland** and **X11**.

Use this skill when the user wants to:
- capture the full desktop
- capture a specific output/monitor
- capture a workspace
- select a region interactively
- capture the active/focused window
- capture a visible window by title or app id/class
- capture a visible window by exact listed window id
- list windows, outputs, or workspaces before choosing one

## Current implementation status

- **Sway / wlroots Wayland:** primary, fully supported path using `grim`, `slurp`, `swaymsg`, and `jq`
- **Hyprland:** implemented path using `grim`, `slurp`, `hyprctl`, and `jq`
- **GNOME Wayland:** basic full-screen and interactive area fallback via `gnome-screenshot`
- **X11:** basic full-screen, region, active-window, and output-list fallback via `gnome-screenshot`, `xdotool`, `xwininfo`, and `xrandr` when available

## Important operating rules

- If the `capture_screenshot` tool is available, prefer it over raw `bash` calls to `capture.sh`, because it can return the PNG inline in supported terminals like Kitty.
- Prefer **non-interactive** capture when the request is unambiguous.
- If the user asks for the **current** or **active** window, prefer `active-window`.
- If the user asks for a window by name/app, prefer `window "..."`.
- On Sway/Hyprland, window and window-id capture are screen-region based; if the target is on another workspace, the backend may briefly switch there, focus it, capture it, and switch back.
- If the query may be ambiguous, first use `list-windows`.
- If `window "..."` returns an ambiguity error, show the candidate matches and ask the user to choose.
- If exact window capture is not supported on the current desktop, explain the limitation and offer `region` as fallback.
- Always save screenshots to a temporary PNG unless `--output <path>` is provided.
- The helper prints JSON so the result is machine-friendly.

## Stable command interface

```bash
{baseDir}/capture.sh full
{baseDir}/capture.sh region
{baseDir}/capture.sh active-window
{baseDir}/capture.sh window "Firefox"
{baseDir}/capture.sh window-id 229
{baseDir}/capture.sh output HDMI-A-1
{baseDir}/capture.sh workspace current
{baseDir}/capture.sh workspace 2
{baseDir}/capture.sh list-windows
{baseDir}/capture.sh list-outputs
{baseDir}/capture.sh list-workspaces
```

Optional explicit output path:

```bash
{baseDir}/capture.sh active-window --output /tmp/window.png
```

## Output format

Successful capture returns JSON like:

```json
{
  "ok": true,
  "backend": "sway-grim",
  "mode": "window",
  "path": "/tmp/pi-screenshot-abc123.png",
  "geometry": {"x": 8, "y": 8, "width": 1908, "height": 2114},
  "image": {"width": 1908, "height": 2114, "bytes": 238379},
  "match": {"id": 371, "title": "tmux", "app_id": "kitty", "score": 96}
}
```

Errors are also structured JSON. Ambiguous window matching includes candidate matches in `details.matches`.

## Recommended workflows

### Active window

```bash
{baseDir}/capture.sh active-window
```

### Window by title/app id

1. If the request is specific enough, try:

```bash
{baseDir}/capture.sh window "Firefox"
```

2. If ambiguous, inspect candidates:

```bash
{baseDir}/capture.sh list-windows
```

3. Ask the user to pick one of the listed windows, then retry with a more specific query.

### Window by exact id

If `list-windows` already returned a specific window id, capture it directly:

```bash
{baseDir}/capture.sh window-id 229
```

### Output/monitor capture

1. Enumerate outputs if needed:

```bash
{baseDir}/capture.sh list-outputs
```

2. Capture a specific one:

```bash
{baseDir}/capture.sh output HDMI-A-1
```

### Workspace capture

```bash
{baseDir}/capture.sh workspace current
{baseDir}/capture.sh workspace 3
{baseDir}/capture.sh list-workspaces
```

### Interactive region capture

Use only when the user explicitly wants a selected area, or when direct window capture is unavailable.

```bash
{baseDir}/capture.sh region
```

## Matching policy

Window matching is ranked, not just substring-based:
- exact title match first
- exact app id/class match second
- prefix match next
- substring match after that
- focused window gets a small tie-break boost

If the top two results have the same score, treat the query as ambiguous instead of guessing.

For Sway/Hyprland, `window` and `window-id` do not capture hidden window surfaces directly. They capture the compositor-visible screen region and may briefly switch to the target workspace to make the window visible first.

## Dependencies

Preferred tools:
- `grim`
- `slurp`
- `jq`

Sway backend:
- `swaymsg`

Hyprland backend:
- `hyprctl`

Fallback tools used when available:
- `gnome-screenshot`
- `xdotool`
- `xwininfo`
- `xrandr`

## Implementation notes

The public interface is intentionally stable behind one entrypoint, `capture.sh`. Backend logic lives under `lib/` so the skill can be extended later for GNOME portals, macOS (`screencapture`), or other compositors without changing how the model uses it.
