---
name: mcp-mouse-coordinates-2x
description: MCP testing-sandbox mouse coords must be OS window coords (2×), not logical viewport coords
metadata:
  type: feedback
---

MCP `mouse_button_press` x/y values must be in **OS window space**, not logical viewport space.

This project uses `viewport_width=640, viewport_height=480` with `window_width_override=1280, window_height_override=960` and `stretch mode="viewport"`. The OS window is 2× the logical canvas. `Input.parse_input_event` receives the event in OS coords; Godot then maps it to viewport coords internally.

**Why:** Clicking at logical y=87 via MCP (which sends `position = Vector2(x, 87)`) lands at logical y=43 in the scene, missing the row entirely. The row never gets selected. This makes features look broken when they actually work fine.

**How to apply:** Always multiply logical screenshot coordinates by 2 when passing to `mouse_button_press` / `mouse_button_release` / `mouse_move`. E.g. a row visible at y=87 in a 640×480 screenshot needs y=174 in the MCP call. This is also why early e2e tests must document their coordinate assumptions.

See also: [[testing-sandbox-stdout-devnull]] — stdout is also discarded, so print() diagnostics are invisible via MCP.
