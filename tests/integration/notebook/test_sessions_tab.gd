## test_sessions_tab.gd (integration)
## Cross-system integration tests for the Slice 6 Sessions-tab save/load wiring.
##
## WHAT THESE TESTS GUARD
## ----------------------
## SessionsTab (ui/notebook/sessions/sessions_tab.gd) wires the Sessions tab's
## "Save" and "Switch to this Story" actions to real persistence:
##   - SaveButton.pressed -> SaveManager.save_slot("default") -> writes
##     SaveManager._slot_path("default")
##   - StoryCard.SwitchButton.pressed -> GameEvents.story_switch_requested("default")
##     -> a connected handler calls SaveManager.load_slot("default") (falling back
##        to SaveManager.new_game() if the slot file does not exist) -> on success,
##        PlayerData._resource reflects the loaded data and
##        GameEvents.player_data_loaded + GameEvents.story_loaded are emitted.
##
## These are integration tests (not unit) because they exercise:
##   - SessionsTab + StoryCard + SaveManager + PlayerData + GameEvents wired
##     together via real scene instantiation and signal emission
##   - real file I/O under user://slots/
##   - the carry-forward fix: ResourceSaver.save() mutates the live shared
##     PlayerDataResource's resource_path, and ResourceLoader.load() may then
##     return that same cached instance — the save-then-mutate-then-load round
##     trip must still surface the SAVED values, and PlayerData.to_resource()
##     after load must be the freshly-loaded instance, not the pre-save one.
##
## HERMETIC FILE I/O
## -----------------
## All tests use the single Phase-1 "default" slot id (matching
## SessionsTab._default_slot.slot_id), since that is the only id the Sessions
## tab's wiring touches. before_each() backs up any real
## user://slots/slot_default.tres bytes; after_each() restores them (or removes
## the file if none existed), so these tests never clobber a real player's
## default save. before_each() also resets PlayerData to a bare
## PlayerDataResource so no prior test's state leaks in.
##
## Requires GUT: https://github.com/bitwes/Gut
## Install via Godot Asset Library (search "GUT - Godot Unit Testing").
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd -gselect=test_sessions_tab.gd -gexit

class_name TestSessionsTabIntegration
extends GutTest


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const SCENE_PATH: String = "res://ui/notebook/sessions/sessions_tab.tscn"

# The single Phase-1 default slot id (design §6.1; slices.md Slice 6 scope).
const DEFAULT_SLOT_ID: String = "default"


# ---------------------------------------------------------------------------
# Shared state
# ---------------------------------------------------------------------------

# Backup of any pre-existing user://slots/slot_default.tres bytes, restored in
# after_each() so these tests don't clobber a real player's default save.
var _slot_backup: PackedByteArray = PackedByteArray()
var _had_slot_file: bool = false
var _slot_path: String = ""


# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

func before_each() -> void:
	_slot_path = SaveManager._slot_path(DEFAULT_SLOT_ID)

	# Back up any real default-slot save so this suite can restore it.
	_had_slot_file = FileAccess.file_exists(_slot_path)
	if _had_slot_file:
		_slot_backup = FileAccess.get_file_as_bytes(_slot_path)
		DirAccess.remove_absolute(_slot_path)

	# Give PlayerData a clean, freshly-constructed (un-seeded) resource before
	# every test, per CLAUDE.md's dependency-injection guidance, so a previous
	# test's load_slot()/new_game()/mutation can't leak into this one.
	PlayerData._load_resource(PlayerDataResource.new())


func after_each() -> void:
	# Remove whatever this test wrote, then restore the pre-existing file (if any).
	if FileAccess.file_exists(_slot_path):
		DirAccess.remove_absolute(_slot_path)

	if _had_slot_file:
		var f: FileAccess = FileAccess.open(_slot_path, FileAccess.WRITE)
		f.store_buffer(_slot_backup)
		f.close()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Instantiate sessions_tab.tscn, add it to the tree (so _ready() runs), and
## populate both pages into disposable parent Controls.
##
## NOTE: populate_left()/populate_right() REPARENT the tab's LeftPage/RightPage
## subtrees into the given parent Controls — they are NOT left as children of
## the tab itself. Callers must search _left_parent / _right_parent (the
## returned dictionary's "left"/"right" keys), not the returned tab, to find
## SaveButton / SwitchButton / etc.
##
## @return a Dictionary with keys "tab" (SessionsTab), "left" (Control),
##         "right" (Control)
func _make_tab() -> Dictionary:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	var tab: SessionsTab = packed.instantiate() as SessionsTab
	add_child_autofree(tab)

	var left_parent: Control = add_child_autofree(Control.new())
	var right_parent: Control = add_child_autofree(Control.new())

	tab.populate_left(left_parent)
	tab.populate_right(right_parent)

	return {"tab": tab, "left": left_parent, "right": right_parent}


## Walk root's subtree and return the first node whose name matches node_name.
## Returns null if none found.
##
## @param root      - node whose subtree to search
## @param node_name - the node name string to match against node.name
## @return the first matching Node, or null
func _find_by_name(root: Node, node_name: String) -> Node:
	for child in root.get_children():
		if child.name == node_name:
			return child
		var found: Node = _find_by_name(child, node_name)
		if found != null:
			return found
	return null


# ---------------------------------------------------------------------------
# Test 1 — "Save" action calls SaveManager.save_slot() and writes the slot file
# ---------------------------------------------------------------------------

func test_save_button_press_writes_default_slot_file() -> void:
	# Arrange: PlayerData has seeded starter content (mirrors a fresh "New
	# Story"), and no slot file exists yet (before_each() removed any backup).
	var data: PlayerDataResource = PlayerDataResource.new()
	data.reset_to_new_game()
	PlayerData._load_resource(data)

	assert_false(FileAccess.file_exists(_slot_path),
			"precondition: no slot_default.tres should exist before Save is pressed")

	var parts: Dictionary = _make_tab()
	var left_parent: Control = parts["left"]

	# Locate the LeftPage's SaveButton inside the reparented LeftPage subtree.
	var save_button: Node = _find_by_name(left_parent, "SaveButton")
	assert_not_null(save_button,
			"sessions_tab.tscn must declare a 'SaveButton' under LeftPage (see test_sessions_tab_scene.gd)")
	if save_button == null:
		return

	# Act: press the Save button.
	(save_button as Button).pressed.emit()

	# Assert: SaveManager.save_slot("default") wrote the slot file.
	assert_true(FileAccess.file_exists(_slot_path),
			"pressing SaveButton must call SaveManager.save_slot('default'), writing '%s'" % _slot_path)


# ---------------------------------------------------------------------------
# Test 2 — "Switch to this Story" calls load_slot("default") and PlayerData rebinds
# ---------------------------------------------------------------------------

func test_switch_button_press_loads_default_slot_and_rebinds_player_data() -> void:
	# Arrange: write a distinguishable saved state to the default slot first.
	var saved_data: PlayerDataResource = PlayerDataResource.new()
	saved_data.reset_to_new_game()
	saved_data.gold = 999
	PlayerData._load_resource(saved_data)
	SaveManager.save_slot(DEFAULT_SLOT_ID)

	# Reset PlayerData to a bare (un-seeded, gold == 0) resource so the only way
	# PlayerData.gold can become 999 again is via the Switch action's load_slot().
	PlayerData._load_resource(PlayerDataResource.new())
	assert_eq(PlayerData.gold, 0,
			"sanity check: PlayerData.gold should be 0 after resetting to a bare resource")

	var parts: Dictionary = _make_tab()
	var left_parent: Control = parts["left"]

	# Locate the StoryCard's SwitchButton inside the reparented LeftPage subtree.
	var switch_button: Node = _find_by_name(left_parent, "SwitchButton")
	assert_not_null(switch_button,
			"populate_left() must produce a StoryCard with a 'SwitchButton' (see story_card.tscn)")
	if switch_button == null:
		return

	watch_signals(GameEvents)

	# Act: press "Switch to this Story".
	(switch_button as Button).pressed.emit()

	# Assert: the switch action ultimately calls load_slot("default"), which
	# swaps PlayerData._resource and emits player_data_loaded.
	assert_signal_emitted(GameEvents, "player_data_loaded",
			"the Switch action should call SaveManager.load_slot('default'), which calls PlayerData._load_resource() and emits player_data_loaded")
	assert_eq(PlayerData.gold, 999,
			"after Switch, PlayerData.gold should reflect the saved slot's value (999)")


# ---------------------------------------------------------------------------
# Test 3 — story_switch_requested emitted with the default slot id
# ---------------------------------------------------------------------------

func test_switch_button_press_emits_story_switch_requested_with_default_id() -> void:
	# Arrange: a slot file must exist so the handler's load_slot() succeeds and
	# we can isolate the story_switch_requested emission itself.
	var saved_data: PlayerDataResource = PlayerDataResource.new()
	saved_data.reset_to_new_game()
	PlayerData._load_resource(saved_data)
	SaveManager.save_slot(DEFAULT_SLOT_ID)

	var parts: Dictionary = _make_tab()
	var left_parent: Control = parts["left"]

	var switch_button: Node = _find_by_name(left_parent, "SwitchButton")
	assert_not_null(switch_button,
			"populate_left() must produce a StoryCard with a 'SwitchButton'")
	if switch_button == null:
		return

	watch_signals(GameEvents)

	(switch_button as Button).pressed.emit()

	assert_signal_emitted_with_parameters(GameEvents, "story_switch_requested", [DEFAULT_SLOT_ID])


# ---------------------------------------------------------------------------
# Test 4 — story_loaded emitted after a successful load_slot()
# ---------------------------------------------------------------------------

func test_switch_button_press_emits_story_loaded_after_successful_load() -> void:
	# Arrange: a slot file must exist so load_slot("default") succeeds and
	# story_loaded fires (as opposed to the new_game() fallback path).
	var saved_data: PlayerDataResource = PlayerDataResource.new()
	saved_data.reset_to_new_game()
	PlayerData._load_resource(saved_data)
	SaveManager.save_slot(DEFAULT_SLOT_ID)

	var parts: Dictionary = _make_tab()
	var left_parent: Control = parts["left"]

	var switch_button: Node = _find_by_name(left_parent, "SwitchButton")
	assert_not_null(switch_button,
			"populate_left() must produce a StoryCard with a 'SwitchButton'")
	if switch_button == null:
		return

	watch_signals(GameEvents)

	(switch_button as Button).pressed.emit()

	# story_loaded lets the rest of the UI (e.g. an open Inventory/Quests tab)
	# rebind alongside player_data_loaded (design §8, slice-6 test plan).
	assert_signal_emitted(GameEvents, "story_loaded",
			"a successful load_slot('default') via the Switch action should emit GameEvents.story_loaded")
	assert_signal_emitted(GameEvents, "player_data_loaded",
			"a successful load_slot('default') via the Switch action should also emit GameEvents.player_data_loaded")


# ---------------------------------------------------------------------------
# Test 5 — load_slot("default") returning false falls back to new_game()
# ---------------------------------------------------------------------------

func test_switch_button_press_falls_back_to_new_game_when_no_slot_file_exists() -> void:
	# Arrange: no slot file exists (first run) — before_each() removed any
	# backup and this test does not call save_slot().
	assert_false(FileAccess.file_exists(_slot_path),
			"precondition: no slot_default.tres should exist for the first-run fallback case")

	# Give PlayerData a distinguishable, non-default state so we can confirm
	# new_game() (not a no-op) ran as the fallback.
	var dirty_data: PlayerDataResource = PlayerDataResource.new()
	dirty_data.gold = 12345
	PlayerData._load_resource(dirty_data)

	var parts: Dictionary = _make_tab()
	var left_parent: Control = parts["left"]

	var switch_button: Node = _find_by_name(left_parent, "SwitchButton")
	assert_not_null(switch_button,
			"populate_left() must produce a StoryCard with a 'SwitchButton'")
	if switch_button == null:
		return

	watch_signals(GameEvents)

	# Act: press "Switch to this Story" with no save file present.
	(switch_button as Button).pressed.emit()

	# Assert: the handler falls back to SaveManager.new_game() rather than
	# leaving PlayerData untouched or crashing. new_game() resets gold to 0 and
	# seeds starter content (design §9.2), and emits player_data_loaded.
	assert_signal_emitted(GameEvents, "player_data_loaded",
			"a missing slot file must fall back to SaveManager.new_game(), which emits player_data_loaded")
	assert_eq(PlayerData.gold, 0,
			"new_game() fallback should reset PlayerData.gold to 0 (was 12345 before the fallback)")
	assert_eq(PlayerData.inventory.stacks.size(), 2,
			"new_game() fallback should populate PlayerData.inventory with the 2 seeded starter stacks")


# ---------------------------------------------------------------------------
# Test 6 — save -> mutate in memory -> switch: SAVED values win (carry-forward fix)
# ---------------------------------------------------------------------------

func test_save_then_mutate_then_switch_loads_saved_values_not_in_memory_mutation() -> void:
	# This is the core Slice 6 round trip and the carry-forward fix from the
	# Wave 2 review: ResourceSaver.save() (inside save_slot()) mutates the live
	# shared PlayerDataResource's resource_path as a side effect. If
	# ResourceLoader.load() subsequently returns that SAME cached instance
	# (because its resource_path now matches the slot file's path), an
	# in-memory mutation made AFTER save_slot() could leak into the "loaded"
	# data — which would be wrong. Switching stories must show the SAVED
	# values, not whatever PlayerData happened to hold in memory afterwards.
	#
	# Arrange: seed PlayerData, set a known gold value, and save it.
	var data: PlayerDataResource = PlayerDataResource.new()
	data.reset_to_new_game()
	data.gold = 100
	PlayerData._load_resource(data)

	var parts: Dictionary = _make_tab()
	var left_parent: Control = parts["left"]

	var save_button: Node = _find_by_name(left_parent, "SaveButton")
	assert_not_null(save_button, "sessions_tab.tscn must declare a 'SaveButton' under LeftPage")
	if save_button == null:
		return

	(save_button as Button).pressed.emit()
	assert_true(FileAccess.file_exists(_slot_path),
			"precondition: Save must write '%s' before the mutate/switch steps" % _slot_path)

	# Mutate PlayerData in memory AFTER saving — this mutation must NOT survive
	# the upcoming "Switch to this Story" (it was never written to disk).
	PlayerData.gold += 50
	assert_eq(PlayerData.gold, 150,
			"sanity check: the in-memory mutation should be visible before Switch is pressed")

	var switch_button: Node = _find_by_name(left_parent, "SwitchButton")
	assert_not_null(switch_button, "populate_left() must produce a StoryCard with a 'SwitchButton'")
	if switch_button == null:
		return

	# Act: press "Switch to this Story" to reload the saved slot.
	(switch_button as Button).pressed.emit()

	# Assert: the SAVED gold value (100) wins — not the in-memory mutation (150).
	assert_eq(PlayerData.gold, 100,
			"after Switch, PlayerData.gold must reflect the SAVED value (100), not the in-memory mutation (150)")

	# Inventory should also reflect the saved (seeded starter bag) shape, not
	# any post-save mutation to it.
	assert_eq(PlayerData.inventory.stacks.size(), 2,
			"after Switch, PlayerData.inventory should reflect the saved starter-bag shape (2 stacks)")


# ---------------------------------------------------------------------------
# Test 7 — after the round trip, to_resource() is the freshly-loaded instance
# ---------------------------------------------------------------------------

func test_save_then_mutate_then_switch_to_resource_is_freshly_loaded_instance() -> void:
	# Companion to Test 6: PlayerData.to_resource() after the Switch action must
	# be the resource instance ResourceLoader.load() returned for THIS load —
	# NOT the pre-save instance whose resource_path was mutated as a side
	# effect of ResourceSaver.save() inside save_slot(). Carry-forward fix from
	# the Wave 2 review: ResourceSaver.save(PlayerData.to_resource(), path)
	# stamps resource_path onto the LIVE resource, so a naive
	# ResourceLoader.load(path) on the next load could return that exact same
	# cached object back (a no-op "load" wearing a disguise) instead of a
	# fresh deserialization from disk.
	var data: PlayerDataResource = PlayerDataResource.new()
	data.reset_to_new_game()
	data.gold = 100
	PlayerData._load_resource(data)

	var pre_save_resource: PlayerDataResource = PlayerData.to_resource()

	var parts: Dictionary = _make_tab()
	var left_parent: Control = parts["left"]

	var save_button: Node = _find_by_name(left_parent, "SaveButton")
	assert_not_null(save_button, "sessions_tab.tscn must declare a 'SaveButton' under LeftPage")
	if save_button == null:
		return

	(save_button as Button).pressed.emit()
	assert_true(FileAccess.file_exists(_slot_path),
			"precondition: Save must write '%s' before the switch step" % _slot_path)

	# Mutate in memory after saving, exactly as in Test 6.
	PlayerData.gold += 50

	var switch_button: Node = _find_by_name(left_parent, "SwitchButton")
	assert_not_null(switch_button, "populate_left() must produce a StoryCard with a 'SwitchButton'")
	if switch_button == null:
		return

	(switch_button as Button).pressed.emit()

	var post_switch_resource: PlayerDataResource = PlayerData.to_resource()

	# Primary assertion: to_resource() after Switch must be a DIFFERENT
	# instance than the pre-save resource. If load_slot()'s ResourceLoader.load()
	# returned the same cached object (whose resource_path was mutated by the
	# preceding save_slot()), PlayerData._load_resource() would swap _resource
	# to that SAME object — an identity match here would mean the "load"
	# didn't actually deserialize a fresh instance from disk.
	assert_ne(post_switch_resource, pre_save_resource,
			"PlayerData.to_resource() after Switch must be the freshly-loaded instance, not the pre-save instance whose resource_path was mutated by ResourceSaver.save()")

	# Secondary assertion: the freshly-loaded instance must carry the SAVED
	# gold value (100), not the in-memory mutation (150) made after saving.
	assert_eq(post_switch_resource.gold, 100,
			"PlayerData.to_resource() after Switch must carry the SAVED gold value (100), not the in-memory mutation (150)")
