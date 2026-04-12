# screenshot-inline

Pi extension that wraps the existing `screenshot-tools` skill backend and returns captured screenshots as inline PNG images in supported terminals like Kitty.

## What it does

Registers:

- custom tool: `capture_screenshot`
- slash command: `/screenshot`
- fallback command: `/screenshot-icat`
- debug command: `/screenshot-debug`

The tool calls the bundled screenshot backend and, when a PNG was captured, returns it as a tool result image attachment.

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
/screenshot workspace current
/screenshot window kitty
/screenshot window-id 229
/screenshot list-windows
```

If no argument is given, `/screenshot` defaults to `active-window`.

Inside tmux, pi's TUI image rendering may not display reliably. In that case, use `/screenshot-icat` as the fallback.

## kitten icat fallback

Examples:

```text
/screenshot-icat
/screenshot-icat active-window
/screenshot-icat window kitty
/screenshot-icat window-id 229
```

This captures a screenshot and displays it via `kitten icat --stdin=no`. It is useful as a tmux fallback when pi's TUI image rendering path does not display images reliably. Because `icat` writes directly to the terminal outside pi's render loop, you may need to press `Esc` afterward to force pi to redraw cleanly.

## Debug command

Examples:

```text
/screenshot-debug
/screenshot-debug message
/screenshot-debug overlay
/screenshot-debug overlay active-window
```

This helps compare different pi image rendering paths when debugging terminal or tmux behavior.

## Exact window-id capture

After `/screenshot list-windows`, you can capture an exact entry by id:

```text
/screenshot window-id 229
/screenshot-icat window-id 229
```

## Notes

- In the package layout, this extension uses the bundled `skills/screenshot-tools` backend.
- It can also fall back to `~/.pi/agent/skills/screenshot-tools` during local development.
- The capture logic stays in the skill backend; this extension only adds inline image return/rendering support.
- After adding or changing the extension, run `/reload` in pi.
