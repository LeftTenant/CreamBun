## test_player_data.gd
## TDD contract tests for the PlayerData autoload (autoloads/player_data.gd).
##
## These tests cover the forwarded getters/setter and the to_resource()
## identity contract — the parts of PlayerData that are pure "thin wrapper"
## logic and can be exercised without any scene tree. Regression guard for
## that shipped behavior. See:
##   docs/features/game-data/design.md (§3, §9.1)
##   docs/features/game-data/slices.md (Slice 1)
##   docs/features/game-data/slice-1-foundation-test-plan.md
##
## NOTE ON ISOLATION
## ------------------
## PlayerData is registered as an autoload, so `PlayerData` here refers to the
## live singleton instance — there is exactly one in the whole test run. Each
## test calls `PlayerData._load_resource(PlayerDataResource.new())` in
## before_each() (per CLAUDE.md's dependency-injection guidance) to give the
## autoload a clean, known resource before making assertions, so tests do not
## leak state into one another via gold or inventory contents left over from a
## previous test.
##
## Requires GUT: https://github.com/bitwes/Gut
## Install via Godot Asset Library (search "GUT - Godot Unit Testing").
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd -gselect=test_player_data.gd -gexit

class_name TestPlayerData
extends GutTest


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func before_each() -> void:
	# Give the autoload a clean, freshly-constructed resource before every
	# test so assertions about gold/inventory/etc. are not affected by
	# whatever a previous test (or game startup) left behind.
	PlayerData._load_resource(PlayerDataResource.new())


# ---------------------------------------------------------------------------
# Test 1 — forwarded getters return the same instances as to_resource()'s fields
# ---------------------------------------------------------------------------

func test_inventory_getter_returns_same_instance_as_to_resource_inventory() -> void:
	assert_eq(PlayerData.inventory, PlayerData.to_resource().inventory,
			"PlayerData.inventory should return the same Inventory instance held by to_resource()")


func test_quest_log_getter_returns_same_instance_as_to_resource_quest_log() -> void:
	assert_eq(PlayerData.quest_log, PlayerData.to_resource().quest_log,
			"PlayerData.quest_log should return the same QuestLog instance held by to_resource()")


func test_map_state_getter_returns_same_instance_as_to_resource_map_state() -> void:
	assert_eq(PlayerData.map_state, PlayerData.to_resource().map_state,
			"PlayerData.map_state should return the same MapState instance held by to_resource()")


# ---------------------------------------------------------------------------
# Test 2 — gold getter forwards to the inner resource
# ---------------------------------------------------------------------------

func test_gold_getter_returns_inner_resource_gold() -> void:
	# Set gold directly on the inner resource, then confirm the autoload's
	# getter reflects it — proving `gold` is a forwarded property, not a
	# separately-tracked copy (per design §3: "no direct field duplication").
	PlayerData.to_resource().gold = 42

	assert_eq(PlayerData.gold, 42,
			"PlayerData.gold should return the inner resource's gold value")


# ---------------------------------------------------------------------------
# Test 3 — gold setter writes through to the inner resource
# ---------------------------------------------------------------------------

func test_gold_setter_writes_through_to_resource() -> void:
	PlayerData.gold = 99

	assert_eq(PlayerData.to_resource().gold, 99,
			"setting PlayerData.gold should write through to to_resource().gold")


# ---------------------------------------------------------------------------
# Test 4 — to_resource() returns the exact instance currently held
# ---------------------------------------------------------------------------

func test_to_resource_returns_currently_held_resource_instance() -> void:
	# Swap in a distinct, identifiable resource and confirm to_resource()
	# returns that exact instance (identity, not a copy/duplicate).
	var fresh: PlayerDataResource = PlayerDataResource.new()
	fresh.gold = 7
	autofree(fresh)

	PlayerData._load_resource(fresh)

	assert_eq(PlayerData.to_resource(), fresh,
			"to_resource() should return the exact PlayerDataResource instance passed to _load_resource()")
	assert_eq(PlayerData.gold, 7,
			"forwarded properties should reflect the newly-loaded resource's data")
