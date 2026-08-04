## test_inventory_row.gd
## Behavior tests for InventoryRow (ui/notebook/inventory/inventory_row.gd).
##
## RELOCATED from tests/integration/notebook/test_inventory_tab.gd (Tests 6-7):
## these only exercise InventoryRow in isolation — no PlayerData, no tab
## wiring — so they belong at the unit level, mirroring the split between
## test_equipment_slot.gd (behavior) and test_equipment_slot_scene.gd
## (structure) already used elsewhere in this folder.
##
## --- SUBJECT CONSTRUCTION NOTE ---
## InventoryRow is instantiated from inventory_row.tscn (not .new()) because
## the script resolves named children via @onready references that only
## exist when the node comes from the scene.
##
## Requires GUT: https://github.com/bitwes/Gut
## Install via Godot Asset Library (search "GUT - Godot Unit Testing").
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd -gselect=test_inventory_row.gd -gexit

class_name TestInventoryRow
extends GutTest


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const SCENE_PATH: String = "res://ui/notebook/inventory/inventory_row.tscn"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Instantiate inventory_row.tscn and add it to the scene tree so @onready
## refs resolve before setup() is called.
##
## @return the instantiated InventoryRow root node
func _make_row() -> InventoryRow:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	var instance: InventoryRow = packed.instantiate() as InventoryRow
	add_child_autofree(instance)
	return instance


## Walk root's full subtree and return every Label whose text satisfies predicate.
## Labels may be deeply nested inside VBox/HBox containers, so a recursive walk
## is necessary — child[0].get_children() alone would miss grandchildren.
func _find_labels(root: Node, predicate: Callable) -> Array[Label]:
	var result: Array[Label] = []
	for child in root.get_children():
		if child is Label and predicate.call(child as Label):
			result.append(child as Label)
		result.append_array(_find_labels(child, predicate))
	return result


# ---------------------------------------------------------------------------
# Test 1 — setup() puts the item name into a Label child
# ---------------------------------------------------------------------------

func test_setup_sets_name_label() -> void:
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

	var row: InventoryRow = _make_row()
	row.setup(stack, item)

	var matches: Array[Label] = _find_labels(row,
			func(lbl: Label) -> bool: return lbl.text == "Berry")

	assert_true(matches.size() >= 1,
			"InventoryRow must contain a Label with text == item.display_name after setup()")


# ---------------------------------------------------------------------------
# Test 2 — _get_drag_data() returns the expected dictionary shape
# ---------------------------------------------------------------------------

func test_get_drag_data_returns_correct_structure() -> void:
	# The drag payload must carry "kind" and "stack" so EquipmentSlot can
	# inspect it in _can_drop_data() and identify it as an item drag.
	var item: ItemData = ItemData.new()
	item.id = &"test_leaf"
	item.display_name = "Test Leaf"
	item.weight = 0.5
	item.stackable = true
	item.max_stack = 99
	autofree(item)

	var stack: ItemStack = ItemStack.new()
	stack.item_id = item.id
	stack.count = 1
	stack.item = item
	autofree(stack)

	var row: InventoryRow = _make_row()
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
