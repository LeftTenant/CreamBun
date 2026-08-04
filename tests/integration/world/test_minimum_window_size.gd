## test_minimum_window_size.gd
## Integration test for the minimum-window-size enforcement added in the
## window-scale rework — world.gd._set_minimum_window_size().
##
## MOVED FROM tests/unit/ (integration, not unit)
## -----------------------------------------------
## The previous version of this test lived in tests/unit/ and asserted a
## test-local duplicate of world.gd's MINIMUM_SCALE constant against itself —
## it never called _set_minimum_window_size() or read Window.min_size, so a
## real bug in world.gd (wrong multiplier, swapped width/height, a deleted
## call) would not have been caught. Its own header cited "world.tscn is too
## fragile to instantiate headless" as the reason to avoid an integration
## test, but tests/integration/world/test_world_scene.gd has instantiated
## world.tscn headless cleanly for a long time — that justification was
## already stale. This version follows test_world_scene.gd's instantiation
## pattern and asserts the real Window.min_size world.gd actually sets.
##
## WHY THIS IS SAFE UNDER HEADLESS GUT (unlike DisplayServer.window_get_size())
## ------------------------------------------------------------------------
## Window.min_size is a plain property on the Window resource itself. Unlike
## DisplayServer.window_get_size() (meaningless in headless mode — see the
## headless guard in tests/integration/notebook/test_settings_tab_handlers.gd),
## setting and reading Window.min_size does not depend on a real OS window
## surface, so it is safe and meaningful to assert here.
##
## The invariant: MINIMUM_SCALE (2) × viewport size must equal Window.min_size
## after World._ready() runs. If project.godot's viewport dimensions change
## without world.gd being updated, or world.gd's multiplier drifts from the
## Settings tab's WINDOW_SCALE_OPTIONS[0], this test fails and points at the
## discrepancy directly.
##
## Requires GUT: https://github.com/bitwes/Gut
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gselect=test_minimum_window_size.gd -gexit

class_name TestMinimumWindowSize
extends GutTest


# Path to the world scene — loaded as a PackedScene and instantiated so
# _ready() (and therefore _set_minimum_window_size()) actually runs.
const WORLD_SCENE_PATH: String = "res://world/world.tscn"

# The minimum integer scale that the Settings tab offers. Must match
# world.gd's local MINIMUM_SCALE constant and SettingsTab.WINDOW_SCALE_OPTIONS[0].
const MINIMUM_SCALE: int = 2


# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

func before_each() -> void:
	# Matches test_world_scene.gd's convention — see that file's before_each()
	# doc comment for why GameState must be set explicitly here.
	GameState.change_state(GameState.State.PLAYING)


# ---------------------------------------------------------------------------
# Test 1 — Window.min_size is 2x the viewport after World._ready() runs
# ---------------------------------------------------------------------------

func test_minimum_window_size_is_2x_viewport_after_world_ready() -> void:
	var packed: PackedScene = load(WORLD_SCENE_PATH)
	assert_not_null(packed, "world/world.tscn should load as a PackedScene")
	if packed == null:
		return

	var world: Node = packed.instantiate()
	add_child_autofree(world)

	var viewport_width: int = ProjectSettings.get_setting(
			"display/window/size/viewport_width", 320) as int
	var viewport_height: int = ProjectSettings.get_setting(
			"display/window/size/viewport_height", 180) as int
	var expected_min_size: Vector2i = Vector2i(
			viewport_width * MINIMUM_SCALE,
			viewport_height * MINIMUM_SCALE)

	assert_eq(get_window().min_size, expected_min_size,
			("World._ready() must set Window.min_size to %d× the %dx%d viewport (expected %s); got %s. "
			+ "If this fails, either world.gd._set_minimum_window_size() drifted from "
			+ "MINIMUM_SCALE, or the viewport dimensions in project.godot changed.") % [
					MINIMUM_SCALE, viewport_width, viewport_height,
					str(expected_min_size), str(get_window().min_size)])


# ---------------------------------------------------------------------------
# Test 2 — minimum scale (2) is smaller than the default scale (4)
# ---------------------------------------------------------------------------

func test_minimum_scale_is_less_than_default_scale() -> void:
	# Guards against a future change that accidentally makes the minimum equal
	# to or larger than the default. If that happened, launching the game at the
	# default 4× window (1280×720) would still work, but "resizing down" past
	# the minimum would be blocked before reaching a reasonable small window.
	var default_scale: int = SettingsTab.DEFAULT_WINDOW_SCALE
	var msg: String = (
			"MINIMUM_SCALE (%d) must be less than DEFAULT_WINDOW_SCALE (%d) — "
			+ "the minimum window enforced by world.gd must be smaller than the "
			+ "default launch size") % [MINIMUM_SCALE, default_scale]
	assert_true(MINIMUM_SCALE < default_scale, msg)


# ---------------------------------------------------------------------------
# Test 3 — minimum scale is the first entry in WINDOW_SCALE_OPTIONS
# ---------------------------------------------------------------------------

func test_minimum_scale_is_first_window_scale_option() -> void:
	# The minimum window size enforced by world.gd (2×) must match the first
	# entry in WINDOW_SCALE_OPTIONS, so the floor and the smallest selectable
	# UI option are always in sync. A drift between the two would mean the UI
	# shows an option the OS will reject.
	assert_eq(SettingsTab.WINDOW_SCALE_OPTIONS[0], MINIMUM_SCALE,
			"WINDOW_SCALE_OPTIONS[0] (%d) must equal the minimum scale (%d) enforced by world.gd" % [
					SettingsTab.WINDOW_SCALE_OPTIONS[0], MINIMUM_SCALE])
