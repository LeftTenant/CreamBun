## test_threshold_class_name.gd
## Unit test for `class_name Threshold` (world/thresholds/threshold.gd) —
## World Thresholds feature, Slice 2.
##
## Split out from test_threshold.gd specifically to keep this ONE test file
## free of the `Threshold` identifier used as a type, anywhere. This test's
## entire point is confirming `class_name Threshold` is registered and
## resolves to threshold.gd, so it checks
## ProjectSettings.get_global_class_list() by name STRING rather than writing
## `Threshold` as a type — using the identifier to test that the identifier
## resolves would make the test circular. Worse than merely circular: a
## GDScript file that fails to PARSE (which is what happens if you write
## `var x: Threshold` and `class_name Threshold` has been removed) is
## silently dropped from a GUT run rather than reported as a failure — so a
## circular version of this test would report the suite as green while
## providing zero protection against the exact regression it exists to
## catch. Keeping it isolated in its own file (rather than merely avoiding
## the identifier by convention inside test_threshold.gd) means it can't pick
## up a stray `Threshold` type hint as that file evolves.
##
## Every other Threshold-related test (root type, script attachment, export
## defaults, collision layer/mask, CollisionShape2D child) lives in
## test_threshold.gd and IS free to type against `Threshold` directly — see
## that file's header.
##
## Design reference: docs/features/world-thresholds/design.md §4
## Test plan: docs/features/world-thresholds/slice-2-threshold-node-test-plan.md
## Slice breakdown: docs/features/world-thresholds/slices.md, Slice 2
##
## Requires GUT: https://github.com/bitwes/Gut
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gselect=test_threshold_class_name.gd -gexit

class_name TestThresholdClassName
extends GutTest


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const SCENE_PATH: String = "res://world/thresholds/threshold.tscn"
const SCRIPT_PATH: String = "res://world/thresholds/threshold.gd"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Load and instantiate threshold.tscn, added to the tree (autofreed).
## Deliberately untyped (returns plain Node) — this is a duplicate of
## test_threshold.gd's `_make_threshold()` base helper, kept local to this
## file rather than shared, so this file never has any reason to import or
## reference anything typed `Threshold`. Returns null, with the failure
## already recorded via assert_not_null(), if the scene doesn't load or the
## instance can't be created.
func _make_threshold() -> Node:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	assert_not_null(packed,
			"%s must exist and load as a PackedScene." % [SCENE_PATH])
	if packed == null:
		return null

	var instance: Node = packed.instantiate()
	assert_not_null(instance, "%s failed to instantiate." % [SCENE_PATH])
	if instance == null:
		return null

	add_child_autofree(instance)
	return instance


## Find a registered global (`class_name`) class by name from
## ProjectSettings.get_global_class_list(), without ever writing the class
## name as a GDScript type — see file header for why that matters here.
## Returns {} if no such class is registered.
## https://docs.godotengine.org/en/stable/classes/class_projectsettings.html#class-projectsettings-method-get-global-class-list
func _find_global_class(global_class_name: String) -> Dictionary:
	for entry in ProjectSettings.get_global_class_list():
		if entry.get("class", "") == global_class_name:
			return entry
	return {}


# ---------------------------------------------------------------------------
# class_name Threshold resolves to threshold.gd
# ---------------------------------------------------------------------------

func test_class_name_threshold_resolves_to_the_attached_script() -> void:
	# Confirmed via the project's global class list rather than the
	# `Threshold` identifier itself — see this file's header note on why this
	# whole file avoids typing against the identifier it's proving exists.
	var class_info: Dictionary = _find_global_class("Threshold")
	assert_false(class_info.is_empty(),
			("a global class named 'Threshold' must be registered — "
					+ "world/thresholds/threshold.gd's `class_name Threshold` "
					+ "(design §4)."))
	if class_info.is_empty():
		return

	assert_eq(class_info.get("base", ""), "Area2D",
			("the 'Threshold' global class must extend Area2D (found base=%s) "
					+ "— design §4's `extends Area2D`.")
					% [class_info.get("base", "")])
	assert_eq(class_info.get("path", ""), SCRIPT_PATH,
			("the 'Threshold' global class must be declared in %s (found %s)."
					% [SCRIPT_PATH, class_info.get("path", "")]))

	# Tie it back to the actual scene: threshold.tscn's root script must be
	# the very file the 'Threshold' global class resolves to, not merely a
	# same-named coincidence. Uses the deliberately-untyped `_make_threshold()`
	# above rather than a `Threshold`-typed helper — get_script() is available
	# on plain Node, so no cast is needed here at all.
	var instance: Node = _make_threshold()
	if instance == null:
		return
	var script: Script = instance.get_script() as Script
	assert_not_null(script,
			"threshold.tscn's root must have a script attached to compare against the 'Threshold' global class.")
	if script == null:
		return
	assert_eq(script.resource_path, class_info.get("path", ""),
			("threshold.tscn's root script (%s) must be the same file the "
					+ "'Threshold' global class resolves to (%s).")
					% [script.resource_path, class_info.get("path", "")])
