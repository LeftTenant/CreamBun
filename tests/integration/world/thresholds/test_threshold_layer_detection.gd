## test_threshold_layer_detection.gd
## Integration test for the World Thresholds feature, Slice 2 — proves the
## `Threshold` node's physics layer/mask actually detects a real player's
## `ThresholdBounds` collider (world-thresholds Slice 1), not just that each
## side's bits are individually correct.
##
## Why this needs its own (integration) test, distinct from
## tests/unit/world/thresholds/test_threshold.gd's per-bit unit checks: two
## masks can each be "correct" in isolation and still fail to see each other
## if a bit is transposed. A unit test asserting
## `collision_mask == PLAYER_BOUNDS_LAYER_BIT` cannot catch, say, both layers
## being defined against the wrong bit index in project.godot, or
## ThresholdBounds's own layer silently drifting — only two REAL nodes
## overlapping and a REAL area_entered signal firing proves the two sides
## actually see each other. This is deliberately the one thing this slice's
## test plan calls out as not premature integration coverage.
##
## Placed under tests/integration/world/thresholds/ (a new directory) rather
## than folded into an existing file: it is the first Threshold-specific
## integration concern, and it anticipates the sibling
## test_threshold_transition.gd this directory's future Slice 3 adds (per
## docs/features/world-thresholds/slices.md) — grouping by feature area
## rather than scattering a lone Threshold check into
## tests/integration/world/test_collision_geometry_invariants.gd or a
## same-named file that already has an unrelated focus.
##
## Asserts ONLY the raw overlap (Area2D.area_entered firing, and the areas
## showing up in each other's get_overlapping_areas()). Nothing in this
## slice listens to area_entered yet — that's Slice 3 — so no downstream
## behavior (freeze/fade/swap) is exercised or asserted here.
##
## Design reference: docs/features/world-thresholds/design.md §4, §6
## Test plan: docs/features/world-thresholds/slice-2-threshold-node-test-plan.md
## Slice breakdown: docs/features/world-thresholds/slices.md, Slice 2
##
## Requires GUT: https://github.com/bitwes/Gut
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gselect=test_threshold_layer_detection.gd -gexit

class_name TestThresholdLayerDetection
extends GutTest


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const THRESHOLD_SCENE_PATH: String = "res://world/thresholds/threshold.tscn"
const PLAYER_SCENE_PATH: String = "res://player/player.tscn"

## A generous, arbitrary size for the Threshold's CollisionShape2D under
## test. threshold.tscn ships an "unsized/placeholder" rect (design §4 —
## meant for a designer to resize per placement), so this test gives it a
## real size rather than depending on whatever the placeholder happens to
## default to. Only the LAYER/MASK wiring is under test here, not any
## particular size or position — see test_threshold.gd for the shape-type
## check.
const THRESHOLD_SHAPE_SIZE: Vector2 = Vector2(64.0, 64.0)

## How far apart to start the two nodes before moving them into overlap —
## comfortably outside both the Threshold's and ThresholdBounds's extents so
## there is no overlap yet when watch_signals() is called (see
## tests/integration/world/test_edge_triggers.gd's established note:
## watch_signals() only catches emissions AFTER it's called, so a test that
## starts already-overlapping can miss the very signal it means to check).
const START_OFFSET: Vector2 = Vector2(300.0, 0.0)

const SHARED_POSITION: Vector2 = Vector2(1000.0, 1000.0)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Load, instantiate, size, and add threshold.tscn's root to the tree
## (autofreed). Typed `Area2D`, not `Threshold` — this helper only ever
## touches the root's Area2D surface (global_position, get_node()), so
## `Area2D` is already the most specific type it needs; there is no cast-to-
## null hole the way there would be with `Threshold` (see
## tests/unit/world/thresholds/test_threshold.gd's `_make_threshold_area()`
## for that case, where the cast itself needs an explicit assertion). The
## `is Area2D` check below is sufficient here precisely because this helper
## never reads a Threshold-declared member (`destination`, `arrival`) — it
## treats the node purely as a generic Area2D.
## Returns null, with the failure already recorded, on any load/instantiate/
## shape problem.
func _make_sized_threshold() -> Area2D:
	var packed: PackedScene = load(THRESHOLD_SCENE_PATH) as PackedScene
	assert_not_null(packed,
			"%s must exist and load as a PackedScene." % [THRESHOLD_SCENE_PATH])
	if packed == null:
		return null

	var instance: Node = packed.instantiate()
	assert_true(instance is Area2D,
			"threshold.tscn's root must be an Area2D (found %s)." % [
					instance.get_class() if instance != null else "null"])
	if not (instance is Area2D):
		return null
	var threshold: Area2D = instance as Area2D

	var collision: CollisionShape2D = threshold.get_node_or_null("CollisionShape2D") as CollisionShape2D
	assert_not_null(collision,
			"threshold.tscn must have a CollisionShape2D child to size for this test.")
	if collision == null:
		return null
	assert_true(collision.shape is RectangleShape2D,
			"threshold.tscn's CollisionShape2D.shape must be a RectangleShape2D to size for this test.")
	if not (collision.shape is RectangleShape2D):
		return null
	# Assign a FRESH RectangleShape2D rather than mutating collision.shape in
	# place. load() caches the PackedScene, and PackedScene.instantiate() does
	# not deep-copy [sub_resource]s, so collision.shape here is the very same
	# Resource object threshold.tscn's on-disk template (and every other
	# instance of it) uses. add_child_autofree() only frees this test's NODE at
	# teardown, not that shared Resource — mutating shape.size in place would
	# leak into every later instantiation of threshold.tscn for the rest of the
	# test process. Assigning a brand-new RectangleShape2D directly onto this
	# live node sidesteps that entirely.
	var shape := RectangleShape2D.new()
	shape.size = THRESHOLD_SHAPE_SIZE
	collision.shape = shape

	add_child_autofree(threshold)
	return threshold


## Load, instantiate, and add player.tscn's root to the tree (autofreed),
## returning the player node itself. The real player scene is used (rather
## than a synthetic stand-in) so this test exercises Slice 1's actual
## ThresholdBounds child, not a hand-rolled approximation of it.
func _make_player() -> CharacterBody2D:
	var packed: PackedScene = load(PLAYER_SCENE_PATH) as PackedScene
	assert_not_null(packed, "%s must exist and load as a PackedScene." % [PLAYER_SCENE_PATH])
	if packed == null:
		return null

	var player: CharacterBody2D = packed.instantiate() as CharacterBody2D
	assert_not_null(player, "player.tscn's root must be a CharacterBody2D.")
	if player == null:
		return null

	add_child_autofree(player)
	return player


## The player's ThresholdBounds Area2D child (world-thresholds Slice 1),
## existence- and type-checked. Returns null, with the failure already
## recorded, if it's missing or the wrong type.
func _get_threshold_bounds(player: CharacterBody2D) -> Area2D:
	var node: Node = player.get_node_or_null("ThresholdBounds")
	assert_not_null(node,
			("player.tscn must have a child named 'ThresholdBounds' "
					+ "(world-thresholds design.md §6, Slice 1) for this test to "
					+ "detect."))
	if node == null:
		return null

	assert_true(node is Area2D,
			"player.tscn's ThresholdBounds must be an Area2D (found %s)." % [node.get_class()])
	if not (node is Area2D):
		return null

	return node as Area2D


# ---------------------------------------------------------------------------
# The load-bearing check: do the two masked layers actually see each other?
# ---------------------------------------------------------------------------

func test_threshold_detects_the_players_threshold_bounds_entering_it() -> void:
	var threshold: Area2D = _make_sized_threshold()
	if threshold == null:
		return
	threshold.global_position = SHARED_POSITION

	var player: CharacterBody2D = _make_player()
	if player == null:
		return
	var bounds: Area2D = _get_threshold_bounds(player)
	if bounds == null:
		return

	# Start clear of the threshold so no overlap exists yet when
	# watch_signals() begins observing.
	player.global_position = SHARED_POSITION + START_OFFSET

	# Let the scene settle for a couple of physics frames before watching —
	# Area2D monitoring needs the physics server to have actually stepped
	# (see test_edge_triggers.gd's note: GUT's simulate() does not step
	# PhysicsServer2D, only real frames do).
	await wait_physics_frames(2)
	watch_signals(threshold)

	# Move the player's ThresholdBounds directly onto the Threshold in one
	# step. This test only needs to prove the OVERLAP gets detected — not
	# exercise movement/input, which is unrelated to what the layer/mask
	# bits are being tested for here.
	player.global_position = threshold.global_position
	await wait_physics_frames(3)

	assert_signal_emitted(threshold, "area_entered",
			("Threshold (collision_mask=player_bounds) must emit area_entered "
					+ "when the player's ThresholdBounds (collision_layer="
					+ "player_bounds) overlaps it. This is the one check a per-bit "
					+ "unit test cannot make: "
					+ "two masks can each be individually 'correct' and still "
					+ "fail to see each other if a bit is transposed on either "
					+ "side."))

	# Corroborate via the areas' own monitoring state, not just the signal —
	# a signal watcher and get_overlapping_areas() are two independent
	# Godot subsystems (an emitted-history log vs. live monitoring state), so
	# agreement between them rules out a signal-plumbing fluke masking an
	# actual detection failure (or vice versa).
	# https://docs.godotengine.org/en/stable/classes/class_area2d.html#class-area2d-method-get-overlapping-areas
	assert_true(threshold.get_overlapping_areas().has(bounds),
			("Threshold.get_overlapping_areas() must include the player's "
					+ "ThresholdBounds once they overlap — corroborating the "
					+ "area_entered signal above via Godot's live monitoring "
					+ "state rather than its emission history alone."))
