## test_tree_oak.gd
## Integration tests for world/props/tree_oak.tscn — Slice 7 of the
## world-collision feature ("Tree: footprint ≠ silhouette").
##
## This is THE slice where design doc §8.3 ("Why not auto-generate colliders
## from sprite alpha?") gets proven end-to-end: a wide canopy is drawn well
## above a one-tile trunk, and the collider must track ONLY the trunk's
## footprint. These tests drive a bare CharacterBody2D probe at the
## instantiated TreeOak via move_and_slide() (the same mechanism the real
## player uses) to prove two things numerically: the trunk's footprint blocks
## movement, and the canopy's wider visual silhouette does not block movement
## AT ALL — not merely "less blocked than the trunk". A bare probe is used
## instead of instancing player.tscn so these tests exercise only the TreeOak
## <-> physics-server relationship, not player.gd's Input/GameState-gated
## movement pipeline (mirrors
## tests/integration/world/props/test_boulder.gd's rationale).
##
## IMPORTANT — GUT's simulate() does not drive a scriptless probe:
## GUT's simulate(obj, ticks, delta) only calls _physics_process on `obj` if
## obj.has_method("_physics_process") is true, which requires a real script
## override. The bare CharacterBody2D.new() probe built by _make_probe() has
## no script, so simulate() would silently never move it (a "blocked"
## assertion would then pass vacuously — the probe never moved at all,
## regardless of collision). _drive_probe() below instead calls
## probe.move_and_slide() directly in a manual per-tick loop. See
## .claude/agent-memory/godot-coder/reference_gut_simulate_needs_scripted_physics_process.md.
##
## IMPORTANT — every "blocked" assertion has BOTH an upper and lower bound:
## an upper-bound-only check ("travelled less than X") is satisfied by a
## probe that never moved at all, which is exactly the silent failure mode
## above. See
## .claude/agent-memory/code-reviewer/gotcha_vacuous_blocked_movement_assertions.md.
## The canopy test goes further still: it doesn't just check "less blocked"
## — it asserts the probe travels within a tight tolerance of the FULL
## unobstructed distance, which is the only way to prove the canopy exerts NO
## collision at all (the exact case design doc §8.3 rejects: a collider
## mistakenly generated from sprite alpha instead of footprint).
##
## Exercises world/props/tree_oak.tscn (this slice's own implementation
## deliverable), which uses the node structure documented in
## tests/unit/world/props/test_tree_oak.gd's class doc comment.
##
## Design reference: docs/features/world-collision/design.md §7, §7.1, §8,
## §8.3
## Test plan: docs/features/world-collision/slice-7-tree-test-plan.md
##
## Requires GUT: https://github.com/bitwes/Gut
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gselect=test_tree_oak.gd -gexit

class_name TestTreeOakIntegration
extends GutTest


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const SCENE_PATH: String = "res://world/props/tree_oak.tscn"
const CANOPY_NODE_NAME: String = "Canopy"

## Physics layer bit for "world" (project.godot [layer_names] 2d_physics/
## layer_1, design doc §11). Duplicated locally per this repo's convention
## (see tests/integration/world/props/test_boulder.gd) rather than
## referencing WorldProp.WORLD_LAYER_BIT, so the expected value is legible
## here without cross-referencing the production script.
const WORLD_LAYER_BIT: int = 1

## A 1x1 footprint's generated collider (world_prop.gd's _rebuild_collider())
## is a RectangleShape2D of size TILE_SIZE = (32, 16), positioned so it spans
## local y in [-16, 0] (the origin is the footprint's FRONT edge, not its
## centre — design doc §8.1) and local x in [-16, 16]. FOOTPRINT_TOP_LOCAL_Y
## is the near (top) edge of that span — identical to boulder's, since both
## are 1x1 footprints (design doc §8.2's oak example).
const FOOTPRINT_TOP_LOCAL_Y: float = -16.0

## Probe body tuning, mirroring test_boulder.gd's and
## test_solids_collision.gd's movement-simulation constants and rationale.
const PROBE_SPEED: float = 200.0
const APPROACH_OFFSET_PX: float = 80.0
const SIMULATION_TICKS: int = 60


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Instantiate tree_oak.tscn and add it to the tree. Autofreed at teardown.
## @return the instantiated TreeOak root, or null (with a failed assertion
## already recorded) if the scene can't be loaded/instantiated.
func _make_tree() -> WorldProp:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	assert_not_null(packed,
			"world/props/tree_oak.tscn should load as a PackedScene — this is Slice 7's own "
			+ "scene deliverable")
	if packed == null:
		return null

	var instance: WorldProp = packed.instantiate() as WorldProp
	assert_not_null(instance, "tree_oak.tscn's root should instantiate as a WorldProp")
	if instance == null:
		return null

	add_child_autofree(instance)
	return instance


## Build a bare CharacterBody2D probe with a 20x10 RectangleShape2D collider
## (matching the real player's collider, design doc §10) and a collision_mask
## that detects the "world" layer. Autofreed at teardown. Identical to
## test_boulder.gd's _make_probe().
func _make_probe() -> CharacterBody2D:
	var body := CharacterBody2D.new()
	body.collision_layer = 0
	body.collision_mask = WORLD_LAYER_BIT

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(20, 10)
	shape.shape = rect
	body.add_child(shape)

	add_child_autofree(body)
	return body


## Fetch the Canopy child, failing with a descriptive message if missing or
## the wrong type.
func _get_canopy(tree: WorldProp) -> Polygon2D:
	var node: Node = tree.get_node_or_null(CANOPY_NODE_NAME)
	assert_not_null(node,
			(
			"tree_oak.tscn should have a child named '%s' (see "
			+ "tests/unit/world/props/test_tree_oak.gd's NODE STRUCTURE doc comment)"
			) % [CANOPY_NODE_NAME])
	if node == null:
		return null

	var polygon: Polygon2D = node as Polygon2D
	assert_not_null(polygon,
			"'%s' should be a Polygon2D (design doc §7.1's placeholder-shape convention)"
			% [CANOPY_NODE_NAME])
	return polygon


## Compute a Polygon2D's bounding rect in ITS PARENT's local coordinate space
## (i.e. TreeOak-local). Mirrors
## tests/unit/world/props/test_tree_oak.gd's _get_local_bounding_rect() and
## test_boulder.gd's _get_local_bounding_rect() — duplicated per GUT test
## files being standalone scripts with no natural place to share a helper.
func _get_local_bounding_rect(polygon: Polygon2D) -> Rect2:
	var points: PackedVector2Array = polygon.polygon
	if points.size() == 0:
		return Rect2()

	var min_pt: Vector2 = points[0]
	var max_pt: Vector2 = points[0]
	for point in points:
		min_pt.x = minf(min_pt.x, point.x)
		min_pt.y = minf(min_pt.y, point.y)
		max_pt.x = maxf(max_pt.x, point.x)
		max_pt.y = maxf(max_pt.y, point.y)

	var rect := Rect2(min_pt, max_pt - min_pt)
	rect.position += polygon.position
	return rect


## Drive `probe` in a straight line for SIMULATION_TICKS physics ticks and
## return the observed vs. theoretical-unobstructed travel. `traveled_px` is
## the distance covered ALONG `velocity`'s own direction (via vector
## projection), so this one helper works for both the vertical (trunk
## north-approach) and horizontal (canopy-crossing) tests below. Identical
## technique to test_boulder.gd's _drive_probe() — see that file's extensive
## comment for why this does NOT use GUT's simulate().
func _drive_probe(probe: CharacterBody2D, start_global: Vector2, velocity: Vector2) -> Dictionary:
	probe.global_position = start_global
	probe.velocity = velocity

	var physics_delta: float = 1.0 / Engine.physics_ticks_per_second

	for _tick in range(SIMULATION_TICKS):
		probe.velocity = velocity
		probe.move_and_slide()

	var direction: Vector2 = velocity.normalized()
	var displacement: Vector2 = probe.global_position - start_global

	return {
		"final_position": probe.global_position,
		"traveled_px": displacement.dot(direction),
		"unobstructed_px": velocity.length() * SIMULATION_TICKS * physics_delta,
	}


# ---------------------------------------------------------------------------
# Test 1 — collision layer/mask match the WorldProp "world" static-solid
#          convention (design §11), on the CONCRETE scene, not just the base
#          class (already covered generically by test_world_prop.gd)
# ---------------------------------------------------------------------------

func test_collision_layer_is_world_and_mask_is_empty() -> void:
	var tree: WorldProp = _make_tree()
	if tree == null:
		return

	assert_eq(tree.collision_layer, WORLD_LAYER_BIT,
			"tree_oak.tscn's collision_layer must be exactly the 'world' layer (bit %d)"
			% [WORLD_LAYER_BIT])
	assert_eq(tree.collision_mask, 0,
			(
			"tree_oak.tscn's collision_mask must be 0 — a static solid collides with nothing "
			+ "itself (design doc §11); this should come from WorldProp's own _ready(), but is "
			+ "asserted here too in case tree_oak.tscn ever overrides it in the .tscn file "
			+ "itself."
			))


# ---------------------------------------------------------------------------
# Test 2 — a straight-line approach into the trunk's 1x1 footprint is blocked
# ---------------------------------------------------------------------------

func test_move_and_slide_into_trunk_footprint_is_blocked() -> void:
	var tree: WorldProp = _make_tree()
	if tree == null:
		return

	await wait_physics_frames(2)

	var probe: CharacterBody2D = _make_probe()
	var tree_origin: Vector2 = tree.global_position

	# Approach from the north and move straight south (+y), directly into the
	# footprint — identical geometry to test_boulder.gd's equivalent test,
	# since both are 1x1 footprints (design doc §8.2).
	var start: Vector2 = tree_origin + Vector2(0.0, -APPROACH_OFFSET_PX)
	var result: Dictionary = _drive_probe(probe, start, Vector2(0.0, PROBE_SPEED))

	# Expected stop distance: APPROACH_OFFSET_PX (80px) minus the footprint's
	# near-edge offset from the anchor (16px) minus the probe's own
	# half-depth (5px) = 59px. Same arithmetic as test_boulder.gd's equivalent
	# test (the two footprints and probe are geometrically identical).
	#
	# BOTH a lower and an upper bound (assert_between), not just an upper
	# bound — a probe that never moves at all (e.g. from a misplaced/oversized
	# collider that traps it at its start position) would otherwise satisfy
	# an upper-bound-only check vacuously. See
	# .claude/agent-memory/code-reviewer/gotcha_vacuous_blocked_movement_assertions.md.
	assert_between(result.traveled_px as float, 49.0, 69.0,
			(
			"probe should stop ~59px into its approach (APPROACH_OFFSET_PX 80px minus the "
			+ "footprint's 16px near-edge offset minus the probe's 5px half-depth), not travel "
			+ "the full unobstructed distance (travelled %.1fpx of an unobstructed %.1fpx) — a "
			+ "value near 0 here would mean the probe never moved at all (a vacuous pass for an "
			+ "upper-bound-only assertion), while a value near %.1f would mean the trunk's "
			+ "footprint collider isn't blocking it. Check world_prop.gd's _rebuild_collider() "
			+ "and tree_oak.tscn's footprint/collision layer values."
			) % [result.traveled_px, result.unobstructed_px, result.unobstructed_px])

	# The footprint's near edge is 16px north of the anchor; the probe (5px
	# half-height) should stop at or before that edge, never reaching the
	# anchor's own y (the collider's FAR edge) let alone crossing it.
	var final_y: float = (result.final_position as Vector2).y
	assert_lt(final_y, tree_origin.y,
			(
			"probe's final y (%.1f) should be north of (less than) the tree's ground-anchor y "
			+ "(%.1f) — it must stop at the trunk's footprint edge, not advance across it."
			) % [final_y, tree_origin.y])


# ---------------------------------------------------------------------------
# Test 3 — a straight-line pass through the canopy's visual silhouette
#          (entirely above the trunk's footprint) is NOT blocked AT ALL —
#          the probe must travel the FULL unobstructed distance, proving the
#          canopy exerts NO collision (not merely "less blocked than the
#          trunk"). This is the test that would catch a collider mistakenly
#          generated from sprite alpha instead of footprint (design §8.3).
# ---------------------------------------------------------------------------

func test_move_and_slide_over_canopy_silhouette_is_not_blocked_at_all() -> void:
	var tree: WorldProp = _make_tree()
	if tree == null:
		return

	var canopy: Polygon2D = _get_canopy(tree)
	if canopy == null:
		return

	var local_rect: Rect2 = _get_local_bounding_rect(canopy)
	assert_true(local_rect.size.x > 0.0 and local_rect.size.y > 0.0,
			(
			"could not compute a bounding rect for the Canopy polygon — expected a non-empty "
			+ "`polygon` array."
			))
	if local_rect.size.x <= 0.0 or local_rect.size.y <= 0.0:
		return

	# The canopy must extend further up-screen (more negative) than
	# FOOTPRINT_TOP_LOCAL_Y for there to be any "silhouette but not footprint"
	# zone to test at all — design doc §7.1's honesty rule, and the same
	# structural check test_boulder.gd's equivalent test makes before probing.
	assert_true(local_rect.position.y < FOOTPRINT_TOP_LOCAL_Y,
			(
			"the canopy's bounding rect top (local y = %.1f) does not extend above the "
			+ "footprint collider's near edge (local y = %.1f) — the canopy must be drawn "
			+ "taller than the 1x1 footprint (design doc §7.1, §8.2) for this test (and the "
			+ "corresponding e2e scenario) to mean anything."
			) % [local_rect.position.y, FOOTPRINT_TOP_LOCAL_Y])
	if local_rect.position.y >= FOOTPRINT_TOP_LOCAL_Y:
		return

	# Pick a y strictly between the canopy's topmost extent and the
	# footprint's edge — guaranteed to be "inside the canopy, outside the
	# collider" regardless of exactly how tall the canopy ends up being.
	var probe_local_y: float = (local_rect.position.y + FOOTPRINT_TOP_LOCAL_Y) / 2.0

	await wait_physics_frames(2)

	var tree_origin: Vector2 = tree.global_position
	var probe: CharacterBody2D = _make_probe()

	# Cross the tree horizontally at probe_local_y, starting well west of the
	# canopy's leftmost extent and running past its rightmost extent — never
	# once entering the trunk's footprint band (y ∈ [-16, 0]).
	var start_x: float = tree_origin.x + local_rect.position.x - APPROACH_OFFSET_PX
	var start: Vector2 = Vector2(start_x, tree_origin.y + probe_local_y)
	var result: Dictionary = _drive_probe(probe, start, Vector2(PROBE_SPEED, 0.0))

	# The strong claim this slice exists to prove: the probe travels the FULL
	# unobstructed distance, within a tight tolerance — not merely "most of
	# it". A one-sided `assert_gt(traveled, unobstructed * 0.9)` (as used for
	# boulder's silhouette check) would still pass if the canopy clipped a
	# few pixels off the probe's travel; this test's whole point is that the
	# canopy contributes ZERO collision, so the bound must be tight on BOTH
	# sides of the theoretical maximum, not just a lower threshold.
	assert_almost_eq(result.traveled_px as float, result.unobstructed_px as float, 2.0,
			(
			"probe should travel the FULL unobstructed distance while passing through the "
			+ "canopy's visual silhouette above the footprint (travelled %.1fpx of an "
			+ "unobstructed %.1fpx) — ANY shortfall here means something (almost certainly an "
			+ "oversized or mispositioned collider tracking the canopy's silhouette rather than "
			+ "`footprint`, exactly the mistake design doc §8.3 rejects) is blocking movement "
			+ "outside the 1x1 trunk footprint."
			) % [result.traveled_px, result.unobstructed_px])
