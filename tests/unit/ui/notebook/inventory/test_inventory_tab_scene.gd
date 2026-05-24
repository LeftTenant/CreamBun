## test_inventory_tab_scene.gd
## Scene-as-data contract tests for the Inventory tab scene migration (Slice 2).
##
## WHAT THESE TESTS GUARD
## ----------------------
## inventory_tab.tscn declares the full static layout as saved editor nodes.
## These tests load the .tscn and walk the resulting tree to assert that the
## named nodes the script depends on are present and of the correct type.
##
## WHY SCENE-AS-DATA TESTS MATTER
## --------------------------------
## The contract between inventory_tab.gd and inventory_tab.tscn is not enforced by
## the type system — find_child("WeightLabel", true, false) returns null at runtime
## with no editor warning if the node was accidentally renamed or deleted. A test
## that loads the PackedScene and walks the instantiated tree catches that breakage
## at CI time rather than during manual QA.
##
## Requires GUT: https://github.com/bitwes/Gut
## Install via Godot Asset Library (search "GUT - Godot Unit Testing").
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd -gselect=test_inventory_tab_scene.gd -gexit

class_name TestInventoryTabScene
extends GutTest


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Canonical path for the scene under test. A constant makes it easy to update
# if the file moves and ensures every test in this file references the same path.
const SCENE_PATH: String = "res://ui/notebook/inventory/inventory_tab.tscn"

# The six slot names that populate_left() depends on to build the equipment
# silhouette. Asserting them as a constant list makes additions visible as a diff.
const SLOT_NAMES: Array[String] = [
	"Slot_BACKPACK",
	"Slot_CLOTHING",
	"Slot_BOOTS",
	"Slot_GLOVES",
	"Slot_GOGGLES",
	"Slot_NECKLACE",
]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Instantiate SCENE_PATH and add it to the scene tree so @onready vars and
## child nodes are fully resolved. The instance is autofreed after the test.
##
## @return the instantiated InventoryTab root node added as a child of the test
func _make_scene_instance() -> Control:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	var instance: Control = packed.instantiate() as Control
	add_child_autofree(instance)
	return instance


## Walk root's subtree depth-first and collect every node that satisfies
## type_check. Used because named nodes may live at any depth inside the layout
## hierarchy — a shallow get_child(0) would miss grandchildren.
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
	# resource, load() returns null. This is the cheapest possible check and
	# gates every subsequent test: if load fails there is no point instantiating.
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	assert_not_null(packed,
			"inventory_tab.tscn must load as a non-null PackedScene")


# ---------------------------------------------------------------------------
# Test 2 — Scene declares a node named LeftPage of type Control / VBoxContainer
# ---------------------------------------------------------------------------

func test_scene_declares_left_page() -> void:
	# LeftPage is the subtree root that populate_left() reparents into the
	# notebook book's page. If it is renamed or deleted the tab's left side
	# will be permanently blank with no runtime error.
	var instance: Control = _make_scene_instance()

	var node: Node = instance.find_child("LeftPage", true, false)
	assert_not_null(node,
			"inventory_tab.tscn must declare a node named 'LeftPage'")
	if node == null:
		return
	assert_true(node is Control,
			"'LeftPage' must be a Control (or subclass), got %s" % node.get_class())


# ---------------------------------------------------------------------------
# Test 3 — Scene declares a node named RightPage of type Control / VBoxContainer
# ---------------------------------------------------------------------------

func test_scene_declares_right_page() -> void:
	# RightPage is the subtree root that populate_right() reparents. Mirrors
	# the LeftPage contract but for the scrollable item list side.
	var instance: Control = _make_scene_instance()

	var node: Node = instance.find_child("RightPage", true, false)
	assert_not_null(node,
			"inventory_tab.tscn must declare a node named 'RightPage'")
	if node == null:
		return
	assert_true(node is Control,
			"'RightPage' must be a Control (or subclass), got %s" % node.get_class())


# ---------------------------------------------------------------------------
# Test 4 — Scene declares exactly the 6 named equipment slot placeholders
# ---------------------------------------------------------------------------

func test_scene_declares_all_six_equipment_slot_placeholders() -> void:
	# populate_left() builds EquipmentSlot nodes named Slot_BACKPACK … Slot_NECKLACE.
	# These names are the stable contract between the tab script and the scene
	# layout. A missing or misspelled name would silently produce a detached slot
	# that never receives drag-drop events. We assert on each name individually so
	# the failure message identifies which slot is missing rather than just "not 6".
	var instance: Control = _make_scene_instance()

	for slot_name: String in SLOT_NAMES:
		var node: Node = instance.find_child(slot_name, true, false)
		assert_not_null(node,
				"inventory_tab.tscn must declare a node named '%s'" % slot_name)


# ---------------------------------------------------------------------------
# Test 5 — Scene declares a node named RowsContainer of type VBoxContainer
# ---------------------------------------------------------------------------

func test_scene_declares_rows_container() -> void:
	# RowsContainer is the VBoxContainer that populate_right() appends
	# InventoryRow instances into. Without it, the item list has nowhere to
	# render and the scroll container would be permanently empty.
	var instance: Control = _make_scene_instance()

	var node: Node = instance.find_child("RowsContainer", true, false)
	assert_not_null(node,
			"inventory_tab.tscn must declare a node named 'RowsContainer'")
	if node == null:
		return
	assert_true(node is VBoxContainer,
			"'RowsContainer' must be a VBoxContainer, got %s" % node.get_class())


# ---------------------------------------------------------------------------
# Test 6 — Scene declares a node named ScrollContainer of type ScrollContainer
# ---------------------------------------------------------------------------

func test_scene_declares_scroll_container() -> void:
	# ScrollContainer wraps RowsContainer so long item lists don't overflow the
	# right page. If it is absent the item list will extend past the page boundary
	# with no scrollbar — a silent layout regression.
	var instance: Control = _make_scene_instance()

	var node: Node = instance.find_child("ScrollContainer", true, false)
	assert_not_null(node,
			"inventory_tab.tscn must declare a node named 'ScrollContainer'")
	if node == null:
		return
	assert_true(node is ScrollContainer,
			"'ScrollContainer' must be a ScrollContainer, got %s" % node.get_class())


# ---------------------------------------------------------------------------
# Test 7 — Scene declares a node named EquipButton of type Button
# ---------------------------------------------------------------------------

func test_scene_declares_equip_button() -> void:
	# EquipButton's pressed signal is connected to _do_equip() by populate_right().
	# Without this node the Equip action is completely unavailable via mouse
	# (keyboard shortcut still works, but the button is missing).
	var instance: Control = _make_scene_instance()

	var node: Node = instance.find_child("EquipButton", true, false)
	assert_not_null(node,
			"inventory_tab.tscn must declare a node named 'EquipButton'")
	if node == null:
		return
	assert_true(node is Button,
			"'EquipButton' must be a Button, got %s" % node.get_class())


# ---------------------------------------------------------------------------
# Test 8 — Scene declares a node named ThrowButton of type Button
# ---------------------------------------------------------------------------

func test_scene_declares_throw_button() -> void:
	# ThrowButton's pressed signal is connected to _do_throw(). Mirrors EquipButton.
	var instance: Control = _make_scene_instance()

	var node: Node = instance.find_child("ThrowButton", true, false)
	assert_not_null(node,
			"inventory_tab.tscn must declare a node named 'ThrowButton'")
	if node == null:
		return
	assert_true(node is Button,
			"'ThrowButton' must be a Button, got %s" % node.get_class())


# ---------------------------------------------------------------------------
# Test 9 — Scene declares a node named RecycleButton of type Button
# ---------------------------------------------------------------------------

func test_scene_declares_recycle_button() -> void:
	# RecycleButton's pressed signal is connected to _do_recycle(). The tab also
	# stores a ref to this button in _recycle_button so it can be disabled when
	# nothing recyclable is selected — the stable name is required for that lookup.
	var instance: Control = _make_scene_instance()

	var node: Node = instance.find_child("RecycleButton", true, false)
	assert_not_null(node,
			"inventory_tab.tscn must declare a node named 'RecycleButton'")
	if node == null:
		return
	assert_true(node is Button,
			"'RecycleButton' must be a Button, got %s" % node.get_class())


# ---------------------------------------------------------------------------
# Test 10 — Scene declares a Label named WeightLabel
# ---------------------------------------------------------------------------

func test_scene_declares_weight_label() -> void:
	# WeightLabel is the node that _update_weight_label() patches with the
	# current carry weight text. Without this stable name the weight display
	# will silently never update after the migration switches from the anonymous
	# _weight_label var to a named-node lookup.
	var instance: Control = _make_scene_instance()

	var node: Node = instance.find_child("WeightLabel", true, false)
	assert_not_null(node,
			"inventory_tab.tscn must declare a node named 'WeightLabel'")
	if node == null:
		return
	assert_true(node is Label,
			"'WeightLabel' must be a Label, got %s" % node.get_class())


# ---------------------------------------------------------------------------
# Test 11 — populate_left(null) does not crash
# ---------------------------------------------------------------------------

func test_populate_left_with_null_parent_does_not_crash() -> void:
	# NotebookTab's contract requires populate_left / populate_right to guard
	# against null. The guard exists in the current code; this test confirms it
	# survives the script rewrite during B3. A crash here would abort the
	# notebook _show_tab flow if the controller ever passes a missing page.
	var instance: Control = _make_scene_instance()
	var tab: InventoryTab = instance as InventoryTab
	assert_not_null(tab,
			"inventory_tab.tscn root must be castable to InventoryTab")
	if tab == null:
		return
	# No assertion beyond "no crash" — GUT records an error automatically if
	# an uncaught exception is thrown.
	tab.populate_left(null)
	assert_true(true, "populate_left(null) completed without error")


# ---------------------------------------------------------------------------
# Test 12 — populate_right(null) does not crash
# ---------------------------------------------------------------------------

func test_populate_right_with_null_parent_does_not_crash() -> void:
	# Mirrors test 11 for the right-page populate method.
	var instance: Control = _make_scene_instance()
	var tab: InventoryTab = instance as InventoryTab
	assert_not_null(tab,
			"inventory_tab.tscn root must be castable to InventoryTab")
	if tab == null:
		return
	tab.populate_right(null)
	assert_true(true, "populate_right(null) completed without error")
