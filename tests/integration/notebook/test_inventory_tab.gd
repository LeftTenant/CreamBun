## test_inventory_tab.gd
## TDD contract tests for the Phase 1 Inventory Tab.
##
## Covers:
##   - InventoryTab  (ui/notebook/inventory/inventory_tab.gd)
##   - EquipmentSlot (ui/notebook/inventory/equipment_slot.gd)
##   - InventoryRow  (ui/notebook/inventory/inventory_row.gd)
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

class_name TestInventoryTab
extends GutTest


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Walk root's full subtree and return every Label whose text satisfies predicate.
## Labels may be deeply nested inside VBox/HBox containers, so a recursive walk
## is necessary — child[0].get_children() alone would miss grandchildren.
##
## @param root      - the node whose subtree to search
## @param predicate - Callable(Label) -> bool; true means include this label
## @return Array of matching Labels in depth-first order
func _find_labels(root: Node, predicate: Callable) -> Array[Label]:
	var result: Array[Label] = []
	for child in root.get_children():
		if child is Label and predicate.call(child as Label):
			result.append(child as Label)
		result.append_array(_find_labels(child, predicate))
	return result


## Find all nodes of a given class anywhere in root's subtree.
## Needed because GDScript's find_children() doesn't accept class objects,
## only type-name strings, which breaks with custom class_name declarations
## in some editor versions.
##
## @param root      - the node whose subtree to search
## @param type_name - the exact class_name string to match against class_name
## @return Array of matching Node objects
func _find_by_class(root: Node, type_name: String) -> Array[Node]:
	var result: Array[Node] = []
	for child in root.get_children():
		if child.get_script() != null:
			var script: Script = child.get_script() as Script
			if script != null and script.get_global_name() == type_name:
				result.append(child)
		result.append_array(_find_by_class(child, type_name))
	return result


## Create a minimal boots ItemData for use in multiple tests.
func _make_boots() -> ItemData:
	var boots: ItemData = ItemData.new()
	boots.id = &"test_boots"
	boots.display_name = "Test Boots"
	boots.weight = 0.8
	boots.equip_slot = ItemData.EquipSlot.BOOTS
	return boots  # caller must autofree


## Create a minimal leaf ItemData (stackable, no equip slot).
func _make_leaf() -> ItemData:
	var leaf: ItemData = ItemData.new()
	leaf.id = &"test_leaf"
	leaf.display_name = "Test Leaf"
	leaf.weight = 0.5
	leaf.stackable = true
	leaf.max_stack = 99
	return leaf  # caller must autofree


# ---------------------------------------------------------------------------
# Test 1 — InventoryTab extends NotebookTab
# ---------------------------------------------------------------------------

func test_inventory_tab_is_a_notebook_tab() -> void:
	# InventoryTab must extend NotebookTab so the notebook controller can call
	# populate_left / populate_right polymorphically on all tabs.
	# https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html#inheritance
	var tab: InventoryTab = InventoryTab.new()
	autofree(tab)

	assert_true(tab is NotebookTab,
			"InventoryTab must be a NotebookTab (extend NotebookTab)")


# ---------------------------------------------------------------------------
# Test 2 — EquipmentSlot.setup() does not crash
# ---------------------------------------------------------------------------

func test_equipment_slot_setup_does_not_crash() -> void:
	# setup() with a null item (empty slot) must be safe — it is the initial
	# state before the player has equipped anything.
	var slot: EquipmentSlot = add_child_autofree(EquipmentSlot.new())

	# If this raises an error GUT records a failure automatically.
	slot.setup(ItemData.EquipSlot.BOOTS, null)

	assert_true(true, "setup() with null item must not crash")


# ---------------------------------------------------------------------------
# Test 3 — EquipmentSlot stores the slot type passed to setup()
# ---------------------------------------------------------------------------

func test_equipment_slot_stores_slot_type() -> void:
	# _slot is the internal record that _can_drop_data() compares against
	# incoming drag data. It must match the value passed to setup().
	var slot: EquipmentSlot = add_child_autofree(EquipmentSlot.new())
	slot.setup(ItemData.EquipSlot.GLOVES, null)

	assert_eq(slot._slot, ItemData.EquipSlot.GLOVES,
			"EquipmentSlot._slot must equal the value passed to setup()")


# ---------------------------------------------------------------------------
# Test 4 — EquipmentSlot rejects items whose equip_slot does not match
# ---------------------------------------------------------------------------

func test_equipment_slot_can_drop_returns_false_for_wrong_slot() -> void:
	# A BOOTS slot must refuse a GLOVES item so the player cannot put the
	# wrong item type in the wrong slot.
	var gloves: ItemData = ItemData.new()
	gloves.id = &"test_gloves"
	gloves.equip_slot = ItemData.EquipSlot.GLOVES
	autofree(gloves)

	var stack: ItemStack = ItemStack.new()
	stack.item_id = gloves.id
	stack.item = gloves  # set runtime reference so _can_drop_data can read equip_slot
	autofree(stack)

	var eq: EquipmentSlot = add_child_autofree(EquipmentSlot.new())
	eq.setup(ItemData.EquipSlot.BOOTS, null)

	var data: Dictionary = {"kind": "item", "stack": stack}
	assert_false(eq._can_drop_data(Vector2.ZERO, data),
			"_can_drop_data must return false when item.equip_slot != this slot")


# ---------------------------------------------------------------------------
# Test 5 — EquipmentSlot accepts items whose equip_slot matches
# ---------------------------------------------------------------------------

func test_equipment_slot_can_drop_returns_true_for_matching_slot() -> void:
	# A BOOTS slot must accept a BOOTS item so drag-to-equip works.
	var boots: ItemData = _make_boots()
	autofree(boots)

	var stack: ItemStack = ItemStack.new()
	stack.item_id = boots.id
	stack.item = boots
	autofree(stack)

	var eq: EquipmentSlot = add_child_autofree(EquipmentSlot.new())
	eq.setup(ItemData.EquipSlot.BOOTS, null)

	var data: Dictionary = {"kind": "item", "stack": stack}
	assert_true(eq._can_drop_data(Vector2.ZERO, data),
			"_can_drop_data must return true when item.equip_slot == this slot")


# ---------------------------------------------------------------------------
# Test 6 — InventoryRow.setup() puts the item name into a Label child
# ---------------------------------------------------------------------------

func test_inventory_row_setup_sets_name_label() -> void:
	# The item name must appear as a Label text so the player can scan the list.
	var item: ItemData = ItemData.new()
	item.id = &"berry"
	item.display_name = "Berry"
	item.weight = 0.2
	autofree(item)

	var stack: ItemStack = ItemStack.new()
	stack.item_id = item.id
	stack.count = 3
	stack.item = item
	autofree(stack)

	var row: InventoryRow = add_child_autofree(InventoryRow.new())
	row.setup(stack, item)

	var matches: Array[Label] = _find_labels(row,
			func(lbl: Label) -> bool: return lbl.text == "Berry")

	assert_true(matches.size() >= 1,
			"InventoryRow must contain a Label with text == item.display_name after setup()")


# ---------------------------------------------------------------------------
# Test 7 — InventoryRow._get_drag_data() returns the expected dictionary shape
# ---------------------------------------------------------------------------

func test_inventory_row_get_drag_data_returns_correct_structure() -> void:
	# The drag payload must carry "kind" and "stack" so EquipmentSlot can
	# inspect it in _can_drop_data() and identify it as an item drag.
	var item: ItemData = _make_leaf()
	autofree(item)

	var stack: ItemStack = ItemStack.new()
	stack.item_id = item.id
	stack.count = 1
	stack.item = item
	autofree(stack)

	var row: InventoryRow = add_child_autofree(InventoryRow.new())
	row.setup(stack, item)

	# Godot 4.6 added a gui_is_dragging() assertion inside set_drag_preview()
	# that fires when no active drag context exists. force_drag() establishes a
	# drag context (sets gui_is_dragging() = true on the viewport) so the
	# subsequent _get_drag_data() call can safely invoke set_drag_preview().
	# We pass a throwaway payload and no preview to start the context cheaply.
	# See: https://docs.godotengine.org/en/stable/classes/class_control.html#class-control-method-force-drag
	row.force_drag({}, null)

	# _get_drag_data's return type is Variant per Godot's drag API contract.
	var data: Variant = row._get_drag_data(Vector2.ZERO)

	assert_true(data is Dictionary,
			"_get_drag_data must return a Dictionary")
	assert_eq((data as Dictionary)["kind"], "item",
			"_get_drag_data payload must have kind == 'item'")
	assert_true((data as Dictionary).has("stack"),
			"_get_drag_data payload must include the 'stack' key")


# ---------------------------------------------------------------------------
# Test 8 — populate_left() adds exactly 6 EquipmentSlot nodes
# ---------------------------------------------------------------------------

func test_inventory_tab_populate_left_adds_six_slots() -> void:
	# One EquipmentSlot per non-NONE EquipSlot value (BACKPACK, CLOTHING,
	# BOOTS, GLOVES, GOGGLES, NECKLACE). NONE is never rendered.
	var tab: InventoryTab = add_child_autofree(InventoryTab.new())
	var parent: Control = add_child_autofree(Control.new())

	tab.populate_left(parent)

	var slots: Array[Node] = _find_by_class(parent, "EquipmentSlot")
	assert_eq(slots.size(), 6,
			"populate_left() must add exactly 6 EquipmentSlot nodes (one per equip slot)")


# ---------------------------------------------------------------------------
# Test 9 — populate_right() adds a weight header starting with "Weight:"
# ---------------------------------------------------------------------------

func test_inventory_tab_populate_right_adds_weight_header() -> void:
	# The weight header tells the player their current carry weight at a glance.
	# It must appear as a Label that starts with "Weight:" (case-sensitive).
	var tab: InventoryTab = add_child_autofree(InventoryTab.new())
	var parent: Control = add_child_autofree(Control.new())

	tab.populate_right(parent)

	var matches: Array[Label] = _find_labels(parent,
			func(lbl: Label) -> bool: return lbl.text.begins_with("Weight:"))

	assert_true(matches.size() >= 1,
			"populate_right() must include a Label whose text starts with 'Weight:'")


# ---------------------------------------------------------------------------
# Test 10 — _do_equip() emits inventory_changed when a boots row is selected
# ---------------------------------------------------------------------------

func test_inventory_tab_do_equip_emits_inventory_changed() -> void:
	# When the player selects an equippable item row and presses E, the bag
	# must emit inventory_changed so the HUD weight bar can refresh.
	var tab: InventoryTab = add_child_autofree(InventoryTab.new())
	var left_parent: Control = add_child_autofree(Control.new())
	var right_parent: Control = add_child_autofree(Control.new())

	tab.populate_left(left_parent)
	tab.populate_right(right_parent)

	# Find the boots row among the rendered rows. The tab pre-populates with
	# a "sample_boots" item (equip_slot == BOOTS) in _ready().
	var all_rows: Array[Node] = _find_by_class(right_parent, "InventoryRow")
	var boots_row: InventoryRow = null
	for node in all_rows:
		var row: InventoryRow = node as InventoryRow
		if row._stack != null and row._stack.item_id == &"sample_boots":
			boots_row = row
			break

	assert_not_null(boots_row, "A boots InventoryRow must exist in the right page after populate_right()")

	# Select the boots row so _do_equip() has a target.
	tab._selected_row = boots_row

	# Watch the GameEvents singleton for the inventory_changed signal.
	# GUT's watch_signals + assert_signal_emitted approach:
	# https://gut.readthedocs.io/en/latest/Signals.html
	watch_signals(GameEvents)
	tab._do_equip()

	assert_signal_emitted(GameEvents, "inventory_changed",
			"_do_equip() must emit GameEvents.inventory_changed when equipping a boots item")


# ---------------------------------------------------------------------------
# Test 11 — _do_throw() emits item_dropped
# ---------------------------------------------------------------------------

func test_inventory_tab_do_throw_emits_item_dropped() -> void:
	# Throwing an item must notify the world (for future particle effects, etc.)
	# via the GameEvents signal bus.
	var tab: InventoryTab = add_child_autofree(InventoryTab.new())
	var parent: Control = add_child_autofree(Control.new())
	tab.populate_right(parent)

	# Select the leaf row — the tab always has a "sample_leaf" stack in _ready().
	var all_rows: Array[Node] = _find_by_class(parent, "InventoryRow")
	var leaf_row: InventoryRow = null
	for node in all_rows:
		var row: InventoryRow = node as InventoryRow
		if row._stack != null and row._stack.item_id == &"sample_leaf":
			leaf_row = row
			break

	assert_not_null(leaf_row, "A leaf InventoryRow must exist after populate_right()")
	tab._selected_row = leaf_row

	watch_signals(GameEvents)
	tab._do_throw()

	assert_signal_emitted(GameEvents, "item_dropped",
			"_do_throw() must emit GameEvents.item_dropped when throwing a selected item")


# ---------------------------------------------------------------------------
# Test 12 — _do_recycle() does nothing when item is not recyclable
# ---------------------------------------------------------------------------

func test_inventory_tab_do_recycle_does_nothing_when_not_recyclable() -> void:
	# Leaves are not recyclable by default (is_recyclable == false).
	# _do_recycle() must silently skip them rather than crashing or removing items.
	var tab: InventoryTab = add_child_autofree(InventoryTab.new())
	var parent: Control = add_child_autofree(Control.new())
	tab.populate_right(parent)

	# Select the leaf row.
	var all_rows: Array[Node] = _find_by_class(parent, "InventoryRow")
	var leaf_row: InventoryRow = null
	for node in all_rows:
		var row: InventoryRow = node as InventoryRow
		if row._stack != null and row._stack.item_id == &"sample_leaf":
			leaf_row = row
			break

	assert_not_null(leaf_row, "A leaf InventoryRow must exist after populate_right()")
	tab._selected_row = leaf_row

	watch_signals(GameEvents)
	tab._do_recycle()

	assert_signal_not_emitted(GameEvents, "item_recycled",
			"_do_recycle() must NOT emit item_recycled when the item is not recyclable")
