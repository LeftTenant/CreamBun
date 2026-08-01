## test_edge_triggers.gd
## Integration tests for Slice 10 of the world-collision feature ("Edge
## transition (fade) and a second area") — the STATIC/GEOMETRIC half of the
## slice: the Edge enum/signal contract, the per-edge trigger-vs-wall
## branching in the perimeter build step, the reciprocal neighbour wiring
## between meadow.tscn and the new second-area fixture (world/areas/orchard.tscn),
## and the corner-dead-zone exclusion on a linked edge's trigger geometry.
##
## The full freeze/fade/swap/spawn SEQUENCE (GameState transitions, the
## Transition overlay, area free/instance/reparent, camera-limit rebuild,
## the opposite-edge spawn placement, the arrival debounce, and
## GameEvents.area_changed) lives in the sibling file test_area_transition.gd
## — that is a distinct concern from "does the right kind of collider exist
## on the right edge," matching this suite's established convention of
## splitting a slice's integration coverage by concern (see
## test_perimeter_walls.gd vs test_camera_dead_zone_and_limits.gd, Slice 9).
##
## IMPLEMENTED — this suite now runs against a real implementation.
## =========================================================================
## WorldArea declares the Edge enum and edge_reached signal, and
## build_perimeter_walls() branches per edge on whether neighbour_* is set:
## an unlinked edge still gets a single full-span StaticBody2D wall (slice 9
## behavior, unchanged); a linked edge gets a THREE-PIECE split instead of one
## full-span trigger — a small StaticBody2D stub over each of the two 32x32px
## corner squares, with an Area2D trigger on the interactable layer over the
## active stretch in between (see world_area.gd's build_perimeter_walls() and
## _linked_edge_rects() doc comments). This corrected an earlier version that
## built one full-span Area2D and suppressed corner crossings only in the
## body_entered handler — that left the corner squares physically open (the
## player could walk straight through them and off the map) and meant a
## crossing suppressed near a corner never re-fired if the player then walked
## into the active stretch without leaving the trigger. The stub/trigger/stub
## split fixes both: the corners are genuinely solid, and entering the
## trigger piece specifically is what fires the signal. meadow.tscn's
## neighbour_east/neighbour_south are wired to world/areas/orchard.tscn (and
## orchard.tscn's neighbour_west/neighbour_north wired back), per
## slice-10-edge-transition-test-plan.md.
##
## Design reference: docs/features/world-collision/design.md §12.2 (neighbour
## slots), §12.4 (open edges vs. walls, corner dead zones).
## Test plan: docs/features/world-collision/slice-10-edge-transition-test-plan.md
##
## Requires GUT: https://github.com/bitwes/Gut
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gselect=test_edge_triggers.gd -gexit

class_name TestEdgeTriggers
extends GutTest


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const WORLD_SCENE_PATH: String = "res://world/world.tscn"
const MEADOW_SCENE_PATH: String = "res://world/areas/meadow.tscn"
const ORCHARD_SCENE_PATH: String = "res://world/areas/orchard.tscn"

## "world"/"interactable" physics layer bit values, project.godot's
## [layer_names] section (2d_physics/layer_1="world", layer_3="interactable").
## Mirrors WORLD_LAYER_BIT's convention already used across this suite
## (test_perimeter_walls.gd, test_solids_collision.gd).
const WORLD_LAYER_BIT: int = 1
const INTERACTABLE_LAYER_BIT: int = 4
## "player" physics layer bit — an interactable Area2D's collision_mask must
## include this to detect the player's CharacterBody2D (design.md §11's
## layer table: "Interaction Area2Ds | interactable | player").
const PLAYER_LAYER_BIT: int = 2

const PERIMETER_WALL_THICKNESS_PX: float = 32.0

## Corner exclusion (design.md §12.4) — mirrored here rather than read off
## WorldArea.CORNER_DEAD_ZONE_PX, matching this suite's own convention of not
## letting a wrong constant in the implementation also validate its own test.
const CORNER_DEAD_ZONE_PX: float = 32.0

## How far south of the true painted north edge the north wall/trigger's
## player-facing surface sits (design.md §12.4's camera-headroom fix) —
## mirrored from WorldArea.NORTH_WALL_HEADROOM_INSET_PX per this suite's own
## "mirror the constant, don't read it" convention above. A vertical (east/
## west) edge's corner dead zone at its NORTH end is measured from this
## playable-facing boundary, not the raw bounds.position.y — see
## _linked_edge_rects()'s doc comment in world_area.gd for why (round 2 of
## code review on this slice found the un-inset version left the NE/NW
## corners with zero px of actual exclusion).
##
## Derived, not mirrored: the inset is now a function of the player's real
## geometry (WorldArea.north_headroom_inset()), so a test that hard-coded it
## would fail with a confusing "expected 48 got 64" the moment the art changed,
## instead of pointing at the collider that moved. These tests check that the
## SYSTEM is self-consistent; whether the derivation itself is right is checked
## against the live player scene by test_collision_geometry_invariants.gd.
var NORTH_WALL_HEADROOM_INSET_PX: float = 0.0

const CollisionProbe := preload("res://tests/integration/world/shared/collision_probe.gd")

## Minimum viewport size an area must cover, design.md §12.3's "at least one
## viewport in each dimension" floor — restated here rather than referenced
## from a constant, so a wrong constant elsewhere can't also validate this
## check.
const MIN_AREA_WIDTH_PX: float = 320.0
const MIN_AREA_HEIGHT_PX: float = 180.0
const MIN_AREA_WIDTH_TILES: int = 10
const MIN_AREA_HEIGHT_TILES: int = 11
const TILE_SIZE: Vector2i = Vector2i(32, 16)

const DRIVE_TICKS: int = 300


# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

func before_each() -> void:
	GameState.change_state(GameState.State.PLAYING)
	NORTH_WALL_HEADROOM_INSET_PX = _derive_headroom_inset()


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



func after_each() -> void:
	Input.action_release("move_up")
	Input.action_release("move_down")
	Input.action_release("move_left")
	Input.action_release("move_right")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Instantiate world.tscn and add it to the tree so World._ready() runs.
## Autofreed at teardown. Mirrors the identically-named helper used across
## this suite's other integration test files.
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


## ActiveArea's single expected child: the instanced meadow WorldArea.
func _get_instanced_area(world: Node) -> WorldArea:
	var active_area: Node = world.get_node_or_null("ActiveArea")
	assert_not_null(active_area, "world.tscn should have a direct child named 'ActiveArea'")
	if active_area == null:
		return null

	assert_gt(active_area.get_child_count(), 0,
			"ActiveArea should hold the instanced meadow WorldArea, found no children")
	if active_area.get_child_count() == 0:
		return null

	var area: Node = active_area.get_child(0)
	if not (area is WorldArea):
		fail_test("the instanced ActiveArea child must be a WorldArea instance — found a %s" % [area.get_class()])
		return null
	return area as WorldArea


## Recursively collect every node of type T under `node`.
func _collect_nodes_of_type(node: Node, type_check: Callable, out: Array) -> void:
	for child in node.get_children():
		if type_check.call(child):
			out.append(child)
		_collect_nodes_of_type(child, type_check, out)


## The union, in global (world) coordinates, of every RectangleShape2D found
## on direct CollisionShape2D children of `collision_object` (works for both
## StaticBody2D and Area2D — both are CollisionObject2D). Returns null if
## none found. Mirrors test_perimeter_walls.gd's _world_bounding_rect().
func _world_bounding_rect(collision_object: CollisionObject2D) -> Variant:
	var result: Rect2
	var found: bool = false
	for child in collision_object.get_children():
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


func _rects_almost_equal(a: Rect2, b: Rect2, tolerance: float = 1.0) -> bool:
	return (a.position - b.position).length() <= tolerance and (a.size - b.size).length() <= tolerance


## Hold `action` for up to `max_ticks` REAL physics frames (not GUT's
## simulate(), which only manually calls _physics_process without stepping
## the actual PhysicsServer2D) — releasing EARLY, the instant GameState
## leaves PLAYING, rather than always holding the full duration. This suite
## needs real frames — unlike test_perimeter_walls.gd's StaticBody2D checks
## (which work fine under simulate() because move_and_slide() queries the
## physics server synchronously), Area2D.body_entered is only emitted once
## the physics server has actually stepped and processed area monitoring,
## which requires real frames to elapse.
## https://docs.godotengine.org/en/stable/classes/class_area2d.html#class-area2d-signal-body-entered
##
## `max_ticks` is an upper-bound safety net for edges that should never
## transition at all (a corner dead zone, an unlinked wall) — GameState then
## never leaves PLAYING, so the loop runs the whole way, unchanged from
## before. It stopped being a fixed hold length for edges that DO transition:
## holding the full 300 ticks (~5s) left the player still walking for ~4.4s
## after world.gd's freeze/fade/swap/spawn/reveal sequence (design.md
## §12.5, a ~0.6s round trip) had already freed the old WorldArea via
## queue_free() — so this suite's own watch_signals(area)/
## assert_signal_emit_count(area, ...) calls, made after the hold, were
## querying a freed object ("Object <Freed Object> does not have the signal
## [edge_reached]"). Releasing input as soon as the crossing is detected
## (GameState.current_state leaving PLAYING is set synchronously in
## world.gd's _on_edge_reached(), the same frame edge_reached fires) removes
## that race without slowing down the real transition to accommodate a test
## artifact.
func _drive_player(player: CharacterBody2D, action: String, max_ticks: int) -> void:
	Input.action_press(action)
	var waited: int = 0
	while waited < max_ticks and GameState.current_state == GameState.State.PLAYING:
		await wait_physics_frames(1)
		waited += 1
	Input.action_release(action)
	player.velocity = Vector2.ZERO


# ---------------------------------------------------------------------------
# Edge enum + edge_reached signal contract (design.md §12.4)
# ---------------------------------------------------------------------------

func test_world_area_exposes_edge_enum_with_four_directions() -> void:
	# A distinctness check as well as an existence check: if any two of the
	# four ever collapsed onto the same underlying int (e.g. a copy-paste
	# mistake), opposite_edge()/is_debounce_armed() would misbehave silently.
	var values: Array = [
		WorldArea.Edge.NORTH, WorldArea.Edge.EAST,
		WorldArea.Edge.SOUTH, WorldArea.Edge.WEST,
	]
	var unique_values: Dictionary = {}
	for v in values:
		unique_values[v] = true
	assert_eq(unique_values.size(), 4,
			"WorldArea.Edge must have four DISTINCT values (NORTH/EAST/SOUTH/WEST) — found only %d unique values among %s" % [unique_values.size(), values])


func test_world_area_has_edge_reached_signal() -> void:
	var area: WorldArea = _load_bare_meadow_area()
	if area == null:
		return
	add_child_autofree(area)

	assert_true(area.has_signal("edge_reached"),
			"WorldArea must declare a signal named 'edge_reached' (design.md §12.4)")


## Load a bare (not-under-world.tscn) meadow.tscn instance — used by tests
## that only need to probe the class contract (e.g. has_signal()) without
## the full World._ready() machinery.
func _load_bare_meadow_area() -> WorldArea:
	var packed: PackedScene = load(MEADOW_SCENE_PATH)
	assert_not_null(packed, "world/areas/meadow.tscn should load as a PackedScene")
	if packed == null:
		return null
	var area: WorldArea = packed.instantiate() as WorldArea
	assert_not_null(area, "meadow.tscn's root must be a WorldArea")
	return area


# ---------------------------------------------------------------------------
# Per-edge branching: linked edge -> Area2D trigger, unlinked edge -> wall
# ---------------------------------------------------------------------------

## Asserts that some Area2D on the interactable layer occupies `expected_rect`
## somewhere under `area`. Shared by the east/south linked-edge tests below.
func _assert_has_matching_trigger(area: WorldArea, expected_rect: Rect2, edge_name: String) -> void:
	var areas: Array = []
	_collect_nodes_of_type(area, func(n): return n is Area2D, areas)

	var found: bool = false
	for candidate in areas:
		var body: Area2D = candidate as Area2D
		if body.collision_layer != INTERACTABLE_LAYER_BIT:
			continue
		var rect: Variant = _world_bounding_rect(body)
		if rect == null:
			continue
		if _rects_almost_equal(rect as Rect2, expected_rect):
			found = true
			break

	assert_true(found,
			(
			"meadow's linked %s edge should build an Area2D on the interactable layer (bit %d) "
			+ "occupying its active (non-corner) stretch at %s — design.md §12.4's 'a neighbour -> "
			+ "an open edge with a trigger', combined with the corner-dead-zone rule made structural "
			+ "(world_area.gd's build_perimeter_walls()/_linked_edge_rects())."
			) % [edge_name, INTERACTABLE_LAYER_BIT, expected_rect])


## Asserts that some StaticBody2D on the world layer occupies `expected_rect`
## somewhere under `area` — one of the two corner stubs a linked edge builds.
func _assert_has_matching_corner_stub(area: WorldArea, expected_rect: Rect2, edge_name: String, which_end: String) -> void:
	var bodies: Array = []
	_collect_nodes_of_type(area, func(n): return n is StaticBody2D, bodies)

	var found: bool = false
	for candidate in bodies:
		var body: StaticBody2D = candidate as StaticBody2D
		if body.collision_layer != WORLD_LAYER_BIT:
			continue
		var rect: Variant = _world_bounding_rect(body)
		if rect == null:
			continue
		if _rects_almost_equal(rect as Rect2, expected_rect):
			found = true
			break

	assert_true(found,
			(
			"meadow's linked %s edge's %s corner square must still be a solid StaticBody2D on the "
			+ "world layer (bit %d) at %s — a corner square is 'ordinary walkable ground you just "
			+ "can't transition from' (design.md §12.4), not an open hole in the map boundary."
			) % [edge_name, which_end, WORLD_LAYER_BIT, expected_rect])


func test_linked_east_edge_gets_an_interactable_area2d_not_a_wall() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var area: WorldArea = _get_instanced_area(world)
	if area == null:
		return

	var bounds: Rect2 = area.get_bounds_px()
	# The east edge is split into three pieces (world_area.gd's
	# _linked_edge_rects()): a north corner stub, an active trigger stretch in
	# the middle, and a south corner stub — together tiling the exact same
	# full rect build_perimeter_walls() would have used for a plain wall on
	# this edge (design.md §12.4).
	var full_rect := Rect2(
			bounds.end.x, bounds.position.y,
			PERIMETER_WALL_THICKNESS_PX, bounds.size.y)
	# The north corner stub's dead zone is measured from the north edge's
	# PLAYABLE-FACING boundary (bounds.position.y + NORTH_WALL_HEADROOM_INSET_PX),
	# not the raw painted north edge — see NORTH_WALL_HEADROOM_INSET_PX's doc
	# comment above. The south stub has no such inset (south is never
	# headroom-corrected), so it's still measured from the raw bounds.end.y.
	var north_dead_zone_end: float = bounds.position.y + NORTH_WALL_HEADROOM_INSET_PX + CORNER_DEAD_ZONE_PX
	var north_stub_rect := Rect2(
			bounds.end.x, bounds.position.y,
			PERIMETER_WALL_THICKNESS_PX, north_dead_zone_end - bounds.position.y)
	var south_stub_rect := Rect2(
			bounds.end.x, bounds.end.y - CORNER_DEAD_ZONE_PX,
			PERIMETER_WALL_THICKNESS_PX, CORNER_DEAD_ZONE_PX)
	var trigger_rect := Rect2(
			bounds.end.x, north_dead_zone_end,
			PERIMETER_WALL_THICKNESS_PX, (bounds.end.y - CORNER_DEAD_ZONE_PX) - north_dead_zone_end)

	_assert_has_matching_trigger(area, trigger_rect, "east")
	_assert_has_matching_corner_stub(area, north_stub_rect, "east", "north")
	_assert_has_matching_corner_stub(area, south_stub_rect, "east", "south")

	# And the converse: no single solid StaticBody2D should span the WHOLE
	# edge (that would mean the split didn't happen and the edge is
	# impassable, or that a full wall was built alongside the trigger).
	var bodies: Array = []
	_collect_nodes_of_type(area, func(n): return n is StaticBody2D, bodies)
	for candidate in bodies:
		var body: StaticBody2D = candidate as StaticBody2D
		if body.collision_layer != WORLD_LAYER_BIT:
			continue
		var rect: Variant = _world_bounding_rect(body)
		if rect == null:
			continue
		assert_false(_rects_almost_equal(rect as Rect2, full_rect),
				"a single StaticBody2D wall was found spanning the entire east edge's rect (%s) even though neighbour_east is set — the middle stretch should have been replaced by a trigger, not left as one solid wall" % [full_rect])


func test_linked_south_edge_gets_an_interactable_area2d_not_a_wall() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var area: WorldArea = _get_instanced_area(world)
	if area == null:
		return

	var bounds: Rect2 = area.get_bounds_px()
	# South edge's full rect (world_area.gd's build_perimeter_walls()):
	# extends PERIMETER_WALL_THICKNESS_PX past each side (corner-closing),
	# flush against bounds.end.y. Split into a west stub, an active trigger
	# middle, and an east stub (world_area.gd's _linked_edge_rects()).
	var full_rect := Rect2(
			bounds.position.x - PERIMETER_WALL_THICKNESS_PX, bounds.end.y,
			bounds.size.x + PERIMETER_WALL_THICKNESS_PX * 2.0, PERIMETER_WALL_THICKNESS_PX)
	var west_stub_rect := Rect2(
			bounds.position.x - PERIMETER_WALL_THICKNESS_PX, bounds.end.y,
			PERIMETER_WALL_THICKNESS_PX + CORNER_DEAD_ZONE_PX, PERIMETER_WALL_THICKNESS_PX)
	var east_stub_rect := Rect2(
			bounds.end.x - CORNER_DEAD_ZONE_PX, bounds.end.y,
			PERIMETER_WALL_THICKNESS_PX + CORNER_DEAD_ZONE_PX, PERIMETER_WALL_THICKNESS_PX)
	var trigger_rect := Rect2(
			bounds.position.x + CORNER_DEAD_ZONE_PX, bounds.end.y,
			bounds.size.x - CORNER_DEAD_ZONE_PX * 2.0, PERIMETER_WALL_THICKNESS_PX)

	_assert_has_matching_trigger(area, trigger_rect, "south")
	_assert_has_matching_corner_stub(area, west_stub_rect, "south", "west")
	_assert_has_matching_corner_stub(area, east_stub_rect, "south", "east")

	var bodies: Array = []
	_collect_nodes_of_type(area, func(n): return n is StaticBody2D, bodies)
	for candidate in bodies:
		var body: StaticBody2D = candidate as StaticBody2D
		if body.collision_layer != WORLD_LAYER_BIT:
			continue
		var rect: Variant = _world_bounding_rect(body)
		if rect == null:
			continue
		assert_false(_rects_almost_equal(rect as Rect2, full_rect),
				"a single StaticBody2D wall was found spanning the entire south edge's rect (%s) even though neighbour_south is set — the middle stretch should have been replaced by a trigger, not left as one solid wall" % [full_rect])


func test_unlinked_north_and_west_edges_still_get_walls_slice_9_regression() -> void:
	# Regression check (test plan: "An edge of the meadow with no neighbour_*
	# scene still behaves exactly like slice 9"). meadow.tscn's north/west
	# slots remain unset — those two edges must still get an ordinary
	# StaticBody2D wall, unaffected by the east/south linking done for this
	# slice.
	var world: Node = _instantiate_world()
	if world == null:
		return
	var area: WorldArea = _get_instanced_area(world)
	if area == null:
		return

	var bounds: Rect2 = area.get_bounds_px()
	var bodies: Array = []
	_collect_nodes_of_type(area, func(n): return n is StaticBody2D, bodies)

	# West wall's exact rect.
	var west_rect := Rect2(
			bounds.position.x - PERIMETER_WALL_THICKNESS_PX, bounds.position.y,
			PERIMETER_WALL_THICKNESS_PX, bounds.size.y)
	var found_west: bool = false
	for candidate in bodies:
		var body: StaticBody2D = candidate as StaticBody2D
		if body.collision_layer != WORLD_LAYER_BIT:
			continue
		var rect: Variant = _world_bounding_rect(body)
		if rect != null and _rects_almost_equal(rect as Rect2, west_rect):
			found_west = true
			break
	assert_true(found_west,
			"meadow's UNLINKED west edge must still get an ordinary StaticBody2D wall at %s (slice 9 behavior, unaffected by this slice's east/south linking)" % [west_rect])


# ---------------------------------------------------------------------------
# Corner dead zones on a LINKED edge's real trigger geometry
# ---------------------------------------------------------------------------
#
# This is now a genuine geometry check: a linked edge's corner squares are
# covered by solid StaticBody2D stubs (world_area.gd's _linked_edge_rects()),
# so a player positioned there is physically blocked from ever reaching the
# Area2D trigger, not merely denied a signal by handler-side suppression.

func test_player_near_east_edge_corner_does_not_trigger_edge_reached() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var area: WorldArea = _get_instanced_area(world)
	if area == null:
		return
	var bounds: Rect2 = area.get_bounds_px()

	var player: CharacterBody2D = world.find_child("Player", true, false) as CharacterBody2D
	assert_not_null(player, "world.tscn's instantiated tree should contain a CharacterBody2D named 'Player'")
	if player == null:
		return

	await wait_physics_frames(2)
	watch_signals(area)

	# East edge's vertical corner dead zone is inset 2 tiles (32px) from the
	# bounds' top/bottom. Start 10px inside the exclusion near the SOUTH end
	# of the east edge, then drive straight into the edge.
	#
	# NOT the north end: bounds.position.y + 10 sits inside the NORTH wall's
	# own solid collision body — the north wall/trigger's player-facing
	# surface is inset NORTH_WALL_HEADROOM_INSET_PX (32px) south of the true
	# edge (design.md §12.4's camera-headroom fix), so its collider physically
	# spans y in [bounds.position.y, bounds.position.y + 32]. A player placed
	# at y = bounds.position.y + 10 starts already overlapping that wall and
	# gets depenetrated south before ever reaching the east edge, so this
	# particular start point can't exercise the east edge's corner logic at
	# all — the south end has no such interference (south has no headroom
	# inset). The north end's own corner exclusion IS now real and testable
	# (it's derived from the north edge's playable boundary, not the raw
	# edge, per design.md §12.4) — reachable player Y there runs roughly
	# [bounds.y + 37, bounds.y + 66) without firing edge_reached — it's just
	# not exercised by this particular test, which targets the south corner.
	var start: Vector2 = Vector2(bounds.end.x - 48.0, bounds.end.y - 10.0)
	player.global_position = start
	player.velocity = Vector2.ZERO

	await _drive_player(player, "move_right", DRIVE_TICKS)

	assert_signal_not_emitted(area, "edge_reached",
			"a player positioned inside the east edge's south corner dead zone (10px from the bottom, well under the 32px exclusion) must NOT trigger edge_reached")
	# "No signal fired" alone is also satisfied by a player who escaped off
	# the map through an open corner (mutation testing confirmed: deleting
	# the corner stubs entirely reopens that exact bug and still leaves this
	# assertion above green). Explicitly confirm containment too: the corner
	# stub must have physically stopped the player at the east edge, not let
	# them walk through it into the void beyond.
	assert_lt(player.global_position.x, bounds.end.x + 5.0,
			"a player in the east edge's south corner must be STOPPED by the corner stub, not walk through it off the map")


func test_player_near_south_edge_corner_does_not_trigger_edge_reached() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var area: WorldArea = _get_instanced_area(world)
	if area == null:
		return
	var bounds: Rect2 = area.get_bounds_px()

	var player: CharacterBody2D = world.find_child("Player", true, false) as CharacterBody2D
	assert_not_null(player, "world.tscn's instantiated tree should contain a CharacterBody2D named 'Player'")
	if player == null:
		return

	await wait_physics_frames(2)
	watch_signals(area)

	# South edge's horizontal corner dead zone is inset 1 tile (32px) from
	# the bounds' east/west ends. Start 10px inside that exclusion near the
	# WEST end of the south edge.
	var start: Vector2 = Vector2(bounds.position.x + 10.0, bounds.end.y - 48.0)
	player.global_position = start
	player.velocity = Vector2.ZERO

	await _drive_player(player, "move_down", DRIVE_TICKS)

	assert_signal_not_emitted(area, "edge_reached",
			"a player positioned inside the south edge's west corner dead zone (10px from the west end, well under the 32px exclusion) must NOT trigger edge_reached")
	# See test_player_near_east_edge_corner_does_not_trigger_edge_reached()'s
	# note above — "no signal fired" alone is also satisfied by an escaped
	# player, so explicitly confirm containment as well.
	assert_lt(player.global_position.y, bounds.end.y + 5.0,
			"a player in the south edge's west corner must be STOPPED by the corner stub, not walk through it off the map")


# ---------------------------------------------------------------------------
# edge_reached fires exactly once, clear of any corner, on both axes
# ---------------------------------------------------------------------------

## A player-origin Y inside the EAST edge's active (non-corner) stretch, along
## which the player can walk the last `approach_px` up to that edge without
## being stopped by painted terrain or a prop first.
##
## Previously both "clear middle of the edge" tests just used the edge's exact
## tangential midpoint. That is clear of the corner dead zones by construction,
## but says nothing about what has been painted in between — and once the
## meadow's Ground layer gained collidable edge tiles (design doc §6.1), the
## south edge's midpoint column ran into one, so the player never reached the
## trigger and the test failed for an unrelated reason. CollisionProbe searches
## outward from that same midpoint, so the lane is still as central as the map
## allows; it just no longer assumes central means empty.
func _clear_approach_row_for_east_edge(area: WorldArea, player: CharacterBody2D,
		bounds: Rect2, approach_px: float) -> float:
	var collider: Rect2 = CollisionProbe.player_collider_extent(player)
	var row: float = CollisionProbe.find_clear_row(
			area, collider,
			bounds.end.x - approach_px, bounds.end.x,
			_playable_north_boundary(bounds) + CORNER_DEAD_ZONE_PX,
			bounds.end.y - CORNER_DEAD_ZONE_PX)
	if is_nan(row):
		fail_test("no obstacle-free approach row exists in the east edge's active (non-corner) stretch — the player cannot reach the trigger to test it. Check what was painted onto Ground/Solids near that edge.")
	return row


## The vertical mirror of _clear_approach_row_for_east_edge(), for the SOUTH
## edge's active stretch.
func _clear_approach_column_for_south_edge(area: WorldArea, player: CharacterBody2D,
		bounds: Rect2, approach_px: float) -> float:
	var collider: Rect2 = CollisionProbe.player_collider_extent(player)
	var column: float = CollisionProbe.find_clear_column(
			area, collider,
			bounds.end.y - approach_px, bounds.end.y,
			bounds.position.x + CORNER_DEAD_ZONE_PX,
			bounds.end.x - CORNER_DEAD_ZONE_PX)
	if is_nan(column):
		fail_test("no obstacle-free approach column exists in the south edge's active (non-corner) stretch — the player cannot reach the trigger to test it. Check what was painted onto Ground/Solids near that edge.")
	return column


## The north edge's playable-facing boundary — the same inset boundary
## world_area.gd's _playable_boundary() computes, restated here per this
## suite's "mirror the constant, don't read it" convention.
func _playable_north_boundary(bounds: Rect2) -> float:
	return bounds.position.y + NORTH_WALL_HEADROOM_INSET_PX


func test_edge_reached_emitted_once_crossing_the_clear_middle_of_east_edge() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var area: WorldArea = _get_instanced_area(world)
	if area == null:
		return
	var bounds: Rect2 = area.get_bounds_px()

	var player: CharacterBody2D = world.find_child("Player", true, false) as CharacterBody2D
	assert_not_null(player, "world.tscn's instantiated tree should contain a CharacterBody2D named 'Player'")
	if player == null:
		return

	await wait_physics_frames(2)
	watch_signals(area)

	# Clear of both corners AND of anything painted in the approach: as close to
	# the centre of the east edge's tangential (Y) span as the map allows.
	var clear_y: float = _clear_approach_row_for_east_edge(area, player, bounds, 96.0)
	if is_nan(clear_y):
		return

	var start: Vector2 = Vector2(bounds.end.x - 96.0, clear_y)
	player.global_position = start
	player.velocity = Vector2.ZERO

	await _drive_player(player, "move_right", DRIVE_TICKS)

	assert_signal_emit_count(area, "edge_reached", 1,
			"walking into the clear middle of meadow's linked east edge must emit edge_reached exactly once")
	# NOTE: assert_signal_emitted_with_parameters()'s 4th positional argument
	# is an emission INDEX, not a failure message (see addons/gut/test.gd's
	# doc comment above the function) — a trailing message string here
	# previously broke the assertion's internal comparison (comparing that
	# string to -1). Dropped, matching the convention already used elsewhere
	# in this codebase (e.g. test_player_data_foundation.gd).
	assert_signal_emitted_with_parameters(area, "edge_reached", [WorldArea.Edge.EAST])


func test_edge_reached_emitted_once_crossing_the_clear_middle_of_south_edge() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var area: WorldArea = _get_instanced_area(world)
	if area == null:
		return
	var bounds: Rect2 = area.get_bounds_px()

	var player: CharacterBody2D = world.find_child("Player", true, false) as CharacterBody2D
	assert_not_null(player, "world.tscn's instantiated tree should contain a CharacterBody2D named 'Player'")
	if player == null:
		return

	await wait_physics_frames(2)
	watch_signals(area)

	var clear_x: float = _clear_approach_column_for_south_edge(area, player, bounds, 96.0)
	if is_nan(clear_x):
		return

	var start: Vector2 = Vector2(clear_x, bounds.end.y - 96.0)
	player.global_position = start
	player.velocity = Vector2.ZERO

	await _drive_player(player, "move_down", DRIVE_TICKS)

	assert_signal_emit_count(area, "edge_reached", 1,
			"walking into the clear middle of meadow's linked south edge must emit edge_reached exactly once")
	# See the east-edge test above for why the trailing message argument was
	# dropped (assert_signal_emitted_with_parameters()'s 4th param is an
	# emission index, not a message).
	assert_signal_emitted_with_parameters(area, "edge_reached", [WorldArea.Edge.SOUTH])


# ---------------------------------------------------------------------------
# Reciprocal neighbour wiring (meadow <-> orchard, both links)
# ---------------------------------------------------------------------------

func test_meadow_neighbour_east_and_orchard_neighbour_west_are_reciprocal() -> void:
	# NOTE: neighbour_* changed from @export PackedScene to
	# @export_file("*.tscn") String during this slice (design.md §12.2) — two
	# areas linking back to each other deadlock Godot's loader if both hold a
	# live PackedScene ext_resource pointing at one another. This test
	# originally asserted `.resource_path` on a PackedScene value; updated to
	# compare the plain path string directly instead.
	var meadow_packed: PackedScene = load(MEADOW_SCENE_PATH)
	var orchard_packed: PackedScene = load(ORCHARD_SCENE_PATH)
	assert_not_null(meadow_packed, "world/areas/meadow.tscn should load")
	assert_not_null(orchard_packed, "world/areas/orchard.tscn should load")
	if meadow_packed == null or orchard_packed == null:
		return

	var meadow: WorldArea = meadow_packed.instantiate() as WorldArea
	var orchard: WorldArea = orchard_packed.instantiate() as WorldArea
	add_child_autofree(meadow)
	add_child_autofree(orchard)

	assert_false(meadow.neighbour_east.is_empty(),
			"meadow.tscn's neighbour_east must reference the second area's scene path for this slice's east/west link")
	assert_false(orchard.neighbour_west.is_empty(),
			"the second area's neighbour_west must reference meadow.tscn's scene path back")

	assert_eq(meadow.neighbour_east, ORCHARD_SCENE_PATH,
			"meadow.tscn's neighbour_east must point at %s" % [ORCHARD_SCENE_PATH])
	assert_eq(orchard.neighbour_west, MEADOW_SCENE_PATH,
			"the second area's neighbour_west must point back at %s" % [MEADOW_SCENE_PATH])


func test_meadow_neighbour_south_and_orchard_neighbour_north_are_reciprocal() -> void:
	# See test_meadow_neighbour_east_and_orchard_neighbour_west_are_reciprocal()'s
	# note above — neighbour_* is now a plain path String, not a PackedScene.
	var meadow_packed: PackedScene = load(MEADOW_SCENE_PATH)
	var orchard_packed: PackedScene = load(ORCHARD_SCENE_PATH)
	assert_not_null(meadow_packed, "world/areas/meadow.tscn should load")
	assert_not_null(orchard_packed, "world/areas/orchard.tscn should load")
	if meadow_packed == null or orchard_packed == null:
		return

	var meadow: WorldArea = meadow_packed.instantiate() as WorldArea
	var orchard: WorldArea = orchard_packed.instantiate() as WorldArea
	add_child_autofree(meadow)
	add_child_autofree(orchard)

	assert_false(meadow.neighbour_south.is_empty(),
			"meadow.tscn's neighbour_south must reference the second area's scene path for this slice's north/south link")
	assert_false(orchard.neighbour_north.is_empty(),
			"the second area's neighbour_north must reference meadow.tscn's scene path back")

	assert_eq(meadow.neighbour_south, ORCHARD_SCENE_PATH,
			"meadow.tscn's neighbour_south must point at %s" % [ORCHARD_SCENE_PATH])
	assert_eq(orchard.neighbour_north, MEADOW_SCENE_PATH,
			"the second area's neighbour_north must point back at %s" % [MEADOW_SCENE_PATH])


# ---------------------------------------------------------------------------
# Second area is at least one full viewport (design.md §12.3's hard floor)
# ---------------------------------------------------------------------------

func test_second_area_bounds_cover_at_least_one_viewport() -> void:
	var packed: PackedScene = load(ORCHARD_SCENE_PATH)
	assert_not_null(packed, "the second-area fixture scene should load as a PackedScene")
	if packed == null:
		return

	var area: WorldArea = packed.instantiate() as WorldArea
	assert_not_null(area, "the second area's root must be a WorldArea")
	if area == null:
		return
	add_child_autofree(area)

	var bounds: Rect2 = area.get_bounds_px()

	assert_gt(bounds.size.x, MIN_AREA_WIDTH_PX - 1.0,
			"the second area's width (%.1fpx) must be at least one viewport wide (%.1fpx) — design.md §12.3's hard floor, or the camera dead-zone/edge-lock checks fail for reasons unrelated to this slice" % [bounds.size.x, MIN_AREA_WIDTH_PX])
	assert_gt(bounds.size.y, MIN_AREA_HEIGHT_PX - 1.0,
			"the second area's height (%.1fpx) must be at least one viewport tall (%.1fpx)" % [bounds.size.y, MIN_AREA_HEIGHT_PX])

	var width_tiles: int = int(round(bounds.size.x / float(TILE_SIZE.x)))
	var height_tiles: int = int(round(bounds.size.y / float(TILE_SIZE.y)))
	assert_gt(width_tiles, MIN_AREA_WIDTH_TILES - 1,
			"the second area must be at least %d tiles wide — found %d" % [MIN_AREA_WIDTH_TILES, width_tiles])
	assert_gt(height_tiles, MIN_AREA_HEIGHT_TILES - 1,
			"the second area must be at least %d tiles tall — found %d" % [MIN_AREA_HEIGHT_TILES, height_tiles])
