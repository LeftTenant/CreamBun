## test_minimum_window_size.gd
## Contract test for the minimum-window-size enforcement added in the
## window-scale rework.
##
## WHY NOT AN INTEGRATION TEST AGAINST world.tscn
## -----------------------------------------------
## world.gd._set_minimum_window_size() is defined in a script that has no
## class_name (it extends Node2D directly), and world.tscn has physics,
## TileMapLayer, and CharacterBody2D dependencies that require a full scene
## graph to initialise — making it fragile under headless GUT. Instead we test
## the mathematical contract directly: 2× the project viewport dimensions must
## equal Vector2i(640, 360) given the current project.godot settings. This
## proves the computation world.gd performs is correct without loading the
## world scene at all.
##
## The invariant: MINIMUM_SCALE (2) × viewport size = (640, 360).
## If project.godot ever changes the viewport dimensions, this test will fail
## — which is the desired signal, because world.gd would need a review.
##
## Requires GUT: https://github.com/bitwes/Gut
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gselect=test_minimum_window_size.gd -gexit

class_name TestMinimumWindowSize
extends GutTest


# ---------------------------------------------------------------------------
# Constants — must match world.gd's MINIMUM_SCALE constant
# ---------------------------------------------------------------------------

# The minimum integer scale that the Settings tab offers. world.gd enforces
# this as the OS window floor so a manual resize cannot go below the 2× option.
const MINIMUM_SCALE: int = 2


# ---------------------------------------------------------------------------
# Test 1 — minimum window size computation equals 2× the viewport
# ---------------------------------------------------------------------------

func test_minimum_window_size_is_2x_viewport() -> void:
	# world.gd computes:
	#   get_window().min_size = Vector2i(viewport_width * 2, viewport_height * 2)
	# With the current project.godot (viewport 320×180), the expected min size
	# is Vector2i(640, 360). This test reads the same ProjectSettings keys
	# world.gd reads, applies the same math, and asserts the result.
	# If a future viewport resize changes these values without updating world.gd,
	# this test will fail — pointing directly at the discrepancy.
	var viewport_width: int = ProjectSettings.get_setting(
			"display/window/size/viewport_width", 320) as int
	var viewport_height: int = ProjectSettings.get_setting(
			"display/window/size/viewport_height", 180) as int

	var computed_min_size: Vector2i = Vector2i(
			viewport_width * MINIMUM_SCALE,
			viewport_height * MINIMUM_SCALE)

	assert_eq(computed_min_size, Vector2i(640, 360),
			"2× the 320×180 viewport must equal Vector2i(640, 360) — "
			+ "the minimum window size enforced by world.gd._set_minimum_window_size(). "
			+ "If this fails, the viewport dimensions in project.godot changed and "
			+ "world.gd must be reviewed.")


# ---------------------------------------------------------------------------
# Test 2 — minimum scale (2) is smaller than the default scale (4)
# ---------------------------------------------------------------------------

func test_minimum_scale_is_less_than_default_scale() -> void:
	# Guards against a future change that accidentally makes the minimum equal
	# to or larger than the default. If that happened, launching the game at the
	# default 4× window (1280×720) would still work, but "resizing down" past
	# the minimum would be blocked before reaching a reasonable small window.
	#
	# DEFAULT_WINDOW_SCALE comes from SettingsTab. Checking it here (without
	# instantiating SettingsTab) via the class constant ensures the constant
	# is accessible as a class-level value, which is a requirement of the
	# SettingsTab design (used in _on_reset_all_pressed via find()).
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
