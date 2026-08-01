class_name CollisionProbe
extends RefCounted
## Test helper: finds a **clear lane** through a loaded `WorldArea` — a row or
## column the player can be driven along without hitting anything except the
## thing the test is actually about.
##
## Why this exists: several movement tests need to drive the player across the
## meadow to reach a perimeter wall or an edge trigger. They used to do that
## along hard-coded coordinates, chosen by hand to dodge "every obstacle
## painted or placed as of this writing" and documented as such in a comment.
## That worked exactly until a designer painted something new. When
## `meadow.tscn`'s `Ground` layer gained collidable edge tiles (design doc
## §6.1), four such tests started failing — not because the behaviour they
## assert broke, but because their lanes now ran through a fence. A stale lane
## is the worst kind of test failure: it points at the wrong thing, and the
## obvious fix (pick new magic numbers) buys only until the next paint pass.
##
## So: derive the lane from the area's ACTUAL collision at run time. A test
## says "find me a row I can cross the whole map on" and gets one, or a clear
## failure if the map no longer has one.
##
## Collision is read from both `TileMapLayer`s (a collidable tile blocks
## movement on either layer — design doc §6.1) and from prop colliders.
## Perimeter walls and edge triggers are deliberately EXCLUDED: they are the
## boundary geometry these tests exist to drive into, not obstacles to route
## around.
##
## Design reference: docs/features/world-collision/design.md §6.1, §10
## Test plan: docs/features/world-collision/player-collider-capsule-test-plan.md

# Auto-built boundary nodes (world_area.gd's build_perimeter_walls()). Named
# by prefix because a linked edge splits into "<name>CornerA"/"<name>CornerB"
# stubs around its trigger, so an exact-name match would miss two thirds of
# them.
const PERIMETER_NODE_PREFIXES: Array[String] = ["PerimeterWall", "EdgeTrigger"]

# How finely to step through candidate lanes. 4px is well under the player's
# 10px collider depth, so no gap wide enough to walk through can be stepped
# over without being tried.
const LANE_SEARCH_STEP_PX: float = 4.0

# Extra clearance required on every side of the player's collider before a lane
# counts as clear. Keeps the search from returning a lane that technically fits
# but leaves the player grazing a polygon, where a pixel of physics jitter
# could turn a passing test into a flaky one.
const LANE_CLEARANCE_MARGIN_PX: float = 3.0


## The player's collider extent relative to their node origin, read from the
## live scene rather than hard-coded — so lanes stay correct when the collider
## is re-shaped (as it was when it became a capsule, design doc §10).
##
## Handles both shapes the player has used: CapsuleShape2D (current — rotated
## 90°, so its height runs along X) and RectangleShape2D (the earlier form,
## still supported here so this helper isn't a second thing to update if the
## collider is ever reverted or a variant is tried).
static func player_collider_extent(player: CharacterBody2D) -> Rect2:
	var collision: CollisionShape2D = (
			player.get_node_or_null("CollisionShape2D") as CollisionShape2D)
	if collision == null:
		return Rect2()

	var half: Vector2
	if collision.shape is CapsuleShape2D:
		var capsule: CapsuleShape2D = collision.shape as CapsuleShape2D
		# Authored vertically; the node's 90° rotation lays it on its side.
		var lengthwise: float = capsule.height / 2.0
		var across: float = capsule.radius
		var horizontal: bool = absf(sin(collision.rotation)) > 0.5
		half = Vector2(lengthwise, across) if horizontal else Vector2(across, lengthwise)
	elif collision.shape is RectangleShape2D:
		half = (collision.shape as RectangleShape2D).size / 2.0
	else:
		return Rect2()

	return Rect2(collision.position - half, half * 2.0)


## Every collidable polygon in `area`, in the area's local pixel space (which
## coincides with global space for every area today — see
## WorldArea.get_bounds_px()'s note on that assumption).
##
## Tile polygons are read from `TileData` rather than from the generated
## physics bodies, because the exact polygon is what matters: the meadow's
## edge-variant tiles carry thin strips along one or two borders, so treating
## a collidable cell as a full solid 32x16 block would reject lanes that are
## in fact perfectly walkable.
static func obstacle_polygons(area: Node2D) -> Array[PackedVector2Array]:
	var polygons: Array[PackedVector2Array] = []
	_collect_tile_polygons(area, polygons)
	_collect_body_polygons(area, polygons)
	return polygons


## Find a horizontal lane: a player-origin Y at which the player can travel the
## full `x_min`..`x_max` span without touching any obstacle.
##
## `y_min`/`y_max` bound the search. Candidates are tried from the midpoint
## outward, so the returned lane sits as close to the centre of the search band
## as the map allows — which keeps tests that mean "cross the middle of this
## edge" reading the way they intend.
##
## Returns NAN when no lane exists, which callers must treat as a test failure
## (the map has been painted shut) rather than silently skipping.
static func find_clear_row(area: Node2D, collider: Rect2, x_min: float, x_max: float,
		y_min: float, y_max: float) -> float:
	var obstacles: Array[PackedVector2Array] = obstacle_polygons(area)
	for candidate_y in _candidates(y_min, y_max):
		var swept := _swept_rect(collider, Vector2(x_min, candidate_y), Vector2(x_max, candidate_y))
		if _is_clear(swept, obstacles):
			return candidate_y
	return NAN


## The vertical mirror of find_clear_row(): a player-origin X at which the
## player can travel the full `y_min`..`y_max` span untouched.
static func find_clear_column(area: Node2D, collider: Rect2, y_min: float, y_max: float,
		x_min: float, x_max: float) -> float:
	var obstacles: Array[PackedVector2Array] = obstacle_polygons(area)
	for candidate_x in _candidates(x_min, x_max):
		var swept := _swept_rect(collider, Vector2(candidate_x, y_min), Vector2(candidate_x, y_max))
		if _is_clear(swept, obstacles):
			return candidate_x
	return NAN


## True if the player can travel from `from` to `to` (both player-ORIGIN
## positions) without their collider touching any of `obstacles`.
##
## The building block find_clear_row()/find_clear_column() search with, exposed
## on its own for callers that already know which path they want to check and
## only need to know whether it is clear — e.g. picking a tile to drive across.
## Pass `obstacles` from obstacle_polygons(); it is a parameter rather than
## re-derived here so a caller testing many paths against one area pays for the
## (comparatively expensive) collection once.
static func is_path_clear(collider: Rect2, from: Vector2, to: Vector2,
		obstacles: Array[PackedVector2Array]) -> bool:
	return _is_clear(_swept_rect(collider, from, to), obstacles)


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Candidate lane coordinates between `low` and `high`, ordered from the
## midpoint outward (mid, mid-step, mid+step, mid-2*step, …).
static func _candidates(low: float, high: float) -> Array[float]:
	var out: Array[float] = []
	if high < low:
		return out

	var mid: float = (low + high) / 2.0
	out.append(mid)
	var offset: float = LANE_SEARCH_STEP_PX
	while mid - offset >= low or mid + offset <= high:
		if mid - offset >= low:
			out.append(mid - offset)
		if mid + offset <= high:
			out.append(mid + offset)
		offset += LANE_SEARCH_STEP_PX
	return out


## The region the player's collider sweeps travelling from `from` to `to`, as a
## polygon, inflated by LANE_CLEARANCE_MARGIN_PX. Both endpoints are player
## ORIGIN positions; `collider` is the extent relative to that origin.
static func _swept_rect(collider: Rect2, from: Vector2, to: Vector2) -> PackedVector2Array:
	var start := Rect2(from + collider.position, collider.size)
	var swept: Rect2 = start.merge(Rect2(to + collider.position, collider.size))
	swept = swept.grow(LANE_CLEARANCE_MARGIN_PX)
	return PackedVector2Array([
		swept.position,
		Vector2(swept.end.x, swept.position.y),
		swept.end,
		Vector2(swept.position.x, swept.end.y),
	])


## True if `swept` overlaps none of `obstacles`.
##
## Uses real polygon intersection rather than bounding-box tests: several of
## the meadow's edge tiles have an L-shaped polygon whose bounding box is the
## whole 32x16 cell, so a bbox test would reject lanes through the open part of
## the L — and, on a densely painted map, could reject every lane there is.
## https://docs.godotengine.org/en/stable/classes/class_geometry2d.html#class-geometry2d-method-intersect-polygons
static func _is_clear(swept: PackedVector2Array, obstacles: Array[PackedVector2Array]) -> bool:
	for obstacle in obstacles:
		if not Geometry2D.intersect_polygons(swept, obstacle).is_empty():
			return false
	return true


## Collision polygons from every TileMapLayer under `area`, converted from
## tile-local to area-local coordinates.
static func _collect_tile_polygons(area: Node2D, out: Array[PackedVector2Array]) -> void:
	for child in area.get_children():
		var layer: TileMapLayer = child as TileMapLayer
		if layer == null:
			continue
		for cell in layer.get_used_cells():
			var tile_data: TileData = layer.get_cell_tile_data(cell)
			if tile_data == null:
				continue
			var cell_centre: Vector2 = layer.position + layer.map_to_local(cell)
			for i in tile_data.get_collision_polygons_count(0):
				var points: PackedVector2Array = tile_data.get_collision_polygon_points(0, i)
				var translated := PackedVector2Array()
				for point in points:
					translated.append(point + cell_centre)
				out.append(translated)


## Collider rects from every prop StaticBody2D under `area`, skipping the
## auto-built perimeter walls and edge triggers (see PERIMETER_NODE_PREFIXES).
static func _collect_body_polygons(area: Node2D, out: Array[PackedVector2Array]) -> void:
	for body in area.find_children("*", "StaticBody2D", true, false):
		if _is_perimeter_node(body):
			continue
		for shape_child in (body as Node).get_children():
			var collision: CollisionShape2D = shape_child as CollisionShape2D
			if collision == null:
				continue
			var rect_shape: RectangleShape2D = collision.shape as RectangleShape2D
			if rect_shape == null:
				continue
			var centre: Vector2 = (body as Node2D).position + collision.position
			var rect := Rect2(centre - rect_shape.size / 2.0, rect_shape.size)
			out.append(PackedVector2Array([
				rect.position,
				Vector2(rect.end.x, rect.position.y),
				rect.end,
				Vector2(rect.position.x, rect.end.y),
			]))


## True if `node` (or an ancestor up to the area root) is one of the auto-built
## boundary nodes. Walks ancestors because a wall's collider is a child node,
## and callers may hand in either.
static func _is_perimeter_node(node: Node) -> bool:
	var current: Node = node
	while current != null:
		for prefix in PERIMETER_NODE_PREFIXES:
			if String(current.name).begins_with(prefix):
				return true
		current = current.get_parent()
	return false
