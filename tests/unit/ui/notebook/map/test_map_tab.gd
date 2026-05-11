## test_map_tab.gd
## TDD contract tests for the Phase 1 Map Tab.
##
## Covers MapTab (ui/notebook/map/map_tab.gd),
## GlobalMap (ui/notebook/map/global_map.gd), and
## LocalMap (ui/notebook/map/local_map.gd).
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

class_name TestMapTab
extends GutTest


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Walk the full subtree of root and return every Label node found.
## populate_left/right add content inside a VBoxContainer that is itself a
## child of parent, making Labels grandchildren rather than direct children.
##
## @param root   - the node whose subtree to search
## @return Array of Label nodes in depth-first order
func _find_labels(root: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child in root.get_children():
		if child is Label:
			result.append(child)
		result.append_array(_find_labels(child))
	return result


# ---------------------------------------------------------------------------
# Test 1 — MapTab inherits NotebookTab
# ---------------------------------------------------------------------------

func test_map_tab_is_a_notebook_tab() -> void:
	# MapTab must extend NotebookTab so the notebook controller can call
	# populate_left / populate_right polymorphically.
	# https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html#inheritance
	var tab: MapTab = MapTab.new()
	autofree(tab)

	assert_true(tab is NotebookTab,
			"MapTab must be a NotebookTab (extend NotebookTab)")


# ---------------------------------------------------------------------------
# Test 2 — populate_left() adds at least one child
# ---------------------------------------------------------------------------

func test_map_tab_populate_left_adds_content() -> void:
	# populate_left() must add a container (VBoxContainer) to the parent so
	# the left page is not visually blank in Phase 1.
	var tab: MapTab = add_child_autofree(MapTab.new())
	var parent: Control = add_child_autofree(Control.new())

	tab.populate_left(parent)

	assert_true(parent.get_child_count() >= 1,
			"populate_left() must add at least one child node to the parent Control")


# ---------------------------------------------------------------------------
# Test 3 — populate_right() adds at least one child
# ---------------------------------------------------------------------------

func test_map_tab_populate_right_adds_content() -> void:
	# populate_right() must add a container to the parent so the right page
	# is not visually blank in Phase 1.
	var tab: MapTab = add_child_autofree(MapTab.new())
	var parent: Control = add_child_autofree(Control.new())

	tab.populate_right(parent)

	assert_true(parent.get_child_count() >= 1,
			"populate_right() must add at least one child node to the parent Control")


# ---------------------------------------------------------------------------
# Test 4 — left page subtree contains at least one Label
# ---------------------------------------------------------------------------

func test_map_tab_left_page_has_label() -> void:
	# The left page shows a "World Map" section heading and a Phase 2 note.
	# At least one Label must exist in the subtree so the player can read
	# something — an entirely empty or unlabelled page would be confusing.
	var tab: MapTab = add_child_autofree(MapTab.new())
	var parent: Control = add_child_autofree(Control.new())

	tab.populate_left(parent)

	var labels: Array[Node] = _find_labels(parent)
	assert_true(labels.size() >= 1,
			"populate_left() subtree must contain at least one Label node")


# ---------------------------------------------------------------------------
# Test 5 — right page subtree contains at least one Label
# ---------------------------------------------------------------------------

func test_map_tab_right_page_has_label() -> void:
	# The right page shows a "Local Area" section heading and a Phase 2 note.
	# Same rationale as the left page — a Label must be present.
	var tab: MapTab = add_child_autofree(MapTab.new())
	var parent: Control = add_child_autofree(Control.new())

	tab.populate_right(parent)

	var labels: Array[Node] = _find_labels(parent)
	assert_true(labels.size() >= 1,
			"populate_right() subtree must contain at least one Label node")


# ---------------------------------------------------------------------------
# Test 6 — GlobalMap is instantiable
# ---------------------------------------------------------------------------

func test_global_map_is_instantiable() -> void:
	# GlobalMap must be constructable so Phase 2 can instance it and embed it
	# inside the left page of the map tab. This test confirms the class exists
	# and that .new() does not crash.
	var gm: GlobalMap = GlobalMap.new()
	autofree(gm)

	# GlobalMap extends Control, which extends Node — is Node is the widest
	# useful assertion and is safe regardless of future base-class changes.
	assert_true(gm is Node,
			"GlobalMap.new() must produce a Node (or subclass)")


# ---------------------------------------------------------------------------
# Test 7 — LocalMap is instantiable
# ---------------------------------------------------------------------------

func test_local_map_is_instantiable() -> void:
	# LocalMap must be constructable for the same reason as GlobalMap.
	# Phase 2 will embed it in the right page.
	var lm: LocalMap = LocalMap.new()
	autofree(lm)

	assert_true(lm is Node,
			"LocalMap.new() must produce a Node (or subclass)")
