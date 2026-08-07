---
name: gotcha-control-size-vs-theme-min-size
description: A Control's authored `size` in a .tscn is silently grown to the theme's combined minimum size, so e2e docs must measure the real rect, not copy the .tscn value
metadata:
  type: project
---

`size = Vector2(w, h)` on a `Control` in a `.tscn` is **not** authoritative. Godot clamps a
Control's size up to `get_combined_minimum_size()`, which for a `Button` is driven by its text,
font and theme stylebox margins. A `Button` authored `size = Vector2(80, 24)` with the default
theme at CreamBun's 320×180 viewport actually renders ~98×31.

**Why:** e2e scenario docs (`tests/e2e/**/*.md`) state click targets as viewport-space rects and
centres. When those numbers are transcribed from the `.tscn`'s `size` line rather than measured,
the doc's "centre" is not the real centre. The scenario can still pass (the stated point is often
inside the larger real rect), so nothing catches the drift — until someone re-derives a coordinate
from the documented rect, or the theme/font changes.

**How to apply:**
- When reviewing an e2e scenario that names a Control rect, verify it against a real measurement,
  not the `.tscn`. Fast check: open the committed baseline screenshot and measure the non-background
  bounding box, then divide by the window/viewport scale factor (window override is 1280×720 over a
  320×180 viewport = 4×, so a 1280×720 capture divides by 4).
- Prefer `custom_minimum_size` (or an explicit anchors/offsets layout) in the fixture when a
  scenario depends on an exact rect — that makes the authored number real instead of advisory.
- Flag a bare `size = ...` on a themed Control in a fixture as inert data if a doc quotes it.
- `custom_minimum_size` is a **floor, not a ceiling** — setting it to the measured size stops the
  rect shrinking but not growing, so reject doc wording like "pinned / deterministic / no longer
  depends on the font". The only way to make a documented rect self-verifying is an explicit
  `size` assertion in the scenario's Setup.
- To verify a documented rect independently: measure the non-background bbox of the committed
  baseline `.png` and divide by the capture scale (1280×720 capture / 320×180 viewport = 4×).

Related: [[gotcha-synthetic-mouse-click-needs-motion]], [[testing-conventions]],
[[gotcha-tscn-default-valued-props]].
