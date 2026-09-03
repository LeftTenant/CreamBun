---
name: gotcha-screenshot-stale-when-window-unfocused
description: testing-sandbox screenshot silently returns a stale frame (missing the latest visual update) when the Godot window loses OS focus — properties read correctly, the PNG does not
metadata:
  type: project
---

When the Godot window spawned by `launch_game` is not the OS-frontmost window (macOS), the
`screenshot` tool can silently save/return a **stale** frame — it reflects the game's visual
state from *before* the window lost focus, not the current one. This happens even though
`get_node_property` reads on the same nodes correctly reflect the live, current state (`visible`,
`_current_tab`, a `ColorRect.color`, etc. are all accurate). There is no error; the tool reports
success and the PNG is well-formed, just outdated by one or more interactions.

**Symptom pattern observed:** after a `mouse_button_press`/`mouse_button_release` pair (both real
input to Godot, confirmed by the resulting property change), the very next `screenshot` — even
after `wait_frames(60)` — still shows the pre-interaction frame. Waiting longer does not fix it;
extra `wait_frames` calls are not the lever. Node-property reads and the screenshot can disagree
for many RPC calls in a row until focus is restored.

**First-open exception:** the *very first* screenshot after a fresh `launch_game` + first
notebook-open sometimes also comes back stale even with no mouse interaction yet — but a second
open (toggle closed, toggle open again) reliably self-heals without any focus fix. Root cause
likely the same (window not yet frontmost right after spawn); this "double-open" trick is a
cheap workaround when you don't want to shell out.

**How to detect:** don't trust `{"saved": path}` as proof of a correct capture. Spot-check by
reading the PNG back (or diffing pixel colors against the expected blend) — a `ColorRect` overlay
with alpha, e.g., either renders as the correctly blended color or is completely absent (0% blend,
not just "hard to see"); the latter is the tell.

**Fix:** force the Godot process to the front before any screenshot that follows mouse input:
```bash
osascript -e 'tell application "System Events" to tell process "Godot" to set frontmost to true'
```
Verify it actually took (macOS sometimes silently no-ops the first call):
```bash
osascript -e 'tell application "System Events" to get frontmost of process "Godot"'
```
If it reports `false`, retry — one retry was consistently enough in practice.  Do this once after
`launch_game`/`stop_game`+`launch_game`, and again after any `mouse_button_press`/`release` pair,
before the screenshot you intend to keep. Keyboard-driven scenarios (`press_action` only, no mouse)
did not reproduce this in a full session — the workaround is only needed once mouse input enters
the scenario.

Related: [[gotcha-synthetic-mouse-click-needs-motion]] (a different #41-era input gotcha — that one
is about `pressed` not firing; this one is about the *screenshot*, not the input, lagging).
