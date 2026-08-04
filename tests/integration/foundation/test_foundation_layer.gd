## test_foundation_layer.gd
## TDD contract tests for the Phase 1 Foundation Layer.
##
## These tests define the expected API for every class introduced in Phase 1.
## Regression guard for that shipped contract.
##
## Requires GUT: https://github.com/bitwes/Gut
## Install via Godot Asset Library (search "GUT - Godot Unit Testing").
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI (once GUT is installed):
##   godot --headless -s addons/gut/gut_cmdln.gd

class_name TestFoundationLayer
extends GutTest


# ---------------------------------------------------------------------------
# Test 1 — ItemData: all required properties and EquipSlot enum
# ---------------------------------------------------------------------------

func test_item_data_has_all_required_properties() -> void:
	# Arrange: create a fresh ItemData instance with no values set.
	# If the class doesn't exist yet this line will error — that is the
	# expected TDD failure signal.
	var item: ItemData = ItemData.new()
	autofree(item)

	# Assert default property types exist and carry sensible zero-values.
	# We test each property individually so a failure message points at
	# exactly which property is missing or mis-typed.
	assert_eq(item.id, &"",              "id should default to empty StringName")
	assert_eq(item.display_name, "",     "display_name should default to empty String")
	assert_null(item.icon,               "icon should default to null (no Texture2D assigned)")
	assert_eq(item.weight, 0.0,          "weight should default to 0.0")
	assert_eq(item.description, "",      "description should default to empty String")
	assert_false(item.is_recyclable,     "is_recyclable should default to false")
	assert_true(item.recycle_yield is Array, "recycle_yield should be an Array")
	assert_false(item.stackable,         "stackable should default to false")
	assert_eq(item.max_stack, 99,        "max_stack should default to 99")
	assert_eq(item.backpack_capacity, 0.0, "backpack_capacity should default to 0.0")


func test_item_data_has_equip_slot_enum() -> void:
	# EquipSlot is defined inside item_data.gd as an inner enum.
	# GDScript inner enums are dictionaries, so we can check their keys.
	# See: https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html#enums
	assert_true(ItemData.EquipSlot.has("NONE"),     "EquipSlot must contain NONE")
	assert_true(ItemData.EquipSlot.has("BACKPACK"),  "EquipSlot must contain BACKPACK")
	assert_true(ItemData.EquipSlot.has("CLOTHING"),  "EquipSlot must contain CLOTHING")
	assert_true(ItemData.EquipSlot.has("BOOTS"),     "EquipSlot must contain BOOTS")
	assert_true(ItemData.EquipSlot.has("GLOVES"),    "EquipSlot must contain GLOVES")
	assert_true(ItemData.EquipSlot.has("GOGGLES"),   "EquipSlot must contain GOGGLES")
	assert_true(ItemData.EquipSlot.has("NECKLACE"),  "EquipSlot must contain NECKLACE")


func test_item_data_equip_slot_default_is_none() -> void:
	var item: ItemData = ItemData.new()
	autofree(item)

	# NONE must be value 0 (first enum entry) so an unset slot reads as NONE
	# without the caller needing to know the numeric value.
	assert_eq(item.equip_slot, ItemData.EquipSlot.NONE,
			"equip_slot should default to EquipSlot.NONE")


# ---------------------------------------------------------------------------
# Test 2 — ItemStack: item_id (StringName) and count (int)
# ---------------------------------------------------------------------------

func test_item_stack_has_item_id_and_count() -> void:
	var stack: ItemStack = ItemStack.new()
	autofree(stack)

	# StringName default is &""
	assert_eq(stack.item_id, &"", "item_id should default to empty StringName")
	# int default is 0
	assert_eq(stack.count, 0,     "count should default to 0")


# ---------------------------------------------------------------------------
# Helper: build a simple ItemData for use in Inventory tests.
# This avoids test-to-test coupling — each test creates its own data.
# ---------------------------------------------------------------------------

func _make_item(id_str: String, wt: float, slot: int = ItemData.EquipSlot.NONE,
		stackable: bool = true, capacity: float = 0.0) -> ItemData:
	var item: ItemData = ItemData.new()
	item.id = StringName(id_str)
	item.display_name = id_str
	item.weight = wt
	item.equip_slot = slot
	item.stackable = stackable
	item.max_stack = 99
	item.backpack_capacity = capacity
	return item  # caller must autofree


# ---------------------------------------------------------------------------
# Test 3 — Inventory.add(): no capacity limit when no backpack is equipped
# ---------------------------------------------------------------------------

func test_inventory_add_returns_zero_leftover_when_no_capacity_limit() -> void:
	# With no backpack equipped, capacity() returns 0.0.
	# The spec says treat 0.0 capacity as *unlimited* — no weight enforcement.
	var inv: Inventory = Inventory.new()
	autofree(inv)

	var item: ItemData = _make_item("leaf", 1.0)
	autofree(item)

	# Act: add 10 of a 1.0-weight item; no backpack is equipped.
	var leftover: int = inv.add(item, 10)

	assert_eq(leftover, 0, "add() should return 0 leftover when no backpack capacity limit applies")
	# Verify the stack was actually created.
	assert_eq(inv.stacks.size(), 1, "stacks should contain exactly one ItemStack after add()")
	assert_eq(inv.stacks[0].count, 10, "the stack count should match what was added")


func test_inventory_add_grows_existing_stack_when_stackable() -> void:
	# If the item is stackable and a stack for that item_id already exists,
	# add() should grow it rather than creating a second stack.
	var inv: Inventory = Inventory.new()
	autofree(inv)

	var item: ItemData = _make_item("berry", 0.5)
	autofree(item)

	inv.add(item, 3)
	inv.add(item, 4)

	assert_eq(inv.stacks.size(), 1,  "stackable items should not create duplicate stacks")
	assert_eq(inv.stacks[0].count, 7, "second add() should grow the existing stack's count")


# ---------------------------------------------------------------------------
# Test 4 — Inventory.add(): respects capacity; returns positive leftover
# ---------------------------------------------------------------------------

func test_inventory_add_returns_leftover_when_backpack_is_full() -> void:
	# Backpack with capacity 5.0; item weighs 2.0 each.
	# Adding 4 items (total weight 8.0) when only 2 fit (weight 4.0 ≤ 5.0)
	# should place 2 and return 2 as leftover.
	var inv: Inventory = Inventory.new()
	autofree(inv)

	var backpack: ItemData = _make_item("starter_pack", 1.0,
			ItemData.EquipSlot.BACKPACK, false, 5.0)
	autofree(backpack)
	inv.equip(backpack)  # puts backpack in equipped[BACKPACK]

	var item: ItemData = _make_item("stone", 2.0)
	autofree(item)

	var leftover: int = inv.add(item, 4)

	# 4 × 2.0 = 8.0 total; capacity is 5.0 → only 2 fit (2 × 2.0 = 4.0 ≤ 5.0)
	assert_eq(leftover, 2,
			"add() should return 2 leftover when only 2 items fit within backpack capacity")
	assert_eq(inv.stacks[0].count, 2,
			"stacks should hold 2 items after a capacity-limited add()")


# ---------------------------------------------------------------------------
# Test 5 — Inventory.remove(): removes items, returns true on success
# ---------------------------------------------------------------------------

func test_inventory_remove_returns_true_on_success() -> void:
	var inv: Inventory = Inventory.new()
	autofree(inv)

	var item: ItemData = _make_item("mushroom", 0.3)
	autofree(item)

	inv.add(item, 5)
	var result: bool = inv.remove(item, 2)

	assert_true(result, "remove() should return true when item is present and count is sufficient")
	assert_eq(inv.stacks[0].count, 3, "remaining count should be 3 after removing 2 from 5")


func test_inventory_remove_empties_stack_when_all_removed() -> void:
	var inv: Inventory = Inventory.new()
	autofree(inv)

	var item: ItemData = _make_item("petal", 0.1)
	autofree(item)

	inv.add(item, 3)
	var result: bool = inv.remove(item, 3)

	assert_true(result, "remove() should return true when removing the exact stack count")
	assert_eq(inv.stacks.size(), 0,
			"stacks should be empty after removing all items from the only stack")


# ---------------------------------------------------------------------------
# Test 6 — Inventory.remove(): returns false when item not present
# ---------------------------------------------------------------------------

func test_inventory_remove_returns_false_when_item_not_in_inventory() -> void:
	var inv: Inventory = Inventory.new()
	autofree(inv)

	var item: ItemData = _make_item("ghost_item", 1.0)
	autofree(item)

	var result: bool = inv.remove(item, 1)

	assert_false(result,
			"remove() should return false when the item is not present in stacks")


func test_inventory_remove_returns_false_when_count_exceeds_stack() -> void:
	var inv: Inventory = Inventory.new()
	autofree(inv)

	var item: ItemData = _make_item("seed", 0.2)
	autofree(item)

	inv.add(item, 2)
	var result: bool = inv.remove(item, 5)

	assert_false(result,
			"remove() should return false when requesting more than the available stack count")
	# The stack should be unchanged — a failed remove must not partially consume.
	assert_eq(inv.stacks[0].count, 2,
			"the stack count should be unchanged after a failed remove()")


# ---------------------------------------------------------------------------
# Test 7 — Inventory.equip(): slots item, returns null when slot was empty
# ---------------------------------------------------------------------------

func test_inventory_equip_moves_item_to_equipped_slot() -> void:
	var inv: Inventory = Inventory.new()
	autofree(inv)

	var boots: ItemData = _make_item("old_boots", 0.5, ItemData.EquipSlot.BOOTS, false)
	autofree(boots)

	inv.add(boots, 1)
	var displaced: ItemData = inv.equip(boots)

	# With no previously equipped boots, equip() returns null.
	assert_null(displaced,
			"equip() should return null when the slot was previously empty")
	# The item must have left stacks and entered equipped.
	assert_eq(inv.stacks.size(), 0,
			"stacks should be empty after equipping the only item")
	assert_eq(inv.equipped.get(ItemData.EquipSlot.BOOTS), boots,
			"equipped[BOOTS] should reference the boots ItemData after equip()")


# ---------------------------------------------------------------------------
# Test 8 — Inventory.equip(): returns previously equipped item when slot was occupied
# ---------------------------------------------------------------------------

func test_inventory_equip_returns_previously_equipped_item() -> void:
	var inv: Inventory = Inventory.new()
	autofree(inv)

	var old_boots: ItemData = _make_item("worn_boots", 0.5, ItemData.EquipSlot.BOOTS, false)
	var new_boots: ItemData = _make_item("leather_boots", 0.8, ItemData.EquipSlot.BOOTS, false)
	autofree(old_boots)
	autofree(new_boots)

	inv.add(old_boots, 1)
	inv.equip(old_boots)

	inv.add(new_boots, 1)
	var displaced: ItemData = inv.equip(new_boots)

	# The old boots should be returned (not null) and land back in stacks.
	assert_eq(displaced, old_boots,
			"equip() should return the previously equipped item when the slot was occupied")
	# new_boots should now be in the slot.
	assert_eq(inv.equipped.get(ItemData.EquipSlot.BOOTS), new_boots,
			"equipped[BOOTS] should reference the new boots after swapping")
	# old_boots should have been added back to stacks by equip().
	var found_old: bool = false
	for stack in inv.stacks:
		if stack.item_id == old_boots.id:
			found_old = true
	assert_true(found_old,
			"the displaced item should be returned to stacks after being replaced by equip()")


# ---------------------------------------------------------------------------
# Test 9 — Inventory.unequip(): clears slot, returns item
# ---------------------------------------------------------------------------

func test_inventory_unequip_removes_item_from_slot_and_returns_it() -> void:
	var inv: Inventory = Inventory.new()
	autofree(inv)

	var gloves: ItemData = _make_item("knit_gloves", 0.3, ItemData.EquipSlot.GLOVES, false)
	autofree(gloves)

	inv.add(gloves, 1)
	inv.equip(gloves)

	var returned: ItemData = inv.unequip(ItemData.EquipSlot.GLOVES)

	assert_eq(returned, gloves,
			"unequip() should return the item that was in the slot")
	assert_false(inv.equipped.has(ItemData.EquipSlot.GLOVES),
			"equipped should no longer contain GLOVES after unequip()")
	# The item should have gone back into stacks.
	assert_eq(inv.stacks.size(), 1,
			"unequip() should add the item back to stacks")


func test_inventory_unequip_returns_null_when_slot_is_empty() -> void:
	var inv: Inventory = Inventory.new()
	autofree(inv)

	var returned: ItemData = inv.unequip(ItemData.EquipSlot.NECKLACE)

	assert_null(returned,
			"unequip() should return null when the slot is already empty")


# ---------------------------------------------------------------------------
# Test 10 — Inventory.capacity(): returns 0.0 when no backpack is equipped
# ---------------------------------------------------------------------------

func test_inventory_capacity_is_zero_with_no_backpack_equipped() -> void:
	var inv: Inventory = Inventory.new()
	autofree(inv)

	assert_eq(inv.capacity(), 0.0,
			"capacity() should return 0.0 when no backpack is in equipped[BACKPACK]")


# ---------------------------------------------------------------------------
# Test 11 — Inventory.capacity(): returns backpack_capacity when backpack is equipped
# ---------------------------------------------------------------------------

func test_inventory_capacity_returns_backpack_capacity_when_equipped() -> void:
	var inv: Inventory = Inventory.new()
	autofree(inv)

	var pack: ItemData = _make_item("canvas_pack", 2.0,
			ItemData.EquipSlot.BACKPACK, false, 30.0)
	autofree(pack)

	inv.equip(pack)

	assert_eq(inv.capacity(), 30.0,
			"capacity() should return the equipped backpack's backpack_capacity (30.0)")


# ---------------------------------------------------------------------------
# Test 12 — Inventory.current_weight(): returns correct weighted sum
# ---------------------------------------------------------------------------
#
# Design decision: current_weight() accepts a registry Dictionary[StringName, ItemData]
# so it can resolve item weights from item_ids stored in stacks. This keeps
# ItemStack a lightweight record (just id + count) while still allowing
# weight queries without a global item registry autoload.
#
# Signature: func current_weight(registry: Dictionary) -> float

func test_inventory_current_weight_returns_sum_of_stack_weights() -> void:
	var inv: Inventory = Inventory.new()
	autofree(inv)

	var leaf: ItemData  = _make_item("leaf",  0.5)
	var stone: ItemData = _make_item("stone", 2.0)
	autofree(leaf)
	autofree(stone)

	inv.add(leaf,  4)  # 4 × 0.5 = 2.0
	inv.add(stone, 3)  # 3 × 2.0 = 6.0
	# Expected total: 8.0

	# Build a registry mapping item_id → ItemData so current_weight can resolve weights.
	var registry: Dictionary = {
		leaf.id:  leaf,
		stone.id: stone,
	}

	var weight: float = inv.current_weight(registry)

	assert_eq(weight, 8.0,
			"current_weight() should return 8.0 (4×0.5 + 3×2.0) given a correct registry")


func test_inventory_current_weight_is_zero_for_empty_stacks() -> void:
	var inv: Inventory = Inventory.new()
	autofree(inv)

	var weight: float = inv.current_weight({})

	assert_eq(weight, 0.0,
			"current_weight() should return 0.0 when stacks is empty")


# ---------------------------------------------------------------------------
# Test 13 — QuestData properties; QuestLog.Status enum
# ---------------------------------------------------------------------------

func test_quest_data_has_all_required_properties() -> void:
	var quest: QuestData = QuestData.new()
	autofree(quest)

	assert_eq(quest.id, &"",          "QuestData.id should default to empty StringName")
	assert_eq(quest.title, "",         "QuestData.title should default to empty String")
	assert_eq(quest.description, "",   "QuestData.description should default to empty String")
	assert_true(quest.objectives is Array,
			"QuestData.objectives should be an Array")
	assert_false(quest.is_main,        "QuestData.is_main should default to false")


func test_quest_log_status_enum_has_required_values() -> void:
	# QuestLog.Status is defined inside quest_log.gd.
	# Verify all three states are present.
	assert_true(QuestLog.Status.has("ACTIVE"),    "QuestLog.Status must contain ACTIVE")
	assert_true(QuestLog.Status.has("COMPLETED"), "QuestLog.Status must contain COMPLETED")
	assert_true(QuestLog.Status.has("HIDDEN"),    "QuestLog.Status must contain HIDDEN")


func test_quest_log_states_defaults_to_empty_dictionary() -> void:
	var log: QuestLog = QuestLog.new()
	autofree(log)

	assert_true(log.states is Dictionary, "QuestLog.states should be a Dictionary")
	assert_eq(log.states.size(), 0,       "QuestLog.states should be empty by default")


# ---------------------------------------------------------------------------
# Test 14 — GameSettings: 5 properties with correct defaults
# ---------------------------------------------------------------------------

func test_game_settings_has_correct_defaults() -> void:
	var settings: GameSettings = GameSettings.new()
	autofree(settings)

	# These defaults come directly from the design doc (section 3.2).
	assert_eq(settings.master_volume, 1.0,
			"master_volume should default to 1.0")
	assert_eq(settings.music_volume, 1.0,
			"music_volume should default to 1.0")
	assert_eq(settings.sfx_volume, 1.0,
			"sfx_volume should default to 1.0")
	assert_eq(settings.window_scale, 4,
			"window_scale should default to 4 (4× the 320×180 viewport → 1280×720 window)")
	assert_eq(settings.text_speed, 1.0,
			"text_speed should default to 1.0")


# ---------------------------------------------------------------------------
# Test 15 — GameState.State enum and GameEvents signals
# ---------------------------------------------------------------------------

func test_game_state_has_notebook_state_not_paused() -> void:
	# The design doc (section 6) explicitly removes PAUSED and renames
	# INVENTORY → NOTEBOOK. Any code checking State.PAUSED is a bug.
	assert_true(GameState.State.has("NOTEBOOK"),
			"GameState.State must contain NOTEBOOK (was INVENTORY in the skeleton)")
	assert_false(GameState.State.has("PAUSED"),
			"GameState.State must NOT contain PAUSED — notebook open IS the pause mechanism")
	assert_false(GameState.State.has("INVENTORY"),
			"GameState.State must NOT contain INVENTORY — it was renamed to NOTEBOOK")


func test_game_state_has_all_other_required_states() -> void:
	# These states should remain unchanged from the skeleton.
	assert_true(GameState.State.has("MAIN_MENU"), "GameState.State must contain MAIN_MENU")
	assert_true(GameState.State.has("PLAYING"),   "GameState.State must contain PLAYING")
	assert_true(GameState.State.has("DIALOGUE"),  "GameState.State must contain DIALOGUE")
	assert_true(GameState.State.has("COMBAT"),    "GameState.State must contain COMBAT")
	assert_true(GameState.State.has("LOADING"),   "GameState.State must contain LOADING")


func test_game_events_has_notebook_lifecycle_signals() -> void:
	# GameEvents is an autoload (singleton). Checking has_signal() verifies the
	# signal is declared. See: https://docs.godotengine.org/en/stable/classes/class_object.html#class-object-method-has-signal
	assert_true(GameEvents.has_signal("notebook_opened"),
			"GameEvents must have signal notebook_opened")
	assert_true(GameEvents.has_signal("notebook_closed"),
			"GameEvents must have signal notebook_closed")
	assert_true(GameEvents.has_signal("notebook_tab_changed"),
			"GameEvents must have signal notebook_tab_changed")


func test_game_events_has_inventory_signals() -> void:
	assert_true(GameEvents.has_signal("inventory_changed"),
			"GameEvents must have signal inventory_changed")
	assert_true(GameEvents.has_signal("item_equipped"),
			"GameEvents must have signal item_equipped")
	assert_true(GameEvents.has_signal("item_unequipped"),
			"GameEvents must have signal item_unequipped")
	assert_true(GameEvents.has_signal("item_dropped"),
			"GameEvents must have signal item_dropped")
	assert_true(GameEvents.has_signal("item_recycled"),
			"GameEvents must have signal item_recycled")
	assert_true(GameEvents.has_signal("inventory_full"),
			"GameEvents must have signal inventory_full")


func test_game_events_has_map_signals() -> void:
	assert_true(GameEvents.has_signal("destination_visited"),
			"GameEvents must have signal destination_visited")
	assert_true(GameEvents.has_signal("fast_travel_requested"),
			"GameEvents must have signal fast_travel_requested")


func test_game_events_has_quest_signals() -> void:
	assert_true(GameEvents.has_signal("quest_added"),
			"GameEvents must have signal quest_added")
	assert_true(GameEvents.has_signal("quest_updated"),
			"GameEvents must have signal quest_updated")
	assert_true(GameEvents.has_signal("quest_completed"),
			"GameEvents must have signal quest_completed")


func test_game_events_has_story_signals() -> void:
	assert_true(GameEvents.has_signal("story_created"),
			"GameEvents must have signal story_created")
	assert_true(GameEvents.has_signal("story_loaded"),
			"GameEvents must have signal story_loaded")
	assert_true(GameEvents.has_signal("story_switch_requested"),
			"GameEvents must have signal story_switch_requested")
