# screenshot-inline

Pi extension that wraps the existing `screenshot-tools` skill backend and returns captured screenshots as inline PNG images in supported terminals like Kitty.

## What it does

Registers:

- custom tool: `capture_screenshot`
- slash command: `/screenshot`

The tool calls the bundled screenshot backend and, when a PNG was captured, returns it as a tool result image attachment. Image rendering is handled by pi's native tool-result rendering pipeline (auto-sized at 60 cell width).

When packaged, it prefers:

- `../../skills/screenshot-tools/capture.sh`

and falls back to:

- `~/.pi/agent/skills/screenshot-tools/capture.sh`

## Supported modes

- `full`
- `region`
- `active-window`
- `window` (requires `query`)
- `window-id` (requires `query`)
- `output` (requires `query`)
- `workspace` (`query` optional, defaults to `current`)
- `list-windows`
- `list-outputs`
- `list-workspaces`

## Slash command

Examples:

```text
/screenshot
/screenshot active-window
/screenshot full
/screenshot region
/screenshot workspace current
/screenshot window kitty
/screenshot window-id 229
/screenshot list-windows
```

If no argument is given, `/screenshot` defaults to `active-window`.

## Exact window-id capture

After `/screenshot list-windows`, you can capture an exact entry by id:

```text
/screenshot window-id 229
```

On Sway and Hyprland, this is still screen-region capture, but the backend may briefly switch to the target workspace, focus the window, capture it, and then switch back.

## Notes

- In the package layout, this extension uses the bundled `skills/screenshot-tools` backend.
- It can also fall back to `~/.pi/agent/skills/screenshot-tools` during local development.
- The capture logic stays in the skill backend; this extension only adds inline image return/rendering support.
- The `capture_screenshot` tool uses pi's native image rendering (no custom `renderResult`). The `/screenshot` command uses a minimal message renderer that displays text + image from `details.imageBase64`.
- `list-windows` now includes visibility and workspace/monitor context when the backend provides it.
- After adding or changing the extension, run `/reload` in pi.
