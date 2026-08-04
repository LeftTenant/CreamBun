## test_save_manager.gd
## TDD contract tests for the SaveManager autoload rewrite
## (autoloads/save_manager.gd) — Slice 2.
##
## These tests cover the purely structural / constant-level parts of the §6.2
## rewrite: the new SETTINGS_PATH / SLOT_DIR constants, _slot_path(), and the
## initial (unloaded) state of `settings`. They do not touch disk or
## PlayerData — see tests/integration/foundation/ for the I/O and
## launch-wiring behaviors.
##
## Regression guard for the §6.2 rewrite. See:
##   docs/features/game-data/design.md (§6.2, §10, §11)
##   docs/features/game-data/slices.md (Slice 2)
##   docs/features/game-data/slice-2-savemanager-test-plan.md
##
## Requires GUT: https://github.com/bitwes/Gut
## Install via Godot Asset Library (search "GUT - Godot Unit Testing").
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd -gselect=test_save_manager.gd -gexit

class_name TestSaveManager
extends GutTest


# ---------------------------------------------------------------------------
# Test 1 — new path constants match design §6.2
# ---------------------------------------------------------------------------

func test_settings_path_constant() -> void:
	assert_eq(SaveManager.SETTINGS_PATH, "user://settings.tres",
			"SaveManager.SETTINGS_PATH should be \"user://settings.tres\" per design §6.2")


func test_slot_dir_constant() -> void:
	assert_eq(SaveManager.SLOT_DIR, "user://slots/",
			"SaveManager.SLOT_DIR should be \"user://slots/\" per design §6.2")


# ---------------------------------------------------------------------------
# Test 2 — _slot_path() builds the per-slot filename from SLOT_DIR
# ---------------------------------------------------------------------------

func test_slot_path_builds_filename_from_slot_id() -> void:
	# §6.2: func _slot_path(slot_id: String) -> String:
	#           return "%sslot_%s.tres" % [SLOT_DIR, slot_id]
	assert_eq(SaveManager._slot_path("default"), "user://slots/slot_default.tres",
			"_slot_path(\"default\") should be \"user://slots/slot_default.tres\"")


func test_slot_path_reflects_slot_dir_for_a_different_slot_id() -> void:
	# Confirm the helper is parameterized on slot_id, not hardcoded to "default" —
	# even though Phase 1 only ever passes a single default slot id at runtime.
	assert_eq(SaveManager._slot_path("alt_slot"), "user://slots/slot_alt_slot.tres",
			"_slot_path(\"alt_slot\") should be \"user://slots/slot_alt_slot.tres\"")


# ---------------------------------------------------------------------------
# Test 3 — settings is null before load_settings() has ever been called
# ---------------------------------------------------------------------------
#
# NOTE: SaveManager is an autoload singleton, so by the time any test runs,
# launch wiring (Slice 2's SaveManager._ready()) has already called
# load_settings() once — `settings` will already be populated in this test
# run. This test instead asserts the *declared default* of the `settings`
# field is null by constructing a second, throwaway SaveManager-scripted node
# and checking its initial value before _ready() has had a chance to run via
# the scene tree (autofree, never added to the tree → _ready() never fires).
# This isolates the "field declaration does not eagerly construct a
# GameSettings" contract from the "_ready() calls load_settings()" contract
# (covered in the integration suite).

func test_settings_field_defaults_to_null_before_load_settings() -> void:
	var fresh_save_manager: Node = SaveManager.get_script().new()
	autofree(fresh_save_manager)
	# Deliberately NOT added to the scene tree — _ready() (and therefore
	# load_settings()) must never run for this instance.

	assert_null(fresh_save_manager.settings,
			"settings should be null on a freshly-constructed SaveManager before load_settings() runs — only load_settings() should populate it")
