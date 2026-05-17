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
- `window_scale = 4` initially per `GameSettings`; left-page reset does not
  touch the option; right-page reset restores it to `2` per
  `_on_reset_right_pressed`. Both pre- and post-reset assertions read the
  current value rather than hardcoding.

Design doc reference: §5.5 (Settings tab).

⚠️ Side-effect note: `_on_window_scale_changed` calls
`DisplayServer.window_set_size`. The right-page reset step in this scenario
will resize the host window — that is the expected behaviour and the test
deliberately exercises it. Run this scenario last in a batch so the resize
does not interfere with other scenarios' screenshots.

TODO: strengthen this scenario by changing the window scale to a non-default
value (e.g. 1× or 4×) via the OptionButton popup **before** clicking the
right-page reset. As written, `GameSettings.window_scale` already defaults
to `2`, so the right-page reset is a no-op for window size and the scenario
does not actually exercise a mid-scenario `DisplayServer.window_set_size`
call. Adding a pre-step that pops the OptionButton, selects a different
scale, then clicks a left-page slider in viewport coords would prove that
the testing-sandbox's per-call viewport→window conversion in
`plugins/godot-testing/godot/testing_server.gd:_viewport_to_window` keeps
mouse coords accurate across a live window resize — which is the case this
scenario is meant to be the canonical proof for.

## Setup
- Load scene: `res://world/world.tscn`
- Wait: 10 frames
- Press action: `open_notebook_inventory`
- Wait: 5 frames
- Press action: `ui_focus_next`     # INVENTORY → MAP
- Wait: 5 frames
- Press action: `ui_focus_next`     # MAP → QUESTS
- Wait: 5 frames
- Press action: `ui_focus_next`     # QUESTS → SETTINGS
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
  ("1× / 2× / 3× / 4×"). Record its current `selected` index for comparison
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

### Step 3: Click "Reset Audio & Gameplay to Defaults"
- Mouse move to: centre of the "Reset Audio & Gameplay to Defaults" button
- Mouse button press: `LEFT`
- Mouse button release: `LEFT`
- Wait: 10 frames
- Screenshot → save / compare reference: `settings_controls_step_03_left_reset.png`
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

### Step 4: Click "Reset Display to Defaults"
- Mouse move to: centre of the "Reset Display to Defaults" button on the right
  page
- Mouse button press: `LEFT`
- Mouse button release: `LEFT`
- Wait: 15 frames     # window resize happens here; let it settle
- Screenshot → save / compare reference: `settings_controls_step_04_right_reset.png`
- Assert: the window-scale `OptionButton.selected` == `1` (index for "2×")
- Assert: `SettingsTab._settings.window_scale` == `2`
