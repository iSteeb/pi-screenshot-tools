# Changelog

## Unreleased

### Changed

- On Sway and Hyprland, `window` and `window-id` now automatically visit the target workspace, focus the window, capture it, and return to the original workspace when needed
- Include window visibility and workspace/monitor context in window listings and match metadata
- Clarify in docs that compositor window capture is screen-region based, not hidden-surface capture

## 0.1.0

Initial release.

### Added

- Cross-desktop screenshot skill for pi
- Sway/wlroots backend using `grim`, `slurp`, `swaymsg`, and `jq`
- Hyprland backend using `grim`, `slurp`, `hyprctl`, and `jq`
- GNOME Wayland fallback for full-screen and region capture
- X11 fallback for full-screen, region, and active-window capture
- Window, output, and workspace listing
- Window ambiguity detection and ranked matching
- Structured JSON output with image metadata
- README documentation and embedded session screenshot
