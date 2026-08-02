## test_threshold.gd
## Unit tests for the `Threshold` node (world/thresholds/threshold.gd /
## threshold.tscn) — World Thresholds feature, Slice 2.
##
## Guards threshold.tscn/threshold.gd's shape (root type, script, exports,
## collision layer/mask, CollisionShape2D child) against regressing — see
## design §4's exact snippet and layer/mask values.
##
## NOTE — the `class_name Threshold` global-registration check used to live
## here, but it has been moved out to its own script:
## tests/unit/world/thresholds/test_threshold_class_name.gd. That test's
## whole point is confirming `class_name Threshold` is registered and
## resolves to this script, which means it cannot ever write the `Threshold`
## identifier as a type without becoming circular (it would then only fail to
## COMPILE, not fail its assertion, if the class_name were ever removed — and
## a GDScript file that fails to parse is silently dropped from a GUT run
## rather than reported as a failure). Keeping that test in a file with zero
## `Threshold` type usage anywhere is the only way to guarantee it can't pick
## up the identifier by accident as this file evolves. Every helper and test
## below IS free to type against `Threshold` directly, since a renamed/
## removed export should be a compile error here, not a silent `null` — see
## `_make_threshold_area()`'s explicit assert_not_null() on the cast.
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
##     -gselect=test_threshold.gd -gexit

class_name TestThreshold
extends GutTest


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const SCENE_PATH: String = "res://world/thresholds/threshold.tscn"
const SCRIPT_PATH: String = "res://world/thresholds/threshold.gd"

## Physics layer bit values, per project.godot's [layer_names] section:
##   2d_physics/layer_1="world"          -> bit 0 -> value 1
##   2d_physics/layer_2="player"         -> bit 1 -> value 2
##   2d_physics/layer_3="interactable"   -> bit 2 -> value 4
##   2d_physics/layer_4="player_bounds"  -> bit 3 -> value 8
## Mirrored here rather than read off a WorldArea/Threshold constant, matching
## this suite's established convention (test_player_scene.gd,
## test_edge_triggers.gd) of not letting a wrong constant in the
## implementation also validate its own test.
const WORLD_LAYER_BIT: int = 1
const PLAYER_LAYER_BIT: int = 2
const INTERACTABLE_LAYER_BIT: int = 4
const PLAYER_BOUNDS_LAYER_BIT: int = 8


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Load and instantiate threshold.tscn, added to the tree (autofreed) so any
## @onready logic in threshold.gd would run. Returns the root as a plain Node,
## deliberately untyped — this is the base helper other helpers narrow from
## (_make_threshold_area() checks `is Area2D` before casting to `Threshold`),
## so it makes no assumption about the root's type itself. Returns null, with
## the failure already recorded via assert_not_null(), if the scene doesn't
## load or the instance can't be created.
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


## _make_threshold(), narrowed to Threshold for the tests that need
## collision_layer/collision_mask/get_node()/destination/arrival — the shared
## "is the root actually an Area2D" check lives here so it isn't repeated in
## every test that needs the cast. Typed `Threshold` (not just `Area2D`) so a
## renamed/removed export fails these tests to COMPILE rather than silently
## reading back `null` from an untyped `.get()` — see file header.
func _make_threshold_area() -> Threshold:
	var instance: Node = _make_threshold()
	if instance == null:
		return null

	assert_true(instance is Area2D,
			("threshold.tscn's root must be an Area2D (found %s) — design §4."
					% [instance.get_class()]))
	if not (instance is Area2D):
		return null

	# Assert on the CAST result itself, not just `instance is Area2D`. If
	# threshold.gd were ever detached from threshold.tscn's root, the node is
	# still a plain Area2D — `is Area2D` above would pass — but `as Threshold`
	# yields null. Without this check, this helper would silently return null
	# and every caller's `if threshold == null: return` guard would fire
	# before either script-attachment assertion below ever ran, so the suite
	# would report a pass on a real regression.
	var threshold: Threshold = instance as Threshold
	assert_not_null(threshold,
			("threshold.tscn's root must have world/thresholds/threshold.gd "
					+ "attached — design §4."))
	return threshold


# ---------------------------------------------------------------------------
# Root node: Area2D, threshold.gd attached
# ---------------------------------------------------------------------------
#
# The sibling check — that `class_name Threshold` resolves to this same
# script — lives in test_threshold_class_name.gd, not here. See file header.

func test_root_node_is_an_area2d_with_threshold_script_attached() -> void:
	var threshold: Threshold = _make_threshold_area()
	if threshold == null:
		return

	var script: Script = threshold.get_script() as Script
	assert_not_null(script,
			("threshold.tscn's root must have a script attached "
					+ "(world/thresholds/threshold.gd) — design §4."))
	if script == null:
		return

	assert_eq(script.resource_path, SCRIPT_PATH,
			("threshold.tscn's root script must be %s (found %s)."
					% [SCRIPT_PATH, script.resource_path]))


# ---------------------------------------------------------------------------
# Export defaults (design §4's exact snippet)
# ---------------------------------------------------------------------------

func test_destination_defaults_to_empty_string() -> void:
	var threshold: Threshold = _make_threshold_area()
	if threshold == null:
		return

	assert_eq(threshold.destination, "",
			("Threshold.destination must default to \"\" — an unconfigured "
					+ "Threshold names no destination scene (design §4)."))


func test_arrival_defaults_to_empty_string_name() -> void:
	var threshold: Threshold = _make_threshold_area()
	if threshold == null:
		return

	assert_eq(threshold.arrival, &"",
			("Threshold.arrival must default to &\"\" — an unconfigured "
					+ "Threshold names no landing marker (design §4)."))


# ---------------------------------------------------------------------------
# Collision layer / mask (design §4, §6)
# ---------------------------------------------------------------------------

func test_collision_layer_is_interactable_only() -> void:
	var threshold: Threshold = _make_threshold_area()
	if threshold == null:
		return

	assert_eq(threshold.collision_layer, INTERACTABLE_LAYER_BIT,
			("Threshold.collision_layer must be exactly the 'interactable' "
					+ "layer (value %d, project.godot's 2d_physics/layer_3) — "
					+ "found %d. A Threshold is detected, it does not itself "
					+ "detect or block anything, so it must not additionally "
					+ "declare itself on 'player_bounds' (%d), 'player' (%d), "
					+ "or 'world' (%d) — design §4.")
					% [
						INTERACTABLE_LAYER_BIT, threshold.collision_layer,
						PLAYER_BOUNDS_LAYER_BIT, PLAYER_LAYER_BIT, WORLD_LAYER_BIT,
					])


func test_collision_mask_is_player_bounds_only_not_the_movement_capsule() -> void:
	# The one check the test plan calls out by name: collision_mask must be
	# player_bounds (bit 3, value 8) — the art-sized ThresholdBounds detection
	# box (design §6) — and specifically NOT player (bit 1, value 2), the
	# movement capsule's layer. Both layers exist and both are plausible
	# values to reach for; masking the movement capsule instead of
	# ThresholdBounds would make a Threshold fire the instant the player's
	# 22x10 collider brushes it, rather than when their full drawn extent
	# does — a real, silent behavior change, not just a wrong number.
	var threshold: Threshold = _make_threshold_area()
	if threshold == null:
		return

	var found: int = threshold.collision_mask
	var detail: String = ""
	if found == PLAYER_LAYER_BIT:
		detail = (
				" Found exactly %d — that IS the 'player' layer (the movement "
				+ "capsule), the specific mix-up design §4 warns about: a "
				+ "Threshold masking the movement CollisionShape2D instead of "
				+ "ThresholdBounds fires as soon as the capsule touches it, "
				+ "not when the art-sized box does. Set collision_mask to bit "
				+ "3 (value %d, 'player_bounds'), not bit 1 (value %d, "
				+ "'player').") % [found, PLAYER_BOUNDS_LAYER_BIT, PLAYER_LAYER_BIT]
	elif found == INTERACTABLE_LAYER_BIT:
		detail = " Found %d — that is 'interactable', the layer a Threshold declares itself ON, not the layer it should mask." % [found]
	elif found == WORLD_LAYER_BIT:
		detail = " Found %d — that is 'world' (solid terrain), which a Threshold never needs to detect." % [found]

	assert_eq(found, PLAYER_BOUNDS_LAYER_BIT,
			("Threshold.collision_mask must be exactly the 'player_bounds' "
					+ "layer (value %d, project.godot's 2d_physics/layer_4) — "
					+ "design §6.%s") % [PLAYER_BOUNDS_LAYER_BIT, detail])


# ---------------------------------------------------------------------------
# CollisionShape2D child (design §4 — "an Area2D a designer drags into an
# area scene and sizes")
# ---------------------------------------------------------------------------

func test_has_a_collision_shape2d_child_using_a_rectangle_shape() -> void:
	var threshold: Threshold = _make_threshold_area()
	if threshold == null:
		return

	var collision: CollisionShape2D = threshold.get_node_or_null("CollisionShape2D") as CollisionShape2D
	assert_not_null(collision,
			("threshold.tscn must have a child named 'CollisionShape2D' — "
					+ "present so a designer has something to resize per "
					+ "placement (design §4: \"an Area2D a designer drags into "
					+ "an area scene and sizes\")."))
	if collision == null:
		return

	assert_true(collision.shape is RectangleShape2D,
			("threshold.tscn's CollisionShape2D.shape must be a "
					+ "RectangleShape2D (found %s) — design §4 describes a "
					+ "resizable rectangular region, not a circle or capsule.")
					% [collision.shape])
