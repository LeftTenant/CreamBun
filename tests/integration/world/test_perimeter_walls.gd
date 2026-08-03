## test_perimeter_walls.gd
## Integration tests for the meadow's perimeter walls — originally Slice 9 of
## the world-collision feature ("Camera dead zone, edge lock, and perimeter
## walls"; camera dead-zone/edge-lock behavior lives in the sibling file
## test_camera_dead_zone_and_limits.gd, two distinct concerns, same slice).
##
## World Thresholds Slice 4 (docs/features/world-thresholds/design.md §7)
## collapsed WorldArea.build_perimeter_walls() to build a full-span wall on
## EVERY edge unconditionally — there is no more linked/unlinked branch, so
## the old "only check edges with no declared neighbour" scoping this file's
## tests used to need is gone along with the neighbour_* exports they read.
## `tests/integration/world/test_area_transition.gd` now separately proves
## full-span wall coverage on ALL four edges of both real areas (including
## the two that carry a placed Threshold) — this file no longer duplicates
## that existence/coverage check. What's left here, and worth keeping in its
## own right:
##   - a genuine 4-corner closure check (point containment at each diagonal,
##     not just per-edge span coverage — a different, complementary
##     assertion test_area_transition.gd doesn't make), and
##   - real collision-RESPONSE checks (does move_and_slide() actually stop
##     the player at the wall, not just "does a collider exist nearby").
## The east/south collision-response checks are gone: those edges now carry a
## placed Threshold (World Thresholds Slice 4's content migration) sitting
## inset from their wall, so a normal approach transitions into orchard
## before ever reaching the wall — "blocked by wall" is no longer observable
## behavior there under normal play. Those two crossings are covered
## end-to-end (approach, transition, landing) by test_area_transition.gd
## instead.
##
## Design reference: docs/features/world-collision/design.md §12.4 (history —
##   the neighbour-slot/linked-edge model those sections describe is
##   superseded); docs/features/world-thresholds/design.md §7 (the collapsed,
##   unconditional wall this file now tests against).
## Test plan: docs/features/world-collision/slice-9-camera-perimeter-test-plan.md
##
## Requires GUT: https://github.com/bitwes/Gut
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gselect=test_perimeter_walls.gd -gexit

class_name TestPerimeterWalls
extends GutTest


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const WORLD_SCENE_PATH: String = "res://world/world.tscn"
const BOULDER_SCENE_PATH: String = "res://world/props/boulder.tscn"
const TREE_SCENE_PATH: String = "res://world/props/tree_oak.tscn"

# "world" physics layer bit value, per project.godot's [layer_names] section
# (2d_physics/layer_1 = "world"). Mirrors the constant of the same name used
# across this suite (test_player_scene.gd, test_solids_collision.gd).
const WORLD_LAYER_BIT: int = 1

# Movement-simulation tuning for the four collision-response tests below.
# 300 physics ticks at the default 60Hz rate (~5s) covers speed(200px/s) *
# 5s = 1000px unobstructed — comfortably more than either dimension of the
# meadow's current bounds (544 x 320px) — so a genuinely missing wall would
# let the player travel far outside get_bounds_px(), not just up to its edge.
const DRIVE_TICKS: int = 300

# How far inside each edge's clear corridor to start the player, so there's
# room to build up speed and produce a clear "blocked early / travelled
# unhindered" contrast (mirrors test_solids_collision.gd's
# APPROACH_OFFSET_PX idea, generalized to four edges here).
const START_MARGIN_PX: float = 48.0

# Clear lanes for the drive tests are no longer hard-coded. They used to be:
# two constants picked by hand to dodge "every obstacle painted or placed in
# meadow.tscn as of this writing", with a comment enumerating the boulder, the
# tree, and the two Solids tiles. That enumeration went stale the moment the
# meadow's Ground layer gained collidable edge tiles (design doc §6.1) — the
# east/west lane at y=300 now runs straight through a painted fence, and the
# test failed for a reason with nothing to do with perimeter walls.
#
# CollisionProbe finds a lane from the area's real collision instead, so these
# tests keep testing walls no matter what a designer paints next.
const CollisionProbe := preload("res://tests/integration/world/shared/collision_probe.gd")


# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

func before_each() -> void:
	# Player movement is gated on GameState.current_state == PLAYING
	# (player.gd). Set explicitly, matching test_solids_collision.gd's
	# convention, so this suite doesn't depend on GameState's default or on
	# whatever an earlier-running test file left it in.
	GameState.change_state(GameState.State.PLAYING)


func after_each() -> void:
	# Defensive belt-and-braces: don't leak a held input action into whatever
	# test runs next if a test errors out before releasing it.
	Input.action_release("move_up")
	Input.action_release("move_down")
	Input.action_release("move_left")
	Input.action_release("move_right")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Instantiate world.tscn and add it to the tree so World._ready() runs.
## Autofreed at teardown. Mirrors the identically-named helper used across
## this suite's other integration test files (see
## test_camera_dead_zone_and_limits.gd's copy for why each file keeps its own).
func _instantiate_world() -> Node:
	var packed: PackedScene = load(WORLD_SCENE_PATH)
	assert_not_null(packed, "world/world.tscn should load as a PackedScene")
	if packed == null:
		return null

	var world: Node = packed.instantiate()
	assert_not_null(world, "world/world.tscn should instantiate without errors")
	if world == null:
		return null

	add_child_autofree(world)
	return world


## ActiveArea's single expected child: the instanced meadow WorldArea. Fails
## (with an assertion already recorded) and returns null if ActiveArea is
## missing or empty.
func _get_instanced_area(world: Node) -> Node:
	var active_area: Node = world.get_node_or_null("ActiveArea")
	assert_not_null(active_area, "world.tscn should have a direct child named 'ActiveArea' (design doc §12.1)")
	if active_area == null:
		return null

	assert_gt(active_area.get_child_count(), 0,
			"ActiveArea should hold the instanced meadow WorldArea, found no children")
	if active_area.get_child_count() == 0:
		return null

	return active_area.get_child(0)


## Recursively collect every StaticBody2D under `node`, EXCLUDING the known
## prop scenes (Boulder, TreeOak — already covered by
## tests/integration/world/props/test_boulder.gd and test_tree_oak.gd) and
## anything nested inside them. What's left after that exclusion is exactly
## the set of "new" StaticBody2D nodes a perimeter-wall implementation would
## have added — there is no third kind of StaticBody2D expected in this
## scene as of this slice.
func _collect_non_prop_static_bodies(node: Node, out: Array[StaticBody2D]) -> void:
	for child in node.get_children():
		if child.scene_file_path == BOULDER_SCENE_PATH or child.scene_file_path == TREE_SCENE_PATH:
			continue
		if child is StaticBody2D:
			out.append(child as StaticBody2D)
		_collect_non_prop_static_bodies(child, out)


## The union, in global (world) coordinates, of every RectangleShape2D found
## on direct CollisionShape2D children of `body`. Returns null (no assertion
## recorded — callers give a more specific message) if `body` has no
## RectangleShape2D collision shape. RectangleShape2D is the only Shape2D
## used anywhere else in this codebase (WorldProp's generated collider,
## the player's collider, world.tscn's TileSet collision polygons are a
## separate mechanism) so it's the only shape this helper needs to handle.
func _world_bounding_rect(body: StaticBody2D) -> Variant:
	var result: Rect2
	var found: bool = false
	for child in body.get_children():
		if not (child is CollisionShape2D):
			continue
		var collision: CollisionShape2D = child as CollisionShape2D
		if collision.shape == null or not (collision.shape is RectangleShape2D):
			continue
		var half: Vector2 = (collision.shape as RectangleShape2D).size / 2.0
		var centre: Vector2 = collision.global_position
		var rect := Rect2(centre - half, half * 2.0)
		if not found:
			result = rect
			found = true
		else:
			result = result.merge(rect)
	if not found:
		return null
	return result


## Hold `action` for `ticks` physics ticks then release it, using the real
## Input singleton so the test exercises player.gd's actual
## Input.get_vector() -> velocity -> move_and_slide() pipeline (same
## convention as test_solids_collision.gd's _drive_player_right_toward()).
func _drive_player(player: CharacterBody2D, action: String, ticks: int) -> void:
	var physics_delta: float = 1.0 / Engine.physics_ticks_per_second
	Input.action_press(action)
	simulate(player, ticks, physics_delta)
	Input.action_release(action)
	player.velocity = Vector2.ZERO


# ---------------------------------------------------------------------------
# Existence and full-edge-span coverage — removed
# ---------------------------------------------------------------------------
#
# test_perimeter_wall_exists_on_each_edge() and
# test_perimeter_walls_cover_full_edge_length_with_no_mid_edge_gaps() used to
# live here, scoped to "only the edges with no declared neighbour" (this
# suite's Slice 9/10 history). World Thresholds Slice 4 made every edge's
# wall unconditional and full-span, so that scoping no longer applies, and
# the resulting all-four-edges check is exactly what
# tests/integration/world/test_area_transition.gd's
# test_meadow_perimeter_walls_exist_on_all_four_edges_including_linked_ones()
# (and its orchard sibling) already assert — keeping a second copy here would
# be pure duplication of the same intervals-cover-the-whole-span check
# against the same real content. Removed rather than un-scoped.


# ---------------------------------------------------------------------------
# Coverage: no corner gaps (a real check distinct from full-span coverage —
# see the removed test above's note)
# ---------------------------------------------------------------------------

## True if some candidate StaticBody2D on the "world" layer has a
## RectangleShape2D collider whose bounding rect contains `point_px`.
## `point_px` is expected in the same space _world_bounding_rect()'s returned
## rects and get_bounds_px()'s returned Rect2 already share elsewhere in this
## file — both are global/world-space today, and coincide with the area's
## own local space only while Ground, the WorldArea root, and ActiveArea all
## sit at (0, 0) (see get_bounds_px()'s docstring in world_area.gd for that
## caveat).
func _some_wall_contains(candidates: Array[StaticBody2D], point_px: Vector2) -> bool:
	for body in candidates:
		if body.collision_layer != WORLD_LAYER_BIT:
			continue
		var rect: Variant = _world_bounding_rect(body)
		if rect == null:
			continue
		if (rect as Rect2).has_point(point_px):
			return true
	return false


## A genuine corner-gap check: for each of the meadow's four corners, checks
## a specific point just past the corner for coverage by SOME wall, rather
## than inferring coverage from per-edge spans (a per-edge span check cannot
## by itself distinguish "corner closed" from "corner open" in this ring
## topology — see world_area.gd's _edge_rect() doc comment for why north/
## south's rects each extend one PERIMETER_WALL_THICKNESS_PX past west/east's
## columns specifically to close these corners).
##
## World Thresholds Slice 4 (design.md §7) made every edge's wall
## unconditional and, with the old north-edge headroom inset gone, fully
## symmetric — so all four corners now get the identical treatment, unlike
## this test's pre-Slice-4 version (which special-cased the north edge's
## inset and skipped any corner touching a then-"linked" edge). Each point
## sits one px diagonally OUTSIDE the true corner, in the region ONLY the
## extending edge (north or south) can reach — west/east's own columns run
## flush with bounds.position.y/end.y and never extend past them — so this
## specifically exercises the north/south extension the corners depend on,
## not west/east's coverage (which the removed full-span-coverage test, now
## living in test_area_transition.gd, already proves independently).
func test_perimeter_walls_close_all_four_corners() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var area: Node = _get_instanced_area(world)
	if area == null:
		return
	if not (area is WorldArea):
		fail_test("the instanced ActiveArea child must be a WorldArea instance to call get_bounds_px() on it — found a %s" % [area.get_class()])
		return
	var world_area: WorldArea = area as WorldArea

	var bounds: Rect2 = world_area.get_bounds_px()
	var candidates: Array[StaticBody2D] = []
	_collect_non_prop_static_bodies(area, candidates)

	var corners: Dictionary = {
		"NW": Vector2(bounds.position.x - 1.0, bounds.position.y - 1.0),
		"NE": Vector2(bounds.end.x + 1.0, bounds.position.y - 1.0),
		"SW": Vector2(bounds.position.x - 1.0, bounds.end.y + 1.0),
		"SE": Vector2(bounds.end.x + 1.0, bounds.end.y + 1.0),
	}
	for corner_name in corners:
		var point: Vector2 = corners[corner_name]
		assert_true(_some_wall_contains(candidates, point),
				(
				"no perimeter wall covers the %s corner's test point %s — a player could slip "
				+ "through here between two walls that were meant to meet at this corner."
				) % [corner_name, point])


# ---------------------------------------------------------------------------
# Collision response: the player is actually blocked, not just "something
# exists nearby" (test plan: "blocked ... on contact ... rather than passing
# through")
# ---------------------------------------------------------------------------

## A player-origin X the player can walk the full height of the map along
## without hitting anything but the perimeter itself. Fails the test (and
## returns NAN) if the meadow has been painted so densely that no such column
## exists — that would make every vertical drive test below meaningless, so it
## must be loud rather than skipped.
func _clear_column_for_vertical_drive(area: WorldArea, player: CharacterBody2D, bounds: Rect2) -> float:
	var collider: Rect2 = CollisionProbe.player_collider_extent(player)
	var column: float = CollisionProbe.find_clear_column(
			area, collider,
			bounds.position.y, bounds.end.y,
			bounds.position.x + START_MARGIN_PX, bounds.end.x - START_MARGIN_PX)
	if is_nan(column):
		fail_test("no obstacle-free column exists across the meadow's full height — a vertical drive test cannot attribute a stop to a perimeter wall without one. Check what was painted onto Ground/Solids.")
	return column


## The horizontal mirror of _clear_column_for_vertical_drive().
func _clear_row_for_horizontal_drive(area: WorldArea, player: CharacterBody2D, bounds: Rect2) -> float:
	var collider: Rect2 = CollisionProbe.player_collider_extent(player)
	var row: float = CollisionProbe.find_clear_row(
			area, collider,
			bounds.position.x, bounds.end.x,
			bounds.position.y + START_MARGIN_PX, bounds.end.y - START_MARGIN_PX)
	if is_nan(row):
		fail_test("no obstacle-free row exists across the meadow's full width — a horizontal drive test cannot attribute a stop to a perimeter wall without one. Check what was painted onto Ground/Solids.")
	return row


func test_player_is_blocked_by_north_perimeter_wall() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var area: Node = _get_instanced_area(world)
	if area == null:
		return
	if not (area is WorldArea):
		fail_test("the instanced ActiveArea child must be a WorldArea instance to call get_bounds_px() on it — found a %s" % [area.get_class()])
		return
	var bounds: Rect2 = (area as WorldArea).get_bounds_px()

	var player: CharacterBody2D = world.find_child("Player", true, false) as CharacterBody2D
	assert_not_null(player, "world.tscn's instantiated tree should contain a CharacterBody2D named 'Player'")
	if player == null:
		return

	# Give freshly-instantiated static bodies (any perimeter walls included) a
	# couple of physics frames to register with the physics server before
	# querying it via move_and_slide() — same convention as
	# test_solids_collision.gd's collision-response tests.
	await wait_physics_frames(2)

	var clear_x: float = _clear_column_for_vertical_drive(area as WorldArea, player, bounds)
	if is_nan(clear_x):
		return

	var start: Vector2 = Vector2(
			clear_x,
			(bounds.position.y + bounds.end.y) / 2.0)
	player.global_position = start
	player.velocity = Vector2.ZERO

	_drive_player(player, "move_up", DRIVE_TICKS)

	var speed: float = player.get("speed")
	var unobstructed_travel: float = speed * DRIVE_TICKS / float(Engine.physics_ticks_per_second)
	var actual_travel: float = start.y - player.global_position.y

	assert_gt(player.global_position.y, bounds.position.y - 1.0,
			(
			"player must not cross north of get_bounds_px()'s top edge (y=%.1f) — found "
			+ "y=%.1f. A missing/incomplete north perimeter wall would let the player walk "
			+ "straight off the map."
			) % [bounds.position.y, player.global_position.y])
	assert_lt(actual_travel, unobstructed_travel * 0.9,
			(
			"player travelled %.1fpx of an unobstructed %.1fpx toward the north edge — it "
			+ "should have been stopped well short of that by a perimeter wall."
			) % [actual_travel, unobstructed_travel])
	# Lower bound: without this, a player that never moved at all (e.g. a
	# broken Input.get_vector() wiring, or move_and_slide() never called)
	# would also satisfy the upper-bound check above — vacuously "blocked".
	# 100.0 sits comfortably below the ~146px this test actually measures
	# (176 - 30: the north wall's player-facing surface sits flush at the true
	# painted edge — World Thresholds Slice 4 removed the camera-headroom
	# inset that used to sit it 32px further in, world_area.gd's
	# build_perimeter_walls()) and comfortably above zero.
	assert_gt(actual_travel, 100.0,
			(
			"player travelled only %.1fpx toward the north edge — expected clearly more than "
			+ "that (a genuinely-moving, wall-stopped player), not a vacuous 'blocked' reading "
			+ "from a player that never moved."
			) % [actual_travel])


# test_player_is_blocked_by_south_perimeter_wall() and
# test_player_is_blocked_by_east_perimeter_wall() used to live here as
# pending() placeholders (Slice 10, when those edges first linked to
# orchard.tscn). Removed rather than left pending indefinitely: World
# Thresholds Slice 4 gave meadow's south/east edges a real placed Threshold,
# sitting inset from their (now unconditional) wall, so a normal approach
# transitions into orchard before ever reaching the wall — "blocked by wall"
# is still true of the underlying geometry (test_perimeter_walls_close_all_
# four_corners() above and test_area_transition.gd's full-span coverage
# tests both prove the wall itself exists), but is no longer observable
# collision-RESPONSE behavior on those two edges under normal play. The
# actual approach-transition-landing behavior for both is covered end-to-end
# by test_area_transition.gd's four real-crossing tests.


func test_player_is_blocked_by_west_perimeter_wall() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var area: Node = _get_instanced_area(world)
	if area == null:
		return
	if not (area is WorldArea):
		fail_test("the instanced ActiveArea child must be a WorldArea instance to call get_bounds_px() on it — found a %s" % [area.get_class()])
		return
	var bounds: Rect2 = (area as WorldArea).get_bounds_px()

	var player: CharacterBody2D = world.find_child("Player", true, false) as CharacterBody2D
	assert_not_null(player, "world.tscn's instantiated tree should contain a CharacterBody2D named 'Player'")
	if player == null:
		return

	await wait_physics_frames(2)

	var clear_y: float = _clear_row_for_horizontal_drive(area as WorldArea, player, bounds)
	if is_nan(clear_y):
		return

	var start: Vector2 = Vector2(
			bounds.end.x - START_MARGIN_PX,
			clear_y)
	player.global_position = start
	player.velocity = Vector2.ZERO

	_drive_player(player, "move_left", DRIVE_TICKS)

	var speed: float = player.get("speed")
	var unobstructed_travel: float = speed * DRIVE_TICKS / float(Engine.physics_ticks_per_second)
	var actual_travel: float = start.x - player.global_position.x

	assert_gt(player.global_position.x, bounds.position.x - 1.0,
			(
			"player must not cross west of get_bounds_px()'s left edge (x=%.1f) — found "
			+ "x=%.1f. A missing/incomplete west perimeter wall would let the player walk "
			+ "straight off the map."
			) % [bounds.position.x, player.global_position.x])
	assert_lt(actual_travel, unobstructed_travel * 0.9,
			(
			"player travelled %.1fpx of an unobstructed %.1fpx toward the west edge — it "
			+ "should have been stopped well short of that by a perimeter wall."
			) % [actual_travel, unobstructed_travel])
	# Lower bound — see test_player_is_blocked_by_north_perimeter_wall()'s
	# identical assertion for why this matters. 400.0 sits comfortably below
	# the ~486px measured for this edge and comfortably above zero.
	assert_gt(actual_travel, 400.0,
			(
			"player travelled only %.1fpx toward the west edge — expected clearly more than "
			+ "that (a genuinely-moving, wall-stopped player), not a vacuous 'blocked' reading "
			+ "from a player that never moved."
			) % [actual_travel])
