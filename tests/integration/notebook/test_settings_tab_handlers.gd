## test_settings_tab_handlers.gd
## Integration tests for SettingsTab signal handlers.
##
## WHAT THESE TESTS GUARD
## ----------------------
## settings_tab.gd resolves slider and option-button references via
## get_node("MasterSlider") etc. on the scene-built settings_tab.tscn. These tests
## confirm the handler side-effects (AudioServer bus volume, DisplayServer window
## size, _settings data model, widget state) behave correctly when driven through
## those named nodes.
##
## WHY THIS IS AN INTEGRATION FILE (not unit)
## ------------------------------------------
## Handler tests must drive a SettingsTab that is wired into a real parent Control
## so the slider's value_changed signal propagates to the handler and
## AudioServer / DisplayServer calls can be verified. A pure unit test of
## _on_master_volume_changed() would call the private method directly and miss
## signal-wiring bugs.
##
## --- SLICE 5 DATA SOURCE NOTE ---
## SettingsTab._settings now IS SaveManager.settings (the same object, not a
## copy — design §11 Step 4). before_each() gives SaveManager.settings a fresh
## default GameSettings before each test, and after_each() clears it back to
## null, so:
##   a) the populated tab in this file always starts from documented defaults
##      regardless of what an earlier test in this file (or another suite) left
##      SaveManager.settings holding, and
##   b) reset assertions that check SaveManager.settings directly (in addition
##      to _tab._settings) prove the reset writes through to the shared
##      instance, not just an in-memory copy held by the tab.
##
## Requires GUT: https://github.com/bitwes/Gut
## Install via Godot Asset Library (search "GUT - Godot Unit Testing").
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd -gselect=test_settings_tab_handlers.gd -gexit

class_name TestSettingsTabHandlers
extends GutTest


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const SCENE_PATH: String = "res://ui/notebook/settings/settings_tab.tscn"

# The tolerance used when comparing AudioServer dB values. linear_to_db can
# produce floating-point noise in the last few ULPs, so exact equality would
# be fragile; 0.01 dB is imperceptible and safe.
const DB_TOLERANCE: float = 0.01


# ---------------------------------------------------------------------------
# Setup / Teardown
# ---------------------------------------------------------------------------

## The SettingsTab under test, added as a child of the test scene.
var _tab: SettingsTab

## Disposable parent Control used as the populate target for both pages.
var _left_parent: Control
var _right_parent: Control


func before_each() -> void:
	# Slice 5: SettingsTab._settings now sources from SaveManager.settings (the
	# same object, not a copy). Reset it to documented defaults BEFORE
	# instantiating the tab so populate_left/right render the defaults this
	# file's tests expect, regardless of what an earlier test left behind.
	SaveManager.settings = GameSettings.new()

	# Instantiate the scene (rather than SettingsTab.new()) so @onready and
	# named-node lookups inside the script work exactly as they will in-game.
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	_tab = packed.instantiate() as SettingsTab
	add_child_autofree(_tab)

	# Provide real parent Controls so the VBoxContainer that populate_left /
	# populate_right creates has a rect to anchor into. Without a rect,
	# get_global_rect() would be zero-sized and slider layout assertions would
	# be meaningless (though these tests do not assert layout).
	_left_parent = Control.new()
	_left_parent.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(_left_parent)

	_right_parent = Control.new()
	_right_parent.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(_right_parent)

	_tab.populate_left(_left_parent)
	_tab.populate_right(_right_parent)


func after_each() -> void:
	# Autofree handles node cleanup. Clear SaveManager.settings so this file
	# does not leak a stale instance into later suites.
	SaveManager.settings = null


# ---------------------------------------------------------------------------
# Helper — resolve a named node from the populated left-page tree
# ---------------------------------------------------------------------------

## Find a named descendant of parent. Returns null if not found.
##
## We use find_child on the parent (not _tab) because populate_left() adds the
## scene subtree to parent, not to _tab directly.
##
## @param parent    the Control populate_left / populate_right added children to
## @param node_name the stable node name to look up
func _get_named_node(parent: Control, node_name: String) -> Node:
	return parent.find_child(node_name, true, false)


# ---------------------------------------------------------------------------
# Test 1 — Master volume slider drives AudioServer bus 0
# ---------------------------------------------------------------------------

func test_master_slider_drives_audio_bus_0() -> void:
	# Moving the master volume slider to 0 must call
	# AudioServer.set_bus_volume_db(0, linear_to_db(0.0)), which is -inf dB
	# in practice. We verify indirectly by reading back the bus volume.
	#
	# Bus index 0 is always the Master bus in Godot's default audio layout.
	# https://docs.godotengine.org/en/stable/classes/class_audioserver.html
	var slider: Node = _get_named_node(_left_parent, "MasterSlider")
	assert_not_null(slider,
			"MasterSlider must exist in the populated left-page tree")
	if slider == null:
		return

	var master_slider: HSlider = slider as HSlider
	master_slider.value = 0.0

	# Allow the signal propagation to settle.
	await get_tree().process_frame

	var expected_db: float = linear_to_db(0.0)
	var actual_db: float = AudioServer.get_bus_volume_db(0)
	assert_almost_eq(actual_db, expected_db, DB_TOLERANCE,
			"AudioServer bus 0 volume must be %.2f dB after master slider → 0; got %.2f dB" % [
					expected_db, actual_db])


# ---------------------------------------------------------------------------
# Test 2 — Music volume slider drives AudioServer bus 1 (guarded by bus count)
# ---------------------------------------------------------------------------

func test_music_slider_drives_audio_bus_1() -> void:
	# Bus index 1 is the Music bus by project convention. The handler guards
	# against this bus not existing (Phase 1 may not have extra buses), so we
	# mirror that guard here: if bus 1 is absent, skip the dB assertion but
	# still verify the slider and _settings update happen.
	var slider: Node = _get_named_node(_left_parent, "MusicSlider")
	assert_not_null(slider,
			"MusicSlider must exist in the populated left-page tree")
	if slider == null:
		return

	var music_slider: HSlider = slider as HSlider
	music_slider.value = 50.0

	await get_tree().process_frame

	# _settings.music_volume is public; verify the data model updated.
	assert_almost_eq(_tab._settings.music_volume, 0.5, 0.001,
			"_settings.music_volume must be 0.5 after MusicSlider → 50")

	if AudioServer.get_bus_count() > 1:
		var expected_db: float = linear_to_db(0.5)
		var actual_db: float = AudioServer.get_bus_volume_db(1)
		assert_almost_eq(actual_db, expected_db, DB_TOLERANCE,
				"AudioServer bus 1 must be %.2f dB after MusicSlider → 50; got %.2f dB" % [
						expected_db, actual_db])
	else:
		gut.p("Skipping AudioServer bus 1 assertion — bus count is %d" % AudioServer.get_bus_count())


# ---------------------------------------------------------------------------
# Test 3 — SFX volume slider drives AudioServer bus 2 (guarded by bus count)
# ---------------------------------------------------------------------------

func test_sfx_slider_drives_audio_bus_2() -> void:
	# Mirrors test 2 for the SFX bus (index 2).
	var slider: Node = _get_named_node(_left_parent, "SfxSlider")
	assert_not_null(slider,
			"SfxSlider must exist in the populated left-page tree")
	if slider == null:
		return

	var sfx_slider: HSlider = slider as HSlider
	sfx_slider.value = 75.0

	await get_tree().process_frame

	assert_almost_eq(_tab._settings.sfx_volume, 0.75, 0.001,
			"_settings.sfx_volume must be 0.75 after SfxSlider → 75")

	if AudioServer.get_bus_count() > 2:
		var expected_db: float = linear_to_db(0.75)
		var actual_db: float = AudioServer.get_bus_volume_db(2)
		assert_almost_eq(actual_db, expected_db, DB_TOLERANCE,
				"AudioServer bus 2 must be %.2f dB after SfxSlider → 75; got %.2f dB" % [
						expected_db, actual_db])
	else:
		gut.p("Skipping AudioServer bus 2 assertion — bus count is %d" % AudioServer.get_bus_count())


# ---------------------------------------------------------------------------
# Test 4 — WindowScaleOption calls DisplayServer.window_set_size
# ---------------------------------------------------------------------------

func test_window_scale_option_calls_display_server() -> void:
	# Selecting a window scale option must call DisplayServer.window_set_size
	# with the correct pixel dimensions derived from the project viewport size.
	# We pick index 0 (2× — the minimum) because it produces the smallest window
	# and is unlikely to cause issues on CI machines with restricted screen sizes.
	# Note: WINDOW_SCALE_OPTIONS = [2, 4, 6, 8]; there is no 1× option.
	#
	# DisplayServer.window_set_size docs:
	# https://docs.godotengine.org/en/stable/classes/class_displayserver.html#class-displayserver-method-window-set-size
	var option: Node = _get_named_node(_right_parent, "WindowScaleOption")
	assert_not_null(option,
			"WindowScaleOption must exist in the populated right-page tree")
	if option == null:
		return

	var opt_btn: OptionButton = option as OptionButton

	# Derive expected size from project settings — mirrors the handler's own math
	# (_scaled_window_size in settings_tab.gd). Fallbacks match the project's
	# actual 320×180 base viewport (not the old 640×360 values).
	var base_width: int = ProjectSettings.get_setting(
			"display/window/size/viewport_width", 320) as int
	var base_height: int = ProjectSettings.get_setting(
			"display/window/size/viewport_height", 180) as int
	# Read the actual scale for index 0 from the source of truth rather than
	# hardcoding 2, so this test stays correct if the options array ever changes.
	var expected_scale: int = SettingsTab.WINDOW_SCALE_OPTIONS[0]
	var expected_size: Vector2i = Vector2i(base_width * expected_scale, base_height * expected_scale)

	# Emit the signal as the player would by selecting index 0 (2× — the minimum).
	# item_selected is only emitted on user interaction, not programmatic select(),
	# so we emit it directly to test the handler in isolation.
	# https://docs.godotengine.org/en/stable/classes/class_optionbutton.html#signal-item-selected
	opt_btn.item_selected.emit(0)

	await get_tree().process_frame

	# The _settings model update must happen unconditionally — mirrors the
	# pattern in test_music_slider_drives_audio_bus_1/2, which assert the
	# _settings side of the handler before their own environment-guarded
	# hardware check below. Without this, the test asserted nothing at all
	# under headless CI (the only environment GUT actually runs in here).
	assert_eq(_tab._settings.window_scale, expected_scale,
			"_settings.window_scale must be %d after selecting index 0 (2×); got %d" % [
					expected_scale, _tab._settings.window_scale])

	# DisplayServer.window_get_size() always returns (0, 0) in headless mode
	# because there is no OS window to query. Godot's headless DisplayServer is
	# a no-op stub; window_set_size() was still called (that is what we care
	# about), but the readback is meaningless. Skip the size assertion rather
	# than asserting (0, 0) == expected_size, which would be a false failure.
	# https://docs.godotengine.org/en/stable/classes/class_displayserver.html#class-displayserver-method-get-name
	if DisplayServer.get_name() == "headless":
		pending("DisplayServer.window_get_size() is not meaningful in headless mode — skipping size readback")
		return

	var actual_size: Vector2i = DisplayServer.window_get_size()
	assert_eq(actual_size, expected_size,
			"DisplayServer.window_get_size() must be %s after selecting 2× scale (index 0); got %s" % [
					str(expected_size), str(actual_size)])


# ---------------------------------------------------------------------------
# Test 5 — Single shared reset button restores all sliders to default values
# ---------------------------------------------------------------------------
#
# NOTE (Slice 3, pixel-art-purist): Per-page reset buttons were replaced by a
# SINGLE "Reset to Defaults" button on the RightPage. TextSpeedSlider also
# moved from the left page to the right page. This test was updated to:
#   - Look for TextSpeedSlider in _right_parent (not _left_parent)
#   - Look for the reset button in _right_parent (not _left_parent)
#   - Assert all settings across both pages are restored in one press

func test_shared_reset_restores_all_slider_defaults() -> void:
	# The single shared reset button (on the right page) must restore all five
	# settings — master/music/sfx volume, text speed, AND window scale — to their
	# defaults, updating both widget state and _settings / SaveManager.settings.
	# We first move each away from its default so the reset is observable.
	var master_node: Node = _get_named_node(_left_parent, "MasterSlider")
	var music_node: Node = _get_named_node(_left_parent, "MusicSlider")
	var sfx_node: Node = _get_named_node(_left_parent, "SfxSlider")
	# TextSpeedSlider and WindowScaleOption both live on the right page (Slice 3).
	var text_speed_node: Node = _get_named_node(_right_parent, "TextSpeedSlider")
	var window_scale_node: Node = _get_named_node(_right_parent, "WindowScaleOption")

	for named: Array in [
		["MasterSlider (left)", master_node],
		["MusicSlider (left)", music_node],
		["SfxSlider (left)", sfx_node],
		["TextSpeedSlider (right)", text_speed_node],
		["WindowScaleOption (right)", window_scale_node],
	]:
		assert_not_null(named[1],
				"%s must exist in its respective populated tree" % named[0])

	if master_node == null or music_node == null or sfx_node == null \
			or text_speed_node == null or window_scale_node == null:
		return

	(master_node as HSlider).value = 30.0
	(music_node as HSlider).value = 40.0
	(sfx_node as HSlider).value = 50.0
	(text_speed_node as HSlider).value = 60.0
	# Move window scale away from default (index 1 = 4×) to index 0 (2× — the minimum).
	# Note: there is no 1× option any more; index 0 = 2×, index 1 = 4× (default).
	(window_scale_node as OptionButton).selected = 0
	SaveManager.settings.window_scale = 2
	await get_tree().process_frame

	# Find and press the single shared reset button. It lives on the right page
	# (RightPage VBoxContainer), so search _right_parent. The button is identified
	# by type (Button, not OptionButton) and its pressed signal is emitted directly
	# to avoid needing screen coordinates.
	var reset_btn: Button = null
	for child: Node in _right_parent.find_children("*", "Button", true, false):
		if child is Button and not child is OptionButton:
			reset_btn = child as Button
			break

	assert_not_null(reset_btn,
			"A reset Button must exist inside the right-page populated tree (single shared reset)")
	if reset_btn == null:
		return

	reset_btn.pressed.emit()
	await get_tree().process_frame

	# Widget state — sliders
	assert_almost_eq((master_node as HSlider).value, 100.0, 0.001,
			"MasterSlider.value must be 100.0 after shared reset")
	assert_almost_eq((music_node as HSlider).value, 100.0, 0.001,
			"MusicSlider.value must be 100.0 after shared reset")
	assert_almost_eq((sfx_node as HSlider).value, 100.0, 0.001,
			"SfxSlider.value must be 100.0 after shared reset")
	assert_almost_eq((text_speed_node as HSlider).value, 100.0, 0.001,
			"TextSpeedSlider.value must be 100.0 after shared reset")

	# Widget state — OptionButton. Index 1 == 4× (the default scale in [2,4,6,8]).
	# Note: the options are [2×, 4×, 6×, 8×]; index 0 = 2× (minimum), index 1 = 4× (default).
	assert_eq((window_scale_node as OptionButton).selected, 1,
			"WindowScaleOption.selected must be 1 (4× default in [2,4,6,8]) after shared reset")

	# Data model — the handler resets _settings before setting slider.value,
	# so these must match the reset values regardless of value_changed ordering.
	assert_almost_eq(_tab._settings.master_volume, 1.0, 0.001,
			"_settings.master_volume must be 1.0 after shared reset")
	assert_almost_eq(_tab._settings.music_volume, 1.0, 0.001,
			"_settings.music_volume must be 1.0 after shared reset")
	assert_almost_eq(_tab._settings.sfx_volume, 1.0, 0.001,
			"_settings.sfx_volume must be 1.0 after shared reset")
	assert_almost_eq(_tab._settings.text_speed, 1.0, 0.001,
			"_settings.text_speed must be 1.0 after shared reset")
	assert_eq(_tab._settings.window_scale, 4,
			"_settings.window_scale must be 4 (4× default) after shared reset")

	# Slice 5: _tab._settings IS SaveManager.settings (same object, not a copy),
	# so the reset must be visible on the shared instance too — proving the
	# reset writes through to the per-device settings, not an in-memory copy.
	assert_almost_eq(SaveManager.settings.master_volume, 1.0, 0.001,
			"SaveManager.settings.master_volume must be 1.0 after shared reset")
	assert_almost_eq(SaveManager.settings.music_volume, 1.0, 0.001,
			"SaveManager.settings.music_volume must be 1.0 after shared reset")
	assert_almost_eq(SaveManager.settings.sfx_volume, 1.0, 0.001,
			"SaveManager.settings.sfx_volume must be 1.0 after shared reset")
	assert_almost_eq(SaveManager.settings.text_speed, 1.0, 0.001,
			"SaveManager.settings.text_speed must be 1.0 after shared reset")
	assert_eq(SaveManager.settings.window_scale, 4,
			"SaveManager.settings.window_scale must be 4 (4× default) after shared reset")


# ---------------------------------------------------------------------------
# Test 6 — Shared reset button sets OptionButton to index 1 without emitting item_selected
# ---------------------------------------------------------------------------

func test_reset_right_selects_default_scale_without_signal() -> void:
	# The shared reset button (_on_reset_all_pressed) assigns
	# _window_scale_option.selected = index_of_DEFAULT_WINDOW_SCALE directly
	# (NOT .select()), which does NOT emit item_selected (only user gestures do).
	# This test confirms:
	#   a) The OptionButton is set to index 1 (4× — the default in [2,4,6,8]).
	#   b) item_selected is NOT emitted, so _on_window_scale_changed is not
	#      called a second time via signal (it IS called directly — see handler).
	#
	# We first select a non-default index (0 = 2× — the minimum) so the reset
	# is observable. Note: there is no 1× option; index 0 = 2× is now the minimum.
	var option_node: Node = _get_named_node(_right_parent, "WindowScaleOption")
	assert_not_null(option_node,
			"WindowScaleOption must exist in the populated right-page tree")
	if option_node == null:
		return

	var opt_btn: OptionButton = option_node as OptionButton

	# Move away from the default (index 0 = 2×, which is not the default 4×).
	opt_btn.selected = 0
	await get_tree().process_frame

	# Wire up signal watch AFTER setup so we only count item_selected emits
	# caused by the reset, not the setup above.
	watch_signals(opt_btn)

	# Find and press the right reset button.
	var reset_btn: Button = null
	for child: Node in _right_parent.find_children("*", "Button", true, false):
		if child is Button and not child is OptionButton:
			reset_btn = child as Button
			break

	assert_not_null(reset_btn,
			"A reset Button must exist inside the right-page populated tree")
	if reset_btn == null:
		return

	reset_btn.pressed.emit()
	await get_tree().process_frame

	# The shared reset handler assigns _window_scale_option.selected = index directly
	# (NOT .select()). Both forms avoid emitting item_selected; what matters is
	# the final widget state. Default is index 1 = 4× in [2,4,6,8].
	assert_eq(opt_btn.selected, 1,
			"WindowScaleOption.selected must be 1 (4× default in [2,4,6,8]) after shared reset")

	# item_selected must NOT fire on a programmatic .selected = assignment. If
	# it did, the window would resize a second time via DisplayServer and any
	# subsequent screenshot assertions in the e2e scenario would be wrong.
	assert_signal_not_emitted(opt_btn, "item_selected",
			"item_selected must not be emitted when the reset button programmatically sets the selection")

	# Slice 5: _tab._settings IS SaveManager.settings (same object, not a copy),
	# so the reset must be visible on the shared instance too.
	assert_eq(SaveManager.settings.window_scale, 4,
			"SaveManager.settings.window_scale must be 4 (default) after shared reset")
