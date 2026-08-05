---
name: gotcha-custom-minimum-size-is-a-floor-not-ceiling
description: Control.custom_minimum_size only raises the rendered size (max() with the theme-driven intrinsic minimum); it cannot shrink a themed Button below its text/font/stylebox minimum
type: reference
---

`Control.get_combined_minimum_size()` is `max(custom_minimum_size, get_minimum_size())`, where
`get_minimum_size()` is the theme-driven intrinsic minimum (for a `Button`, driven by
text + font + stylebox content margins). Godot's `Control.set_size()` clamps up to this combined
minimum on every size assignment — including on scene load, for any `Control`, even one whose
parent is a plain `Control` and not a `Container`.

**Consequence:** setting `custom_minimum_size` to a value *smaller* than the current intrinsic
minimum has zero effect on the rendered size. Verified empirically on
`tests/e2e/testing-sandbox/fixtures/mouse_input_isolation.tscn`: a `Button` with `size =
Vector2(80, 24)` and no theme override actually renders at `(98, 31)` under Godot's default
engine theme (CreamBun's `base_theme.tres` is only applied via the Notebook's `Book` ancestor
theme cascade — a bare fixture `Control` outside that tree gets the built-in default theme).
Adding `custom_minimum_size = Vector2(80, 24)` to that same node changed nothing — still `(98,
31)` — because `80 < 98` and `24 < 31`, so the theme minimum still wins the `max()`.

**How to apply:** if an e2e/design doc needs a `Control`'s rendered rect to be a known, exact
value, either (a) measure the real intrinsic minimum first (get_node_property on `size` via the
testing-sandbox MCP after `wait_frames`, or read a committed baseline screenshot) and set
`custom_minimum_size` to *that* value to pin it deterministically, or (b) actually shrink the
intrinsic minimum itself (`clip_text = true` removes the text-width contribution but not the
line-height/stylebox-margin contribution to height; shrinking below the theme's stylebox margins
needs theme overrides). Do not assume a `custom_minimum_size` smaller than the current rendered
size will shrink anything — check empirically via the running game, not just by reading the
`.tscn`.

Related: `.claude/agent-memory/code-reviewer/gotcha_control_size_vs_theme_min_size.md` documents
the doc-side symptom (e2e docs quoting the `.tscn`'s inert `size` instead of the real rect).
