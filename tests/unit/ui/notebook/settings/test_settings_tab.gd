## test_settings_tab.gd
## TDD contract tests for the Phase 1 Settings Tab.
##
## Covers SettingsTab (ui/notebook/settings/settings_tab.gd).
##
## These tests define the expected API. They will FAIL until the implementation
## files exist — that is by design. Run them after implementing each class to
## confirm the contract is met.
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

	var settings: GameSettings = GameSettings.new()
	# Confirm the default we are testing against — if GameSettings changes,
	# this assertion will point directly at the broken default.
	assert_eq(settings.master_volume, 1.0,
			"precondition: GameSettings default master_volume must be 1.0")

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
