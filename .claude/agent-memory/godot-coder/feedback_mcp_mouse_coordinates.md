---
name: mcp-mouse-coordinates-window-space
description: MCP testing-sandbox mouse coords are OS-window pixels, not logical viewport pixels — scale by window/viewport ratio
metadata:
  type: feedback
---

MCP `mouse_button_press` / `mouse_button_release` / `mouse_move` x/y values are in **OS window pixel space**, not logical render-viewport space. `Input.parse_input_event` receives the event in window coords; Godot maps it to the viewport internally.

**Why:** if you read a coordinate off a viewport-sized screenshot and pass it straight to the MCP call while the window is larger than the render viewport, the click lands at `coord ÷ scale` in the scene and misses its target — making a working feature look broken.

**How to apply:** convert logical/viewport coordinates to window coordinates before sending them, using the current scale factor:

    scale = current_window_size / render_viewport_size

Do not hardcode the factor — this project's render viewport (`display/window/size/viewport_*`) and the window are decoupled, and the window is user-resizable through the Settings window-scale option, so the ratio changes at runtime. Read the live window size (`DisplayServer.window_get_size()`) and the viewport size rather than assuming a fixed multiple. When authoring an e2e scenario, capture the screenshot and the window size together and document the coordinate space the scenario assumes.

See also: [[testing-sandbox-stdout-devnull]] — stdout is also discarded, so print() diagnostics are invisible via MCP.
