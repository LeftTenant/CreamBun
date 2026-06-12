## test_player_data_resource.gd
## TDD contract tests for PlayerDataResource (resources/data/player_data_resource.gd).
##
## These tests define the expected API and Phase 1 seeding behavior for
## PlayerDataResource. They will FAIL until that file exists. That is by
## design — the tests are the spec. See:
##   docs/features/game-data/design.md (§9.2)
##   docs/features/game-data/slices.md (Slice 1)
##   docs/features/game-data/slice-1-foundation-test-plan.md
##
## Requires GUT: https://github.com/bitwes/Gut
## Install via Godot Asset Library (search "GUT - Godot Unit Testing").
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd -gselect=test_player_data_resource.gd -gexit

class_name TestPlayerDataResource
extends GutTest


# ---------------------------------------------------------------------------
# Test 1 — default-constructed PlayerDataResource has non-null sub-resources
# ---------------------------------------------------------------------------

func test_default_constructed_resource_has_non_null_fields() -> void:
	# §9.2: @export vars are initialized inline (Inventory.new(), QuestLog.new(),
	# MapState.new()) so a freshly constructed resource is never half-null —
	# even before reset_to_new_game() runs.
	var data: PlayerDataResource = PlayerDataResource.new()
	autofree(data)

	assert_not_null(data.inventory, "inventory should be non-null on a default-constructed PlayerDataResource")
	assert_not_null(data.quest_log, "quest_log should be non-null on a default-constructed PlayerDataResource")
	assert_not_null(data.map_state, "map_state should be non-null on a default-constructed PlayerDataResource")


func test_default_constructed_resource_has_zero_gold() -> void:
	var data: PlayerDataResource = PlayerDataResource.new()
	autofree(data)

	assert_eq(data.gold, 0, "gold should default to 0 on a freshly constructed PlayerDataResource")


func test_default_constructed_resource_save_version_matches_current_version() -> void:
	# CURRENT_VERSION is the schema stamp; a fresh resource should already be
	# on the current schema (no migration needed for a brand-new object).
	var data: PlayerDataResource = PlayerDataResource.new()
	autofree(data)

	assert_eq(data.save_version, PlayerDataResource.CURRENT_VERSION,
			"save_version should equal CURRENT_VERSION on a default-constructed PlayerDataResource")
	assert_eq(PlayerDataResource.CURRENT_VERSION, 1,
			"CURRENT_VERSION should be 1 for Phase 1 (no schema migrations yet)")


# ---------------------------------------------------------------------------
# Test 2 — reset_to_new_game(): replaces sub-resources with fresh instances
# ---------------------------------------------------------------------------

func test_reset_to_new_game_replaces_inventory_quest_log_and_map_state_with_fresh_instances() -> void:
	# Capture the original sub-resource identities, then confirm reset_to_new_game()
	# swaps in DIFFERENT objects (not just clears the existing ones in place).
	# This matters because a caller might be holding a reference to the old
	# inventory/quest_log/map_state — reset must not silently mutate those refs.
	var data: PlayerDataResource = PlayerDataResource.new()
	autofree(data)

	var original_inventory: Inventory = data.inventory
	var original_quest_log: QuestLog = data.quest_log
	var original_map_state: MapState = data.map_state

	data.reset_to_new_game()

	assert_ne(data.inventory, original_inventory,
			"reset_to_new_game() should replace inventory with a fresh Inventory instance")
	assert_ne(data.quest_log, original_quest_log,
			"reset_to_new_game() should replace quest_log with a fresh QuestLog instance")
	assert_ne(data.map_state, original_map_state,
			"reset_to_new_game() should replace map_state with a fresh MapState instance")


func test_reset_to_new_game_resets_gold_to_zero() -> void:
	var data: PlayerDataResource = PlayerDataResource.new()
	autofree(data)

	# Simulate a save where the player had accumulated gold.
	data.gold = 250

	data.reset_to_new_game()

	assert_eq(data.gold, 0, "reset_to_new_game() should reset gold to 0")


func test_reset_to_new_game_leaves_map_state_empty() -> void:
	# §4 / Slice 1: map_state is part of the Phase 1 schema but Scope A defers
	# any seeding of it — a fresh game should have an empty MapState.
	var data: PlayerDataResource = PlayerDataResource.new()
	autofree(data)

	data.reset_to_new_game()

	assert_eq(data.map_state.visited_destinations.size(), 0,
			"reset_to_new_game() should leave map_state.visited_destinations empty")
	assert_eq(data.map_state.fog_data.size(), 0,
			"reset_to_new_game() should leave map_state.fog_data empty")


# ---------------------------------------------------------------------------
# Test 3 — reset_to_new_game(): sets save_version to CURRENT_VERSION
# ---------------------------------------------------------------------------

func test_reset_to_new_game_sets_save_version_to_current_version() -> void:
	var data: PlayerDataResource = PlayerDataResource.new()
	autofree(data)

	# Simulate an old/garbage version stamp before reset.
	data.save_version = -1

	data.reset_to_new_game()

	assert_eq(data.save_version, PlayerDataResource.CURRENT_VERSION,
			"reset_to_new_game() should set save_version to CURRENT_VERSION")


# ---------------------------------------------------------------------------
# Test 4 — reset_to_new_game(): seeds the_foraging_book quest as COMPLETED
# ---------------------------------------------------------------------------

func test_reset_to_new_game_seeds_foraging_book_quest_as_completed() -> void:
	# §9.2 _seed_starter_content(): the_foraging_book is the intro quest and
	# ships pre-completed with all three objectives marked done.
	var data: PlayerDataResource = PlayerDataResource.new()
	autofree(data)

	data.reset_to_new_game()

	var states: Dictionary = data.quest_log.states
	assert_true(states.has(&"the_foraging_book"),
			"reset_to_new_game() should seed quest_log.states[&\"the_foraging_book\"]")
	if not states.has(&"the_foraging_book"):
		return  # avoid null-ref on the assertions below

	var entry: Dictionary = states[&"the_foraging_book"]
	assert_eq(entry.get("status"), QuestLog.Status.COMPLETED,
			"the_foraging_book status should be QuestLog.Status.COMPLETED")
	assert_eq(entry.get("completed_objectives"), [0, 1, 2],
			"the_foraging_book completed_objectives should be [0, 1, 2]")


# ---------------------------------------------------------------------------
# Test 5 — reset_to_new_game(): seeds the default starter bag
# ---------------------------------------------------------------------------

func test_reset_to_new_game_seeds_starter_bag_with_leaves_and_boots() -> void:
	# Slice 1 (user review 2026-06-11): the starter inventory — 3x sample_leaf
	# and 1x sample_boots — moves from inventory_tab.gd's hand-seeded sample
	# data into _seed_starter_content(). This is now the single source of
	# truth, asserted directly by item_id and count (no dependency on
	# inventory_tab.gd).
	var data: PlayerDataResource = PlayerDataResource.new()
	autofree(data)

	data.reset_to_new_game()

	var stacks: Array[ItemStack] = data.inventory.stacks
	assert_eq(stacks.size(), 2,
			"a fresh starter bag should contain exactly 2 stacks (sample_leaf, sample_boots); got %d" % stacks.size())

	var leaf_stack: ItemStack = null
	var boots_stack: ItemStack = null
	for stack: ItemStack in stacks:
		if stack.item_id == &"sample_leaf":
			leaf_stack = stack
		elif stack.item_id == &"sample_boots":
			boots_stack = stack

	assert_not_null(leaf_stack, "starter bag must contain a stack with item_id &\"sample_leaf\"")
	assert_not_null(boots_stack, "starter bag must contain a stack with item_id &\"sample_boots\"")

	if leaf_stack != null:
		assert_eq(leaf_stack.count, 3, "sample_leaf starter stack should have count 3")
	if boots_stack != null:
		assert_eq(boots_stack.count, 1, "sample_boots starter stack should have count 1")


# ---------------------------------------------------------------------------
# Test 6 — rehydrate(): documented no-op, runs without error
# ---------------------------------------------------------------------------

func test_rehydrate_runs_without_error_and_leaves_fields_unchanged() -> void:
	# §6.3 / §9.2 / §13: rehydrate() is a documented no-op in Phase 1 — the real
	# ItemDatabase re-linking is out of scope until that helper exists. This
	# test guards that calling it is harmless and does not mutate inventory,
	# quest_log, or map_state.
	var data: PlayerDataResource = PlayerDataResource.new()
	autofree(data)

	data.reset_to_new_game()

	var inventory_before: Inventory = data.inventory
	var quest_log_before: QuestLog = data.quest_log
	var map_state_before: MapState = data.map_state
	var stacks_count_before: int = data.inventory.stacks.size()
	var quest_states_before: Dictionary = data.quest_log.states.duplicate()

	data.rehydrate()

	assert_eq(data.inventory, inventory_before,
			"rehydrate() must not replace the inventory instance")
	assert_eq(data.quest_log, quest_log_before,
			"rehydrate() must not replace the quest_log instance")
	assert_eq(data.map_state, map_state_before,
			"rehydrate() must not replace the map_state instance")
	assert_eq(data.inventory.stacks.size(), stacks_count_before,
			"rehydrate() must not change the number of inventory stacks")
	assert_eq(data.quest_log.states, quest_states_before,
			"rehydrate() must not change quest_log.states")
