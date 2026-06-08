# Cave

> **Status: stub — not yet implemented**

## Description

Shade cells at the border to reveal an unshaded 'cave'. The cave must be connected; all shaded cells must be connected too.

## Files to create

- `board.lua` — game logic, puzzle generator, serialize/load
- `board_widget.lua` — grid rendering and tap gestures
- `screen.lua` — full-screen layout (buttons + board)
- `main.lua` — PluginBase entry point

## Notes

Grid-based logic puzzle — use GridWidgetBase from game-common.
