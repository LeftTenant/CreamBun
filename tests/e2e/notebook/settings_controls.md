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

### Step 2: Move the master volume slider to 0
- Mouse move to: leftmost edge of the Master Volume HSlider
- Mouse button press: `LEFT`
- Mouse button release: `LEFT`
- Wait: 5 frames
- Screenshot → save / compare reference: `settings_controls_step_02_master_zero.png`
- Assert: the Master Volume slider's `value` is `0.0`
  (the click on the leftmost edge drags the thumb to the slider minimum)
- Assert: the active `SettingsTab._settings.master_volume` reads as `0.0`

### Step 3: Click "Reset Audio & Gameplay to Defaults"
- Mouse move to: centre of the "Reset Audio & Gameplay to Defaults" button
- Mouse button press: `LEFT`
- Mouse button release: `LEFT`
- Wait: 10 frames
- Screenshot → save / compare reference: `settings_controls_step_03_left_reset.png`
- Assert: all three volume sliders are back to `value == 100.0`
- Assert: the Text Speed slider is back to `value == 100.0`
- Assert: `SettingsTab._settings.master_volume` == `1.0`
- Assert: `SettingsTab._settings.music_volume` == `1.0`
- Assert: `SettingsTab._settings.sfx_volume` == `1.0`
- Assert: `SettingsTab._settings.text_speed` == `1.0`

### Step 4: Click "Reset Display to Defaults"
- Mouse move to: centre of the "Reset Display to Defaults" button on the right
  page
- Mouse button press: `LEFT`
- Mouse button release: `LEFT`
- Wait: 15 frames     # window resize happens here; let it settle
- Screenshot → save / compare reference: `settings_controls_step_04_right_reset.png`
- Assert: the window-scale `OptionButton.selected` == `1` (index for "2×")
- Assert: `SettingsTab._settings.window_scale` == `2`
