---
name: gotcha-synthetic-mouse-click-needs-motion
description: Injected mouse clicks need an InputEventMouseMotion before BOTH the press and release event, or BaseButton.pressed fires only intermittently
metadata:
  type: project
---

In the testing-sandbox plugin (`plugins/godot-testing/godot/testing_server.gd`), every
synthetic `InputEventMouseButton` sent via `Input.parse_input_event()` must be preceded by
an `InputEventMouseMotion` at the same position — for the **release** as well as the press.

**Why:** `BaseButton` only emits `pressed` when `status.press_attempt && status.pressing_inside`
are both true at button-up. `pressing_inside` is (re)computed from motion events and cleared by
`NOTIFICATION_MOUSE_EXIT`, which `Viewport`'s hover bookkeeping can fire between an injected
press and release (the developer's *real* physical pointer is also feeding the same viewport).
Priming with a motion event at the release point restores that state deterministically. Symptom
when missing: `button_down` / `button_up` fire reliably on every injected click while `pressed`
(and `button_pressed` for a toggle button) fires on some cycles and not others.

**How to apply:**
- When reviewing or writing e2e mouse scenarios, `button_down_count` / `button_up_count`
  incrementing is **not** evidence that a click completed — always assert on `pressed`/
  `button_pressed`, and assert across **two** consecutive click cycles, since the failure mode
  is intermittent and a single cycle can pass by luck.
- When reviewing changes to the sandbox's input-injection handlers, check press/release/move
  for **symmetry**: an asymmetry between the press and release paths is the first thing to
  suspect for flaky GUI input.
- The synthetic motion sets `position`/`global_position` only — `relative` stays `(0,0)` and
  `button_mask` stays empty. A real OS motion during a held drag carries the button mask, so
  drag-and-drop paths that gate on `mm->get_button_mask()` still do not see injected motion as
  a drag. Keep that in mind before assuming injected drags behave like real ones.
- Do **not** justify this in comments as "the OS always sends a motion event before a button
  event" — a stationary click emits no motion event on X11/Windows/macOS. The real reason is
  the stale hover / `pressing_inside` state above.
- **The release-side fix explains `Button`/`BaseButton` symptoms only.** `Slider` (`HSlider`/
  `VSlider`) sets its value from the click position in `gui_input` on mouse-button-**down**
  (`Slider::gui_input` calls `set_as_ratio()` in the `is_pressed()` branch), so a slider that
  didn't move on an injected click means the button-down GUI event never reached it — a
  *different* failure (usually a click coordinate derived from an inert `.tscn` `size`, see
  [[gotcha-control-size-vs-theme-min-size]]). Don't let a doc attribute a stuck-slider session to
  this `pressing_inside` root cause without re-running it.

Related: [[testing-conventions]], [[project-patterns]].
