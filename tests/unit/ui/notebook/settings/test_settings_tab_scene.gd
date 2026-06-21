## test_settings_tab_scene.gd
## Scene-as-data contract tests for the Settings tab scene (settings_tab.tscn).
##
## WHAT THESE TESTS GUARD
## ----------------------
## settings_tab.tscn declares the full static layout as saved editor nodes. These
## tests load the .tscn and walk the resulting tree to assert that the named nodes
## the script depends on are present and of the correct type.
##
## WHY SCENE-AS-DATA TESTS MATTER
## --------------------------------
## The contract between settings_tab.gd and settings_tab.tscn is not enforced by
## the type system — get_node("MasterSlider") returns null at runtime with no
## editor warning if the node was accidentally renamed or deleted. A test that
## loads the PackedScene and walks the instantiated tree catches that breakage at
## CI time rather than at runtime during QA.
##
## --- SLICE 5 DATA SOURCE NOTE ---
## _make_scene_instance() adds the instantiated SettingsTab to the tree, which
## runs _ready(). Since Slice 5, _ready() reads SaveManager.settings instead of
## constructing a fresh GameSettings — before_each() gives SaveManager.settings
## a known-default instance so node-lookup/populate tests in this file are not
## affected by whatever a prior suite left behind, and after_each() clears it
## again so this file doesn't leak state into later suites.
##
## Requires GUT: https://github.com/bitwes/Gut
## Install via Godot Asset Library (search "GUT - Godot Unit Testing").
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd -gselect=test_settings_tab_scene.gd -gexit

class_name TestSettingsTabScene
extends GutTest


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Canonical path for the scene under test. Using a constant makes it easy to
# update if the file moves and ensures all tests in this file reference the
# same path.
const SCENE_PATH: String = "res://ui/notebook/settings/settings_tab.tscn"


# ---------------------------------------------------------------------------
# Setup / Teardown
# ---------------------------------------------------------------------------

func before_each() -> void:
	# Fresh defaults before every test — see Slice 5 note above.
	SaveManager.settings = GameSettings.new()


func after_each() -> void:
	SaveManager.settings = null


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Instantiate SCENE_PATH and add it to the scene tree so @onready vars and
## child nodes are fully resolved. The instance is autofreed.
##
## @return the instantiated SettingsTab root node, added as a child of the test
func _make_scene_instance() -> Control:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	var instance: Control = packed.instantiate() as Control
	add_child_autofree(instance)
	return instance


## Walk the subtree of root depth-first and collect every node that satisfies
## the type_check Callable. Used because named nodes may live at any depth
## inside the VBoxContainer hierarchy.
##
## @param root       the node whose subtree to search
## @param type_check Callable(Node) -> bool; returns true for matching nodes
## @return Array of matching nodes in depth-first order
func _find_nodes_of_type(root: Node, type_check: Callable) -> Array[Node]:
	var result: Array[Node] = []
	for child: Node in root.get_children():
		if type_check.call(child):
			result.append(child)
		result.append_array(_find_nodes_of_type(child, type_check))
	return result


# ---------------------------------------------------------------------------
# Test 1 — Scene file loads as a valid PackedScene
# ---------------------------------------------------------------------------

func test_scene_loads_without_error() -> void:
	# If the .tscn file is corrupt, mis-formatted, or references a missing
	# resource, load() will return null. This is the cheapest possible check
	# and gates every subsequent test: if load fails there is no point
	# instantiating the scene.
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	assert_not_null(packed,
			"settings_tab.tscn must load as a non-null PackedScene")


# ---------------------------------------------------------------------------
# Test 2 — Scene declares a node named MasterSlider of type HSlider
# ---------------------------------------------------------------------------

func test_scene_declares_master_slider() -> void:
	# MasterSlider is the named-node contract that settings_tab.gd depends on
	# to store a ref, init the value, and wire value_changed. If a developer
	# renames or removes this node in the editor, this test fails immediately
	# rather than silently producing a null ref at runtime.
	var instance: Control = _make_scene_instance()

	var node: Node = instance.find_child("MasterSlider", true, false)
	assert_not_null(node,
			"settings_tab.tscn must declare a node named 'MasterSlider'")
	if node == null:
		return  # Guard: skip cast assertion if the node is missing.
	assert_true(node is HSlider,
			"'MasterSlider' must be an HSlider, got %s" % node.get_class())


# ---------------------------------------------------------------------------
# Test 3 — Scene declares MusicSlider, SfxSlider, and TextSpeedSlider
# ---------------------------------------------------------------------------

func test_scene_declares_remaining_sliders() -> void:
	# These three sliders span both pages: MusicSlider and SfxSlider live on the
	# left page (audio); TextSpeedSlider lives on the right page (gameplay, moved
	# there in Slice 3 — pixel-art-purist — to fit the 320×180 viewport).
	# Each name must exist in the scene and be the correct type; a wrong type
	# would cause a silent null cast when the script assigns the node ref.
	var instance: Control = _make_scene_instance()

	var slider_names: Array[String] = ["MusicSlider", "SfxSlider", "TextSpeedSlider"]
	for slider_name: String in slider_names:
		var node: Node = instance.find_child(slider_name, true, false)
		assert_not_null(node,
				"settings_tab.tscn must declare a node named '%s'" % slider_name)
		if node == null:
			continue
		assert_true(node is HSlider,
				"'%s' must be an HSlider, got %s" % [slider_name, node.get_class()])


# ---------------------------------------------------------------------------
# Test 4 — Scene declares a node named WindowScaleOption of type OptionButton
# ---------------------------------------------------------------------------

func test_scene_declares_window_scale_option() -> void:
	# WindowScaleOption is the only OptionButton in the scene. The script finds
	# it by name to wire item_selected and to call select() during resets.
	var instance: Control = _make_scene_instance()

	var node: Node = instance.find_child("WindowScaleOption", true, false)
	assert_not_null(node,
			"settings_tab.tscn must declare a node named 'WindowScaleOption'")
	if node == null:
		return
	assert_true(node is OptionButton,
			"'WindowScaleOption' must be an OptionButton, got %s" % node.get_class())


# ---------------------------------------------------------------------------
# Test 5 — Scene declares exactly ONE shared reset button (named "ResetButton")
# ---------------------------------------------------------------------------
#
# NOTE (Slice 3, pixel-art-purist): Per-page reset buttons (ResetLeftButton,
# ResetRightButton) were replaced by a SINGLE "Reset to Defaults" button on
# the right page that resets ALL settings across both pages in one press.
# This test was updated from "≥ 2 buttons" to "exactly 1 button named ResetButton"
# to match the approved new design and prevent silent regressions where someone
# accidentally re-adds a second button.

func test_scene_declares_single_shared_reset_button() -> void:
	# The one reset button is named "ResetButton" in settings_tab.tscn and lives
	# on the RightPage VBoxContainer. This test asserts type-and-count so it also
	# catches "a reset button was accidentally added back in the editor" alongside
	# the name-based contract test above.
	var instance: Control = _make_scene_instance()

	var buttons: Array[Node] = _find_nodes_of_type(instance,
			func(n: Node) -> bool: return n is Button and not n is OptionButton)

	assert_eq(buttons.size(), 1,
			"settings_tab.tscn must declare exactly 1 Button node (the single shared reset), found %d" % buttons.size())

	# Also verify the button has the correct name, so a rename in the editor
	# does not silently break settings_tab.gd's get_node("ResetButton") lookup.
	if buttons.size() == 1:
		assert_eq(buttons[0].name, "ResetButton",
				"The single reset Button must be named 'ResetButton' (settings_tab.gd uses get_node(\"ResetButton\"))")


# ---------------------------------------------------------------------------
# Test 6 — Scene declares Labels with text "Audio" and "Display"
# ---------------------------------------------------------------------------

func test_scene_declares_audio_and_display_section_headers() -> void:
	# Section header Labels are baked into the .tscn rather than injected at
	# runtime. This test confirms the static content is present and correctly
	# spelled — a typo in the editor would go undetected by any other test.
	var instance: Control = _make_scene_instance()

	var labels: Array[Node] = _find_nodes_of_type(instance,
			func(n: Node) -> bool: return n is Label)

	var label_texts: Array[String] = []
	for label_node: Node in labels:
		label_texts.append((label_node as Label).text)

	assert_true("Audio" in label_texts,
			"settings_tab.tscn must contain a Label with text 'Audio' (left-page section header)")
	assert_true("Display" in label_texts,
			"settings_tab.tscn must contain a Label with text 'Display' (right-page section header)")


# ---------------------------------------------------------------------------
# Test 7 — populate_left(null) does not crash
# ---------------------------------------------------------------------------

func test_populate_left_with_null_parent_does_not_crash() -> void:
	# The NotebookTab contract documents that populate_left / populate_right
	# must guard against null. Crashing here would abort the notebook _show_tab
	# flow if the controller ever passes a missing page.
	var instance: Control = _make_scene_instance()
	var tab: SettingsTab = instance as SettingsTab
	assert_not_null(tab,
			"settings_tab.tscn root must be castable to SettingsTab")
	if tab == null:
		return
	# No assertion needed — the test fails if this call throws an error.
	tab.populate_left(null)
	assert_true(true, "populate_left(null) completed without error")


# ---------------------------------------------------------------------------
# Test 8 — populate_right(null) does not crash
# ---------------------------------------------------------------------------

func test_populate_right_with_null_parent_does_not_crash() -> void:
	# Mirrors test 7 for the right-page populate method.
	var instance: Control = _make_scene_instance()
	var tab: SettingsTab = instance as SettingsTab
	assert_not_null(tab,
			"settings_tab.tscn root must be castable to SettingsTab")
	if tab == null:
		return
	tab.populate_right(null)
	assert_true(true, "populate_right(null) completed without error")
