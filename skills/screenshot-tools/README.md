# screenshot-tools

Cross-desktop screenshot skill for [pi](https://github.com/badlogic/pi-mono) with a strong compositor-native implementation for **Sway/wlroots**, an implemented **Hyprland** backend, and practical fallbacks for **GNOME Wayland** and **X11**.

It lets pi take screenshots of:

- the **active window**
- a **specific visible window** by title or app id/class
- the **current workspace**
- a **specific workspace**
- a **specific output / monitor**
- the **full desktop**
- an **interactive region**
- and it can **list windows, outputs, and workspaces** before capturing

![pi session screenshot](docs/images/pi-session.png)

## Why this skill exists

On Linux, screenshot capture is not just one command. The actual screenshot tool and the way you identify a window depend on the desktop session:

- **Sway / wlroots**: `grim`, `slurp`, `swaymsg`
- **Hyprland**: `grim`, `slurp`, `hyprctl`
- **GNOME Wayland**: usually `gnome-screenshot` or portal-based fallbacks
- **X11**: `gnome-screenshot`, `xdotool`, `xwininfo`, `xrandr`

This skill hides those differences behind one stable interface, so pi can use it reliably.

## Features

- **Compositor-native Sway support** using `grim` + `swaymsg`
- **Hyprland support** using `grim` + `hyprctl`
- **Ranked window matching** by title and app id/class
- **Visibility-aware window capture** on Sway/Hyprland so hidden windows are rejected instead of producing misleading screenshots
- **Ambiguity detection** so the agent does not guess incorrectly
- **Structured JSON output** for reliable agent use
- **Image metadata** in results: width, height, file size
- **Workspace capture** and enumeration
- **Output/monitor capture** and enumeration
- **Interactive region capture** when needed
- Refactored backend layout ready for future **GNOME improvements**, **macOS**, and other platforms

## What you can ask pi

Natural-language prompts:

- `Take a screenshot of the active window`
- `Take a screenshot of the current workspace`
- `Take a screenshot of workspace 4`
- `Take a screenshot of output HDMI-A-1`
- `Take a full-screen screenshot`
- `Take a region screenshot`
- `List windows I can capture`
- `List outputs I can capture`
- `List workspaces I can capture`
- `Take a screenshot of the Firefox window`
- `Take a screenshot of the tmux window`
- `Take a screenshot of the kitty window`

If a window query is ambiguous, the skill returns candidate matches instead of guessing.

On Sway and Hyprland, window and window-id capture are screen-region based. That means they can only reliably capture windows that are currently visible on a workspace/monitor; hidden or off-workspace windows are rejected.

## Direct command-line usage

The skill is implemented behind one stable entrypoint:

```bash
./capture.sh full
./capture.sh region
./capture.sh active-window
./capture.sh window "Firefox"
./capture.sh window-id 229
./capture.sh output HDMI-A-1
./capture.sh workspace current
./capture.sh workspace 4
./capture.sh list-windows
./capture.sh list-outputs
./capture.sh list-workspaces
```

Optional explicit output path:

```bash
./capture.sh active-window --output /tmp/window.png
```

## Example output

Successful capture returns structured JSON:

```json
{
  "ok": true,
  "backend": "sway-grim",
  "mode": "window",
  "path": "/tmp/pi-screenshot-abc123.png",
  "geometry": {
    "x": 8,
    "y": 8,
    "width": 1908,
    "height": 2114,
    "title": "tmux",
    "app_id": "kitty"
  },
  "image": {
    "width": 1908,
    "height": 2114,
    "bytes": 238379
  },
  "match": {
    "id": 371,
    "title": "tmux",
    "app_id": "kitty",
    "score": 96,
    "base_score": 95
  }
}
```

Ambiguous window matching returns structured error JSON:

```json
{
  "ok": false,
  "backend": "sway-grim",
  "mode": "window",
  "error": "Ambiguous window query: Firefox",
  "details": {
    "query": "Firefox",
    "matches": ["..."]
  }
}
```

## Backend support

### Sway / wlroots

Primary implementation. Supports:

- full desktop
- region
- active window
- window by query (visible windows only)
- window by exact id (visible windows only)
- output by name
- workspace by name/number/current
- list windows
- list outputs
- list workspaces

### Hyprland

Implemented backend with the same major capabilities as Sway. Window capture is also visibility-aware there.

### GNOME Wayland

Current fallback implementation supports:

- full desktop
- region

Direct arbitrary window/output/workspace capture is not fully implemented yet.

### X11

Current fallback implementation supports:

- full desktop
- region
- active window
- basic output listing

## Installation

### As a local skill

Copy or clone this directory into one of pi's skill locations, for example:

```bash
~/.pi/agent/skills/screenshot-tools/
```

Then reload pi:

```bash
/reload
```

### Via a pi package from git

Once this repository is published as a pi package:

```bash
pi install git:github.com/M64GitHub/pi-screenshot-tools
```

### Via npm

Once published to npm as a pi package:

```bash
pi install npm:pi-screenshot-tools
```

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
- `python3`

## Repository layout

```text
screenshot-tools/
├── README.md
├── SKILL.md
├── capture.sh
├── docs/
│   └── images/
├── lib/
│   ├── common.sh
│   ├── sway.sh
│   ├── hyprland.sh
│   ├── gnome-wayland.sh
│   └── x11.sh
```

## Development notes

- `capture.sh` is the stable public interface
- backend-specific logic lives under `lib/`
- output is intentionally JSON-first for good LLM/tool interoperability
- on Sway/Hyprland, `window` and `window-id` use screen-region capture under the compositor, not direct hidden-surface capture
- the matching logic prefers exact matches, then prefix matches, then substring matches
- if top matches are tied, the script reports ambiguity instead of choosing arbitrarily

The current focus is making Linux desktop screenshot automation reliable and easy for pi to use. The structure is intentionally backend-oriented so support can continue to improve for GNOME Wayland, X11, macOS, and other environments over time.

