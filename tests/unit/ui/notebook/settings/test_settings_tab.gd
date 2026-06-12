## test_settings_tab.gd
## TDD contract tests for the Phase 1 Settings Tab.
##
## Covers SettingsTab (ui/notebook/settings/settings_tab.gd).
##
## These tests define the expected API. They will FAIL until the implementation
## files exist — that is by design. Run them after implementing each class to
## confirm the contract is met.
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
			"OptionButton must have at least 4 items (1×, 2×, 3×, 4×)")


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
	# The design doc specifies exactly four scale options (1×, 2×, 3×, 4×).
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
			"window scale OptionButton must have exactly 4 items (1×, 2×, 3×, 4×)")


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
	assert_eq(settings.window_scale, 2,
			"window_scale must default to 2 (the 1280×960 preset)")


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
	SaveManager.settings.master_volume = 0.3
	SaveManager.settings.text_speed = 0.6

	var tab: SettingsTab = add_child_autofree(SettingsTab.new())
	var parent: Control = add_child_autofree(Control.new())

	tab.populate_left(parent)

	assert_not_null(tab._master_slider,
			"_master_slider must be non-null after populate_left() runs")
	assert_almost_eq(tab._master_slider.value, 30.0, 0.001,
			"master slider value must reflect SaveManager.settings.master_volume == 0.3 (-> 30.0), not the GameSettings default (100.0)")
	assert_almost_eq(tab._text_speed_slider.value, 60.0, 0.001,
			"text speed slider value must reflect SaveManager.settings.text_speed == 0.6 (-> 60.0), not the GameSettings default (100.0)")


# ---------------------------------------------------------------------------
# Test 10 — populate_right() renders a non-default window_scale
# ---------------------------------------------------------------------------

func test_populate_right_renders_non_default_window_scale() -> void:
	# Mirrors test 9 for the right page: a non-default window_scale on
	# SaveManager.settings must select the matching OptionButton index
	# (index = scale - 1), not the GameSettings default (index 1 = 2×).
	SaveManager.settings.window_scale = 4

	var tab: SettingsTab = add_child_autofree(SettingsTab.new())
	var parent: Control = add_child_autofree(Control.new())

	tab.populate_right(parent)

	assert_not_null(tab._window_scale_option,
			"_window_scale_option must be non-null after populate_right() runs")
	assert_eq(tab._window_scale_option.selected, 3,
			"WindowScaleOption.selected must be 3 (4× -> index 3) to reflect SaveManager.settings.window_scale == 4")


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
# Test 12 — Reset buttons restore SaveManager.settings to documented defaults
# ---------------------------------------------------------------------------

func test_reset_left_restores_save_manager_settings_to_defaults() -> void:
	# Reset behaviour is unchanged by the data-source swap: pressing the
	# left-page reset must restore the shared SaveManager.settings instance
	# (now _settings) to the documented GameSettings defaults.
	var tab: SettingsTab = add_child_autofree(SettingsTab.new())
	var parent: Control = add_child_autofree(Control.new())

	tab.populate_left(parent)

	# Move away from defaults first so the reset is observable.
	tab._master_slider.value = 10.0
	tab._music_slider.value = 20.0
	tab._sfx_slider.value = 30.0
	tab._text_speed_slider.value = 40.0

	tab._on_reset_left_pressed()

	assert_eq(SaveManager.settings.master_volume, 1.0,
			"SaveManager.settings.master_volume must be 1.0 after left reset")
	assert_eq(SaveManager.settings.music_volume, 1.0,
			"SaveManager.settings.music_volume must be 1.0 after left reset")
	assert_eq(SaveManager.settings.sfx_volume, 1.0,
			"SaveManager.settings.sfx_volume must be 1.0 after left reset")
	assert_eq(SaveManager.settings.text_speed, 1.0,
			"SaveManager.settings.text_speed must be 1.0 after left reset")


func test_reset_right_restores_save_manager_settings_window_scale() -> void:
	# Mirrors test_reset_left_restores_save_manager_settings_to_defaults() for
	# the right-page reset and window_scale.
	var tab: SettingsTab = add_child_autofree(SettingsTab.new())
	var parent: Control = add_child_autofree(Control.new())

	tab.populate_right(parent)

	# Move away from the default (2) first so the reset is observable.
	SaveManager.settings.window_scale = 4
	tab._window_scale_option.selected = 3

	tab._on_reset_right_pressed()

	assert_eq(SaveManager.settings.window_scale, 2,
			"SaveManager.settings.window_scale must be 2 after right reset")
