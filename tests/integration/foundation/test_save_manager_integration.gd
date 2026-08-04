## test_save_manager_integration.gd
## TDD contract tests for the Slice 2 SaveManager rewrite + launch wiring:
## new_game(), load_slot(), save_slot(), load_settings(), save_settings(),
## and the launch-time PlayerData seeding (design §6.2, §10, §11).
##
## These are integration tests (not unit) because they assert on:
##  - cross-autoload effects (SaveManager → PlayerData → GameEvents)
##  - real file I/O under user://slots/ and user://settings.tres
##  - the launch-time call sequence (SaveManager._ready() → load_settings() +
##    new_game())
##
## Regression guard for the §6.2 rewrite and its launch wiring
## (load_settings() + new_game() from _ready()). See:
##   docs/features/game-data/design.md (§6.2, §10, §11)
##   docs/features/game-data/slices.md (Slice 2)
##   docs/features/game-data/slice-2-savemanager-test-plan.md
##
## HERMETIC FILE I/O
## -----------------
## Tests that write to disk use a slot id ("test_slot_2") distinct from any
## real default slot, and a renamed/relocated settings file is never created
## by these tests directly — save_settings()/load_settings() always operate
## on the single real SaveManager.SETTINGS_PATH ("user://settings.tres"), so
## tests that touch settings save the pre-existing file's bytes (if any) in
## before_each() and restore them in after_each(), and always restore
## SaveManager.settings to a fresh default afterwards. Slot files are removed
## in after_each()/after_all() via DirAccess so repeated runs are clean.
##
## Requires GUT: https://github.com/bitwes/Gut
## Install via Godot Asset Library (search "GUT - Godot Unit Testing").
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd -gselect=test_save_manager_integration.gd -gexit

class_name TestSaveManagerIntegration
extends GutTest


# Slot id used by file-I/O tests. Distinct from "default" so these tests
# never touch a real player's default save slot.
const _TEST_SLOT_ID: String = "test_slot_2"

# Backup of any pre-existing user://settings.tres bytes, restored in
# after_each() so these tests don't clobber a real settings file.
var _settings_backup: PackedByteArray = PackedByteArray()
var _had_settings_file: bool = false


# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

func before_each() -> void:
	# Give PlayerData a clean, freshly-constructed (un-seeded) resource before
	# every test, per CLAUDE.md's dependency-injection guidance, so a previous
	# test's new_game()/load_slot() call can't leak state into this one.
	PlayerData._load_resource(PlayerDataResource.new())

	# Back up any real user://settings.tres so tests that call
	# save_settings()/load_settings() can restore it afterwards.
	_had_settings_file = FileAccess.file_exists(SaveManager.SETTINGS_PATH)
	if _had_settings_file:
		_settings_backup = FileAccess.get_file_as_bytes(SaveManager.SETTINGS_PATH)


func after_each() -> void:
	# Remove any slot file written by this test so repeated runs are clean.
	_delete_file_if_exists(SaveManager._slot_path(_TEST_SLOT_ID))

	# Restore (or remove) user://settings.tres to whatever existed before
	# this test ran, then reset SaveManager.settings to a known default so
	# later tests in this suite (or other suites) don't see a stale instance.
	if _had_settings_file:
		var f: FileAccess = FileAccess.open(SaveManager.SETTINGS_PATH, FileAccess.WRITE)
		f.store_buffer(_settings_backup)
		f.close()
	else:
		_delete_file_if_exists(SaveManager.SETTINGS_PATH)

	SaveManager.settings = null


func _delete_file_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		# DirAccess.remove_absolute works on user:// paths.
		# https://docs.godotengine.org/en/stable/classes/class_diraccess.html#class-diraccess-method-remove-absolute
		DirAccess.remove_absolute(path)


# ---------------------------------------------------------------------------
# Test 1 — launch wiring: PlayerData is seeded before any tab opens
# ---------------------------------------------------------------------------

func test_launch_seeds_player_data_with_starter_content() -> void:
	# By the time any test runs, the SaveManager autoload's _ready() has
	# already executed once during engine startup (load_settings() +
	# new_game()). before_each() then resets PlayerData to a *bare*
	# PlayerDataResource — so to re-exercise the launch contract directly we
	# call new_game() ourselves and assert the same seeded shape design §9.2
	# documents. This is the call launch wiring is expected to make.
	SaveManager.new_game()

	assert_eq(PlayerData.gold, 0,
			"new_game() should leave gold at 0 for a fresh game")

	# Foraging-book quest ships pre-completed (§9.2 _seed_starter_content()).
	var states: Dictionary = PlayerData.quest_log.states
	assert_true(states.has(&"the_foraging_book"),
			"PlayerData.quest_log should have the_foraging_book seeded after new_game()")
	if states.has(&"the_foraging_book"):
		assert_eq(states[&"the_foraging_book"].get("status"), QuestLog.Status.COMPLETED,
				"the_foraging_book should be seeded as COMPLETED")

	# Starter bag: 3x sample_leaf + 1x sample_boots (§9.2).
	var stacks: Array[ItemStack] = PlayerData.inventory.stacks
	assert_eq(stacks.size(), 2,
			"PlayerData.inventory should contain exactly 2 starter stacks after new_game()")

	var leaf_count: int = 0
	var boots_count: int = 0
	for stack: ItemStack in stacks:
		if stack.item_id == &"sample_leaf":
			leaf_count = stack.count
		elif stack.item_id == &"sample_boots":
			boots_count = stack.count

	assert_eq(leaf_count, 3, "starter bag should contain 3x sample_leaf")
	assert_eq(boots_count, 1, "starter bag should contain 1x sample_boots")


# ---------------------------------------------------------------------------
# Test 2 — load_settings(): non-null GameSettings with defaults when no file
# ---------------------------------------------------------------------------

func test_load_settings_produces_default_game_settings_when_no_file_exists() -> void:
	# Ensure no settings file exists for this test's call to load_settings().
	_delete_file_if_exists(SaveManager.SETTINGS_PATH)
	SaveManager.settings = null

	SaveManager.load_settings()

	assert_not_null(SaveManager.settings,
			"load_settings() should populate SaveManager.settings even on first run (no file)")
	assert_true(SaveManager.settings is GameSettings,
			"SaveManager.settings should be a GameSettings instance")

	# Defaults per resources/data/settings/game_settings.gd / design §3.2.
	assert_eq(SaveManager.settings.master_volume, 1.0,
			"a first-run GameSettings should default master_volume to 1.0")
	assert_eq(SaveManager.settings.window_scale, 4,
			"a first-run GameSettings should default window_scale to 4 (4× the 320×180 viewport)")


# ---------------------------------------------------------------------------
# Test 3 — new_game(): PlayerData._resource reflects a freshly seeded resource
# ---------------------------------------------------------------------------

func test_new_game_populates_player_data_resource_with_seeded_data() -> void:
	# Mutate PlayerData away from a fresh-game shape first, so this test can
	# distinguish "new_game() actually ran" from "PlayerData already looked
	# like this."
	PlayerData.gold = 500

	SaveManager.new_game()

	assert_eq(PlayerData.gold, 0,
			"new_game() should reset PlayerData.gold to 0 via a freshly-seeded resource")
	assert_eq(PlayerData.inventory.stacks.size(), 2,
			"new_game() should populate PlayerData.inventory with the 2 seeded starter stacks")
	assert_true(PlayerData.quest_log.states.has(&"the_foraging_book"),
			"new_game() should populate PlayerData.quest_log with the seeded the_foraging_book entry")


# ---------------------------------------------------------------------------
# Test 4 — new_game(): emits player_data_loaded exactly once
# ---------------------------------------------------------------------------

func test_new_game_emits_player_data_loaded_exactly_once() -> void:
	# §10: new_game() -> PlayerDataResource.new() + reset_to_new_game()
	#               -> PlayerData._load_resource(data)
	#               -> GameEvents.player_data_loaded.emit()
	# A single new_game() call must result in exactly one emission — not zero
	# (forgot to call _load_resource()), and not two (an extra stray
	# _load_resource() call somewhere in new_game()'s implementation).
	watch_signals(GameEvents)

	SaveManager.new_game()

	assert_signal_emit_count(GameEvents, "player_data_loaded", 1,
			"new_game() should emit GameEvents.player_data_loaded exactly once")


# ---------------------------------------------------------------------------
# Test 5 — new_game(): hands PlayerData a resource that is ALREADY seeded
# ---------------------------------------------------------------------------

func test_new_game_calls_load_resource_with_already_seeded_data() -> void:
	# §6.2: new_game() calls reset_to_new_game() on the new PlayerDataResource
	# BEFORE handing it to PlayerData._load_resource() — the seeded content
	# must be present immediately inside the _load_resource() call, not
	# applied afterwards. We verify this by intercepting _load_resource() via
	# a temporary override: connect to player_data_loaded and inspect
	# PlayerData.to_resource() inside the handler. Because GDScript signals
	# are emitted synchronously, by the time our handler runs, _resource has
	# already been swapped to the argument new_game() passed in — so this
	# also confirms that argument was pre-seeded.
	var captured_stack_count: Array = [-1]
	var captured_has_quest: Array = [false]

	var listener: Callable = func() -> void:
		captured_stack_count[0] = PlayerData.inventory.stacks.size()
		captured_has_quest[0] = PlayerData.quest_log.states.has(&"the_foraging_book")

	GameEvents.player_data_loaded.connect(listener)

	SaveManager.new_game()

	GameEvents.player_data_loaded.disconnect(listener)

	assert_eq(captured_stack_count[0], 2,
			"the resource passed to _load_resource() should already have the 2 seeded starter stacks at emission time")
	assert_true(captured_has_quest[0],
			"the resource passed to _load_resource() should already have the_foraging_book seeded at emission time")


# ---------------------------------------------------------------------------
# Test 6 — save_slot(): writes a .tres file under user://slots/, creating the dir
# ---------------------------------------------------------------------------

func test_save_slot_writes_file_at_slot_path_and_creates_directory() -> void:
	# Sanity: the slot file must not exist before save_slot() runs.
	var slot_path: String = SaveManager._slot_path(_TEST_SLOT_ID)
	_delete_file_if_exists(slot_path)
	assert_false(FileAccess.file_exists(slot_path),
			"precondition: slot file should not exist before save_slot()")

	SaveManager.new_game()
	SaveManager.save_slot(_TEST_SLOT_ID)

	assert_true(FileAccess.file_exists(slot_path),
			"save_slot() should write a file at _slot_path(slot_id)")
	assert_true(DirAccess.dir_exists_absolute(SaveManager.SLOT_DIR),
			"save_slot() should create SLOT_DIR if it does not already exist")


# ---------------------------------------------------------------------------
# Test 7 — save_slot() + load_slot(): round-trips PlayerData's state
# ---------------------------------------------------------------------------

func test_save_slot_then_load_slot_round_trips_player_data_state() -> void:
	# Arrange: build a distinguishable, non-default state.
	SaveManager.new_game()
	PlayerData.gold = 77
	var leaf: ItemData = ItemData.new()
	leaf.id = &"round_trip_item"
	leaf.display_name = "Round Trip Item"
	leaf.weight = 1.0
	leaf.stackable = true
	leaf.max_stack = 99
	PlayerData.inventory.add(leaf, 5)
	PlayerData.quest_log.states[&"round_trip_quest"] = {
		"status": QuestLog.Status.ACTIVE,
		"completed_objectives": [0],
	}

	SaveManager.save_slot(_TEST_SLOT_ID)

	# Reset PlayerData to a bare resource so load_slot() is the only thing
	# that can repopulate it.
	PlayerData._load_resource(PlayerDataResource.new())
	assert_eq(PlayerData.gold, 0,
			"sanity check: PlayerData.gold should be 0 after resetting to a bare resource")

	var ok: bool = SaveManager.load_slot(_TEST_SLOT_ID)

	assert_true(ok, "load_slot() should return true when the slot file exists and loads successfully")
	assert_eq(PlayerData.gold, 77,
			"load_slot() should restore gold (77) saved by save_slot()")

	# Inventory stack contents: starter bag (2 stacks) + our added stack (1) = 3.
	var stacks: Array[ItemStack] = PlayerData.inventory.stacks
	var round_trip_count: int = 0
	for stack: ItemStack in stacks:
		if stack.item_id == &"round_trip_item":
			round_trip_count = stack.count
	assert_eq(round_trip_count, 5,
			"load_slot() should restore the round_trip_item stack count (5) saved by save_slot()")

	# Quest log states: both the seeded foraging-book quest and our added quest.
	var states: Dictionary = PlayerData.quest_log.states
	assert_true(states.has(&"the_foraging_book"),
			"load_slot() should restore the seeded the_foraging_book quest entry")
	assert_true(states.has(&"round_trip_quest"),
			"load_slot() should restore the round_trip_quest entry saved by save_slot()")
	if states.has(&"round_trip_quest"):
		assert_eq(states[&"round_trip_quest"].get("status"), QuestLog.Status.ACTIVE,
				"round_trip_quest status should be ACTIVE after round-trip")


# ---------------------------------------------------------------------------
# Test 8 — load_slot(): returns false and leaves PlayerData unchanged when missing
# ---------------------------------------------------------------------------

func test_load_slot_returns_false_and_leaves_player_data_unchanged_when_file_missing() -> void:
	var missing_slot_id: String = "does_not_exist_slot"
	var missing_path: String = SaveManager._slot_path(missing_slot_id)
	_delete_file_if_exists(missing_path)
	assert_false(FileAccess.file_exists(missing_path),
			"precondition: the missing slot's file should not exist")

	# Give PlayerData a known, distinguishable state before the failed load.
	SaveManager.new_game()
	PlayerData.gold = 321
	var resource_before: PlayerDataResource = PlayerData.to_resource()

	var ok: bool = SaveManager.load_slot(missing_slot_id)

	assert_false(ok, "load_slot() should return false when no file exists at _slot_path(slot_id)")
	assert_eq(PlayerData.gold, 321,
			"a failed load_slot() must not change PlayerData.gold")
	assert_eq(PlayerData.to_resource(), resource_before,
			"a failed load_slot() must not swap PlayerData._resource")


# ---------------------------------------------------------------------------
# Test 9 — load_slot(): on success, calls _load_resource() (player_data_loaded emits)
# ---------------------------------------------------------------------------

func test_load_slot_success_emits_player_data_loaded() -> void:
	SaveManager.new_game()
	SaveManager.save_slot(_TEST_SLOT_ID)

	# Reset to a bare resource before the load so any emission we observe is
	# attributable to load_slot(), not the setup above.
	PlayerData._load_resource(PlayerDataResource.new())

	watch_signals(GameEvents)

	var ok: bool = SaveManager.load_slot(_TEST_SLOT_ID)

	assert_true(ok, "precondition: load_slot() should succeed for a freshly-saved slot")
	assert_signal_emitted(GameEvents, "player_data_loaded",
			"a successful load_slot() should call PlayerData._load_resource(), emitting player_data_loaded so listeners rebind")


# ---------------------------------------------------------------------------
# Test 10 — save_settings() + load_settings(): round-trips a changed field
# ---------------------------------------------------------------------------

func test_save_settings_then_load_settings_round_trips_master_volume() -> void:
	# Arrange: start from defaults, then change a field.
	SaveManager.settings = GameSettings.new()
	SaveManager.settings.master_volume = 0.25

	SaveManager.save_settings()

	# Load into a *fresh* SaveManager.settings instance (per the test plan:
	# "a fresh SaveManager.settings instance") so this is a genuine round
	# trip through disk, not just reading back the same object.
	SaveManager.settings = null
	SaveManager.load_settings()

	assert_not_null(SaveManager.settings,
			"load_settings() should populate settings after a prior save_settings()")
	assert_eq(SaveManager.settings.master_volume, 0.25,
			"load_settings() should restore master_volume (0.25) written by save_settings()")
