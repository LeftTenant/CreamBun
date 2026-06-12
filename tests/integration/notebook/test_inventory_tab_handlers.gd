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
## --- SLICE 3 DATA SOURCE NOTE ---
## InventoryTab no longer constructs its own Inventory/_item_registry in
## _ready() — it reads PlayerData.inventory directly (design §7.4, §13).
## before_each() seeds PlayerData with a fresh reset_to_new_game() resource
## (3x sample_leaf, 1x sample_boots — see _seed_starter_content()) BEFORE
## instantiating the tab and calling populate_left/right, so the rendered
## rows come from the same starter bag the old _ready() sample-data block
## used to construct locally.
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
	# Seed PlayerData BEFORE instantiating the tab so populate_left/right
	# (called below) build their rows/slots from the starter bag, exactly as
	# a freshly-loaded game would. See the SLICE 3 DATA SOURCE NOTE above.
	var data: PlayerDataResource = PlayerDataResource.new()
	data.reset_to_new_game()
	PlayerData._load_resource(data)

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


## Find the rendered InventoryRow for a given item_id, or null if not present.
func _find_row(root: Node, item_id: StringName) -> InventoryRow:
	var rows: Array[Node] = _find_all_by_class(root, "InventoryRow")
	for node: Node in rows:
		var row: InventoryRow = node as InventoryRow
		if row._stack != null and row._stack.item_id == item_id:
			return row
	return null


## Count how many stacks in `inventory` have the given item_id, summing counts
## across any split stacks (mirrors the loop in Inventory.remove()).
func _stack_count(inventory: Inventory, item_id: StringName) -> int:
	var total: int = 0
	for stack: ItemStack in inventory.stacks:
		if stack.item_id == item_id:
			total += stack.count
	return total


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

	# Also add this item to PlayerData.inventory so equip() doesn't silently
	# fail. _on_slot_drop() resolves the item via stack.item (set above) with
	# a registry fallback, so this is mainly to keep Inventory.equip()'s
	# bookkeeping consistent.
	PlayerData.inventory.add(boots, 1)

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

	# Select the leaf row — PlayerData.inventory always has a "sample_leaf"
	# stack after before_each()'s reset_to_new_game().
	var leaf_row: InventoryRow = _find_row(_right_parent, &"sample_leaf")
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
	# We create a recyclable item, add it to PlayerData.inventory, repopulate
	# the right page so a row is created, then select it and call _do_recycle().

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

	# Add directly to PlayerData.inventory — the single source of truth.
	PlayerData.inventory.add(herb, 2)

	# Rebuild the right page so the new row exists.
	_tab.populate_right(_right_parent)

	# Find the herb row.
	var herb_row: InventoryRow = _find_row(_right_parent, &"test_herb")
	assert_not_null(herb_row,
			"A test_herb InventoryRow must exist after populate_right() with the herb in PlayerData.inventory")
	if herb_row == null:
		return

	_tab._selected_row = herb_row

	watch_signals(GameEvents)
	_tab._do_recycle()

	assert_signal_emitted(GameEvents, "item_recycled",
			"_do_recycle() must emit GameEvents.item_recycled when item.is_recyclable is true")
	assert_signal_emitted(GameEvents, "inventory_changed",
			"_do_recycle() must emit GameEvents.inventory_changed when item.is_recyclable is true")


# ---------------------------------------------------------------------------
# Test 5 — _do_equip() mutates PlayerData.inventory.equipped (not a tab-local copy)
# ---------------------------------------------------------------------------

func test_do_equip_mutates_player_data_equipped() -> void:
	# Core Slice 3 contract: _do_equip() must call equip() on the SAME
	# Inventory instance held by PlayerData, so PlayerData.inventory.equipped
	# reflects the change immediately — not a tab-local copy that the rest of
	# the game can't see.
	var boots_row: InventoryRow = _find_row(_right_parent, &"sample_boots")
	assert_not_null(boots_row, "A sample_boots InventoryRow must exist after populate_right()")
	if boots_row == null:
		return

	_tab._selected_row = boots_row

	watch_signals(GameEvents)
	_tab._do_equip()

	assert_true(PlayerData.inventory.equipped.has(ItemData.EquipSlot.BOOTS),
			"_do_equip() must place the boots into PlayerData.inventory.equipped[BOOTS]")
	assert_eq((PlayerData.inventory.equipped.get(ItemData.EquipSlot.BOOTS) as ItemData).id, &"sample_boots",
			"PlayerData.inventory.equipped[BOOTS] must be the sample_boots item after equipping")

	assert_signal_emitted(GameEvents, "item_equipped",
			"_do_equip() must emit GameEvents.item_equipped")
	assert_signal_emitted(GameEvents, "inventory_changed",
			"_do_equip() must emit GameEvents.inventory_changed")


# ---------------------------------------------------------------------------
# Test 6 — _do_throw() removes the item from PlayerData.inventory.stacks
# ---------------------------------------------------------------------------

func test_do_throw_removes_from_player_data_stacks() -> void:
	# Core Slice 3 contract: _do_throw() must remove from
	# PlayerData.inventory.stacks (the single source of truth), not a
	# tab-local copy.
	var before_count: int = _stack_count(PlayerData.inventory, &"sample_leaf")
	assert_eq(before_count, 3, "the starter bag should have 3x sample_leaf before throwing")

	var leaf_row: InventoryRow = _find_row(_right_parent, &"sample_leaf")
	assert_not_null(leaf_row, "A sample_leaf InventoryRow must exist after populate_right()")
	if leaf_row == null:
		return

	_tab._selected_row = leaf_row

	watch_signals(GameEvents)
	_tab._do_throw()

	var after_count: int = _stack_count(PlayerData.inventory, &"sample_leaf")
	assert_eq(after_count, before_count - 1,
			"_do_throw() must remove exactly one unit of sample_leaf from PlayerData.inventory.stacks")

	assert_signal_emitted(GameEvents, "item_dropped",
			"_do_throw() must emit GameEvents.item_dropped")
	assert_signal_emitted(GameEvents, "inventory_changed",
			"_do_throw() must emit GameEvents.inventory_changed")


# ---------------------------------------------------------------------------
# Test 7 — _do_recycle() mutates PlayerData.inventory.stacks
#          (consumed item removed, yield items added)
# ---------------------------------------------------------------------------

func test_do_recycle_mutates_player_data_stacks_with_yield() -> void:
	# Build a recyclable item whose recycle_yield contains a hydrated ItemStack
	# (item ref set) so _do_recycle()'s yield-adding loop runs.
	var yield_item: ItemData = ItemData.new()
	yield_item.id = &"test_herb_scraps"
	yield_item.display_name = "Herb Scraps"
	yield_item.weight = 0.05
	yield_item.stackable = true
	yield_item.max_stack = 99
	autofree(yield_item)

	var yield_stack: ItemStack = ItemStack.new()
	yield_stack.item_id = yield_item.id
	yield_stack.item = yield_item
	yield_stack.count = 2
	autofree(yield_stack)

	var herb: ItemData = ItemData.new()
	herb.id = &"test_recyclable_herb"
	herb.display_name = "Recyclable Herb"
	herb.weight = 0.1
	herb.stackable = true
	herb.max_stack = 99
	herb.is_recyclable = true
	herb.recycle_yield = [yield_stack]
	autofree(herb)

	# Add directly to PlayerData.inventory — the single source of truth — and
	# rebuild the right page so a row exists for it.
	PlayerData.inventory.add(herb, 1)
	_tab.populate_right(_right_parent)

	var herb_row: InventoryRow = _find_row(_right_parent, &"test_recyclable_herb")
	assert_not_null(herb_row, "A test_recyclable_herb InventoryRow must exist after populate_right()")
	if herb_row == null:
		return

	_tab._selected_row = herb_row

	watch_signals(GameEvents)
	_tab._do_recycle()

	# The consumed item must be gone from PlayerData.inventory.stacks.
	assert_eq(_stack_count(PlayerData.inventory, &"test_recyclable_herb"), 0,
			"_do_recycle() must remove the consumed item from PlayerData.inventory.stacks")

	# The yield item must have been added to PlayerData.inventory.stacks.
	assert_eq(_stack_count(PlayerData.inventory, &"test_herb_scraps"), 2,
			"_do_recycle() must add the recycle_yield items to PlayerData.inventory.stacks")

	assert_signal_emitted(GameEvents, "item_recycled",
			"_do_recycle() must emit GameEvents.item_recycled")
	assert_signal_emitted(GameEvents, "inventory_changed",
			"_do_recycle() must emit GameEvents.inventory_changed")


# ---------------------------------------------------------------------------
# Test 8 — _on_slot_drop() equips into PlayerData.inventory.equipped
# ---------------------------------------------------------------------------

func test_on_slot_drop_equips_into_player_data_equipped() -> void:
	# _on_slot_drop() is the handler behind drag-to-equip. It must equip into
	# PlayerData.inventory.equipped (the single source of truth) and emit
	# item_equipped + inventory_changed, mirroring _do_equip()'s contract.
	var boots: ItemData = ItemData.new()
	boots.id = &"slot_drop_boots"
	boots.display_name = "Slot Drop Boots"
	boots.weight = 0.8
	boots.equip_slot = ItemData.EquipSlot.BOOTS
	autofree(boots)

	var stack: ItemStack = ItemStack.new()
	stack.item_id = boots.id
	stack.item = boots
	stack.count = 1
	autofree(stack)

	PlayerData.inventory.add(boots, 1)

	watch_signals(GameEvents)
	_tab._on_slot_drop(stack, ItemData.EquipSlot.BOOTS)

	assert_true(PlayerData.inventory.equipped.has(ItemData.EquipSlot.BOOTS),
			"_on_slot_drop() must place the dropped item into PlayerData.inventory.equipped[BOOTS]")
	assert_eq((PlayerData.inventory.equipped.get(ItemData.EquipSlot.BOOTS) as ItemData).id, &"slot_drop_boots",
			"PlayerData.inventory.equipped[BOOTS] must be the dropped item")

	assert_signal_emitted(GameEvents, "item_equipped",
			"_on_slot_drop() must emit GameEvents.item_equipped")
	assert_signal_emitted(GameEvents, "inventory_changed",
			"_on_slot_drop() must emit GameEvents.inventory_changed")


# ---------------------------------------------------------------------------
# Test 9 — GameEvents.inventory_changed refreshes the tab while visible
# ---------------------------------------------------------------------------

func test_inventory_changed_refreshes_visible_tab() -> void:
	# design §7.4: _on_inventory_changed() must call _refresh_both_pages() when
	# the tab is visible. Mutate PlayerData.inventory directly (simulating a
	# foraging/market system writing to the shared bag from elsewhere), then
	# emit inventory_changed and confirm the rendered rows + weight label pick
	# up the new stack without the test calling populate_right() again.
	_tab.visible = true

	var berry: ItemData = ItemData.new()
	berry.id = &"refresh_berry"
	berry.display_name = "Refresh Berry"
	berry.weight = 0.3
	berry.stackable = true
	berry.max_stack = 99
	autofree(berry)

	PlayerData.inventory.add(berry, 4)

	var weight_label_node: Node = _right_parent.find_child("WeightLabel", true, false)
	assert_not_null(weight_label_node, "A named WeightLabel node must exist after populate_right()")
	var text_before: String = (weight_label_node as Label).text

	GameEvents.inventory_changed.emit()

	var berry_row: InventoryRow = _find_row(_right_parent, &"refresh_berry")
	assert_not_null(berry_row,
			"inventory_changed while visible must rebuild the right page to include the new berry stack")
	if berry_row != null:
		assert_eq(berry_row._stack.count, 4,
				"the refreshed berry row must show the count added directly to PlayerData.inventory")

	var refreshed_label: Node = _right_parent.find_child("WeightLabel", true, false)
	assert_not_null(refreshed_label, "WeightLabel must still be findable after the refresh rebuild")
	if refreshed_label != null:
		assert_ne((refreshed_label as Label).text, text_before,
				"the weight header must reflect the new total weight after inventory_changed")


# ---------------------------------------------------------------------------
# Test 10 — GameEvents.inventory_changed does NOT rebuild a hidden tab
# ---------------------------------------------------------------------------

func test_inventory_changed_does_not_rebuild_hidden_tab() -> void:
	# design §7.4: "if visible: _refresh_both_pages()". When the tab is NOT
	# visible (the player has another notebook tab open), inventory_changed
	# must be a no-op for this tab — no rebuild, no crash, no orphaned nodes.
	# The page must still reflect the latest PlayerData.inventory state the
	# NEXT time it is shown (i.e. data isn't lost — only the rebuild is
	# deferred).
	_tab.visible = false

	# Capture the row count before the mutation + signal.
	var rows_before: Array[Node] = _find_all_by_class(_right_parent, "InventoryRow")
	var count_before: int = rows_before.size()

	var berry: ItemData = ItemData.new()
	berry.id = &"hidden_refresh_berry"
	berry.display_name = "Hidden Refresh Berry"
	berry.weight = 0.3
	berry.stackable = true
	berry.max_stack = 99
	autofree(berry)

	PlayerData.inventory.add(berry, 1)

	GameEvents.inventory_changed.emit()

	# The hidden tab's already-built right page must be untouched — same
	# number of rows as before, no row for the new berry yet.
	var rows_after: Array[Node] = _find_all_by_class(_right_parent, "InventoryRow")
	assert_eq(rows_after.size(), count_before,
			"inventory_changed while hidden must NOT rebuild the right page (row count unchanged)")
	assert_null(_find_row(_right_parent, &"hidden_refresh_berry"),
			"a hidden tab's stale right page must not contain a row for data added after the last build")

	# On next show, an explicit populate_right() (as notebook.gd performs when
	# switching to this tab) must reflect the latest PlayerData.inventory —
	# proving no data was lost, only the rebuild was deferred.
	_tab.visible = true
	_tab.populate_right(_right_parent)

	assert_not_null(_find_row(_right_parent, &"hidden_refresh_berry"),
			"showing the tab and repopulating must reflect PlayerData.inventory's latest state")


# ---------------------------------------------------------------------------
# Test 11 — Two InventoryTab instances observe the same bag contents
# ---------------------------------------------------------------------------

func test_two_tab_instances_observe_same_bag() -> void:
	# Proves the tab is no longer self-owned data: a second InventoryTab
	# instance, populated independently, must render the same PlayerData
	# starter bag as _tab (instantiated in before_each()).
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	var second_tab: InventoryTab = packed.instantiate() as InventoryTab
	add_child_autofree(second_tab)

	var second_right_parent: Control = Control.new()
	second_right_parent.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(second_right_parent)

	second_tab.populate_right(second_right_parent)

	# Both tabs must show the same sample_leaf count from the shared starter bag.
	var first_leaf: InventoryRow = _find_row(_right_parent, &"sample_leaf")
	var second_leaf: InventoryRow = _find_row(second_right_parent, &"sample_leaf")

	assert_not_null(first_leaf, "_tab must render a sample_leaf row")
	assert_not_null(second_leaf, "second_tab must render a sample_leaf row")
	if first_leaf != null and second_leaf != null:
		assert_eq(first_leaf._stack.count, second_leaf._stack.count,
				"both tab instances must show the same sample_leaf count from the shared PlayerData.inventory")

	# Now mutate PlayerData.inventory directly and confirm a fresh populate on
	# EITHER tab reflects the shared change — the two tabs are views over one
	# bag, not independent copies.
	var trinket: ItemData = ItemData.new()
	trinket.id = &"shared_trinket"
	trinket.display_name = "Shared Trinket"
	trinket.weight = 0.2
	trinket.stackable = true
	trinket.max_stack = 99
	autofree(trinket)
	PlayerData.inventory.add(trinket, 1)

	_tab.populate_right(_right_parent)
	second_tab.populate_right(second_right_parent)

	assert_not_null(_find_row(_right_parent, &"shared_trinket"),
			"_tab must render the trinket added to the shared PlayerData.inventory")
	assert_not_null(_find_row(second_right_parent, &"shared_trinket"),
			"second_tab must render the same trinket added to the shared PlayerData.inventory")
