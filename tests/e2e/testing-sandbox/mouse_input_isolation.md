# Scenario: Sandbox mouse input reaches a non-paused Control (issue #41)

Isolation regression guard for the testing-sandbox plugin's mouse commands
(`mouse_move`, `mouse_button_press`, `mouse_button_release` — implemented in
`plugins/godot-testing/godot/testing_server.gd`). Drives a throwaway,
never-paused `Button` fixture and asserts on its own click/hover counters and
`button_pressed` toggle state, entirely independent of the notebook or any
other game feature.

This scenario exists because every interactive `Control` currently in
CreamBun lives inside the Notebook, which sets `get_tree().paused = true`
while open (`ui/notebook/notebook.gd` `open()`) — so the real-world symptom in
`tests/e2e/notebook/settings_controls.md` (slider drag / `OptionButton` press
never registering) has never been isolated from that pause. This fixture has
no pause involvement at all, so a failure here proves the bug is in the
sandbox's input-injection plumbing itself, not (or not only) in
pause/process_mode interaction.

Fixture: `tests/e2e/testing-sandbox/fixtures/mouse_input_isolation.tscn` +
`mouse_input_isolation_button.gd`. The `TestButton` is a `toggle_mode` Button
positioned at (120, 70). A `Control`'s authored `size` in a `.tscn` is not
authoritative — Godot clamps it up to `get_combined_minimum_size()`, which
for a themed `Button` depends on its text/font/stylebox margins. This
fixture has no theme override, so under the default engine theme "Test
Button" actually renders at 98×31, not the 80×24 the old `size` line alone
implied. `custom_minimum_size` is set explicitly to `Vector2(98, 31)` to
match and pin that real size, so it is deterministic rather than an
incidental side effect of the current default font. The button's true
viewport rect is therefore (120, 70)–(218, 101), centre (169, 85) — the
coordinates the steps below click. It exposes four counters (`hover_count`,
`button_down_count`, `button_up_count`, `click_count`) plus the inherited
`button_pressed` toggle state, so every stage of a click is independently
assertable via `get_node_property` without depending on screenshot
comparison.

Test plan: `docs/features/testing-sandbox/issue-41-mouse-input-test-plan.md`.

✅ STATUS (2026-08-04): fixed on branch `fix/41-e2e-mouse-input-not-registering`.
`_cmd_mouse_button_release` in `plugins/godot-testing/godot/testing_server.gd`
now sends a synthetic `InputEventMouseMotion` at the release position
immediately before the button-up event, mirroring `_cmd_mouse_button_press`.
Re-run live against the fix: all three steps pass, including two consecutive
click cycles (Step 2 then Step 3) — `click_count` reaches `1` then `2`,
`button_pressed` flips `true` then back to `false`, matching
`button_down_count`/`button_up_count` on every cycle.

**Pre-fix symptom (2026-08-04, run against `main` commit `7665d93`):** raw
`button_down`/`button_up` counters incremented reliably on every injected
click, but the `pressed` signal completed on only some click cycles, not
consistently zero or all — see issue #41 for the full investigation.

## Setup
- Stop game (if running) — start from a guaranteed-fresh, guaranteed-unpaused
  process rather than relying on `reset_state`, which reloads the current
  scene but does not touch `get_tree().paused`. A full relaunch is the only
  way to be certain this scenario starts unpaused, which matters because its
  whole job is to prove the sandbox's mouse plumbing works on its own terms,
  independent of any pause state.
- Launch game
- Load scene: `res://tests/e2e/testing-sandbox/fixtures/mouse_input_isolation.tscn`
- Wait: 10 frames
- Assert: node property `TestButton.click_count` == `0`
- Assert: node property `TestButton.button_pressed` == `false`
- Assert: node property `TestButton.hover_count` == `0`

## Steps

### Step 1: `mouse_move` alone registers hover before any click
- Mouse move to: `(169, 85)` (centre of `TestButton`)
- Wait: 5 frames
- Assert: node property `TestButton.hover_count` == `1`
  (isolates whether pointer motion reaches GUI dispatch at all, independent
  of button press/release — a hover failure here would mean the bug is in
  motion-event routing, not click routing specifically)

### Step 2: full press + release registers a click and flips `button_pressed`
- Mouse button press: `LEFT` at `(169, 85)`
- Wait: 3 frames
- Assert: node property `TestButton.button_down_count` == `1`
  (this counter reliably reached 1 on every injected click even before the
  fix — issue #41 was never a routing failure at this stage; no signal bus,
  no autoload, nothing but BaseButton's own GUI input handling between the
  injected event and this counter)
- Mouse button release: `LEFT` at `(169, 85)`
- Wait: 5 frames
- Screenshot → save / compare reference: `mouse_input_isolation_step_02_after_click.png`
  (visual sanity only — the hard assertions below are the actual pass/fail
  gate)
- Assert: node property `TestButton.button_up_count` == `1`
- Assert: node property `TestButton.click_count` == `1`
- Assert: node property `TestButton.button_pressed` == `true`

### Step 3: a second, independent click also registers
- Mouse button press: `LEFT` at `(169, 85)`
- Wait: 3 frames
- Mouse button release: `LEFT` at `(169, 85)`
- Wait: 5 frames
- Assert: node property `TestButton.click_count` == `2`
- Assert: node property `TestButton.button_down_count` == `2`
- Assert: node property `TestButton.button_up_count` == `2`
- Assert: node property `TestButton.button_pressed` == `false`
  (toggle_mode flips back off on the second full click — proves the first
  pass wasn't a one-shot fluke in either direction)

## Reporting note

Issue #41 is confirmed fixed: this scenario has been re-run live end to end
and all three steps pass. `mouse_input_isolation_step_02_after_click.png`
under `tests/e2e/testing-sandbox/screenshots/` is the committed baseline from
that passing run, captured the same way as any other scenario's reference
screenshot.
