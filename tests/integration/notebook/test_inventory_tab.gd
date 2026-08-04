## test_inventory_tab.gd
## Contract tests for the Slice 3 Inventory Tab: InventoryTab
## (ui/notebook/inventory/inventory_tab.gd) as a whole — populate_left/right,
## the PlayerData.inventory data source, and the starter-bag render. Tests
## that exercise EquipmentSlot or InventoryRow in isolation (no tab wiring)
## live in tests/unit/ui/notebook/inventory/test_equipment_slot.gd and
## test_inventory_row.gd; tests that exercise _do_equip()/_do_throw()/etc.
## against PlayerData live in test_inventory_tab_handlers.gd.
##
## --- SLICE 3 DATA SOURCE NOTE ---
## InventoryTab no longer constructs its own Inventory/sample items in _ready().
## It reads PlayerData.inventory directly (design §7.4, §13). Tests give the
## PlayerData autoload a clean, seeded resource in before_each() via
## PlayerData._load_resource(<resource>) where <resource>.reset_to_new_game()
## has been applied — this seeds the same starter bag (3x sample_leaf,
## 1x sample_boots) that PlayerDataResource._seed_starter_content() defines
## (resources/data/player_data_resource.gd), so the tab renders the same
## "starter bag" content the old _ready() sample-data block used to construct
## locally.
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
# Constants
# ---------------------------------------------------------------------------

# Scene path used by helper factories below. Using the scene (not bare
# .new()) so that @onready refs in the script resolve correctly.
const INVENTORY_TAB_SCENE: String = "res://ui/notebook/inventory/inventory_tab.tscn"


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Give PlayerData a freshly-seeded resource before every test so the tab
## reads the same starter bag (3x sample_leaf, 1x sample_boots) the old
## _ready() sample-data block used to construct locally. Per CLAUDE.md's
## dependency-injection guidance for autoload tests.
func before_each() -> void:
	var data: PlayerDataResource = PlayerDataResource.new()
	data.reset_to_new_game()
	PlayerData._load_resource(data)


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


# ---------------------------------------------------------------------------
# Test 1 — InventoryTab extends NotebookTab
# ---------------------------------------------------------------------------

func test_inventory_tab_is_a_notebook_tab() -> void:
	# InventoryTab must extend NotebookTab so the notebook controller can call
	# populate_left / populate_right polymorphically on all tabs.
	# https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html#inheritance
	#
	# Instantiate from scene so @onready refs resolve correctly.
	var packed: PackedScene = load(INVENTORY_TAB_SCENE) as PackedScene
	var tab: InventoryTab = add_child_autofree(packed.instantiate() as InventoryTab)

	assert_true(tab is NotebookTab,
			"InventoryTab must be a NotebookTab (extend NotebookTab)")


# ---------------------------------------------------------------------------
# Test 2 — populate_left() adds exactly 6 EquipmentSlot nodes
# ---------------------------------------------------------------------------
# NOTE: EquipmentSlot- and InventoryRow-only tests (setup() crash safety,
# _slot storage, _can_drop_data(), name label, _get_drag_data()) moved to
# tests/unit/ui/notebook/inventory/test_equipment_slot.gd and
# test_inventory_row.gd — they exercised those components in isolation with
# no PlayerData/tab wiring, so they belong at the unit level.

func test_inventory_tab_populate_left_adds_six_slots() -> void:
	# One EquipmentSlot per non-NONE EquipSlot value (BACKPACK, CLOTHING,
	# BOOTS, GLOVES, GOGGLES, NECKLACE). NONE is never rendered.
	# Instantiate from scene so @onready refs resolve correctly.
	var packed: PackedScene = load(INVENTORY_TAB_SCENE) as PackedScene
	var tab: InventoryTab = add_child_autofree(packed.instantiate() as InventoryTab)
	var parent: Control = add_child_autofree(Control.new())

	tab.populate_left(parent)

	var slots: Array[Node] = _find_by_class(parent, "EquipmentSlot")
	assert_eq(slots.size(), 6,
			"populate_left() must add exactly 6 EquipmentSlot nodes (one per equip slot)")


# ---------------------------------------------------------------------------
# Test 3 — populate_right() adds a weight header starting with "Weight:"
# ---------------------------------------------------------------------------

func test_inventory_tab_populate_right_adds_weight_header() -> void:
	# The weight header tells the player their current carry weight at a glance.
	# It must appear as a Label that starts with "Weight:" (case-sensitive).
	# Instantiate from scene so @onready refs resolve correctly.
	var packed: PackedScene = load(INVENTORY_TAB_SCENE) as PackedScene
	var tab: InventoryTab = add_child_autofree(packed.instantiate() as InventoryTab)
	var parent: Control = add_child_autofree(Control.new())

	tab.populate_right(parent)

	var matches: Array[Label] = _find_labels(parent,
			func(lbl: Label) -> bool: return lbl.text.begins_with("Weight:"))

	assert_true(matches.size() >= 1,
			"populate_right() must include a Label whose text starts with 'Weight:'")


# ---------------------------------------------------------------------------
# Test 4 — _do_recycle() does nothing when item is not recyclable
# ---------------------------------------------------------------------------
# NOTE: _do_equip()/_do_throw() signal-emission tests moved to
# test_inventory_tab_handlers.gd's test_do_equip_mutates_player_data_equipped
# and test_do_throw_removes_from_player_data_stacks, which assert a strict
# superset (the PlayerData mutation plus the identical signal emissions) — no
# unique failure mode survived without them here.

func test_inventory_tab_do_recycle_does_nothing_when_not_recyclable() -> void:
	# Leaves are not recyclable by default (is_recyclable == false).
	# _do_recycle() must silently skip them rather than crashing or removing items.
	# Instantiate from scene so @onready refs resolve correctly.
	var packed: PackedScene = load(INVENTORY_TAB_SCENE) as PackedScene
	var tab: InventoryTab = add_child_autofree(packed.instantiate() as InventoryTab)
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


# ---------------------------------------------------------------------------
# Test 5 — populate_right() renders PlayerData.inventory, not a tab-owned bag
# ---------------------------------------------------------------------------

func test_populate_right_renders_player_data_inventory_directly() -> void:
	# Core Slice 3 contract (design §7.4, §13): the bag rendered by
	# populate_right() IS PlayerData.inventory — not a copy constructed in
	# _ready(). Mutate PlayerData.inventory directly (bypassing the tab
	# entirely) and confirm the rendered rows reflect that mutation.
	var packed: PackedScene = load(INVENTORY_TAB_SCENE) as PackedScene
	var tab: InventoryTab = add_child_autofree(packed.instantiate() as InventoryTab)
	var parent: Control = add_child_autofree(Control.new())

	# Add a brand-new item directly to PlayerData.inventory, bypassing the tab.
	var herb: ItemData = ItemData.new()
	herb.id = &"slice3_herb"
	herb.display_name = "Slice 3 Herb"
	herb.weight = 0.1
	herb.stackable = true
	herb.max_stack = 99
	autofree(herb)
	PlayerData.inventory.add(herb, 5)

	tab.populate_right(parent)

	var rows: Array[Node] = _find_by_class(parent, "InventoryRow")
	var herb_row: InventoryRow = null
	for node in rows:
		var row: InventoryRow = node as InventoryRow
		if row._stack != null and row._stack.item_id == &"slice3_herb":
			herb_row = row
			break

	assert_not_null(herb_row,
			"populate_right() must render a row for an item added directly to PlayerData.inventory")
	if herb_row != null:
		assert_eq(herb_row._stack.count, 5,
				"the rendered row's stack count must match PlayerData.inventory's stack count")


# ---------------------------------------------------------------------------
# Test 6 — A fresh reset_to_new_game() resource renders the starter bag and
#          equipment silhouette on both pages
# ---------------------------------------------------------------------------

func test_fresh_player_data_renders_starter_bag_and_equipment_silhouette() -> void:
	# A fresh PlayerDataResource seeded via reset_to_new_game() (3x sample_leaf
	# + 1x sample_boots, see _seed_starter_content()) must render as the
	# starter bag on the right page and the equipment silhouette on the left
	# page when the tab populates both. before_each() already performed the
	# reset_to_new_game() seeding; this test asserts the rendered output.
	var packed: PackedScene = load(INVENTORY_TAB_SCENE) as PackedScene
	var tab: InventoryTab = add_child_autofree(packed.instantiate() as InventoryTab)
	var left_parent: Control = add_child_autofree(Control.new())
	var right_parent: Control = add_child_autofree(Control.new())

	tab.populate_left(left_parent)
	tab.populate_right(right_parent)

	# Left page: 6 equipment slots regardless of what's equipped.
	var slots: Array[Node] = _find_by_class(left_parent, "EquipmentSlot")
	assert_eq(slots.size(), 6,
			"populate_left() must render all 6 equipment slots for a fresh starter game")

	# Right page: exactly 2 rows (sample_leaf x3, sample_boots x1).
	var rows: Array[Node] = _find_by_class(right_parent, "InventoryRow")
	var leaf_row: InventoryRow = null
	var boots_row: InventoryRow = null
	for node in rows:
		var row: InventoryRow = node as InventoryRow
		if row._stack == null:
			continue
		if row._stack.item_id == &"sample_leaf":
			leaf_row = row
		elif row._stack.item_id == &"sample_boots":
			boots_row = row

	assert_not_null(leaf_row, "the starter bag must render a sample_leaf row")
	assert_not_null(boots_row, "the starter bag must render a sample_boots row")
	if leaf_row != null:
		assert_eq(leaf_row._stack.count, 3, "the starter sample_leaf row must show count 3")
	if boots_row != null:
		assert_eq(boots_row._stack.count, 1, "the starter sample_boots row must show count 1")

	# Weight header must reflect the seeded bag's non-zero weight
	# (3 x 0.5 + 1 x 0.8 = 2.3 kg per _seed_starter_content()).
	var weight_labels: Array[Label] = _find_labels(right_parent,
			func(lbl: Label) -> bool: return lbl.text.begins_with("Weight:"))
	assert_true(weight_labels.size() >= 1,
			"populate_right() must render a Weight: label for the starter bag")
	if weight_labels.size() >= 1:
		assert_ne(weight_labels[0].text, "Weight: 0.0 / ∞",
				"the starter bag's weight header must reflect a non-zero total weight")
