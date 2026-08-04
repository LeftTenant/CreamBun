## test_settings_tab.gd
## TDD contract tests for the Phase 1 Settings Tab.
##
## Covers SettingsTab (ui/notebook/settings/settings_tab.gd).
##
## These tests define the expected API. Regression guard for that shipped
## contract.
##
## --- SLICE 5 DATA SOURCE NOTE ---
## SettingsTab._settings now sources from the shared SaveManager.settings
## (design §11 Step 4) instead of constructing a fresh GameSettings per
## session. before_each() resets SaveManager.settings to a freshly-constructed
## GameSettings so the "defaults" precondition tests below still hold, and so
## tests are hermetic — no test leaks a SaveManager.settings mutation into the
## next one. after_each() clears SaveManager.settings back to null, matching
## the pre-load_settings() state documented in save_manager.gd.
##
## Requires GUT: https://github.com/bitwes/Gut
## Install via Godot Asset Library (search "GUT - Godot Unit Testing").
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI (once GUT is installed):
##   godot --headless -s addons/gut/gut_cmdln.gd

class_name TestSettingsTab
extends GutTest


# ---------------------------------------------------------------------------
# Setup / Teardown
# ---------------------------------------------------------------------------

func before_each() -> void:
	# Give SaveManager a fresh, default GameSettings before every test so
	# SettingsTab._ready() (which now reads SaveManager.settings — Slice 5)
	# sees the documented defaults regardless of what an earlier test left
	# behind.
	SaveManager.settings = GameSettings.new()


func after_each() -> void:
	# Reset to null so a later suite's SaveManager._ready()/load_settings()
	# expectations are not affected by a stale instance from this file.
	SaveManager.settings = null


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Walk the full subtree of root and return every node that passes the
## type_check callable. Used because populate_left/right add children to a
## VBoxContainer that is itself a child of parent, making sliders and buttons
## grandchildren (not direct children) of the parent passed to the test.
##
## @param root       - the node whose subtree to search
## @param type_check - a Callable(Node) -> bool that returns true for matching nodes
## @return Array of matching nodes, in depth-first order
func _find_nodes_of_type(root: Node, type_check: Callable) -> Array[Node]:
	var result: Array[Node] = []
	for child in root.get_children():
		if type_check.call(child):
			result.append(child)
		result.append_array(_find_nodes_of_type(child, type_check))
	return result


# ---------------------------------------------------------------------------
# Test 1 — SettingsTab inherits NotebookTab
# ---------------------------------------------------------------------------

func test_settings_tab_is_a_notebook_tab() -> void:
	# SettingsTab must extend NotebookTab so the notebook controller can call
	# populate_left / populate_right polymorphically.
	# https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html#inheritance
	var tab: SettingsTab = SettingsTab.new()
	autofree(tab)

	assert_true(tab is NotebookTab,
			"SettingsTab must be a NotebookTab (extend NotebookTab)")


# ---------------------------------------------------------------------------
# Test 2 — populate_left() adds at least 3 HSliders (master, music, sfx)
# ---------------------------------------------------------------------------

func test_settings_tab_populate_left_adds_audio_sliders() -> void:
	# Audio is the primary purpose of the left page. Master, Music, and SFX
	# volume sliders must be present so the player can adjust all three buses.
	var tab: SettingsTab = add_child_autofree(SettingsTab.new())
	var parent: Control = add_child_autofree(Control.new())

	tab.populate_left(parent)

	# Sliders live inside a VBoxContainer child of parent, so we need a
	# recursive search rather than get_children() which only looks one level deep.
	var sliders: Array = _find_nodes_of_type(parent,
			func(n: Node) -> bool: return n is HSlider)

	assert_true(sliders.size() >= 3,
			"populate_left() must add at least 3 HSliders (master, music, sfx)")


# ---------------------------------------------------------------------------
# Test 3 — populate_right() adds an OptionButton with 4 items
# ---------------------------------------------------------------------------

func test_settings_tab_populate_right_adds_option_button() -> void:
	# Window scale is the display setting on the right page. It must present
	# the four valid scale factors as selectable options.
	var tab: SettingsTab = add_child_autofree(SettingsTab.new())
	var parent: Control = add_child_autofree(Control.new())

	tab.populate_right(parent)

	var option_buttons: Array = _find_nodes_of_type(parent,
			func(n: Node) -> bool: return n is OptionButton)

	assert_true(option_buttons.size() >= 1,
			"populate_right() must add at least one OptionButton")

	# Cast is safe — we just asserted size >= 1.
	var option: OptionButton = option_buttons[0] as OptionButton
	assert_true(option.item_count >= 4,
			"OptionButton must have at least 4 items (2×, 4×, 6×, 8×)")


# ---------------------------------------------------------------------------
# Test 4 — Master slider initial value matches GameSettings.master_volume
# ---------------------------------------------------------------------------

func test_settings_tab_initial_volume_matches_game_settings() -> void:
	# The slider range is 0–100, and GameSettings.master_volume is 0.0–1.0.
	# A default master_volume of 1.0 must render as slider value 100.0.
	# This test catches off-by-one scaling errors (e.g. forgetting the × 100).
	var tab: SettingsTab = add_child_autofree(SettingsTab.new())
	var parent: Control = add_child_autofree(Control.new())

	# Confirm the default we are testing against — if GameSettings changes,
	# this assertion will point directly at the broken default. SettingsTab now
	# sources _settings from SaveManager.settings (Slice 5), so the precondition
	# is checked against the shared instance before_each() reset to defaults.
	assert_eq(SaveManager.settings.master_volume, 1.0,
			"precondition: SaveManager.settings default master_volume must be 1.0")

	tab.populate_left(parent)

	# _master_slider is set by populate_left, so access it directly.
	# GDScript does not enforce underscore-prefix access control in tests.
	assert_not_null(tab._master_slider,
			"_master_slider must be non-null after populate_left() runs")

	# 1.0 * 100 = 100.0 on the 0–100 slider
	assert_almost_eq(tab._master_slider.value, 100.0, 0.001,
			"master slider value must be 100.0 when master_volume defaults to 1.0")


# ---------------------------------------------------------------------------
# Test 5 — Window scale OptionButton has exactly 4 items
# ---------------------------------------------------------------------------

func test_settings_tab_window_scale_option_has_four_items() -> void:
	# The design doc specifies exactly four scale options (2×, 4×, 6×, 8×).
	# Having more or fewer would expose unsupported window sizes to the player.
	var tab: SettingsTab = add_child_autofree(SettingsTab.new())
	var parent: Control = add_child_autofree(Control.new())

	tab.populate_right(parent)

	var option_buttons: Array = _find_nodes_of_type(parent,
			func(n: Node) -> bool: return n is OptionButton)

	assert_true(option_buttons.size() >= 1,
			"precondition: OptionButton must exist after populate_right()")

	var option: OptionButton = option_buttons[0] as OptionButton
	assert_eq(option.item_count, 4,
			"window scale OptionButton must have exactly 4 items (2×, 4×, 6×, 8×)")


# ---------------------------------------------------------------------------
# Test 6 — GameSettings defaults are correct (spot-check from this layer)
# ---------------------------------------------------------------------------

func test_game_settings_defaults_are_correct() -> void:
	# The foundation layer tests cover this more thoroughly. This test guards
	# against accidental regressions introduced while implementing SettingsTab —
	# if the defaults drift, both layers catch it independently.
	var settings: GameSettings = GameSettings.new()
	autofree(settings)

	assert_eq(settings.master_volume, 1.0,
			"master_volume must default to 1.0")
	assert_eq(settings.music_volume, 1.0,
			"music_volume must default to 1.0")
	assert_eq(settings.sfx_volume, 1.0,
			"sfx_volume must default to 1.0")
	assert_eq(settings.window_scale, 4,
			"window_scale must default to 4 (the 1280×720 preset)")


# ---------------------------------------------------------------------------
# Test 7 — SettingsTab._settings is the same object identity as SaveManager.settings
# ---------------------------------------------------------------------------

func test_settings_tab_settings_is_save_manager_settings_instance() -> void:
	# Slice 5: SettingsTab._ready() (or the first populate_* call) must source
	# _settings from SaveManager.settings directly — the SAME object, not a
	# duplicate(). Comparing object identity (==) on Resources compares
	# reference identity, so this fails if SettingsTab ever copies the
	# resource instead of sharing it.
	var tab: SettingsTab = add_child_autofree(SettingsTab.new())

	assert_same(tab._settings, SaveManager.settings,
			"SettingsTab._settings must be the exact SaveManager.settings instance, not a copy")


# ---------------------------------------------------------------------------
# Test 8 — SettingsTab does not construct its own GameSettings.new() when
# SaveManager.settings is already populated
# ---------------------------------------------------------------------------

func test_settings_tab_does_not_construct_fresh_game_settings() -> void:
	# Guards against the old Phase-1 "fresh GameSettings every session" code
	# path silently surviving alongside the new SaveManager.settings read.
	# We pre-populate SaveManager.settings with a distinguishable non-default
	# value; if SettingsTab._ready() still does `_settings = GameSettings.new()`
	# this value would be overwritten with the GameSettings default (1.0).
	SaveManager.settings.master_volume = 0.42

	var tab: SettingsTab = add_child_autofree(SettingsTab.new())

	assert_eq(tab._settings.master_volume, 0.42,
			"SettingsTab._settings.master_volume must retain the pre-set SaveManager.settings value (0.42), not a fresh GameSettings default (1.0)")


# ---------------------------------------------------------------------------
# Test 9 — populate_left() renders non-default SaveManager.settings values
# ---------------------------------------------------------------------------

func test_populate_left_renders_non_default_master_volume() -> void:
	# A SettingsTab created after SaveManager.settings has been changed away
	# from defaults (e.g. by a previous notebook session) must render those
	# changed values on its sliders — not GameSettings.new() defaults.
	#
	# NOTE (Slice 3, pixel-art-purist): TextSpeedSlider was moved from the left
	# page to the right page so the left page fits the 320×180 viewport without
	# overflowing. This test covers left-page controls only (master volume).
	# Text-speed rendering is exercised by test_populate_right_renders_non_default_window_scale,
	# which already calls populate_right(); adding it here would require
	# calling populate_right() too, which is tested separately.
	SaveManager.settings.master_volume = 0.3

	var tab: SettingsTab = add_child_autofree(SettingsTab.new())
	var parent: Control = add_child_autofree(Control.new())

	tab.populate_left(parent)

	assert_not_null(tab._master_slider,
			"_master_slider must be non-null after populate_left() runs")
	assert_almost_eq(tab._master_slider.value, 30.0, 0.001,
			"master slider value must reflect SaveManager.settings.master_volume == 0.3 (-> 30.0), not the GameSettings default (100.0)")


# ---------------------------------------------------------------------------
# Test 10 — populate_right() renders a non-default window_scale
# ---------------------------------------------------------------------------

func test_populate_right_renders_non_default_window_scale() -> void:
	# Mirrors test 9 for the right page: a non-default window_scale on
	# SaveManager.settings must select the matching OptionButton index
	# via WINDOW_SCALE_OPTIONS.find(scale), not by arithmetic.
	# WINDOW_SCALE_OPTIONS = [2, 4, 6, 8]; the default is 4 (index 1).
	# We use window_scale=8 (index 3) — clearly non-default — to prove the
	# find-based mapping works at the far end of the array.
	SaveManager.settings.window_scale = 8

	var tab: SettingsTab = add_child_autofree(SettingsTab.new())
	var parent: Control = add_child_autofree(Control.new())

	tab.populate_right(parent)

	assert_not_null(tab._window_scale_option,
			"_window_scale_option must be non-null after populate_right() runs")
	assert_eq(tab._window_scale_option.selected, 3,
			"WindowScaleOption.selected must be 3 (8× -> index 3 in [2,4,6,8]) to reflect SaveManager.settings.window_scale == 8")


# ---------------------------------------------------------------------------
# Test 11 — slider edits are immediately reflected on SaveManager.settings
# ---------------------------------------------------------------------------

func test_slider_edit_is_reflected_on_save_manager_settings() -> void:
	# Because _settings IS SaveManager.settings (test 7), a slider-driven
	# change to _settings must be observable by reading SaveManager.settings
	# independently of the tab — there is no separate copy that could drift.
	var tab: SettingsTab = add_child_autofree(SettingsTab.new())
	var parent: Control = add_child_autofree(Control.new())

	tab.populate_left(parent)

	tab._master_slider.value = 25.0

	assert_almost_eq(SaveManager.settings.master_volume, 0.25, 0.001,
			"SaveManager.settings.master_volume must read 0.25 after the master slider is set to 25, with no separate copy")


# ---------------------------------------------------------------------------
# Test 12 — Single shared reset button restores ALL SaveManager.settings to defaults
# ---------------------------------------------------------------------------
#
# NOTE (Slice 3, pixel-art-purist): Per-page reset buttons were replaced by a
# SINGLE "Reset to Defaults" button on the right page that resets every setting
# across BOTH pages — audio volume, text speed, and window scale — in one press.
# This test has been updated accordingly: it populates both pages, mutates
# settings on both sides, then invokes the single _on_reset_all_pressed() handler
# and asserts all settings (including text speed on the right page) are restored.

func test_shared_reset_restores_all_save_manager_settings_to_defaults() -> void:
	# The single reset must restore the shared SaveManager.settings instance
	# (_settings) to the documented GameSettings defaults across ALL settings,
	# regardless of which page is currently visible.
	var tab: SettingsTab = add_child_autofree(SettingsTab.new())
	var left_parent: Control = add_child_autofree(Control.new())
	var right_parent: Control = add_child_autofree(Control.new())

	# Populate both pages so all slider/option refs are resolved before reset.
	tab.populate_left(left_parent)
	tab.populate_right(right_parent)

	# Move every setting away from defaults so the reset is observable.
	# Default window_scale is now 4 (index 1 in [2,4,6,8]); move to index 0 (2×).
	tab._master_slider.value = 10.0
	tab._music_slider.value = 20.0
	tab._sfx_slider.value = 30.0
	tab._text_speed_slider.value = 40.0
	tab._window_scale_option.selected = 0  # 2× (default is index 1 = 4×)

	tab._on_reset_all_pressed()

	assert_eq(SaveManager.settings.master_volume, 1.0,
			"SaveManager.settings.master_volume must be 1.0 after shared reset")
	assert_eq(SaveManager.settings.music_volume, 1.0,
			"SaveManager.settings.music_volume must be 1.0 after shared reset")
	assert_eq(SaveManager.settings.sfx_volume, 1.0,
			"SaveManager.settings.sfx_volume must be 1.0 after shared reset")
	assert_eq(SaveManager.settings.text_speed, 1.0,
			"SaveManager.settings.text_speed must be 1.0 after shared reset")
	assert_eq(SaveManager.settings.window_scale, 4,
			"SaveManager.settings.window_scale must be 4 (4× default) after shared reset")


func test_shared_reset_restores_save_manager_settings_window_scale() -> void:
	# The shared reset button (_on_reset_all_pressed) must restore window_scale
	# to 4 (4× — the new default) on SaveManager.settings and set the OptionButton
	# to index 1 (the position of 4 in WINDOW_SCALE_OPTIONS = [2,4,6,8]).
	# populate_right is sufficient here because window_scale lives on that page;
	# populate_left is not needed for this narrow assertion.
	var tab: SettingsTab = add_child_autofree(SettingsTab.new())
	var parent: Control = add_child_autofree(Control.new())

	tab.populate_right(parent)

	# Move away from the default (4) first so the reset is observable.
	SaveManager.settings.window_scale = 8
	tab._window_scale_option.selected = 3  # index 3 == 8×

	tab._on_reset_all_pressed()

	assert_eq(SaveManager.settings.window_scale, 4,
			"SaveManager.settings.window_scale must be 4 (4× default) after shared reset")
	assert_eq(tab._window_scale_option.selected, 1,
			"WindowScaleOption.selected must be 1 (index of 4 in [2,4,6,8]) after shared reset")


# ---------------------------------------------------------------------------
# NEW Test — OptionButton lists exactly the scales [2, 4, 6, 8]
# ---------------------------------------------------------------------------

func test_window_scale_option_lists_scales_2_4_6_8() -> void:
	# Guard that WINDOW_SCALE_OPTIONS was not accidentally edited. The OptionButton
	# items are built from this constant, so checking the constant is sufficient;
	# the item-count test above confirms the items were added.
	#
	# We also verify the item labels contain the scale multiplier so a label-only
	# typo ("5×" vs "4×") is caught without loading the full scene.
	assert_eq(SettingsTab.WINDOW_SCALE_OPTIONS, [2, 4, 6, 8],
			"WINDOW_SCALE_OPTIONS must be [2, 4, 6, 8]")

	var tab: SettingsTab = add_child_autofree(SettingsTab.new())
	var parent: Control = add_child_autofree(Control.new())

	tab.populate_right(parent)

	assert_not_null(tab._window_scale_option,
			"precondition: _window_scale_option must be non-null after populate_right()")

	# Verify each item's label contains the expected scale prefix ("2×", "4×", etc.)
	# so a copy-paste error in the label text is caught here.
	var scale_labels: Array[String] = ["2×", "4×", "6×", "8×"]
	for i: int in range(scale_labels.size()):
		var label: String = tab._window_scale_option.get_item_text(i)
		assert_true(label.begins_with(scale_labels[i]),
				"OptionButton item %d label must begin with '%s', got '%s'" % [
						i, scale_labels[i], label])


# ---------------------------------------------------------------------------
# NEW Test — Each OptionButton index maps to the correct scale and pixel size
# ---------------------------------------------------------------------------

func test_each_scale_index_maps_to_correct_window_size() -> void:
	# WINDOW_SCALE_OPTIONS = [2, 4, 6, 8]; viewport = 320×180.
	# Expected pixel sizes:
	#   index 0: 2× → 640×360
	#   index 1: 4× → 1280×720
	#   index 2: 6× → 1920×1080
	#   index 3: 8× → 2560×1440
	# This test drives item_selected.emit() for each index and confirms:
	#   a) _settings.window_scale holds the corresponding array value
	#   b) _scaled_window_size() returns the right pixel dimensions
	var tab: SettingsTab = add_child_autofree(SettingsTab.new())
	var parent: Control = add_child_autofree(Control.new())

	tab.populate_right(parent)
	assert_not_null(tab._window_scale_option,
			"precondition: _window_scale_option must be non-null after populate_right()")

	var expected_scales: Array[int] = [2, 4, 6, 8]
	# Viewport is 320×180 per project.godot.
	var expected_sizes: Array[Vector2i] = [
		Vector2i(640,  360),
		Vector2i(1280, 720),
		Vector2i(1920, 1080),
		Vector2i(2560, 1440),
	]

	for i: int in range(4):
		# item_selected is emitted by user interaction; emit directly to call the handler.
		tab._window_scale_option.item_selected.emit(i)

		assert_eq(SaveManager.settings.window_scale, expected_scales[i],
				"After selecting index %d, window_scale must be %d" % [i, expected_scales[i]])

		# _scaled_window_size is private but accessible in GDScript tests.
		var actual_size: Vector2i = tab._scaled_window_size(SaveManager.settings.window_scale)
		assert_eq(actual_size, expected_sizes[i],
				"_scaled_window_size(%d) must be %s; got %s" % [
						expected_scales[i], str(expected_sizes[i]), str(actual_size)])


# ---------------------------------------------------------------------------
# NEW Test — Legacy/unknown window_scale falls back to DEFAULT_WINDOW_SCALE
# ---------------------------------------------------------------------------

func test_unknown_window_scale_falls_back_to_default_index() -> void:
	# If a legacy save stored an old value not in WINDOW_SCALE_OPTIONS (e.g. 1 or 3),
	# WINDOW_SCALE_OPTIONS.find() returns -1. The implementation must detect this and
	# fall back to the DEFAULT_WINDOW_SCALE (4) rather than leaving the OptionButton
	# on a broken index of -1.
	#
	# We store a legacy value (1) before populate_right() runs so it is the value
	# visible to the tab when it tries to set the initial selection.
	SaveManager.settings.window_scale = 1  # not in [2, 4, 6, 8]

	var tab: SettingsTab = add_child_autofree(SettingsTab.new())
	var parent: Control = add_child_autofree(Control.new())

	tab.populate_right(parent)

	assert_not_null(tab._window_scale_option,
			"precondition: _window_scale_option must be non-null after populate_right()")

	# The fallback must land on the DEFAULT_WINDOW_SCALE (4), not on -1 or an
	# arbitrary out-of-range index.
	var default_index: int = SettingsTab.WINDOW_SCALE_OPTIONS.find(SettingsTab.DEFAULT_WINDOW_SCALE)
	assert_eq(tab._window_scale_option.selected, default_index,
			"An unknown window_scale (1) must fall back to the DEFAULT_WINDOW_SCALE index (%d), not -1" % default_index)
