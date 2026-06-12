## test_notebook_shell.gd
## TDD contract tests for the Phase 1 Core Notebook Shell.
##
## These tests define the expected API for Notebook (ui/notebook/notebook.gd) and
## NotebookTab (ui/notebook/shared/notebook_tab.gd). They will FAIL until those
## files exist. That is by design — the tests are the spec. Run them after
## implementing each class to confirm the contract is met.
##
## Requires GUT: https://github.com/bitwes/Gut
## Install via Godot Asset Library (search "GUT - Godot Unit Testing").
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI (once GUT is installed):
##   godot --headless -s addons/gut/gut_cmdln.gd
##
## TREE-PAUSE WARNING
## ------------------
## Notebook.open() pauses the scene tree (get_tree().paused = true) so the world
## freezes while the notebook is open. This affects GUT itself because GUT runs
## inside the same tree. Every test that calls open() MUST call close() before
## the test ends; after_each() enforces this as a safety net.
##
## The Notebook CanvasLayer sets process_mode = ALWAYS so it keeps ticking while
## paused — GUT's own process_mode also needs to be ALWAYS, which the GUT addon
## configures automatically when it is installed correctly.
##
## --- SLICE 5 CLOSE HOOK NOTE ---
## notebook.gd's close() now calls SaveManager.save_settings() in addition to
## its existing GameEvents.notebook_closed.emit() (design §11 Step 4, approved
## option (a) — a single shared close hook in notebook.gd's close()). Every
## test in this file that calls close() — including after_each()'s safety net —
## therefore writes user://settings.tres. before_each()/after_each() back up
## and restore any pre-existing settings.tres so this suite never clobbers a
## real player's settings file, and before_each() also gives SaveManager.settings
## a fresh default GameSettings so the writes are deterministic.

class_name TestNotebookShell
extends GutTest


# ---------------------------------------------------------------------------
# Setup / Teardown
# ---------------------------------------------------------------------------

## The Notebook instance shared by tests that need it in the tree.
## Declared here so after_each() can always call close(), even if a test
## errors before it can clean up.
var _notebook: Notebook

## Backup of any pre-existing user://settings.tres bytes, restored in
## after_each() — see "SLICE 5 CLOSE HOOK NOTE" above.
var _settings_backup: PackedByteArray = PackedByteArray()
var _had_settings_file: bool = false


func before_each() -> void:
	# Restore known-good state before every test. GameState starts at PLAYING
	# so that close() restores to PLAYING (matching the open() precondition).
	GameState.change_state(GameState.State.PLAYING)
	get_tree().paused = false
	_notebook = null

	# Back up any real user://settings.tres before close()'s save_settings()
	# side effect can overwrite it.
	_had_settings_file = FileAccess.file_exists(SaveManager.SETTINGS_PATH)
	if _had_settings_file:
		_settings_backup = FileAccess.get_file_as_bytes(SaveManager.SETTINGS_PATH)

	# Give SaveManager a fresh, default GameSettings so every test's close()
	# writes a deterministic, known payload.
	SaveManager.settings = GameSettings.new()


func after_each() -> void:
	# Safety net: if any test left the notebook open (and the tree paused),
	# force-close to prevent the pause leaking into the next test.
	if _notebook != null and _notebook.visible:
		_notebook.close()
	# Double-check the tree is unpaused regardless — a test that crashed mid-
	# open() may have skipped close() entirely.
	get_tree().paused = false
	# Reset game state so the next test starts from a clean baseline.
	GameState.change_state(GameState.State.PLAYING)

	# Restore (or remove) user://settings.tres to whatever existed before this
	# test ran, then reset SaveManager.settings so later suites don't see a
	# stale instance from this file.
	if _had_settings_file:
		var f: FileAccess = FileAccess.open(SaveManager.SETTINGS_PATH, FileAccess.WRITE)
		f.store_buffer(_settings_backup)
		f.close()
	elif FileAccess.file_exists(SaveManager.SETTINGS_PATH):
		DirAccess.remove_absolute(SaveManager.SETTINGS_PATH)
	SaveManager.settings = null


# ---------------------------------------------------------------------------
# Helper: create a Notebook and add it to the test scene tree.
# Using add_child_autofree() means GUT removes the node after each test,
# preventing node leaks. We also store it in _notebook so after_each() can
# close it if needed.
# ---------------------------------------------------------------------------

func _make_notebook() -> Notebook:
	# Load and instantiate the notebook from its .tscn scene file so that the
	# full child subtree (Book/Pages/LeftPage, Book/Pages/RightPage, etc.) is
	# present when _ready() fires and resolves @onready variables.
	# Bare Notebook.new() produces an empty CanvasLayer with no children, which
	# caused "$Book/Pages/LeftPage" NodePath lookups to fail under GUT 9.6.0
	# (which promotes engine ERRORs to test failures via failure_error_types).
	# See: https://docs.godotengine.org/en/stable/classes/class_node.html
	var nb: Notebook = load("res://ui/notebook/notebook.tscn").instantiate()
	# The .tscn already sets process_mode = ALWAYS (process_mode = 3) on the
	# root CanvasLayer node, so no manual assignment is needed here.
	add_child_autofree(nb)
	_notebook = nb
	return nb


## Build a pressed InputEventAction for the given action name.
## Used by input tests to call _unhandled_input() directly without going
## through the engine's event routing, which is unavailable in headless mode.
func _make_action(action_name: String) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action_name
	event.pressed = true
	return event


# ---------------------------------------------------------------------------
# Test 1 — NotebookTab enum: all five values exist
# ---------------------------------------------------------------------------

func test_notebook_tab_enum_has_all_five_values() -> void:
	# GDScript enums expose their keys via the has() method because they are
	# dictionaries under the hood.
	# See: https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html#enums
	assert_true(Notebook.NotebookTab.has("INVENTORY"), "NotebookTab must contain INVENTORY")
	assert_true(Notebook.NotebookTab.has("MAP"),       "NotebookTab must contain MAP")
	assert_true(Notebook.NotebookTab.has("QUESTS"),    "NotebookTab must contain QUESTS")
	assert_true(Notebook.NotebookTab.has("SETTINGS"),  "NotebookTab must contain SETTINGS")
	assert_true(Notebook.NotebookTab.has("SESSIONS"),  "NotebookTab must contain SESSIONS")


# ---------------------------------------------------------------------------
# Test 2 — NotebookTab enum: values are 0–4 in order
# ---------------------------------------------------------------------------

func test_notebook_tab_enum_values_are_sequential() -> void:
	# Exact integer values matter because they are stored in save data and
	# passed over GameEvents signals. If they shift, old saves silently
	# open the wrong tab.
	assert_eq(Notebook.NotebookTab.INVENTORY, 0, "INVENTORY must be 0")
	assert_eq(Notebook.NotebookTab.MAP,       1, "MAP must be 1")
	assert_eq(Notebook.NotebookTab.QUESTS,    2, "QUESTS must be 2")
	assert_eq(Notebook.NotebookTab.SETTINGS,  3, "SETTINGS must be 3")
	assert_eq(Notebook.NotebookTab.SESSIONS,  4, "SESSIONS must be 4")


# ---------------------------------------------------------------------------
# Test 3 — open(): sets GameState to NOTEBOOK
# ---------------------------------------------------------------------------

func test_notebook_open_changes_game_state_to_notebook() -> void:
	# Precondition: world is running normally.
	assert_eq(GameState.current_state, GameState.State.PLAYING,
			"precondition: GameState should be PLAYING before open()")

	var nb: Notebook = _make_notebook()
	nb.open()

	assert_eq(GameState.current_state, GameState.State.NOTEBOOK,
			"open() must change GameState to NOTEBOOK")


# ---------------------------------------------------------------------------
# Test 4 — open(): makes the notebook visible
# ---------------------------------------------------------------------------

func test_notebook_open_makes_notebook_visible() -> void:
	var nb: Notebook = _make_notebook()

	# Notebooks start hidden; open() should reveal it.
	nb.visible = false
	nb.open()

	assert_true(nb.visible,
			"open() must set visible = true on the Notebook CanvasLayer")


# ---------------------------------------------------------------------------
# Test 5 — open(): emits notebook_opened with the correct tab argument
# ---------------------------------------------------------------------------

func test_notebook_open_emits_notebook_opened_signal() -> void:
	var nb: Notebook = _make_notebook()

	# watch_signals() must be called BEFORE the act that emits the signal.
	# See: https://gut.readthedocs.io/en/latest/Signals.html
	watch_signals(GameEvents)

	nb.open(Notebook.NotebookTab.MAP)

	# assert_signal_emitted_with_parameters checks both that the signal fired
	# and that its arguments matched. Parameters is an Array of expected values
	# in emission order. The optional fourth arg is an emission index, not a
	# message string — GUT 9.3.1 has no message parameter for this assertion.
	assert_signal_emitted_with_parameters(GameEvents, "notebook_opened",
			[Notebook.NotebookTab.MAP])


# ---------------------------------------------------------------------------
# Test 6 — close(): hides the notebook
# ---------------------------------------------------------------------------

func test_notebook_close_hides_notebook() -> void:
	var nb: Notebook = _make_notebook()
	nb.open()

	# Confirm it is visible before we close it — a vacuous test otherwise.
	assert_true(nb.visible, "precondition: notebook should be visible after open()")

	nb.close()

	assert_false(nb.visible,
			"close() must set visible = false on the Notebook CanvasLayer")


# ---------------------------------------------------------------------------
# Test 7 — close(): restores previous GameState
# ---------------------------------------------------------------------------

func test_notebook_close_restores_previous_state() -> void:
	# The notebook must remember the state that was active when open() was
	# called and restore it on close(). This is important for DIALOGUE → open
	# notebook → close → resume dialogue flows.
	GameState.change_state(GameState.State.PLAYING)

	var nb: Notebook = _make_notebook()
	nb.open()
	nb.close()

	assert_eq(GameState.current_state, GameState.State.PLAYING,
			"close() must restore the GameState that was active before open()")


# ---------------------------------------------------------------------------
# Test 8 — close(): emits notebook_closed
# ---------------------------------------------------------------------------

func test_notebook_close_emits_notebook_closed_signal() -> void:
	var nb: Notebook = _make_notebook()
	nb.open()

	watch_signals(GameEvents)

	nb.close()

	assert_signal_emitted(GameEvents, "notebook_closed",
			"close() must emit GameEvents.notebook_closed()")


# ---------------------------------------------------------------------------
# Test 9 — _switch_tab(): updates _current_tab
# ---------------------------------------------------------------------------

func test_notebook_switch_tab_updates_current_tab() -> void:
	# _switch_tab is named with a leading underscore by convention (private),
	# but GDScript does not enforce access control — we call it directly here
	# to test state transitions without going through full open/close cycles.
	var nb: Notebook = _make_notebook()
	nb.open(Notebook.NotebookTab.INVENTORY)

	nb._switch_tab(Notebook.NotebookTab.QUESTS)

	assert_eq(nb._current_tab, Notebook.NotebookTab.QUESTS,
			"_switch_tab() must update _current_tab to the new tab")


# ---------------------------------------------------------------------------
# Test 10 — _switch_tab(): emits notebook_tab_changed with the new tab
# ---------------------------------------------------------------------------

func test_notebook_switch_tab_emits_tab_changed_signal() -> void:
	var nb: Notebook = _make_notebook()
	nb.open(Notebook.NotebookTab.INVENTORY)

	watch_signals(GameEvents)

	nb._switch_tab(Notebook.NotebookTab.SETTINGS)

	assert_signal_emitted_with_parameters(GameEvents, "notebook_tab_changed",
			[Notebook.NotebookTab.SETTINGS])


# ---------------------------------------------------------------------------
# Test 11 — _switch_tab(): updates _last_tab to match the new tab
# ---------------------------------------------------------------------------

func test_notebook_switch_tab_updates_last_tab() -> void:
	# _last_tab is used to reopen the notebook to the most recent tab when
	# the player presses the same hotkey again. If it is not updated here,
	# re-open flows will silently snap back to a stale tab.
	var nb: Notebook = _make_notebook()
	nb.open(Notebook.NotebookTab.INVENTORY)

	nb._switch_tab(Notebook.NotebookTab.MAP)

	assert_eq(nb._last_tab, Notebook.NotebookTab.MAP,
			"_switch_tab() must update _last_tab so re-open flows recall the right tab")


# ---------------------------------------------------------------------------
# Test 12 — open() default argument: opens to INVENTORY when no tab given
# ---------------------------------------------------------------------------

func test_notebook_open_defaults_to_inventory_tab() -> void:
	var nb: Notebook = _make_notebook()

	# Call open() with no argument — should default to INVENTORY (0).
	nb.open()

	assert_eq(nb._current_tab, Notebook.NotebookTab.INVENTORY,
			"open() with no argument must default to the INVENTORY tab")


# ---------------------------------------------------------------------------
# Test 13 — open() with explicit tab: _current_tab matches the argument
# ---------------------------------------------------------------------------

func test_notebook_open_with_tab_argument_sets_current_tab() -> void:
	var nb: Notebook = _make_notebook()

	nb.open(Notebook.NotebookTab.QUESTS)

	assert_eq(nb._current_tab, Notebook.NotebookTab.QUESTS,
			"open(QUESTS) must set _current_tab to QUESTS")


# ---------------------------------------------------------------------------
# Test 14 — open(): pauses the scene tree
# ---------------------------------------------------------------------------

func test_notebook_open_pauses_the_scene_tree() -> void:
	# The world freezes while the notebook is open. This is what makes the
	# notebook the pause mechanism (GameState.NOTEBOOK replaces PAUSED).
	var nb: Notebook = _make_notebook()
	nb.open()

	assert_true(get_tree().paused,
			"open() must set get_tree().paused = true to freeze world simulation")


# ---------------------------------------------------------------------------
# Test 15 — close(): unpauses the scene tree
# ---------------------------------------------------------------------------

func test_notebook_close_unpauses_the_scene_tree() -> void:
	var nb: Notebook = _make_notebook()
	nb.open()

	assert_true(get_tree().paused, "precondition: tree should be paused after open()")

	nb.close()

	assert_false(get_tree().paused,
			"close() must set get_tree().paused = false to resume world simulation")


# ---------------------------------------------------------------------------
# Test 16 — NotebookTab base class: populate methods do not crash
# ---------------------------------------------------------------------------

func test_notebook_tab_base_class_populate_methods_do_not_crash() -> void:
	# NotebookTab is a stub base class. The only contract for Phase 1 is that
	# both populate methods exist and accept a Control (or null) without
	# raising an error. Subclasses will override them with real content.
	var tab: NotebookTab = NotebookTab.new()
	add_child_autofree(tab)

	# No assertion is needed — if either call throws, GUT will record a failure.
	tab.populate_left(null)
	tab.populate_right(null)

	# Explicit pass confirms we reached this line without a crash.
	assert_true(true, "populate_left(null) and populate_right(null) must not crash")


# ---------------------------------------------------------------------------
# Test 17 — _unhandled_input: hotkey opens notebook to the correct tab
# ---------------------------------------------------------------------------

func test_notebook_input_hotkey_opens_when_closed() -> void:
	# Pressing the inventory hotkey while closed must open the notebook and
	# switch to INVENTORY. Verifies the I-key routing works end-to-end.
	var nb: Notebook = _make_notebook()
	nb.visible = false

	nb._unhandled_input(_make_action("open_notebook_inventory"))

	assert_true(nb.visible,
			"pressing open_notebook_inventory must open the notebook")
	assert_eq(nb._current_tab, Notebook.NotebookTab.INVENTORY,
			"must open to INVENTORY when open_notebook_inventory is pressed")


# ---------------------------------------------------------------------------
# Test 18 — _unhandled_input: pressing the same tab hotkey while open closes it
# ---------------------------------------------------------------------------

func test_notebook_input_same_hotkey_toggles_closed() -> void:
	# The toggle design: pressing I while INVENTORY is already shown closes the
	# notebook. This is the "press again to dismiss" UX pattern.
	var nb: Notebook = _make_notebook()
	nb.open(Notebook.NotebookTab.INVENTORY)

	nb._unhandled_input(_make_action("open_notebook_inventory"))

	assert_false(nb.visible,
			"pressing open_notebook_inventory while INVENTORY is active must close the notebook")


# ---------------------------------------------------------------------------
# Test 19 — _unhandled_input: pressing a different tab hotkey switches without closing
# ---------------------------------------------------------------------------

func test_notebook_input_different_hotkey_switches_tab() -> void:
	# Pressing M while open on INVENTORY should switch to MAP without closing.
	# This lets the player hop between tabs using hotkeys.
	var nb: Notebook = _make_notebook()
	nb.open(Notebook.NotebookTab.INVENTORY)

	nb._unhandled_input(_make_action("open_notebook_map"))

	assert_true(nb.visible,
			"pressing a different tab hotkey must keep the notebook open")
	assert_eq(nb._current_tab, Notebook.NotebookTab.MAP,
			"pressing open_notebook_map must switch _current_tab to MAP")


# ---------------------------------------------------------------------------
# Test 20 — _unhandled_input: ui_cancel closes notebook when open
# ---------------------------------------------------------------------------

func test_notebook_input_ui_cancel_closes_when_open() -> void:
	# Pressing Escape while open must close the notebook — the universal
	# dismiss gesture consistent with other UI panels.
	var nb: Notebook = _make_notebook()
	nb.open()

	nb._unhandled_input(_make_action("ui_cancel"))

	assert_false(nb.visible,
			"ui_cancel while notebook is open must close it")


# ---------------------------------------------------------------------------
# Test 21 — _unhandled_input: ui_cancel opens to _last_tab when closed
# ---------------------------------------------------------------------------

func test_notebook_input_ui_cancel_opens_to_last_tab_when_closed() -> void:
	# Escape while closed reopens to the most recently viewed tab so the player
	# can quickly resume where they left off.
	var nb: Notebook = _make_notebook()
	nb.open(Notebook.NotebookTab.QUESTS)
	nb.close()

	nb._unhandled_input(_make_action("ui_cancel"))

	assert_true(nb.visible,
			"ui_cancel while notebook is closed must open it")
	assert_eq(nb._current_tab, Notebook.NotebookTab.QUESTS,
			"ui_cancel must reopen to _last_tab (QUESTS in this case)")


# ---------------------------------------------------------------------------
# Test 22 — _unhandled_input: Tab key cycles forward through tabs
# ---------------------------------------------------------------------------

func test_notebook_input_tab_key_cycles_forward() -> void:
	# While open, Tab advances to the next tab. INVENTORY(0) → MAP(1).
	# This lets keyboard-only players browse tabs without using hotkeys.
	var nb: Notebook = _make_notebook()
	nb.open(Notebook.NotebookTab.INVENTORY)

	nb._unhandled_input(_make_action("ui_focus_next"))

	assert_eq(nb._current_tab, Notebook.NotebookTab.MAP,
			"Tab from INVENTORY must advance _current_tab to MAP")


# ---------------------------------------------------------------------------
# Test 23 — _unhandled_input: Shift+Tab cycles backward and wraps around
# ---------------------------------------------------------------------------

func test_notebook_input_shift_tab_cycles_backward_with_wrap() -> void:
	# Shift+Tab goes backward. From INVENTORY(0), wrapping backward should
	# land on SESSIONS(4) — the last tab in the enum.
	var nb: Notebook = _make_notebook()
	nb.open(Notebook.NotebookTab.INVENTORY)

	nb._unhandled_input(_make_action("ui_focus_prev"))

	assert_eq(nb._current_tab, Notebook.NotebookTab.SESSIONS,
			"Shift+Tab from INVENTORY must wrap backward to SESSIONS")


# ---------------------------------------------------------------------------
# Test 24 — close(): writes the current SaveManager.settings to settings.tres
# ---------------------------------------------------------------------------

func test_notebook_close_writes_settings_to_disk() -> void:
	# design §11 Step 4: closing the notebook persists per-device settings via
	# SaveManager.save_settings(). before_each() already gave SaveManager.settings
	# a fresh default GameSettings; remove any pre-existing settings.tres here
	# (restored in after_each()) so a non-existent file becoming present after
	# close() is directly attributable to this slice's close hook.
	if FileAccess.file_exists(SaveManager.SETTINGS_PATH):
		DirAccess.remove_absolute(SaveManager.SETTINGS_PATH)
	assert_false(FileAccess.file_exists(SaveManager.SETTINGS_PATH),
			"precondition: settings.tres should not exist before close()")

	var nb: Notebook = _make_notebook()
	nb.open()
	nb.close()

	assert_true(FileAccess.file_exists(SaveManager.SETTINGS_PATH),
			"close() must write user://settings.tres via SaveManager.save_settings()")


# ---------------------------------------------------------------------------
# Test 25 — close() -> load_settings(): round-trips a changed setting
# ---------------------------------------------------------------------------

func test_notebook_close_then_load_settings_round_trips_changed_value() -> void:
	# Arrange: change a setting on the shared SaveManager.settings instance —
	# simulating a player moving the Master Volume slider via SettingsTab,
	# whose _settings IS SaveManager.settings (Slice 5).
	SaveManager.settings.master_volume = 0.3
	SaveManager.settings.window_scale = 4

	var nb: Notebook = _make_notebook()
	nb.open(Notebook.NotebookTab.SETTINGS)
	nb.close()

	# Act: load into a FRESH SaveManager.settings instance so this is a genuine
	# round trip through disk, not a read of the same object we just wrote.
	SaveManager.settings = null
	SaveManager.load_settings()

	assert_not_null(SaveManager.settings,
			"load_settings() should populate SaveManager.settings after notebook close persisted it")
	assert_eq(SaveManager.settings.master_volume, 0.3,
			"master_volume (0.3) must survive a notebook close + load_settings() round trip")
	assert_eq(SaveManager.settings.window_scale, 4,
			"window_scale (4) must survive a notebook close + load_settings() round trip")


# ---------------------------------------------------------------------------
# Test 26 — reopen to Settings after close shows persisted (non-default) values
# ---------------------------------------------------------------------------

func test_reopen_to_settings_after_close_shows_persisted_values() -> void:
	# Open to Settings, change a value (simulating a slider edit on the shared
	# SaveManager.settings), close (persists via save_settings()), then reopen
	# to Settings again. The second populate_left() pass must show the
	# persisted value, not reset to GameSettings defaults — proving
	# SettingsTab keeps reading the shared SaveManager.settings instance across
	# a close + reopen cycle within the same session.
	var nb: Notebook = _make_notebook()
	nb.open(Notebook.NotebookTab.SETTINGS)

	# Simulate a slider edit: SettingsTab._settings IS SaveManager.settings
	# (Slice 5), so mutating the shared instance is equivalent to moving the
	# slider for the purposes of this test.
	SaveManager.settings.master_volume = 0.45

	nb.close()
	nb.open(Notebook.NotebookTab.SETTINGS)

	var settings_tab: SettingsTab = nb._tab_instances[Notebook.NotebookTab.SETTINGS] as SettingsTab
	assert_not_null(settings_tab,
			"precondition: a SettingsTab instance must exist after opening to SETTINGS")
	assert_almost_eq(settings_tab._master_slider.value, 45.0, 0.001,
			"reopening to Settings after close must show the persisted master_volume (0.45 -> slider 45.0), not the GameSettings default (100.0)")

	nb.close()


# ---------------------------------------------------------------------------
# Test 27 — settings-only edit + close does not change PlayerData.to_resource()
# ---------------------------------------------------------------------------

func test_settings_edit_and_close_does_not_change_player_data() -> void:
	# design §5 / §11 Step 4: GameSettings stays OUT of PlayerData — settings
	# are per-device, PlayerData is per-save. Seed PlayerData the way a fresh
	# "New Story" does (mirrors test_quests_tab.gd / test_inventory_tab*.gd
	# conventions for Slice 3/4), capture distinguishing values, then perform a
	# settings-only edit + notebook close and confirm PlayerData is untouched.
	var data: PlayerDataResource = PlayerDataResource.new()
	data.reset_to_new_game()
	PlayerData._load_resource(data)
	PlayerData.gold = 250

	var resource_before: PlayerDataResource = PlayerData.to_resource()
	var gold_before: int = PlayerData.gold
	var stack_count_before: int = PlayerData.inventory.stacks.size()
	var quest_states_before: Dictionary = PlayerData.quest_log.states.duplicate(true)

	var nb: Notebook = _make_notebook()
	nb.open(Notebook.NotebookTab.SETTINGS)
	SaveManager.settings.master_volume = 0.1
	SaveManager.settings.window_scale = 1
	nb.close()

	assert_same(PlayerData.to_resource(), resource_before,
			"a settings-only edit + notebook close must not swap PlayerData._resource")
	assert_eq(PlayerData.gold, gold_before,
			"a settings-only edit + notebook close must not change PlayerData.gold")
	assert_eq(PlayerData.inventory.stacks.size(), stack_count_before,
			"a settings-only edit + notebook close must not change PlayerData.inventory stack count")
	assert_eq(PlayerData.quest_log.states, quest_states_before,
			"a settings-only edit + notebook close must not change PlayerData.quest_log.states")


# ---------------------------------------------------------------------------
# Test 28 — close() persists settings regardless of which tab was last active
# ---------------------------------------------------------------------------

func test_notebook_close_persists_settings_regardless_of_active_tab() -> void:
	# The close hook (design §11 Step 4, approved option (a)) lives in
	# notebook.gd's close() itself — a single shared call, not a per-tab
	# listener. Closing while a DIFFERENT tab (INVENTORY) is active must still
	# persist SaveManager.settings, proving the hook does not depend on
	# SettingsTab being the active tab when close() runs.
	SaveManager.settings.sfx_volume = 0.2

	var nb: Notebook = _make_notebook()
	# Open to SETTINGS first so _settings is sourced from SaveManager.settings
	# and the edit above is "live" on the shared instance, then switch away.
	nb.open(Notebook.NotebookTab.SETTINGS)
	nb._switch_tab(Notebook.NotebookTab.INVENTORY)
	nb.close()

	SaveManager.settings = null
	SaveManager.load_settings()

	assert_eq(SaveManager.settings.sfx_volume, 0.2,
			"closing while INVENTORY (not SETTINGS) is active must still persist sfx_volume (0.2) via the shared close hook")


# ---------------------------------------------------------------------------
# Test 29 — close(): notebook_closed still emits exactly once with the new hook
# ---------------------------------------------------------------------------

func test_notebook_close_emits_notebook_closed_exactly_once_with_save_hook() -> void:
	# Regression guard: adding the save_settings() call to close() must not
	# cause notebook_closed to be emitted more than once (e.g. via an
	# accidental extra signal connection added alongside the new hook).
	var nb: Notebook = _make_notebook()
	nb.open()

	watch_signals(GameEvents)

	nb.close()

	assert_signal_emit_count(GameEvents, "notebook_closed", 1,
			"close() must emit GameEvents.notebook_closed exactly once even with the new save_settings() hook")
