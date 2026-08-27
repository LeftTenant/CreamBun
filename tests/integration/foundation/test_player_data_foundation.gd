## test_player_data_foundation.gd
## TDD contract tests for the Slice 1 cross-system wiring: the PlayerData
## autoload's registration, its always-non-null _resource, the
## _load_resource() swap + player_data_loaded signal, and the new
## GameEvents.gold_changed signal.
##
## These are integration tests (not unit) because they assert on the
## autoload graph itself (registration order, singleton reachability) and on
## GameEvents signal emission/reception across objects — concerns that only
## exist once the full autoload set is loaded by the engine.
##
## They will FAIL until PlayerDataResource, the PlayerData autoload, its
## registration in project.godot, and the two new GameEvents signals
## (player_data_loaded, gold_changed) all exist. That is by design — the
## tests are the spec. See:
##   docs/features/game-data/design.md (§3, §8, §9)
##   docs/features/game-data/slices.md (Slice 1)
##   docs/features/game-data/slice-1-foundation-test-plan.md
##
## Requires GUT: https://github.com/bitwes/Gut
## Install via Godot Asset Library (search "GUT - Godot Unit Testing").
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd -gselect=test_player_data_foundation.gd -gexit

class_name TestPlayerDataFoundation
extends GutTest


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func before_each() -> void:
	# Give the PlayerData autoload a clean, freshly-constructed resource
	# before every test (per CLAUDE.md's dependency-injection guidance for
	# autoload tests), so a previous test's _load_resource() swap or gold
	# mutation can't leak into this one.
	PlayerData._load_resource(PlayerDataResource.new())


# ---------------------------------------------------------------------------
# Test 1 — PlayerData is reachable as an autoload singleton
# ---------------------------------------------------------------------------

func test_player_data_autoload_is_reachable() -> void:
	# Referencing the global `PlayerData` name resolves only if it is
	# registered as an autoload singleton in project.godot (after
	# SaveManager, per Slice 1). If registration is missing or misordered,
	# this line errors at parse/resolve time — the first failure signal.
	assert_not_null(PlayerData, "PlayerData must be reachable as an autoload singleton")


func test_other_core_autoloads_remain_reachable_alongside_player_data() -> void:
	# Guards against a botched autoload list edit breaking the existing
	# autoloads while inserting PlayerData.
	assert_not_null(GameEvents, "GameEvents must remain reachable as an autoload singleton")
	assert_not_null(GameState, "GameState must remain reachable as an autoload singleton")
	assert_not_null(SaveManager, "SaveManager must remain reachable as an autoload singleton")


# ---------------------------------------------------------------------------
# Test 2 — PlayerData._resource is never null at startup
# ---------------------------------------------------------------------------

func test_player_data_resource_is_never_null() -> void:
	# §9.1 / §10: _resource is initialized inline (PlayerDataResource.new())
	# in the field declaration, so to_resource() must never return null —
	# even before any new_game()/load_slot() call. Tested here without any
	# prior _load_resource() call in this specific assertion's intent, but
	# before_each() already swapped in a fresh resource; to_resource() must
	# still be non-null regardless.
	assert_not_null(PlayerData.to_resource(),
			"PlayerData.to_resource() must never return null")


# ---------------------------------------------------------------------------
# Test 3 — _load_resource() swaps in a new PlayerDataResource
# ---------------------------------------------------------------------------

func test_load_resource_swaps_resource_and_forwarded_reads_reflect_new_data() -> void:
	# Build a distinguishable resource (non-default gold + a seeded inventory
	# via reset_to_new_game()) and load it. Forwarded reads on PlayerData
	# (inventory, quest_log, map_state, gold) must reflect the NEW resource's
	# data, not the previous one's.
	var new_data: PlayerDataResource = PlayerDataResource.new()
	new_data.reset_to_new_game()
	new_data.gold = 123
	autofree(new_data)

	PlayerData._load_resource(new_data)

	assert_eq(PlayerData.gold, 123,
			"PlayerData.gold should reflect the newly-loaded resource's gold (123)")
	assert_eq(PlayerData.inventory, new_data.inventory,
			"PlayerData.inventory should reflect the newly-loaded resource's inventory")
	assert_eq(PlayerData.quest_log, new_data.quest_log,
			"PlayerData.quest_log should reflect the newly-loaded resource's quest_log")
	assert_eq(PlayerData.map_state, new_data.map_state,
			"PlayerData.map_state should reflect the newly-loaded resource's map_state")
	# reset_to_new_game() seeds the starter bag (3x sample_leaf + 1x sample_scarf) —
	# confirm the swapped-in inventory carries that seeded content through.
	assert_eq(PlayerData.inventory.stacks.size(), 2,
			"the newly-loaded resource's seeded starter bag should be visible via PlayerData.inventory")


# ---------------------------------------------------------------------------
# Test 4 — _load_resource() emits GameEvents.player_data_loaded
# ---------------------------------------------------------------------------

func test_load_resource_emits_player_data_loaded() -> void:
	# watch_signals must be set up on GameEvents BEFORE the act, so GUT can
	# record the emission. See:
	# https://github.com/bitwes/Gut/wiki/Signals
	watch_signals(GameEvents)

	var new_data: PlayerDataResource = PlayerDataResource.new()
	autofree(new_data)

	PlayerData._load_resource(new_data)

	assert_signal_emitted(GameEvents, "player_data_loaded",
			"_load_resource() should emit GameEvents.player_data_loaded so listeners rebind to the new resource")


# ---------------------------------------------------------------------------
# Test 5 — GameEvents.gold_changed can be emitted with an int payload
# ---------------------------------------------------------------------------

func test_gold_changed_signal_emits_with_int_payload() -> void:
	# §8: signal gold_changed(new_total: int). Confirm the signal exists and
	# that a listener receives the emitted int payload correctly. We connect
	# a local callable rather than relying solely on watch_signals' parameter
	# capture, to make the "received by a listener" requirement explicit and
	# directly verifiable.
	var received_values: Array[int] = []
	var listener: Callable = func(new_total: int) -> void:
		received_values.append(new_total)

	GameEvents.gold_changed.connect(listener)

	watch_signals(GameEvents)
	GameEvents.gold_changed.emit(150)

	# NOTE: assert_signal_emitted_with_parameters(object, signal_name, params) has
	# no trailing "message" argument — its 4th positional param is an int `index`
	# (see addons/gut/test.gd SignalAssertParameters). Passing a String there
	# previously caused an internal 'String' vs 'int' comparison error.
	assert_signal_emitted_with_parameters(GameEvents, "gold_changed", [150])
	assert_eq(received_values, [150],
			"a connected listener should receive the int payload (150) via gold_changed")

	# Clean up the connection so this test's listener doesn't linger and
	# affect later tests that also emit gold_changed.
	GameEvents.gold_changed.disconnect(listener)
