## test_area_transition.gd
## Integration tests for World Thresholds Slice 4 ("Switchover: collapse
## WorldArea, remove the old path, migrate real content").
##
## REWRITTEN IN PLACE. This file used to hold the world-collision slice-10
## suite for the edge-derived transition mechanism (neighbour_*, edge_reached,
## corner dead zones, the arrival debounce). That mechanism, and the tests
## that proved it, are deleted in the SAME commit that adds the real content
## this file now proves (docs/features/world-thresholds/slices.md, Slice 4 —
## "why this cannot be split further and stay green throughout"). Nothing
## below references neighbour_*, edge_reached, opposite_edge(),
## compute_entry_position(), area_id_from_scene_path(), north_headroom_inset(),
## CORNER_DEAD_ZONE_PX, the debounce methods/constants, or
## Player.get_visual_extent()/get_collider_extent() — every one of those is
## gone from WorldArea/player.gd by the time this slice lands, and the test
## plan's own "parse-failure warning" is exactly about a stray reference to
## one of them silently dropping a whole test file from the run.
##
## PARITY, not new behavior: World Thresholds Slice 3
## (test_threshold_transition.gd) already proved the generic Threshold-driven
## sequence — freeze/fade/swap/place/reveal, resolve-before-destroy,
## re-entry guard — against small fixture WorldAreas. This file does not
## re-prove that mechanism in the abstract; it proves the mechanism was
## actually wired into the real meadow.tscn <-> orchard.tscn link the design
## doc's acceptance bar cares about (design.md §10: "the existing two-way
## meadow <-> orchard link works exactly as it does today, via placed
## Thresholds and Arrivals").
##
## THE SETTLED REAL-CONTENT AUTHORING CONTRACT THIS SUITE ASSUMES
## =========================================================================
## slices.md's Slice 4 settles WHICH scenes link on WHICH edges ("meadow.tscn
## gains a ThresholdToOrchard (east) and a second Threshold on its south edge
## ... orchard.tscn gains the reciprocal pair") but does not spell out exact
## node names for the second Threshold on each area or for the four Arrivals.
## This suite is test-first — written before the migration — so it settles
## that naming here, as the contract godot-coder's implementation step must
## match (see the constants below):
##
##   meadow.tscn
##     ThresholdToOrchardEast   (east edge)  -> orchard.tscn, arrival &"ArrivalFromMeadowEast"
##     ThresholdToOrchardSouth  (south edge) -> orchard.tscn, arrival &"ArrivalFromMeadowSouth"
##     ArrivalFromOrchardNorth  (Marker2D, near meadow's south edge — the reverse trip's landing spot)
##     ArrivalFromOrchardWest   (Marker2D, near meadow's east edge — the reverse trip's landing spot)
##   orchard.tscn
##     ThresholdToMeadowNorth   (north edge) -> meadow.tscn, arrival &"ArrivalFromOrchardNorth"
##     ThresholdToMeadowWest    (west edge)  -> meadow.tscn, arrival &"ArrivalFromOrchardWest"
##     ArrivalFromMeadowEast    (Marker2D, near orchard's west edge)
##     ArrivalFromMeadowSouth   (Marker2D, near orchard's north edge)
##
## This reproduces today's live neighbour_* wiring one-for-one — meadow
## currently declares neighbour_east/neighbour_south = orchard.tscn, and
## orchard currently declares neighbour_north/neighbour_west = meadow.tscn
## (see both .tscn files' current source, deleted by this same slice).
##
## EXPECTED TO FAIL UNTIL GODOT-CODER'S IMPLEMENTATION STEP LANDS
## =========================================================================
## As of this test-authoring pass, WorldArea.build_perimeter_walls() still
## takes its old headroom_inset_px argument and branches on neighbour_*, and
## neither meadow.tscn nor orchard.tscn has a single placed Threshold or
## Arrival node. Every test below that depends on real content is EXPECTED to
## fail right now, for that reason — this is the same "prove the plan before
## the code exists" shape every other slice in this feature went through (see
## slices.md's "B2" convention). What must NOT happen is a silent parse-time
## drop of this whole file — see the header warning above.
##
## Design reference: docs/features/world-thresholds/design.md §4, §5, §7, §8, §9, §10.
## Test plan: docs/features/world-thresholds/slice-4-switchover-test-plan.md
## Slice breakdown: docs/features/world-thresholds/slices.md, Slice 4
##
## Requires GUT: https://github.com/bitwes/Gut
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gselect=test_area_transition.gd -gexit

class_name TestAreaTransition
extends GutTest


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const WORLD_SCENE_PATH: String = "res://world/world.tscn"
const MEADOW_SCENE_PATH: String = "res://world/areas/meadow.tscn"
const ORCHARD_SCENE_PATH: String = "res://world/areas/orchard.tscn"

const MEADOW_ID: StringName = &"meadow"
const ORCHARD_ID: StringName = &"orchard"

## See this file's header for the full authoring-contract note.
const THRESHOLD_MEADOW_EAST: String = "ThresholdToOrchardEast"
const THRESHOLD_MEADOW_SOUTH: String = "ThresholdToOrchardSouth"
const THRESHOLD_ORCHARD_NORTH: String = "ThresholdToMeadowNorth"
const THRESHOLD_ORCHARD_WEST: String = "ThresholdToMeadowWest"

const ARRIVAL_FROM_MEADOW_EAST: String = "ArrivalFromMeadowEast"
const ARRIVAL_FROM_MEADOW_SOUTH: String = "ArrivalFromMeadowSouth"
const ARRIVAL_FROM_ORCHARD_NORTH: String = "ArrivalFromOrchardNorth"
const ARRIVAL_FROM_ORCHARD_WEST: String = "ArrivalFromOrchardWest"

## "world" physics layer bit (project.godot's [layer_names], layer_1="world").
const WORLD_LAYER_BIT: int = 1

## Prop scenes to exclude when scanning for perimeter-wall StaticBody2Ds —
## mirrors test_perimeter_walls.gd's identical exclusion list. Kept as its own
## copy per this project's "each test file is self-contained" convention.
const PROP_SCENE_PATHS: Array[String] = [
	"res://world/props/boulder.tscn",
	"res://world/props/tree_oak.tscn",
]

## How many REAL physics frames to hold movement input while walking into a
## Threshold or a wall. Mirrors the pre-Slice-4 version of this file's
## identical constant.
const DRIVE_TICKS: int = 300

## Upper bound on how long the freeze/fade/swap/place/reveal sequence is
## allowed to take before this suite gives up waiting — a ceiling, not a
## fixed sleep (see _wait_until_playing_or_timeout()).
const TRANSITION_TIMEOUT_TICKS: int = 300  # ~5s at 60Hz

## How far back from an edge to start a clear-lane search, and how wide a band
## around an edge line counts as "near that edge" when looking for a wall or a
## Threshold. Mirrors test_perimeter_walls.gd's EDGE_BAND_PX.
const APPROACH_OFFSET_PX: float = 100.0
const EDGE_BAND_PX: float = 48.0

const CollisionProbe := preload("res://tests/integration/world/shared/collision_probe.gd")


# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

func before_each() -> void:
	GameState.change_state(GameState.State.PLAYING)


func after_each() -> void:
	Input.action_release("move_up")
	Input.action_release("move_down")
	Input.action_release("move_left")
	Input.action_release("move_right")


# ---------------------------------------------------------------------------
# Helpers — instantiation
# ---------------------------------------------------------------------------

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


func _get_active_area(world: Node) -> WorldArea:
	var active_area: Node = world.get_node_or_null("ActiveArea")
	assert_not_null(active_area, "world.tscn should have a direct child named 'ActiveArea'")
	if active_area == null:
		return null
	assert_gt(active_area.get_child_count(), 0, "ActiveArea should hold an instanced WorldArea")
	if active_area.get_child_count() == 0:
		return null
	var area: Node = active_area.get_child(0)
	if not (area is WorldArea):
		fail_test("the instanced ActiveArea child must be a WorldArea instance — found a %s" % [area.get_class()])
		return null
	return area as WorldArea


func _get_player(world: Node) -> CharacterBody2D:
	var player: CharacterBody2D = world.find_child("Player", true, false) as CharacterBody2D
	assert_not_null(player, "world.tscn's instantiated tree should contain a CharacterBody2D named 'Player'")
	return player


# ---------------------------------------------------------------------------
# Helpers — sequence timing (mirrors test_threshold_transition.gd's identical
# helpers, kept self-contained per this project's per-file convention)
# ---------------------------------------------------------------------------

func _find_fade_canvas_item(transition: Node) -> CanvasItem:
	for child in transition.get_children():
		if child is CanvasItem:
			return child as CanvasItem
	return null


func _wait_until_playing_or_timeout() -> bool:
	var waited: int = 0
	while waited < TRANSITION_TIMEOUT_TICKS:
		if GameState.current_state == GameState.State.PLAYING:
			return true
		await wait_physics_frames(10)
		waited += 10
	return GameState.current_state == GameState.State.PLAYING


## Hold `action` for up to `max_ticks` real physics frames, releasing EARLY —
## the instant GameState leaves PLAYING — rather than always holding the full
## duration (see the pre-rewrite version of this file for the original
## reasoning: holding input past the crossing carries the player well past
## the intended landing spot and can strand GameState back at PLAYING by the
## time a caller samples it).
func _drive_player(player: CharacterBody2D, action: String, max_ticks: int) -> void:
	Input.action_press(action)
	var waited: int = 0
	while waited < max_ticks and GameState.current_state == GameState.State.PLAYING:
		await wait_physics_frames(1)
		waited += 1
	Input.action_release(action)
	player.velocity = Vector2.ZERO


# ---------------------------------------------------------------------------
# Helpers — geometry (walls, Thresholds)
# ---------------------------------------------------------------------------

## The global bounding rect of the first RectangleShape2D found on a direct
## CollisionShape2D child of `body` — the shared shape both perimeter walls
## and Threshold use. Returns null if none found. Mirrors
## test_perimeter_walls.gd's _world_bounding_rect(), generalized to any
## Node2D (StaticBody2D or Area2D both qualify).
func _node_bounding_rect(body: Node2D) -> Variant:
	for child in body.get_children():
		var collision: CollisionShape2D = child as CollisionShape2D
		if collision == null or collision.shape == null:
			continue
		var shape: RectangleShape2D = collision.shape as RectangleShape2D
		if shape == null:
			continue
		var half: Vector2 = shape.size / 2.0
		var centre: Vector2 = collision.global_position
		return Rect2(centre - half, half * 2.0)
	return null


## Every StaticBody2D on the "world" layer anywhere under `area`, excluding
## prop scenes. Mirrors test_perimeter_walls.gd's
## _collect_non_prop_static_bodies(), kept self-contained here.
func _collect_perimeter_walls(node: Node, out: Array[StaticBody2D]) -> void:
	for child in node.get_children():
		if child.scene_file_path in PROP_SCENE_PATHS:
			continue
		if child is StaticBody2D and (child as StaticBody2D).collision_layer == WORLD_LAYER_BIT:
			out.append(child as StaticBody2D)
		_collect_perimeter_walls(child, out)


## The detection band for one edge of `bounds` — mirrors
## test_perimeter_walls.gd's _edge_band().
func _edge_band(bounds: Rect2, edge: String) -> Rect2:
	match edge:
		"north":
			return Rect2(bounds.position.x - EDGE_BAND_PX, bounds.position.y - EDGE_BAND_PX,
					bounds.size.x + EDGE_BAND_PX * 2.0, EDGE_BAND_PX * 2.0)
		"south":
			return Rect2(bounds.position.x - EDGE_BAND_PX, bounds.end.y - EDGE_BAND_PX,
					bounds.size.x + EDGE_BAND_PX * 2.0, EDGE_BAND_PX * 2.0)
		"west":
			return Rect2(bounds.position.x - EDGE_BAND_PX, bounds.position.y - EDGE_BAND_PX,
					EDGE_BAND_PX * 2.0, bounds.size.y + EDGE_BAND_PX * 2.0)
		"east":
			return Rect2(bounds.end.x - EDGE_BAND_PX, bounds.position.y - EDGE_BAND_PX,
					EDGE_BAND_PX * 2.0, bounds.size.y + EDGE_BAND_PX * 2.0)
		_:
			push_error("_edge_band: unknown edge '%s'" % [edge])
			return Rect2()


## [min, max] tangential-axis intervals (x for north/south, y for east/west)
## for every wall in `walls` whose bounding rect falls in `edge`'s detection
## band. Mirrors test_perimeter_walls.gd's _matching_intervals_for_edge().
func _wall_intervals_for_edge(walls: Array[StaticBody2D], bounds: Rect2, edge: String) -> Array:
	var band: Rect2 = _edge_band(bounds, edge)
	var intervals: Array = []
	for wall in walls:
		var rect_v: Variant = _node_bounding_rect(wall)
		if rect_v == null:
			continue
		var rect: Rect2 = rect_v
		if not rect.intersects(band):
			continue
		if edge == "north" or edge == "south":
			intervals.append([rect.position.x, rect.end.x])
		else:
			intervals.append([rect.position.y, rect.end.y])
	return intervals


## True if `intervals` (an Array of [min, max] float pairs, in any order,
## possibly overlapping) covers [span_min, span_max] with no gap wider than
## a few px. Mirrors test_perimeter_walls.gd's _covers_full_span() — used here
## to distinguish a genuine FULL-SPAN wall (design.md §7's collapsed,
## unconditional API) from the old mechanism's two small corner stubs either
## side of an open-edge trigger, which a plain "is there a wall SOMEWHERE near
## this edge" check cannot tell apart (a linked edge always had corner stubs,
## even before this slice).
func _covers_full_span(intervals: Array, span_min: float, span_max: float) -> bool:
	const GAP_TOLERANCE_PX: float = 1.0
	if intervals.is_empty():
		return false
	var sorted_intervals: Array = intervals.duplicate()
	sorted_intervals.sort_custom(func(a, b): return a[0] < b[0])
	var covered_up_to: float = span_min
	for interval in sorted_intervals:
		if interval[0] > covered_up_to + GAP_TOLERANCE_PX:
			return false
		covered_up_to = maxf(covered_up_to, interval[1])
	return covered_up_to >= span_max - GAP_TOLERANCE_PX


## True if the walls on `edge` of `bounds` cover the ENTIRE edge span with no
## gap — not merely "some wall exists somewhere near this edge" (which the
## old mechanism's corner stubs alone would already satisfy on a linked edge,
## making that check pass today for the wrong reason and prove nothing about
## Slice 4's unconditional-wall collapse).
func _wall_covers_full_edge(walls: Array[StaticBody2D], bounds: Rect2, edge: String) -> bool:
	var intervals: Array = _wall_intervals_for_edge(walls, bounds, edge)
	if edge == "north" or edge == "south":
		return _covers_full_span(intervals, bounds.position.x, bounds.end.x)
	else:
		return _covers_full_span(intervals, bounds.position.y, bounds.end.y)


## A player-origin start position roughly APPROACH_OFFSET_PX inward from
## `edge` of `bounds`, on a lane CollisionProbe confirms is free of obstacles
## all the way to the edge — so a real, obstacle-avoiding drive can attribute
## a stop (or a crossing) to whatever sits on that edge specifically, not to
## something a designer happened to paint or place nearby. Returns a Vector2
## with NAN components if no clear lane exists.
func _clear_approach(area: WorldArea, collider: Rect2, bounds: Rect2, edge: String) -> Vector2:
	match edge:
		"east":
			var y: float = CollisionProbe.find_clear_row(area, collider,
					bounds.end.x - APPROACH_OFFSET_PX, bounds.end.x - 10.0,
					bounds.position.y + 40.0, bounds.end.y - 40.0)
			return Vector2(bounds.end.x - APPROACH_OFFSET_PX, y)
		"west":
			var y: float = CollisionProbe.find_clear_row(area, collider,
					bounds.position.x + 10.0, bounds.position.x + APPROACH_OFFSET_PX,
					bounds.position.y + 40.0, bounds.end.y - 40.0)
			return Vector2(bounds.position.x + APPROACH_OFFSET_PX, y)
		"south":
			var x: float = CollisionProbe.find_clear_column(area, collider,
					bounds.end.y - APPROACH_OFFSET_PX, bounds.end.y - 10.0,
					bounds.position.x + 40.0, bounds.end.x - 40.0)
			return Vector2(x, bounds.end.y - APPROACH_OFFSET_PX)
		"north":
			var x: float = CollisionProbe.find_clear_column(area, collider,
					bounds.position.y + 10.0, bounds.position.y + APPROACH_OFFSET_PX,
					bounds.position.x + 40.0, bounds.end.x - 40.0)
			return Vector2(x, bounds.position.y + APPROACH_OFFSET_PX)
		_:
			push_error("_clear_approach: unknown edge '%s'" % [edge])
			return Vector2(NAN, NAN)


## Asserts `threshold_name`'s CollisionShape2D sits inset from — not
## overlapping, and not far inside the map from — `wall_name`'s own collider
## on the same edge (design.md §4/§7: "Thresholds sit inset from the
## perimeter wall, not flush against it ... so the player always meets the
## Threshold before the wall"). Also checks the Threshold's own depth is
## close to the settled 2px (slices.md's Slice 4 "Threshold depth — settled"
## note).
func _assert_threshold_inset_from_wall(area: WorldArea, threshold_name: String,
		wall_name: String, edge: String) -> void:
	var threshold: Node2D = area.find_child(threshold_name, true, false) as Node2D
	assert_not_null(threshold,
			"%s should contain a Threshold named '%s'" % [area.scene_file_path, threshold_name])
	var wall: StaticBody2D = area.get_node_or_null(wall_name) as StaticBody2D
	assert_not_null(wall,
			"%s should have a perimeter wall named '%s' on its %s edge" % [area.scene_file_path, wall_name, edge])
	if threshold == null or wall == null:
		return

	var threshold_rect_v: Variant = _node_bounding_rect(threshold)
	var wall_rect_v: Variant = _node_bounding_rect(wall)
	assert_not_null(threshold_rect_v, "%s's CollisionShape2D must have a RectangleShape2D" % [threshold_name])
	assert_not_null(wall_rect_v, "%s's CollisionShape2D must have a RectangleShape2D" % [wall_name])
	if threshold_rect_v == null or wall_rect_v == null:
		return

	var t_rect: Rect2 = threshold_rect_v
	var w_rect: Rect2 = wall_rect_v

	assert_false(t_rect.intersects(w_rect),
			"%s must not overlap %s — a Threshold sits INSET from its edge's wall, not flush against or inside it (design.md §4)"
					% [threshold_name, wall_name])

	var depth: float = 0.0
	var gap: float = 0.0
	match edge:
		"east":
			depth = t_rect.size.x
			gap = w_rect.position.x - t_rect.end.x
		"west":
			depth = t_rect.size.x
			gap = t_rect.position.x - w_rect.end.x
		"south":
			depth = t_rect.size.y
			gap = w_rect.position.y - t_rect.end.y
		"north":
			depth = t_rect.size.y
			gap = t_rect.position.y - w_rect.end.y
		_:
			fail_test("_assert_threshold_inset_from_wall: unknown edge '%s'" % [edge])
			return

	assert_almost_eq(depth, 2.0, 1.5,
			"%s should be ~2px deep (slices.md's Slice 4 'Threshold depth — settled' note) — found %.2fpx"
					% [threshold_name, depth])
	assert_true(gap >= -0.5 and gap <= 8.0,
			("%s should hug the inside of %s with only a small gap (design.md §4: 'hugging the " +
			"inside of the perimeter wall') — found a %.2fpx gap between them")
					% [threshold_name, wall_name, gap])


# ---------------------------------------------------------------------------
# Helpers — real crossings
# ---------------------------------------------------------------------------

## Perform a full real crossing: walk `player` off `source_area`'s `edge`
## toward `action`, then assert every Integration-plan behavior common to all
## four real crossings — GameState LOADING then PLAYING, the fade opaque then
## transparent, the swap/reparent, the exact Arrival landing position, the
## reset camera limits, GameEvents.area_changed firing once with the correct
## id, and the re-entry guard holding once landed.
func _cross_and_verify(world: Node, source_area: WorldArea, player: CharacterBody2D,
		edge: String, action: String, threshold_name: String,
		destination_scene_path: String, destination_id: StringName, arrival_name: String) -> void:
	var threshold: Node2D = source_area.find_child(threshold_name, true, false) as Node2D
	assert_not_null(threshold,
			"%s should contain a Threshold named '%s' (World Thresholds Slice 4 content migration)"
					% [source_area.scene_file_path, threshold_name])
	if threshold == null:
		return

	var bounds: Rect2 = source_area.get_bounds_px()
	var collider: Rect2 = CollisionProbe.player_collider_extent(player)
	var start: Vector2 = _clear_approach(source_area, collider, bounds, edge)
	if is_nan(start.x) or is_nan(start.y):
		fail_test("no obstacle-free approach lane exists on %s's %s edge — cannot drive a real crossing"
				% [source_area.scene_file_path, edge])
		return

	var transition: Node = world.get_node_or_null("Transition")
	assert_not_null(transition, "world.tscn should have a direct child named 'Transition'")

	watch_signals(GameEvents)
	player.global_position = start
	player.velocity = Vector2.ZERO
	await wait_physics_frames(2)
	await _drive_player(player, action, DRIVE_TICKS)

	assert_eq(GameState.current_state, GameState.State.LOADING,
			"crossing %s should freeze GameState to LOADING before the fade/swap/place sequence runs"
					% [threshold_name])

	if transition != null:
		await wait_physics_frames(20)
		var fade_out: CanvasItem = _find_fade_canvas_item(transition)
		if fade_out != null:
			assert_gt(fade_out.modulate.a, 0.0,
					"the Transition overlay should have started becoming opaque while GameState is LOADING (crossing %s)"
							% [threshold_name])

	var reached_playing: bool = await _wait_until_playing_or_timeout()
	assert_true(reached_playing,
			"the freeze/fade/swap/place/reveal sequence should complete for %s within %d ticks (~%.0fs) — GameState stuck at %d"
					% [threshold_name, TRANSITION_TIMEOUT_TICKS, TRANSITION_TIMEOUT_TICKS / 60.0, GameState.current_state])
	if not reached_playing:
		return

	if transition != null:
		var fade_in: CanvasItem = _find_fade_canvas_item(transition)
		if fade_in != null:
			assert_almost_eq(fade_in.modulate.a, 0.0, 0.05,
					"the Transition overlay must be fully transparent again once %s's crossing completes"
							% [threshold_name])

	var active_area: Node = world.get_node_or_null("ActiveArea")
	if active_area == null or active_area.get_child_count() == 0:
		fail_test("no instanced area found under ActiveArea after crossing %s" % [threshold_name])
		return
	var new_area: WorldArea = active_area.get_child(0) as WorldArea
	assert_not_null(new_area, "the newly-instanced area after crossing %s must be a WorldArea" % [threshold_name])
	if new_area == null:
		return
	assert_eq(new_area.scene_file_path, destination_scene_path,
			"crossing %s should land in %s — found '%s'"
					% [threshold_name, destination_scene_path, new_area.scene_file_path])

	assert_eq(player.get_parent(), new_area,
			"the Player must be reparented into the destination area after crossing %s" % [threshold_name])

	var arrival: Marker2D = new_area.find_child(arrival_name, true, false) as Marker2D
	assert_not_null(arrival, "%s should contain a Marker2D named '%s'" % [destination_scene_path, arrival_name])
	if arrival != null:
		# THE pass/fail bar for this whole suite (test plan's explicit
		# correction): the marker's OWN authored position, read live off the
		# instance — not any preserved offset carried over from the deleted
		# edge-derived mechanism.
		assert_almost_eq(player.global_position, arrival.global_position, Vector2(0.5, 0.5),
				("the player's landing position after crossing %s must exactly match %s's " +
				"authored position (%s) — found %s")
						% [threshold_name, arrival_name, arrival.global_position, player.global_position])

	var new_bounds: Rect2 = new_area.get_bounds_px()
	var camera: Camera2D = player.get_node_or_null("Camera2D") as Camera2D
	assert_not_null(camera, "Player must still have a Camera2D child after crossing %s" % [threshold_name])
	if camera != null:
		assert_eq(camera.limit_left, int(new_bounds.position.x),
				"Camera2D.limit_left must be reset to %s's bounds after crossing %s, not left at the source area's stale value"
						% [destination_scene_path, threshold_name])
		assert_eq(camera.limit_top, int(new_bounds.position.y),
				"Camera2D.limit_top must be reset to %s's bounds after crossing %s"
						% [destination_scene_path, threshold_name])
		assert_eq(camera.limit_right, int(new_bounds.end.x),
				"Camera2D.limit_right must be reset to %s's bounds after crossing %s"
						% [destination_scene_path, threshold_name])
		assert_eq(camera.limit_bottom, int(new_bounds.end.y),
				"Camera2D.limit_bottom must be reset to %s's bounds after crossing %s"
						% [destination_scene_path, threshold_name])

	assert_signal_emit_count(GameEvents, "area_changed", 1,
			"crossing %s must emit GameEvents.area_changed exactly once" % [threshold_name])
	# NOTE: assert_signal_emitted_with_parameters()'s 4th positional argument
	# is an emission INDEX, not a failure message (see
	# test_area_transition.gd's pre-rewrite history / test_threshold_transition.gd's
	# identical note) — no trailing message string here.
	assert_signal_emitted_with_parameters(GameEvents, "area_changed", [destination_id])

	# Re-entry guard (design.md §5): landing on a real Arrival must not
	# immediately re-fire the Threshold the player just spawned into/onto. A
	# settle window long enough to notice a wrongly-fired transition, nowhere
	# near TRANSITION_TIMEOUT_TICKS.
	await wait_physics_frames(30)
	assert_eq(GameState.current_state, GameState.State.PLAYING,
			"landing on %s must not immediately re-trigger a transition — the re-entry guard must hold for real content, not just fixtures"
					% [arrival_name])
	assert_signal_emit_count(GameEvents, "area_changed", 1,
			"landing on %s must not have emitted a second area_changed during the settle window" % [arrival_name])


## Walk the player off meadow's east edge into orchard WITHOUT the full
## assertion suite above — setup-only, for tests that need to be standing in
## orchard before they can exercise something orchard-specific (its south/
## east unlinked edges, e.g.). Returns the orchard WorldArea instance, or null
## with the failure already recorded.
func _enter_orchard_via_east(world: Node, meadow: WorldArea, player: CharacterBody2D) -> WorldArea:
	var bounds: Rect2 = meadow.get_bounds_px()
	var collider: Rect2 = CollisionProbe.player_collider_extent(player)
	var start: Vector2 = _clear_approach(meadow, collider, bounds, "east")
	if is_nan(start.x) or is_nan(start.y):
		fail_test("no obstacle-free approach lane exists on meadow's east edge — cannot set up an orchard-side test")
		return null

	player.global_position = start
	player.velocity = Vector2.ZERO
	await wait_physics_frames(2)
	await _drive_player(player, "move_right", DRIVE_TICKS)
	var reached_playing: bool = await _wait_until_playing_or_timeout()
	if not reached_playing:
		fail_test("could not enter orchard via meadow's east edge — cannot set up an orchard-side test")
		return null

	var active_area: Node = world.get_node_or_null("ActiveArea")
	if active_area == null or active_area.get_child_count() == 0:
		fail_test("no instanced area found under ActiveArea after entering orchard")
		return null
	return active_area.get_child(0) as WorldArea


## Walks `player` into `edge` of `area` and asserts the parity bar for an
## edge with NO placed Threshold (meadow north/west, orchard south/east):
## still walled, still stops the player, never transitions.
func _assert_edge_walls_with_no_transition(area: WorldArea, player: CharacterBody2D,
		edge: String, action: String) -> void:
	var bounds: Rect2 = area.get_bounds_px()
	var collider: Rect2 = CollisionProbe.player_collider_extent(player)
	var start: Vector2 = _clear_approach(area, collider, bounds, edge)
	if is_nan(start.x) or is_nan(start.y):
		fail_test("no obstacle-free approach lane exists on %s's %s edge" % [area.scene_file_path, edge])
		return

	watch_signals(GameEvents)
	player.global_position = start
	player.velocity = Vector2.ZERO
	await wait_physics_frames(2)
	Input.action_press(action)
	await wait_physics_frames(DRIVE_TICKS)
	Input.action_release(action)
	player.velocity = Vector2.ZERO

	assert_eq(GameState.current_state, GameState.State.PLAYING,
			"walking into %s's %s edge (no placed Threshold there) must never change GameState away from PLAYING"
					% [area.scene_file_path, edge])
	assert_signal_not_emitted(GameEvents, "area_changed",
			"walking into an edge with no placed Threshold must never emit GameEvents.area_changed")

	# 5px of slack (matching tests/e2e/world-collision/edge_transition.md's
	# identical "a few px of slack for physics settling" convention) rather
	# than a tight 1px bound: driving continuously into a solid wall for the
	# full DRIVE_TICKS (~5s) can settle a few px deeper than the wall's exact
	# face under sustained pressure — a real move_and_slide() behavior, not a
	# containment failure, and this check's job is "did the player stay on
	# the map," not "down to the pixel, where did they stop."
	const WALL_STOP_SLACK_PX: float = 5.0
	match edge:
		"north":
			assert_gt(player.global_position.y, bounds.position.y - WALL_STOP_SLACK_PX,
					"the player must still be stopped by the north perimeter wall (design.md §7: every edge always gets a wall)")
		"south":
			assert_lt(player.global_position.y, bounds.end.y + WALL_STOP_SLACK_PX,
					"the player must still be stopped by the south perimeter wall")
		"east":
			assert_lt(player.global_position.x, bounds.end.x + WALL_STOP_SLACK_PX,
					"the player must still be stopped by the east perimeter wall")
		"west":
			assert_gt(player.global_position.x, bounds.position.x - WALL_STOP_SLACK_PX,
					"the player must still be stopped by the west perimeter wall")


# ---------------------------------------------------------------------------
# The four real crossings (test plan's Integration section)
# ---------------------------------------------------------------------------

func test_meadow_east_edge_crossing_lands_at_orchards_arrival() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var meadow: WorldArea = _get_active_area(world)
	if meadow == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return

	await _cross_and_verify(world, meadow, player, "east", "move_right",
			THRESHOLD_MEADOW_EAST, ORCHARD_SCENE_PATH, ORCHARD_ID, ARRIVAL_FROM_MEADOW_EAST)


func test_meadow_south_edge_crossing_lands_at_orchards_arrival() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var meadow: WorldArea = _get_active_area(world)
	if meadow == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return

	await _cross_and_verify(world, meadow, player, "south", "move_down",
			THRESHOLD_MEADOW_SOUTH, ORCHARD_SCENE_PATH, ORCHARD_ID, ARRIVAL_FROM_MEADOW_SOUTH)


func test_orchard_north_edge_crossing_lands_at_meadows_arrival() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var meadow: WorldArea = _get_active_area(world)
	if meadow == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return
	var orchard: WorldArea = await _enter_orchard_via_east(world, meadow, player)
	if orchard == null:
		return

	await _cross_and_verify(world, orchard, player, "north", "move_up",
			THRESHOLD_ORCHARD_NORTH, MEADOW_SCENE_PATH, MEADOW_ID, ARRIVAL_FROM_ORCHARD_NORTH)


func test_orchard_west_edge_crossing_lands_at_meadows_arrival() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var meadow: WorldArea = _get_active_area(world)
	if meadow == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return
	var orchard: WorldArea = await _enter_orchard_via_east(world, meadow, player)
	if orchard == null:
		return

	await _cross_and_verify(world, orchard, player, "west", "move_left",
			THRESHOLD_ORCHARD_WEST, MEADOW_SCENE_PATH, MEADOW_ID, ARRIVAL_FROM_ORCHARD_WEST)


# ---------------------------------------------------------------------------
# Unconditional perimeter walls (test plan: "on all four edges of both
# meadow.tscn and orchard.tscn ... including the edges that carry a placed
# Threshold" — design.md §7's collapsed API)
# ---------------------------------------------------------------------------

func test_meadow_perimeter_walls_exist_on_all_four_edges_including_linked_ones() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var meadow: WorldArea = _get_active_area(world)
	if meadow == null:
		return

	var bounds: Rect2 = meadow.get_bounds_px()
	var walls: Array[StaticBody2D] = []
	_collect_perimeter_walls(meadow, walls)

	for edge in ["north", "east", "south", "west"]:
		assert_true(_wall_covers_full_edge(walls, bounds, edge),
				("meadow.tscn must have a perimeter wall spanning the FULL %s edge — design.md §7's " +
				"collapsed WorldArea.build_perimeter_walls() builds a wall on EVERY edge " +
				"unconditionally, whether or not that edge also carries a placed Threshold. A wall " +
				"only near the CORNERS (the old mechanism's stub/trigger/stub split on a linked " +
				"edge) is not enough — this checks the whole span, not just 'something exists " +
				"nearby'.") % [edge])


func test_orchard_perimeter_walls_exist_on_all_four_edges_including_linked_ones() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var meadow: WorldArea = _get_active_area(world)
	if meadow == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return
	var orchard: WorldArea = await _enter_orchard_via_east(world, meadow, player)
	if orchard == null:
		return

	var bounds: Rect2 = orchard.get_bounds_px()
	var walls: Array[StaticBody2D] = []
	_collect_perimeter_walls(orchard, walls)

	for edge in ["north", "east", "south", "west"]:
		assert_true(_wall_covers_full_edge(walls, bounds, edge),
				("orchard.tscn must have a perimeter wall spanning the FULL %s edge — design.md §7's " +
				"collapsed WorldArea.build_perimeter_walls() builds a wall on EVERY edge " +
				"unconditionally, whether or not that edge also carries a placed Threshold. A wall " +
				"only near the CORNERS (the old mechanism's stub/trigger/stub split on a linked " +
				"edge) is not enough — this checks the whole span, not just 'something exists " +
				"nearby'.") % [edge])


# ---------------------------------------------------------------------------
# Thresholds sit inset from their edge's wall (test plan / design.md §4)
# ---------------------------------------------------------------------------

func test_meadow_east_threshold_sits_inset_from_its_wall() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var meadow: WorldArea = _get_active_area(world)
	if meadow == null:
		return

	_assert_threshold_inset_from_wall(meadow, THRESHOLD_MEADOW_EAST, "PerimeterWallEast", "east")


func test_meadow_south_threshold_sits_inset_from_its_wall() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var meadow: WorldArea = _get_active_area(world)
	if meadow == null:
		return

	_assert_threshold_inset_from_wall(meadow, THRESHOLD_MEADOW_SOUTH, "PerimeterWallSouth", "south")


func test_orchard_north_threshold_sits_inset_from_its_wall() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var meadow: WorldArea = _get_active_area(world)
	if meadow == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return
	var orchard: WorldArea = await _enter_orchard_via_east(world, meadow, player)
	if orchard == null:
		return

	_assert_threshold_inset_from_wall(orchard, THRESHOLD_ORCHARD_NORTH, "PerimeterWallNorth", "north")


func test_orchard_west_threshold_sits_inset_from_its_wall() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var meadow: WorldArea = _get_active_area(world)
	if meadow == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return
	var orchard: WorldArea = await _enter_orchard_via_east(world, meadow, player)
	if orchard == null:
		return

	_assert_threshold_inset_from_wall(orchard, THRESHOLD_ORCHARD_WEST, "PerimeterWallWest", "west")


# ---------------------------------------------------------------------------
# An edge with no placed Threshold still walls, with no transition (test
# plan / parity with today's "unlinked edge just walls" behavior)
# ---------------------------------------------------------------------------

func test_meadow_north_edge_has_no_threshold_and_still_walls_with_no_transition() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var meadow: WorldArea = _get_active_area(world)
	if meadow == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return

	await _assert_edge_walls_with_no_transition(meadow, player, "north", "move_up")


func test_meadow_west_edge_has_no_threshold_and_still_walls_with_no_transition() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var meadow: WorldArea = _get_active_area(world)
	if meadow == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return

	await _assert_edge_walls_with_no_transition(meadow, player, "west", "move_left")


func test_orchard_south_edge_has_no_threshold_and_still_walls_with_no_transition() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var meadow: WorldArea = _get_active_area(world)
	if meadow == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return
	var orchard: WorldArea = await _enter_orchard_via_east(world, meadow, player)
	if orchard == null:
		return

	await _assert_edge_walls_with_no_transition(orchard, player, "south", "move_down")


func test_orchard_east_edge_has_no_threshold_and_still_walls_with_no_transition() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var meadow: WorldArea = _get_active_area(world)
	if meadow == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return
	var orchard: WorldArea = await _enter_orchard_via_east(world, meadow, player)
	if orchard == null:
		return

	await _assert_edge_walls_with_no_transition(orchard, player, "east", "move_right")
