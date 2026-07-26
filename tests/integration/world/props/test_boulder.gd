## test_boulder.gd
## Integration tests for world/props/boulder.tscn — Slice 6 of the
## world-collision feature ("Boulder: first real prop, proven end-to-end").
##
## These tests are integration-level (not unit) because they exercise the
## real physics server: a bare probe CharacterBody2D is driven at the
## instantiated Boulder via move_and_slide(), the same mechanism the real
## player uses, to prove the design's central claim end-to-end — the
## COLLIDER (generated from `footprint`) blocks movement, while the
## placeholder ellipse's wider VISUAL silhouette (design doc §7.1) does not.
## A bare CharacterBody2D probe is used instead of instancing player.tscn so
## these tests exercise only the Boulder <-> physics-server relationship, not
## player.gd's Input/GameState-gated movement pipeline (that pipeline is
## covered by tests/integration/world/test_solids_collision.gd and the
## world-collision e2e scenarios).
##
## Written test-first, ahead of world/props/boulder.tscn — the scene now
## exists and all tests below pass against it.
##
## Design reference: docs/features/world-collision/design.md §7, §7.1, §8
## Test plan: docs/features/world-collision/slice-6-boulder-test-plan.md
##
## Requires GUT: https://github.com/bitwes/Gut
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gselect=test_boulder.gd -gexit

class_name TestBoulderIntegration
extends GutTest


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const SCENE_PATH: String = "res://world/props/boulder.tscn"
const COLLISION_NODE_NAME: String = "CollisionShape2D"

## Physics layer bit for "world" (project.godot [layer_names] 2d_physics/
## layer_1, design doc §11). Duplicated locally rather than referencing
## WorldProp.WORLD_LAYER_BIT so the expected value is legible in this file
## without cross-referencing the production script — same convention as
## tests/unit/world/props/shared/test_world_prop.gd and
## tests/integration/world/test_solids_collision.gd.
const WORLD_LAYER_BIT: int = 1

## A 1x1 footprint's generated collider (world_prop.gd's _rebuild_collider())
## is a RectangleShape2D of size TILE_SIZE = (32, 16), positioned so it spans
## local y in [-16, 0] (the origin is the footprint's FRONT edge, not its
## centre — design doc §8.1) and local x in [-16, 16]. FOOTPRINT_TOP_LOCAL_Y
## is the near (top) edge of that span — the boundary the "silhouette but not
## footprint" test below must stay on the correct side of.
const FOOTPRINT_TOP_LOCAL_Y: float = -16.0

## Probe body tuning, mirroring test_solids_collision.gd's movement-simulation
## constants and rationale.
const PROBE_SPEED: float = 200.0
const APPROACH_OFFSET_PX: float = 80.0
const SIMULATION_TICKS: int = 60


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Instantiate boulder.tscn and add it to the tree. Autofreed at teardown.
## @return the instantiated Boulder root, or null (with a failed assertion
## already recorded) if the scene can't be loaded/instantiated.
func _make_boulder() -> WorldProp:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	assert_not_null(packed,
			"world/props/boulder.tscn should load as a PackedScene — this is Slice 6's own "
			+ "scene deliverable")
	if packed == null:
		return null

	var instance: WorldProp = packed.instantiate() as WorldProp
	assert_not_null(instance, "boulder.tscn's root should instantiate as a WorldProp")
	if instance == null:
		return null

	add_child_autofree(instance)
	return instance


## Build a bare CharacterBody2D probe with a 20x10 RectangleShape2D collider
## (matching the real player's collider, design doc §10) and a collision_mask
## that detects the "world" layer. Autofreed at teardown.
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


## Find Boulder's placeholder visual child (the one child that isn't the
## CollisionShape2D WorldProp manages). See
## tests/unit/world/props/test_boulder.gd's _find_visual_child() for the
## same lookup at the unit level — duplicated here rather than shared,
## since GUT test files are standalone scripts with no natural place to
## share a helper across unit/ and integration/.
func _find_visual_child(boulder: WorldProp) -> CanvasItem:
	for child in boulder.get_children():
		if child.name == COLLISION_NODE_NAME:
			continue
		if child is CanvasItem:
			return child as CanvasItem
	return null


## Compute a visual node's bounding rect in ITS PARENT's local coordinate
## space (i.e. Boulder-local, since the visual is a direct child of Boulder).
## Supports the two node types design doc §7.1 names as valid placeholders:
## Polygon2D (bounding box of its `polygon` points) and ColorRect (its own
## position/size, being a Control anchored at a local offset). Returns an
## empty Rect2 for anything else — callers must check `rect.size` before
## trusting it.
func _get_local_bounding_rect(visual: CanvasItem) -> Rect2:
	if visual is Polygon2D:
		var poly: PackedVector2Array = (visual as Polygon2D).polygon
		if poly.size() == 0:
			return Rect2()
		var min_pt: Vector2 = poly[0]
		var max_pt: Vector2 = poly[0]
		for point in poly:
			min_pt.x = minf(min_pt.x, point.x)
			min_pt.y = minf(min_pt.y, point.y)
			max_pt.x = maxf(max_pt.x, point.x)
			max_pt.y = maxf(max_pt.y, point.y)
		var local_rect := Rect2(min_pt, max_pt - min_pt)
		local_rect.position += (visual as Polygon2D).position
		return local_rect
	elif visual is ColorRect:
		var color_rect := visual as ColorRect
		return Rect2(color_rect.position, color_rect.size)
	else:
		return Rect2()


## Drive `probe` in a straight line for SIMULATION_TICKS physics ticks and
## return the observed vs. theoretical-unobstructed travel, same contrast
## technique as test_solids_collision.gd's _drive_player_right_toward().
## `traveled_px` is the distance covered ALONG `velocity`'s own direction
## (via vector projection), so this one helper works for both the vertical
## (north-approach) and horizontal (silhouette-crossing) tests below without
## the caller having to pick apart which axis moved.
func _drive_probe(probe: CharacterBody2D, start_global: Vector2, velocity: Vector2) -> Dictionary:
	probe.global_position = start_global
	probe.velocity = velocity

	var physics_delta: float = 1.0 / Engine.physics_ticks_per_second

	# NOTE: this does NOT use GUT's simulate() helper (contrast with
	# test_solids_collision.gd's _drive_player_right_toward()). simulate()
	# only calls _physics_process on an object if
	# obj.has_method("_physics_process") is true — which requires a real
	# script override. player.tscn's Player has one (player.gd calls
	# move_and_slide() from its own _physics_process), so simulate() drives
	# it correctly there. `probe` here is a bare CharacterBody2D.new() with
	# no script (by design — see _make_probe()'s doc comment: it exists to
	# test the Boulder <-> physics-server relationship in isolation, not
	# player.gd's input pipeline), so it has no _physics_process for
	# simulate() to call and move_and_slide() would otherwise never run,
	# leaving the probe motionless for the entire simulated run regardless
	# of collision. Driving move_and_slide() directly, once per tick, is the
	# straight-line equivalent for a body with no script of its own.
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
	var boulder: WorldProp = _make_boulder()
	if boulder == null:
		return

	assert_eq(boulder.collision_layer, WORLD_LAYER_BIT,
			"boulder.tscn's collision_layer must be exactly the 'world' layer (bit %d)"
			% [WORLD_LAYER_BIT])
	assert_eq(boulder.collision_mask, 0,
			(
			"boulder.tscn's collision_mask must be 0 — a static solid collides with nothing "
			+ "itself (design doc §11); this should come from WorldProp's own _ready(), but is "
			+ "asserted here too in case boulder.tscn ever overrides it in the .tscn file "
			+ "itself."
			))


# ---------------------------------------------------------------------------
# Test 2 — a straight-line approach into the 1x1 footprint is blocked
# ---------------------------------------------------------------------------

func test_move_and_slide_into_footprint_is_blocked() -> void:
	var boulder: WorldProp = _make_boulder()
	if boulder == null:
		return

	await wait_physics_frames(2)

	var probe: CharacterBody2D = _make_probe()
	var boulder_origin: Vector2 = boulder.global_position

	# Approach from the north (start well above/screen-up from the anchor)
	# and move straight south (+y), directly into the footprint. The
	# footprint's near edge sits at local y = -16 (TILE_SIZE.y, 1x1
	# footprint) — APPROACH_OFFSET_PX (80px) starts well clear of it so the
	# probe covers real distance before the block, per
	# test_solids_collision.gd's tuning rationale.
	var start: Vector2 = boulder_origin + Vector2(0.0, -APPROACH_OFFSET_PX)
	var result: Dictionary = _drive_probe(probe, start, Vector2(0.0, PROBE_SPEED))

	# Expected stop distance: APPROACH_OFFSET_PX (80px) minus the footprint's
	# near-edge offset from the anchor (16px, FOOTPRINT_TOP_LOCAL_Y magnitude)
	# minus the probe's own half-depth (5px, half of the 10px-tall probe
	# collider) = 59px. Verified empirically against the real physics server
	# (not just hand arithmetic) with a temporary debug assertion: the probe
	# actually travels ~59.0px before move_and_slide() halts it.
	#
	# This is checked with BOTH a lower and an upper bound (rather than only
	# `assert_lt(..., unobstructed_px * 0.5)`, the test's original form) so a
	# future regression to "the probe never moves at all" (travelled_px ~= 0,
	# e.g. from a misplaced/oversized collider that traps the probe at its
	# start position) fails loudly here instead of vacuously satisfying an
	# upper-bound-only check. A generous +/-10px tolerance around the
	# geometric expectation absorbs normal physics-engine slop (contact
	# margins, one tick's worth of overshoot, etc.) without being so wide it
	# would let "probe barely moved" or "probe blew through" slip past.
	assert_between(result.traveled_px as float, 49.0, 69.0,
			(
			"probe should stop ~59px into its approach (APPROACH_OFFSET_PX 80px minus the "
			+ "footprint's 16px near-edge offset minus the probe's 5px half-depth), not travel the "
			+ "full unobstructed distance (travelled %.1fpx of an unobstructed %.1fpx) — a value "
			+ "near 0 here would mean the probe never moved at all (a vacuous pass for the old "
			+ "upper-bound-only assertion), while a value near %.1f would mean the footprint "
			+ "collider isn't blocking it. Check world_prop.gd's _rebuild_collider() and "
			+ "boulder.tscn's footprint/collision layer values."
			) % [result.traveled_px, result.unobstructed_px, result.unobstructed_px])

	# The footprint's near edge is 16px north of the anchor; the probe (5px
	# half-height) should stop at or before that edge, never reaching the
	# anchor's own y (the collider's FAR edge) let alone crossing it.
	var final_y: float = (result.final_position as Vector2).y
	assert_lt(final_y, boulder_origin.y,
			(
			"probe's final y (%.1f) should be north of (less than) the boulder's ground-anchor "
			+ "y (%.1f) — it must stop at the footprint's edge, not advance across it."
			) % [final_y, boulder_origin.y])


# ---------------------------------------------------------------------------
# Test 3 — a straight-line pass that only overlaps the placeholder ellipse's
#          visual silhouette (above the footprint's top edge) is NOT blocked
# ---------------------------------------------------------------------------

func test_move_and_slide_over_visual_silhouette_outside_footprint_is_not_blocked() -> void:
	# This is the test that would catch a collider mistakenly generated from
	# (or matched to) the placeholder's sprite silhouette rather than
	# `footprint` alone (design doc §8.3's explicitly-rejected alternative).
	var boulder: WorldProp = _make_boulder()
	if boulder == null:
		return

	var visual: CanvasItem = _find_visual_child(boulder)
	assert_not_null(visual,
			"boulder.tscn should have a placeholder visual child (Polygon2D or ColorRect, "
			+ "design doc §7.1) to test the silhouette-vs-footprint distinction against")
	if visual == null:
		return

	var local_rect: Rect2 = _get_local_bounding_rect(visual)
	assert_true(local_rect.size.x > 0.0 and local_rect.size.y > 0.0,
			(
			"could not compute a bounding rect for the placeholder visual (a %s) — expected a "
			+ "Polygon2D with a non-empty `polygon` or a ColorRect with a non-zero `size`."
			) % [visual.get_class()])
	if local_rect.size.x <= 0.0 or local_rect.size.y <= 0.0:
		return

	# The visual's silhouette must extend further up-screen (more negative)
	# than FOOTPRINT_TOP_LOCAL_Y for there to be any "silhouette but not
	# footprint" zone to test at all — exactly design doc §7.1's second
	# honesty rule ("give it the real silhouette-vs-footprint shape... a
	# placeholder that is just a footprint-sized box proves nothing").
	assert_true(local_rect.position.y < FOOTPRINT_TOP_LOCAL_Y,
			(
			"the placeholder visual's bounding rect top (local y = %.1f) does not extend above "
			+ "the footprint collider's near edge (local y = %.1f) — the ellipse must be drawn "
			+ "taller than the 1x1 footprint (design doc §7.1) for this test (and the "
			+ "corresponding e2e scenario) to mean anything."
			) % [local_rect.position.y, FOOTPRINT_TOP_LOCAL_Y])
	if local_rect.position.y >= FOOTPRINT_TOP_LOCAL_Y:
		return

	# Pick a y strictly between the silhouette's topmost extent and the
	# footprint's edge — guaranteed to be "inside the ellipse, outside the
	# collider" regardless of exactly how tall the ellipse ends up being.
	var probe_local_y: float = (local_rect.position.y + FOOTPRINT_TOP_LOCAL_Y) / 2.0

	await wait_physics_frames(2)

	var boulder_origin: Vector2 = boulder.global_position
	var probe: CharacterBody2D = _make_probe()

	# Cross the boulder horizontally at probe_local_y, starting well west of
	# the silhouette's leftmost extent and running past its rightmost extent.
	var start_x: float = boulder_origin.x + local_rect.position.x - APPROACH_OFFSET_PX
	var start: Vector2 = Vector2(start_x, boulder_origin.y + probe_local_y)
	var result: Dictionary = _drive_probe(probe, start, Vector2(PROBE_SPEED, 0.0))

	assert_gt(result.traveled_px as float, result.unobstructed_px as float * 0.9,
			(
			"probe should cross close to the unobstructed distance while passing through the "
			+ "placeholder's visual silhouette above the footprint (travelled %.1fpx of an "
			+ "unobstructed %.1fpx) — if this fails, something (likely an oversized or "
			+ "mispositioned collider) is blocking movement outside the 1x1 footprint."
			) % [result.traveled_px, result.unobstructed_px])
