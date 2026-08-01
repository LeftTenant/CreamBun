## test_perimeter_walls.gd
## Integration tests for Slice 9 of the world-collision feature ("Camera dead
## zone, edge lock, and perimeter walls") — the perimeter-wall half of the
## slice. Camera dead-zone/edge-lock behavior lives in the sibling file
## test_camera_dead_zone_and_limits.gd (two distinct concerns, same slice —
## see that file's header for why they're split).
##
## Scope note (design doc §12.4): this slice only covers the "no neighbour ->
## invisible wall" case, since meadow.tscn declares no neighbour_* scenes yet
## (slice 10 adds the open-edge/trigger case once a second area exists to link
## to). So every edge of the meadow is expected to get a wall in this slice.
##
## Written test-first, ahead of the implementation: at the time this suite
## was authored, no perimeter-wall generation existed anywhere (not on
## WorldArea, not in world.gd). Perimeter-wall generation now exists on
## WorldArea.build_perimeter_walls() (world/areas/shared/world_area.gd), and
## every test below passes against it — this file's job now is to guard that
## behavior against regressions as slice 10's open-edge/neighbour work lands.
##
## Design reference: docs/features/world-collision/design.md §12.4 (the
## no-neighbour wall case only).
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

# How far outward/inward from get_bounds_px()'s exact edge line to look for a
# candidate wall's collider. Generous on purpose: this suite deliberately
# does not assume a specific wall thickness or exact placement (flush with
# the edge vs. straddling it vs. just outside it) — only that *something*
# solid exists in the neighbourhood of each edge. 48px is 1.5 tiles, well
# beyond any plausible wall thickness.
const EDGE_BAND_PX: float = 48.0

# Slack allowed when checking that wall coverage has no gap along an edge.
# 1px absorbs floating point noise; an actual "corner gap a player could slip
# through" (the test plan's concern) would be many pixels, not one.
const EDGE_GAP_TOLERANCE_PX: float = 1.0

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

## The north headroom inset the world will actually build with, derived from
## the project's real player scene (WorldArea.north_headroom_inset()).
##
## Instantiated standalone rather than read off a constant: there is no longer
## a constant to read. Kept as a helper on each suite that needs it rather than
## hoisted somewhere shared, matching this project's convention of
## self-contained test files.
func _derive_headroom_inset() -> float:
	var packed: PackedScene = load("res://player/player.tscn")
	if packed == null:
		fail_test("player/player.tscn should load as a PackedScene")
		return 0.0
	var player: CharacterBody2D = packed.instantiate() as CharacterBody2D
	if player == null:
		fail_test("player.tscn's root must be a CharacterBody2D")
		return 0.0
	autofree(player)
	return WorldArea.north_headroom_inset(
			player.get_visual_extent(), player.get_collider_extent())


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


## The detection band for one edge of `bounds` — a strip EDGE_BAND_PX wide
## straddling that edge's line, extended EDGE_BAND_PX past each corner too
## (so a wall segment placed slightly past the corner still counts).
func _edge_band(bounds: Rect2, edge: String) -> Rect2:
	match edge:
		"north":
			return Rect2(
					bounds.position.x - EDGE_BAND_PX, bounds.position.y - EDGE_BAND_PX,
					bounds.size.x + EDGE_BAND_PX * 2.0, EDGE_BAND_PX * 2.0)
		"south":
			return Rect2(
					bounds.position.x - EDGE_BAND_PX, bounds.end.y - EDGE_BAND_PX,
					bounds.size.x + EDGE_BAND_PX * 2.0, EDGE_BAND_PX * 2.0)
		"west":
			return Rect2(
					bounds.position.x - EDGE_BAND_PX, bounds.position.y - EDGE_BAND_PX,
					EDGE_BAND_PX * 2.0, bounds.size.y + EDGE_BAND_PX * 2.0)
		"east":
			return Rect2(
					bounds.end.x - EDGE_BAND_PX, bounds.position.y - EDGE_BAND_PX,
					EDGE_BAND_PX * 2.0, bounds.size.y + EDGE_BAND_PX * 2.0)
		_:
			push_error("_edge_band: unknown edge '%s'" % [edge])
			return Rect2()


## True if `intervals` (an Array of [min, max] float pairs, in any order,
## possibly overlapping) covers [span_min, span_max] with no gap wider than
## EDGE_GAP_TOLERANCE_PX. Used to check a wall (or set of wall segments)
## spans an entire edge with no corner gap a player could slip through.
func _covers_full_span(intervals: Array, span_min: float, span_max: float) -> bool:
	if intervals.is_empty():
		return false

	var sorted_intervals: Array = intervals.duplicate()
	sorted_intervals.sort_custom(func(a, b): return a[0] < b[0])

	var covered_up_to: float = span_min
	for interval in sorted_intervals:
		if interval[0] > covered_up_to + EDGE_GAP_TOLERANCE_PX:
			return false  # a gap between what's covered so far and this segment
		covered_up_to = maxf(covered_up_to, interval[1])

	return covered_up_to >= span_max - EDGE_GAP_TOLERANCE_PX


## Collect [min, max] tangential-axis intervals (x for north/south, y for
## east/west) for every candidate wall whose bounding rect falls in `edge`'s
## detection band and is on the "world" collision layer.
func _matching_intervals_for_edge(candidates: Array[StaticBody2D], bounds: Rect2, edge: String) -> Array:
	var band: Rect2 = _edge_band(bounds, edge)
	var intervals: Array = []
	for body in candidates:
		if body.collision_layer != WORLD_LAYER_BIT:
			continue
		var rect: Variant = _world_bounding_rect(body)
		if rect == null:
			continue
		var wall_rect: Rect2 = rect
		if not wall_rect.intersects(band):
			continue
		if edge == "north" or edge == "south":
			intervals.append([wall_rect.position.x, wall_rect.end.x])
		else:
			intervals.append([wall_rect.position.y, wall_rect.end.y])
	return intervals


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
# Existence: a wall on every edge (design doc §12.4, "no neighbour -> wall")
# ---------------------------------------------------------------------------

func test_perimeter_wall_exists_on_each_edge() -> void:
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

	# UPDATED for Slice 10 (design.md §12.4): meadow.tscn now declares
	# neighbour_east/neighbour_south (wired to world/areas/orchard.tscn), so
	# those two edges correctly get an open-edge Area2D TRIGGER instead of a
	# wall (see test_edge_triggers.gd's
	# test_linked_east/south_edge_gets_an_interactable_area2d_not_a_wall).
	# This test's real invariant was always "an edge with NO declared
	# neighbour gets a wall" — originally every edge qualified because no
	# neighbour_* slot was filled yet (this suite's own header note: "this
	# slice only covers the 'no neighbour -> invisible wall' case, since
	# meadow.tscn declares no neighbour_* scenes yet"). That precondition no
	# longer holds for east/south, so the loop below is restricted to
	# edges whose neighbour_* slot is still empty, rather than a hard-coded
	# four-edge list — preserving the same check for north/west while
	# dropping the now-inapplicable assertion for east/south (covered
	# instead by test_edge_triggers.gd).
	var unlinked_edges: Dictionary = {
		"north": world_area.neighbour_north.is_empty(),
		"east": world_area.neighbour_east.is_empty(),
		"south": world_area.neighbour_south.is_empty(),
		"west": world_area.neighbour_west.is_empty(),
	}
	for edge in unlinked_edges:
		if not unlinked_edges[edge]:
			continue
		var intervals: Array = _matching_intervals_for_edge(candidates, bounds, edge)
		assert_gt(intervals.size(), 0,
				(
				"expected at least one StaticBody2D on the 'world' layer (bit %d) near "
				+ "the %s edge of get_bounds_px() (%s) — none found. meadow.tscn declares "
				+ "no neighbour_%s scene, so design doc §12.4 requires an invisible wall "
				+ "here: 'No neighbour -> an invisible wall. A StaticBody2D on the world "
				+ "layer spanning that edge.'"
				) % [WORLD_LAYER_BIT, edge, bounds, edge])


# ---------------------------------------------------------------------------
# Coverage: no gaps along the middle of an edge (test plan: "covers the full
# length of its edge")
# ---------------------------------------------------------------------------

## Third review round (mutation testing): the ORIGINAL version of this test
## additionally widened each edge's checked span by one wall thickness (plus
## an asymmetric `north_reach` term on the vertical edges) and claimed that
## widening exercised "corner-closing" behavior. It did not. On this closed
## rectangular ring, `_matching_intervals_for_edge()` collects every
## StaticBody2D intersecting an edge's band — not just the wall named for
## that edge — so the west/east walls' full-bounds-height rects always
## supplied exactly the corner coverage the widened north/south ends were
## meant to guard, regardless of whether north/south were actually extended.
## Confirmed by stripping the `± PERIMETER_WALL_THICKNESS_PX` extension from
## both the north and south walls in world_area.gd's build_perimeter_walls()
## and observing every test in this file — including the widened version of
## this one — still pass. The widening was inert, not merely untested, so the
## old test's name and comments overclaimed what it verified.
##
## This rewritten version drops the widening and the `north_reach` term
## entirely and checks only the plain, unwidened span of each edge — "does a
## wall (or set of wall segments) cover this whole edge with no gap wide
## enough for a player to slip through in the MIDDLE of it." A genuine
## corner-closure check now lives in
## test_perimeter_walls_close_all_four_corners() below, which targets the
## specific geometry (the south wall's x-extension) that actually IS
## load-bearing for corner closure — see that test's docstring for why north
## corners and south corners are not symmetric here.
func test_perimeter_walls_cover_full_edge_length_with_no_mid_edge_gaps() -> void:
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

	# UPDATED for Slice 10 (design.md §12.4): "no mid-edge gap" is only a
	# meaningful StaticBody2D-coverage check for edges that are actually
	# walled — meadow.tscn's south/east are now linked (Area2D triggers, not
	# walls), so they no longer have anything for _matching_intervals_for_edge
	# (which only looks at StaticBody2D) to find. Restricted to unlinked
	# edges, same rationale as test_perimeter_wall_exists_on_each_edge()
	# above.
	var unlinked_horizontal: Dictionary = {
		"north": world_area.neighbour_north.is_empty(),
		"south": world_area.neighbour_south.is_empty(),
	}
	for edge in unlinked_horizontal:
		if not unlinked_horizontal[edge]:
			continue
		var intervals: Array = _matching_intervals_for_edge(candidates, bounds, edge)
		assert_true(_covers_full_span(intervals, bounds.position.x, bounds.end.x),
				(
				"the %s perimeter wall(s) must fully cover x in [%.1f, %.1f] with no gap wider "
				+ "than %.1fpx — a gap here is a spot mid-edge a player could slip through."
				) % [edge, bounds.position.x, bounds.end.x, EDGE_GAP_TOLERANCE_PX])

	var unlinked_vertical: Dictionary = {
		"east": world_area.neighbour_east.is_empty(),
		"west": world_area.neighbour_west.is_empty(),
	}
	for edge in unlinked_vertical:
		if not unlinked_vertical[edge]:
			continue
		var intervals: Array = _matching_intervals_for_edge(candidates, bounds, edge)
		assert_true(_covers_full_span(intervals, bounds.position.y, bounds.end.y),
				(
				"the %s perimeter wall(s) must fully cover y in [%.1f, %.1f] with no gap wider "
				+ "than %.1fpx — a gap here is a spot mid-edge a player could slip through."
				) % [edge, bounds.position.y, bounds.end.y, EDGE_GAP_TOLERANCE_PX])


# ---------------------------------------------------------------------------
# Coverage: no corner gaps (a real check — see the mid-edge test above for
# why its old widened-span version could not actually verify this)
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
## than inferring coverage from widened per-edge spans (which the third
## review round showed cannot actually distinguish "corner closed" from
## "corner open" in this ring topology).
##
## The four points are NOT mirror images of each other, because the north
## wall is inset (world_area.gd's NORTH_WALL_HEADROOM_INSET_PX) while south/
## east/west are not:
##
## - NW/NE: y is `bounds.position.y + NORTH_WALL_HEADROOM_INSET_PX + 1` — one
##   px south of the north wall's actual (inset) player-facing surface, not
##   one px south of the true painted edge. With today's constants, the north
##   wall's row happens to start exactly where the west/east walls' full-
##   height columns also start, so this point is ALWAYS covered by the west/
##   east wall alone — it does not, today, depend on the north wall's own
##   x-extension. That is fine: the failure mode this guards against is a
##   future change to west/east's own vertical extent or to the inset
##   constant, not the specific mutation covered by the SW/SE points below.
## - SW/SE: y is `bounds.end.y + 1` — one px south of the true painted south
##   edge (south has no inset). Unlike north, the west/east walls' columns
##   stop exactly AT the true south edge — so this point is covered ONLY
##   because the south wall's own `± PERIMETER_WALL_THICKNESS_PX`
##   x-extension reaches into the west/east columns' x-range. Stripping that
##   extension (the same mutation the third review round applied) leaves
##   this exact point uncovered — re-verified against this rewritten test,
##   which now correctly fails on that mutation (the old widened-span test
##   did not).
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

	var inset: float = _derive_headroom_inset()
	# UPDATED for Slice 10 (design.md §12.4): a corner's "no gap between two
	# walls" concern only applies when BOTH edges meeting there are
	# unlinked (solid StaticBody2D walls). meadow.tscn now links east/south
	# to orchard.tscn, so NE/SW/SE each have at least one open (Area2D
	# trigger, not solid) side — there is no wall-vs-wall gap to close
	# there, since the player is meant to be able to cross through the
	# linked side entirely. Only NW (north+west, both still unlinked)
	# remains a meaningful check for this fixture; the guard below keeps
	# this test generically correct (rather than meadow-specific) by
	# skipping any corner where either adjacent edge has a neighbour set.
	# The corners this narrows away (NE/SW/SE) are NOT left uncovered by this
	# suite overall — tests/integration/world/test_edge_triggers.gd's corner-
	# dead-zone tests (test_player_near_east_edge_corner_does_not_trigger_
	# edge_reached and its south-edge sibling) cover linked-corner containment
	# instead, since a linked corner's "wall" is a stub/trigger/stub split
	# this file's plain-StaticBody2D scan wasn't written to reason about.
	var corners: Dictionary = {
		"NW": [Vector2(bounds.position.x - 1.0, bounds.position.y + inset + 1.0),
				world_area.neighbour_north.is_empty() and world_area.neighbour_west.is_empty()],
		"NE": [Vector2(bounds.end.x + 1.0, bounds.position.y + inset + 1.0),
				world_area.neighbour_north.is_empty() and world_area.neighbour_east.is_empty()],
		"SW": [Vector2(bounds.position.x - 1.0, bounds.end.y + 1.0),
				world_area.neighbour_south.is_empty() and world_area.neighbour_west.is_empty()],
		"SE": [Vector2(bounds.end.x + 1.0, bounds.end.y + 1.0),
				world_area.neighbour_south.is_empty() and world_area.neighbour_east.is_empty()],
	}
	for corner_name in corners:
		var point: Vector2 = corners[corner_name][0]
		var both_edges_unlinked: bool = corners[corner_name][1]
		if not both_edges_unlinked:
			continue
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
	# 100.0 sits comfortably below the ~123.0px this test actually measures
	# (re-verified empirically after adding the north wall's camera-headroom
	# inset above, which shortened this specific edge's travel from the
	# ~155px measured pre-inset, since the wall's player-facing surface now
	# sits NORTH_WALL_HEADROOM_INSET_PX/32px closer to the start point —
	# world_area.gd's build_perimeter_walls()) and comfortably above zero.
	assert_gt(actual_travel, 100.0,
			(
			"player travelled only %.1fpx toward the north edge — expected clearly more than "
			+ "that (a genuinely-moving, wall-stopped player), not a vacuous 'blocked' reading "
			+ "from a player that never moved."
			) % [actual_travel])


func test_player_is_blocked_by_south_perimeter_wall() -> void:
	# UPDATED for Slice 10 (design.md §12.4): meadow.tscn's south edge is now
	# linked (neighbour_south -> orchard.tscn), so it is built as an open
	# Area2D trigger, not a solid StaticBody2D wall — a "blocked by wall"
	# check no longer applies to it (this file's own header scoped it to
	# "the no-neighbour-wall case", a precondition that stopped holding for
	# this edge once slice 10 wired the fixture). The south-edge transition
	# behavior itself (frozen input, correct spawn on the far side, etc.) is
	# covered by tests/integration/world/test_area_transition.gd and
	# test_edge_triggers.gd instead.
	pending("meadow's south edge is now a linked open-edge trigger (design.md §12.4) — " +
			"see test_edge_triggers.gd / test_area_transition.gd for its actual behavior")


func test_player_is_blocked_by_east_perimeter_wall() -> void:
	# UPDATED for Slice 10 (design.md §12.4): meadow.tscn's east edge is now
	# linked (neighbour_east -> orchard.tscn), so it is built as an open
	# Area2D trigger, not a solid StaticBody2D wall — see
	# test_player_is_blocked_by_south_perimeter_wall()'s identical note.
	pending("meadow's east edge is now a linked open-edge trigger (design.md §12.4) — " +
			"see test_edge_triggers.gd / test_area_transition.gd for its actual behavior")


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
