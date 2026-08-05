# Scenario: Settings tab — sliders render and reset restores defaults

Verifies the settings tab renders three audio sliders + text-speed slider
on the left page and a window-scale `OptionButton` on the right page, that
the underlying `_settings: GameSettings` values match the default state,
and that the per-page "Reset" buttons restore the defaults after the player
moves the sliders away from them.

Defaults from `GameSettings`:
- `master_volume = 1.0`, shown on slider as 100
- `music_volume = 1.0`, shown on slider as 100
- `sfx_volume = 1.0`, shown on slider as 100
- `text_speed = 1.0`, shown on slider as 100 (range 0–200)
- `window_scale = 4` default per `GameSettings`; the single shared reset
  button (`_on_reset_all_pressed`, node `ResetButton` on the right page)
  restores it to `4` along with all other settings. Both pre- and post-reset
  assertions read the current value rather than hardcoding.

Design doc reference: §5.5 (Settings tab).

NOTE: there is exactly one reset button in `settings_tab.tscn`
(`RightPage/ResetButton`, text "Reset to Defaults"). A previous revision of
this scenario had the reset split across two steps — one clicking a
"Reset Audio & Gameplay to Defaults" button that does not exist in the
current scene. That was a leftover from before the pixel-art-purist Slice 3
consolidation to a single shared reset button (see the SLICE 3 note in
`tests/integration/notebook/test_settings_tab_handlers.gd`). Fixed below:
there is now one reset step (Step 3) that presses the real `ResetButton` and
asserts every setting it restores in one press.

⚠️ Side-effect note: `_on_window_scale_changed` calls
`DisplayServer.window_set_size`. The reset step in this scenario will resize
the host window — that is the expected behaviour and the test deliberately
exercises it. Run this scenario last in a batch so the resize does not
interfere with other scenarios' screenshots.

TODO: strengthen this scenario by changing the window scale to a non-default
value (e.g. 2× or 8×) via the OptionButton popup **before** clicking
`ResetButton`. As written, `GameSettings.window_scale` already defaults to
`4` (index 1 in [2×, 4×, 6×, 8×]), so the reset is a no-op for window size
and the scenario does not actually exercise a mid-scenario
`DisplayServer.window_set_size` call. A pre-step that pops the OptionButton,
selects a different scale, then clicks a left-page slider in viewport
coords would prove that the testing-sandbox's per-call viewport→window
conversion in `plugins/godot-testing/godot/testing_server.gd:_viewport_to_window`
keeps mouse coords accurate across a live window resize — which is the case
this scenario is meant to be the canonical proof for.

Attempted live (2026-08-03) and backed out: clicking the OptionButton at its
on-screen centre produced no visible popup and left `.selected` unchanged,
but so did a repeat click on the Master Volume slider's leftmost edge in the
same session — i.e. mouse input was not registering on *any* control that
run, not something specific to OptionButton popups. This was **not** a
stuck/stale sandbox session — it was issue #41: `testing_server.gd`'s
`_cmd_mouse_button_release` sent the button-up event with no synthetic
`InputEventMouseMotion` immediately before it, leaving `BaseButton`'s
`pressing_inside` state stale at release time. Fixed on branch
`fix/41-e2e-mouse-input-not-registering` by priming a motion event at the
release position right before the button-up event (mirroring what
`_cmd_mouse_button_press` already did); see
`tests/e2e/testing-sandbox/mouse_input_isolation.md` for the isolated
regression guard. This scenario should be re-run against the fix to confirm
it also holds for a paused, in-notebook `Control`.

⚠️ STALE REFERENCE SCREENSHOTS (found 2026-08-03, not yet fixed): every
`.png` still committed under `tests/e2e/notebook/screenshots/settings_controls_*`
(`step_00_setup`, `step_01_defaults`, `step_02_sliders_moved`,
`step_02_master_zero`) predates the pixel-art-purist theme pass — they show
the old generic UI font and the old two-reset-button layout, not the current
monogram-themed single-`ResetButton` layout visible today. A real run of
this scenario would screenshot-diff-fail on every step, not just the ones
touched above. The two screenshots tied to the removed phantom-button step
(`step_03_left_reset`, `step_04_right_reset`) were deleted as part of this
pass since the step they illustrated no longer exists; the remaining four
still need to be regenerated from a real run before this scenario's
screenshot comparisons can be trusted again.

## Setup
- Load scene: `res://world/world.tscn`
- Wait: 10 frames
- Press action: `open_notebook_inventory`
- Wait: 5 frames
- Press action: `notebook_page_next`     # INVENTORY → MAP
- Wait: 5 frames
- Press action: `notebook_page_next`     # MAP → QUESTS
- Wait: 5 frames
- Press action: `notebook_page_next`     # QUESTS → SETTINGS
- Wait: 15 frames
- Assert: node property `Notebook._current_tab` == `3` (SETTINGS)

## Steps

### Step 1: Defaults populated on both pages
- Screenshot → save / compare reference: `settings_controls_step_01_defaults.png`
- Assert: the left page contains three HSlider children whose `value` is `100.0`
  (Master, Music, SFX volume — each stored as 1.0 in `GameSettings` and
  multiplied by 100 for the slider widget).
- Assert: the left page also contains an HSlider for Text Speed with `value`
  == `100.0` (Text Speed is 1.0 * 100).
- Assert: the right page contains an `OptionButton` with `item_count` == 4
  ("2× / 4× / 6× / 8×"). Record its current `selected` index for comparison
  after the reset.

### Step 2: Move sliders away from their defaults
**2a — Master Volume to 0**
- Mouse move to: leftmost edge of the Master Volume HSlider
- Mouse button press: `LEFT`
- Mouse button release: `LEFT`
- Wait: 5 frames
- Assert: the Master Volume slider's `value` is `0.0`
  (click on the leftmost edge drives the thumb to the slider minimum)
- Assert: `SettingsTab._settings.master_volume` reads as `0.0`

**2b — Text Speed to 0**
- Mouse move to: leftmost edge of the Text Speed HSlider
- Mouse button press: `LEFT`
- Mouse button release: `LEFT`
- Wait: 5 frames
- Screenshot → save / compare reference: `settings_controls_step_02_sliders_moved.png`
- Assert: the Text Speed slider's `value` is `0.0`
  (clicking the leftmost edge drives the thumb to the slider minimum of 0)
- Assert: `SettingsTab._settings.text_speed` reads as `0.0`
  (this is the assertion that would have caught the bug where `_text_speed_slider`
  was a local variable and the reset handler could not update the widget)

### Step 3: Click "Reset to Defaults" (the single shared reset button)
- Mouse move to: centre of the "Reset to Defaults" button (`ResetButton`) on
  the right page — this is the single shared button that resets ALL settings
  (audio volumes, text speed, and window scale) via `_on_reset_all_pressed`
- Mouse button press: `LEFT`
- Mouse button release: `LEFT`
- Wait: 15 frames     # window resize happens here; let it settle
- Screenshot → save / compare reference: `settings_controls_step_03_shared_reset.png`
- Assert: all three volume sliders are back to `value == 100.0`
- Assert: the Text Speed slider widget `value` is exactly `100.0`
  (not "approximately default" — the reset handler must explicitly set
  `_text_speed_slider.value = 100.0`; a value of `0.0` here is the failure mode
  the scenario was previously unable to detect)
- Assert: `SettingsTab._settings.master_volume` == `1.0`
- Assert: `SettingsTab._settings.music_volume` == `1.0`
- Assert: `SettingsTab._settings.sfx_volume` == `1.0`
- Assert: `SettingsTab._settings.text_speed` == `1.0`
  (data model must be restored alongside the widget)
- Assert: the window-scale `OptionButton.selected` == `1` (index for "4×" — the default in [2×,4×,6×,8×])
- Assert: `SettingsTab._settings.window_scale` == `4`
