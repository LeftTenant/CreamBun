## test_inventory_tab_handlers.gd
## Integration tests for InventoryTab signal handlers.
##
## WHAT THESE TESTS GUARD
## ----------------------
## inventory_tab.gd instantiates EquipmentSlot and InventoryRow nodes from their
## respective .tscn files (via preload(...).instantiate()). These tests confirm
## the four critical signal wires hold through that scene-instantiation path:
##
##   1. slot_drop_received — wired in populate_left(); drives _on_slot_drop()
##   2. row.selected       — wired in _build_right_page(); drives _on_row_selected()
##   3. WeightLabel update — _update_weight_label() resolves the named node from
##                           the scene-built right page
##   4. _do_recycle() positive path — verifies the recyclable-item branch works
##      (complement to the existing negative test)
##
## WHY THIS IS INTEGRATION (not unit)
## ------------------------------------
## These tests require multiple classes wired together:
##   - InventoryTab → populate_left/right → EquipmentSlot / InventoryRow
##   - EquipmentSlot.slot_drop_received → _on_slot_drop → GameEvents.inventory_changed
##   - InventoryRow.selected → _on_row_selected → tab._selected_row
## A pure unit test of the handler alone would miss signal-wiring bugs in the
## scene-instantiation construction path.
##
## Requires GUT: https://github.com/bitwes/Gut
## Install via Godot Asset Library (search "GUT - Godot Unit Testing").
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd -gselect=test_inventory_tab_handlers.gd -gexit

class_name TestInventoryTabHandlers
extends GutTest


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const SCENE_PATH: String = "res://ui/notebook/inventory/inventory_tab.tscn"


# ---------------------------------------------------------------------------
# Shared state
# ---------------------------------------------------------------------------

## The InventoryTab under test — instantiated from the scene so @onready and
## named-node lookups inside the script work exactly as they will in-game.
var _tab: InventoryTab

## Disposable parent Controls used as populate targets. Providing real Controls
## (not bare Control.new()) ensures anchor presets applied inside populate_left /
## populate_right have a rect to anchor into.
var _left_parent: Control
var _right_parent: Control


# ---------------------------------------------------------------------------
# Setup / Teardown
# ---------------------------------------------------------------------------

func before_each() -> void:
	# Instantiate from the scene rather than InventoryTab.new() so the test runs
	# against the same construction path as the in-game notebook controller.
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	_tab = packed.instantiate() as InventoryTab
	add_child_autofree(_tab)

	_left_parent = Control.new()
	_left_parent.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(_left_parent)

	_right_parent = Control.new()
	_right_parent.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(_right_parent)

	_tab.populate_left(_left_parent)
	_tab.populate_right(_right_parent)


func after_each() -> void:
	# Autofree handles node cleanup. Nothing extra needed here.
	pass


# ---------------------------------------------------------------------------
# Helper — walk a subtree and return the first node matching a class_name string
# ---------------------------------------------------------------------------

## Recursively find the first node in root's subtree whose script has the given
## global class_name. Used because find_children() type-string matching can be
## unreliable with custom class_name declarations in some Godot versions.
##
## @param root       the node whose subtree to search
## @param class_name_str  the exact class_name string to match
## @return the first matching node, or null if none found
func _find_first_by_class(root: Node, class_name_str: String) -> Node:
	for child: Node in root.get_children():
		if child.get_script() != null:
			var script: Script = child.get_script() as Script
			if script != null and script.get_global_name() == class_name_str:
				return child
		var found: Node = _find_first_by_class(child, class_name_str)
		if found != null:
			return found
	return null


## Walk root's subtree and return every node whose script has the given class_name.
##
## @param root           the node whose subtree to search
## @param class_name_str the exact class_name string to match
## @return Array of matching nodes in depth-first order
func _find_all_by_class(root: Node, class_name_str: String) -> Array[Node]:
	var result: Array[Node] = []
	for child: Node in root.get_children():
		if child.get_script() != null:
			var script: Script = child.get_script() as Script
			if script != null and script.get_global_name() == class_name_str:
				result.append(child)
		result.append_array(_find_all_by_class(child, class_name_str))
	return result


# ---------------------------------------------------------------------------
# Test 1 — slot_drop_received from an EquipmentSlot reaches _on_slot_drop
#           and emits GameEvents.inventory_changed
# ---------------------------------------------------------------------------

func test_slot_drop_received_emits_inventory_changed() -> void:
	# This test verifies the full signal chain:
	#   EquipmentSlot.slot_drop_received → _on_slot_drop → inventory.equip()
	#   → GameEvents.inventory_changed
	#
	# The chain is established inside populate_left() by:
	#   slot_node.slot_drop_received.connect(_on_slot_drop)
	# The slot_node comes from preload(...).instantiate() — this test confirms the
	# connection is established for scene-instantiated slots.
	#
	# We invoke _drop_data() directly rather than simulating GUI drag-and-drop
	# because the latter requires a running OS window and a real drag context.
	# _drop_data() emits slot_drop_received synchronously, so no await is needed
	# between the emit and the GameEvents assertion.

	# Find any BOOTS slot — it accepts boots items and is reliably present.
	var boots_slot: EquipmentSlot = null
	var slots: Array[Node] = _find_all_by_class(_left_parent, "EquipmentSlot")
	for node: Node in slots:
		var es: EquipmentSlot = node as EquipmentSlot
		if es._slot == ItemData.EquipSlot.BOOTS:
			boots_slot = es
			break

	assert_not_null(boots_slot,
			"A BOOTS EquipmentSlot must exist in the left page after populate_left()")
	if boots_slot == null:
		return

	# Build a boots ItemStack payload matching the slot.
	var boots: ItemData = ItemData.new()
	boots.id = &"drop_test_boots"
	boots.display_name = "Drop Test Boots"
	boots.weight = 0.8
	boots.equip_slot = ItemData.EquipSlot.BOOTS
	autofree(boots)

	var stack: ItemStack = ItemStack.new()
	stack.item_id = boots.id
	stack.item = boots
	stack.count = 1
	autofree(stack)

	# Also add this item to the tab's inventory so equip() doesn't silently fail.
	# _tab._inventory is public in Phase 1 for exactly this kind of test setup.
	_tab._inventory.add(boots, 1)
	_tab._item_registry[boots.id] = boots

	watch_signals(GameEvents)

	# _drop_data() validates the payload via _can_drop_data() internally, then
	# emits slot_drop_received. We bypass that and emit the signal directly so
	# the test doesn't depend on the drag-and-drop GUI context.
	# https://docs.godotengine.org/en/stable/classes/class_signal.html#class-signal-method-emit
	boots_slot.slot_drop_received.emit(stack, ItemData.EquipSlot.BOOTS)

	assert_signal_emitted(GameEvents, "inventory_changed",
			"slot_drop_received on a BOOTS slot must ultimately emit GameEvents.inventory_changed")


# ---------------------------------------------------------------------------
# Test 2 — row.selected connects to _on_row_selected;
#           clicking a row sets _selected_row and calls set_selected(true)
# ---------------------------------------------------------------------------

func test_row_selected_signal_sets_active_selection() -> void:
	# _on_row_selected is connected to each row's selected signal inside
	# _build_right_page(). The rows come from preload(...).instantiate() — this test
	# confirms the connection holds for scene-instantiated rows.
	#
	# We emit selected directly (rather than simulating a mouse click) so the test
	# does not depend on a real viewport focus or an OS window being present.

	var rows: Array[Node] = _find_all_by_class(_right_parent, "InventoryRow")
	assert_true(rows.size() > 0,
			"At least one InventoryRow must exist after populate_right()")
	if rows.is_empty():
		return

	var first_row: InventoryRow = rows[0] as InventoryRow

	# Verify the tab starts with no selection so the change is observable.
	assert_null(_tab._selected_row,
			"_selected_row must be null before any row is clicked")

	# Emit the signal as a left-click would.
	first_row.selected.emit(first_row)

	# _on_row_selected stores the row reference and calls set_selected(true).
	assert_eq(_tab._selected_row, first_row,
			"_selected_row must point to the row that emitted selected")

	# Confirm the visual selection rect is visible — set_selected(true) was called.
	# We check _selection_rect.visible rather than calling set_selected again so
	# we detect if the signal handler forgot to call it.
	var selection_rect: Node = first_row.find_child("SelectionRect", true, false)
	assert_not_null(selection_rect,
			"InventoryRow must contain a named SelectionRect node")
	if selection_rect != null:
		assert_true((selection_rect as ColorRect).visible,
				"SelectionRect must be visible after _on_row_selected fires")


# ---------------------------------------------------------------------------
# Test 3 — _do_throw() removes an item and updates the WeightLabel text
# ---------------------------------------------------------------------------

func test_do_throw_updates_weight_label() -> void:
	# _update_weight_label() is called after every action that changes inventory.
	# It resolves WeightLabel via a named-node lookup on the scene-built right
	# page. This test confirms the label text changes after a throw, which means
	# the lookup found the node and the text was updated.
	#
	# We capture the text before throwing and assert it differs afterwards. We do
	# not assert a specific string because the exact format ("Weight: X / Y") is
	# an implementation detail and might change.

	# Select the leaf row — the tab always seeds "sample_leaf" in _ready().
	var rows: Array[Node] = _find_all_by_class(_right_parent, "InventoryRow")
	var leaf_row: InventoryRow = null
	for node: Node in rows:
		var row: InventoryRow = node as InventoryRow
		if row._stack != null and row._stack.item_id == &"sample_leaf":
			leaf_row = row
			break

	assert_not_null(leaf_row, "A sample_leaf InventoryRow must exist after populate_right()")
	if leaf_row == null:
		return

	# Find the WeightLabel before the throw so we can assert it changes.
	# _build_right_page() produces a node named "WeightLabel" in the right page tree.
	var weight_label_node: Node = _right_parent.find_child("WeightLabel", true, false)
	assert_not_null(weight_label_node,
			"A named WeightLabel node must exist after populate_right()")
	var weight_label: Label = weight_label_node as Label
	if weight_label == null:
		return

	var text_before: String = weight_label.text

	# Select and throw one leaf.
	_tab._selected_row = leaf_row
	_tab._do_throw()

	# After _do_throw() the page is rebuilt so the weight_label reference may point
	# to a freed node. Find it again from the refreshed tree.
	var refreshed_node: Node = _right_parent.find_child("WeightLabel", true, false)
	if refreshed_node == null and _tab._weight_label != null:
		refreshed_node = _tab._weight_label
	assert_not_null(refreshed_node,
			"WeightLabel must still be findable after _do_throw() rebuilds the page")
	if refreshed_node == null:
		return

	var text_after: String = (refreshed_node as Label).text
	assert_ne(text_after, text_before,
			"WeightLabel text must change after _do_throw() removes an item")


# ---------------------------------------------------------------------------
# Test 4 — _do_recycle() positive path emits item_recycled and inventory_changed
# ---------------------------------------------------------------------------

func test_do_recycle_on_recyclable_item_emits_signals() -> void:
	# The existing test in test_inventory_tab.gd covers the negative path
	# (_do_recycle does nothing when item is NOT recyclable). This test covers
	# the positive path: when the item IS recyclable, both item_recycled and
	# inventory_changed must be emitted. This confirms the handler survives the
	# migration when the branch condition is true.
	#
	# We create a recyclable item, add it to the tab's inventory, populate the
	# right page so a row is created, then select it and call _do_recycle().

	# Build a recyclable ingredient. recycle_yield is empty here because we only
	# need to verify signal emission, not that yield items were added correctly.
	var herb: ItemData = ItemData.new()
	herb.id = &"test_herb"
	herb.display_name = "Test Herb"
	herb.weight = 0.1
	herb.stackable = true
	herb.max_stack = 99
	herb.is_recyclable = true
	# recycle_yield stays empty — _do_recycle iterates it safely even when empty.
	autofree(herb)

	# Add to tab's inventory and registry so _build_right_page creates a row for it.
	_tab._inventory.add(herb, 2)
	_tab._item_registry[herb.id] = herb

	# Rebuild the right page so the new row exists.
	_tab.populate_right(_right_parent)

	# Find the herb row.
	var rows: Array[Node] = _find_all_by_class(_right_parent, "InventoryRow")
	var herb_row: InventoryRow = null
	for node: Node in rows:
		var row: InventoryRow = node as InventoryRow
		if row._stack != null and row._stack.item_id == &"test_herb":
			herb_row = row
			break

	assert_not_null(herb_row,
			"A test_herb InventoryRow must exist after populate_right() with the herb in inventory")
	if herb_row == null:
		return

	_tab._selected_row = herb_row

	watch_signals(GameEvents)
	_tab._do_recycle()

	assert_signal_emitted(GameEvents, "item_recycled",
			"_do_recycle() must emit GameEvents.item_recycled when item.is_recyclable is true")
	assert_signal_emitted(GameEvents, "inventory_changed",
			"_do_recycle() must emit GameEvents.inventory_changed when item.is_recyclable is true")
