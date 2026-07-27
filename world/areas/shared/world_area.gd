@tool
class_name WorldArea
extends Node2D
## Base class for every concrete area scene (meadow.tscn, orchard.tscn, and
## later market.tscn, a cave mouth, …).
##
## An area holds one place's `Ground` / `Solids` tile layers (design doc
## §6.1) and its props — the boulder, the trees, whatever else a designer
## drops in. `world.tscn` is the persistent shell that outlives any single
## area; it instances exactly one `WorldArea` under its `ActiveArea` node at
## a time and reparents the player into it so Y-sort has one shared scope to
## sort against (design doc §12.1).
##
## Slice 10 adds the edge-transition mechanism (design doc §12.4-§12.5): a
## filled neighbour_* slot builds an Area2D trigger instead of a
## StaticBody2D wall, and this class exposes edge_reached plus the four pure
## geometry/mapping functions the transition math needs
## (opposite_edge/area_id_from_scene_path/is_debounce_armed/
## compute_entry_position). world.gd owns the actual freeze/fade/swap/spawn/
## reveal sequence; this class only owns the geometry and the
## moment-of-crossing signal.
##
## `@tool` mirrors world_prop.gd's convention: this class has no editor-time
## behavior of its own yet, but declaring it `@tool` now means a future
## editor-time helper (e.g. a perimeter-wall preview) can be added without
## churning the base class declaration again.
##
## Design reference: docs/features/world-collision/design.md §12.1, §12.2, §12.4, §12.5


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Fired when the player's body enters an open edge's trigger (design doc
## §12.4) — never fired from inside a corner dead zone, and never fired for
## the just-entered edge until the arrival debounce clears (see
## begin_entry_debounce()). world.gd connects to this on every area it
## activates and drives the transition sequence from it.
signal edge_reached(direction: Edge)


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

## The four edges of get_bounds_px(). Values must stay distinct — several
## call sites (is_debounce_armed(), compute_entry_position()) switch on them.
enum Edge { NORTH, EAST, SOUTH, WEST }


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const TILE_SIZE := Vector2i(32, 16)

## Physics layer bits (project.godot's [layer_names]: layer_1="world",
## layer_2="player", layer_3="interactable" — design doc §11). Named so the
## significance of each bit is legible at the call site rather than a bare
## number. WORLD_LAYER_BIT mirrors the identically-named, identically-valued
## constant in world/props/shared/world_prop.gd — both classes build
## StaticBody2D colliders on the same physics layer, but there is no natural
## shared base to hoist a single copy onto (a WorldProp is a placed object;
## a perimeter wall is boundary geometry with no footprint, sprite, or
## ground anchor), so the small duplication is intentional.
const WORLD_LAYER_BIT: int = 1
const PLAYER_LAYER_BIT: int = 2
const INTERACTABLE_LAYER_BIT: int = 4

## Thickness (px) of an auto-built perimeter wall or edge trigger (design doc
## §12.4). Not derived from TILE_SIZE — a wall isn't a tile, it just needs to
## be thick enough to reliably stop/detect the player (whose collider is a
## 20x10 RectangleShape2D, player/player.tscn) and thin enough not to
## visually eat into the playable area from outside the map's painted edge,
## where it sits.
const PERIMETER_WALL_THICKNESS_PX: float = 32.0

## How far south of the painted floor's true north edge the north wall's (or
## trigger's) player-facing surface sits, in px — see _edge_rect()'s doc
## comment for why only the north edge is inset like this. Chosen as one
## sprite-height (matching the AnimatedSprite2D's 32px frame height,
## player/player.tscn) so the camera always has a full sprite-height of
## headroom above the player's feet, even when they are stopped flush
## against the edge.
const NORTH_WALL_HEADROOM_INSET_PX: float = 32.0

## Corner exclusion (design doc §12.4): a horizontal edge (north/south) is
## inset 1 tile (32px, TILE_SIZE.x) from each end; a vertical edge
## (east/west) is inset 2 tiles (32px, TILE_SIZE.y * 2) from each end. Both
## come out to the same 32px because tiles are 2:1 — one constant serves
## both orientations.
const CORNER_DEAD_ZONE_PX: float = 32.0

## "One tile inward" spawn offset (design doc §12.5), per crossed axis.
const ENTRY_OFFSET_EAST_WEST_PX: float = 32.0    # TILE_SIZE.x
const ENTRY_OFFSET_NORTH_SOUTH_PX: float = 16.0  # TILE_SIZE.y

## Arrival debounce distance (design doc §12.4): 0.5 tile, per crossed axis.
const DEBOUNCE_EAST_WEST_PX: float = 16.0    # 0.5 * TILE_SIZE.x
const DEBOUNCE_NORTH_SOUTH_PX: float = 8.0   # 0.5 * TILE_SIZE.y


# ---------------------------------------------------------------------------
# Exported variables
# ---------------------------------------------------------------------------

## The scenes reached by walking off each edge, as a `.tscn` path. An empty
## string is a hard boundary (a wall, not a doorway). These are genuine new
## information — you cannot derive which area lies north — so, unlike the
## bounds below, they are declared by hand (design doc §12.2).
##
## A file path `String`, not a `PackedScene` resource reference: two areas
## that link back to each other (the normal case) would each embed an
## `ext_resource` pointing at the other if this were `PackedScene`, and
## Godot's loader deadlocks on that cycle at parse time. A path string has
## no such reference for the loader to eagerly resolve — world.gd calls
## load() on it at transition time instead (design doc §12.2, §12.5).
@export_file("*.tscn") var neighbour_north: String = ""
@export_file("*.tscn") var neighbour_east: String = ""
@export_file("*.tscn") var neighbour_south: String = ""
@export_file("*.tscn") var neighbour_west: String = ""


# ---------------------------------------------------------------------------
# Onready variables
# ---------------------------------------------------------------------------

@onready var _ground: TileMapLayer = $Ground


# ---------------------------------------------------------------------------
# Private variables
# ---------------------------------------------------------------------------

## True once build_perimeter_walls() has already run for this area instance.
## A plain flag rather than e.g. `has_node("PerimeterWallNorth")`: that node
## only exists when `neighbour_north` is empty, so an area WITH a north
## neighbour would never see a has_node guard trigger — a second call would
## then duplicate the OTHER walls/triggers under auto-renamed names, which
## is exactly the bug the guard exists to prevent. A flag has no such blind
## spot: it is set once build_perimeter_walls() has run, full stop,
## regardless of which (if any) walls/triggers that run actually built.
var _walls_built: bool = false

## The edge the player most recently arrived through, as an int so it can
## hold the "no debounce active" sentinel (-1) that Edge's own values
## (0-3) don't have room for. Set by begin_entry_debounce(); cleared (armed)
## once the player's distance from that edge exceeds the design doc §12.4
## threshold. Design doc §12.5's own correction note: this should never
## actually be load-bearing once compute_entry_position() places the player
## correctly clear of the entry edge's trigger zone — it exists purely as a
## safety margin against physics-timing/reparenting jitter on the transition
## frame, so its absence of effect in practice is expected, not a bug.
var _debounce_edge: int = -1
var _debounce_armed: bool = true


# ---------------------------------------------------------------------------
# Built-in overrides
# ---------------------------------------------------------------------------

## Watches the (already-armed-or-not) entry debounce and re-arms it once the
## player has walked far enough from the edge they just arrived through
## (design doc §12.4). Skipped in the editor (@tool guard) since there is no
## live player to measure against at edit time.
##
## Reads the player via get_node_or_null("Player") rather than a stored
## reference: world.gd reparents the persistent Player node into this area
## (design doc §12.1) under that exact name, so once the reparent has
## happened this area's own tree already has everything needed — no extra
## wiring required, and it degrades to a harmless no-op before the reparent
## or in a bare (player-less) test instantiation.
func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _debounce_armed or _debounce_edge < 0:
		return

	var player: CharacterBody2D = get_node_or_null("Player") as CharacterBody2D
	if player == null:
		return

	var bounds: Rect2 = get_bounds_px()
	var edge: Edge = _debounce_edge as Edge
	var boundary: float = _playable_boundary(edge, bounds)
	var distance: float
	if edge == Edge.EAST or edge == Edge.WEST:
		distance = absf(player.global_position.x - boundary)
	else:
		distance = absf(player.global_position.y - boundary)

	if is_debounce_armed(edge, distance):
		_debounce_armed = true


# ---------------------------------------------------------------------------
# Public methods
# ---------------------------------------------------------------------------

## Area extent in world pixels, taken from the painted floor. Designers
## never re-declare geometry they already painted (cf. design doc §5's
## collision-follows-the-asset principle, applied here to area bounds).
##
## get_used_rect() returns the tile-coordinate bounding box of painted cells;
## this scales both its position and size by TILE_SIZE to convert tile-space
## to pixel-space.
##
## Returned rect is in $Ground's LOCAL pixel space. That is only the same as
## this WorldArea's local space (as build_perimeter_walls() below assumes)
## and world/global space (as world.gd's _set_camera_limits() assumes) while
## Ground, this WorldArea's root, and ActiveArea all sit at (0, 0) — true for
## every area today. If that ever changes, callers needing world-space should
## go through `_ground.to_global(...)` instead of using this rect directly.
## https://docs.godotengine.org/en/stable/classes/class_tilemaplayer.html#class-tilemaplayer-method-get-used-rect
func get_bounds_px() -> Rect2:
	var cells := _ground.get_used_rect()
	return Rect2(Vector2(cells.position) * Vector2(TILE_SIZE),
			Vector2(cells.size) * Vector2(TILE_SIZE))


## Build, along each edge of get_bounds_px(), either:
##   - a StaticBody2D wall (design doc §12.4's "no neighbour -> an invisible
##     wall"), spanning the FULL edge, when that edge's neighbour_* slot is
##     empty; or
##   - three pieces occupying that same full-edge rect between them (§12.4's
##     "a neighbour -> an open edge with a trigger", combined with its
##     corner-dead-zone rule), when the slot is filled: a small StaticBody2D
##     stub over each of the two 32x32px corner squares, and an Area2D
##     trigger on the interactable layer over the active stretch in between.
##
## The corner stubs are what makes "corner squares are ordinary walkable
## ground you just can't transition from" (design doc §12.4) an actual
## containment guarantee rather than a handler-side suppression: a player
## standing in a corner square is stopped by solid geometry exactly like they
## would be on an unlinked edge, not merely denied a signal while free to
## walk straight through into the void. See _linked_edge_rects()'s doc
## comment for the exact three-way split.
##
## Called once by world.gd right after an area is instanced and added under
## ActiveArea — both for the starting area and for every area entered via a
## transition.
func build_perimeter_walls() -> void:
	if _walls_built:
		# Already built — guards area-transition reloads against duplicating
		# wall/trigger nodes under auto-renamed names.
		return

	var bounds: Rect2 = get_bounds_px()

	_build_edge("PerimeterWallNorth", "EdgeTriggerNorth", Edge.NORTH, neighbour_north, bounds)
	_build_edge("PerimeterWallEast", "EdgeTriggerEast", Edge.EAST, neighbour_east, bounds)
	_build_edge("PerimeterWallSouth", "EdgeTriggerSouth", Edge.SOUTH, neighbour_south, bounds)
	_build_edge("PerimeterWallWest", "EdgeTriggerWest", Edge.WEST, neighbour_west, bounds)

	_walls_built = true


## Which neighbour_* export corresponds to `edge`. A small lookup so world.gd
## doesn't need its own copy of the Edge-to-export mapping.
func neighbour_for_edge(edge: Edge) -> String:
	match edge:
		Edge.NORTH:
			return neighbour_north
		Edge.EAST:
			return neighbour_east
		Edge.SOUTH:
			return neighbour_south
		Edge.WEST:
			return neighbour_west
	return ""


## Called by world.gd right after placing the player on the opposite edge of
## a freshly-entered area (design doc §12.5's step 4, feeding §12.4's
## arrival debounce). Marks `edge` as the one the player just arrived
## through, inert until _physics_process() observes the player has walked
## the required distance away from it.
func begin_entry_debounce(edge: Edge) -> void:
	_debounce_edge = edge
	_debounce_armed = false


# ---------------------------------------------------------------------------
# Public static methods — pure functions, design doc §12.4/§12.5
# ---------------------------------------------------------------------------
#
# These four are kept static and free of any scene-tree state so the
# opposite-edge spawn mechanism can be unit-tested independently of a live
# WorldArea instance (see tests/unit/world/areas/shared/
# test_world_area_edge_transition.gd). WorldArea is the natural owner: every
# one of them operates purely on Edge/geometry concepts this class already
# owns (TILE_SIZE, get_bounds_px(), Edge/edge_reached above).

## design doc §12.5's exit-edge -> entry-edge table.
static func opposite_edge(edge: Edge) -> Edge:
	match edge:
		Edge.NORTH:
			return Edge.SOUTH
		Edge.SOUTH:
			return Edge.NORTH
		Edge.EAST:
			return Edge.WEST
		Edge.WEST:
			return Edge.EAST
	return edge


## design doc §12.5 step 5: the newly-loaded area's scene file name without
## its .tscn extension (e.g. "res://world/areas/meadow.tscn" -> "meadow").
static func area_id_from_scene_path(scene_path: String) -> StringName:
	return StringName(scene_path.get_file().get_basename())


## True if `distance_from_edge_px` clears the arrival debounce threshold for
## `edge` (design doc §12.4: 0.5 tile — 16px east/west, 8px north/south). A
## plain distance check, not a timer: calling this again with the same
## distance gives the same answer, with no hidden state.
static func is_debounce_armed(edge: Edge, distance_from_edge_px: float) -> bool:
	var threshold: float = (
			DEBOUNCE_EAST_WEST_PX if (edge == Edge.EAST or edge == Edge.WEST)
			else DEBOUNCE_NORTH_SOUTH_PX)
	return distance_from_edge_px > threshold


## design doc §12.5's opposite-edge spawn maths: given the coordinate the
## player exited `exit_edge` at and the newly-entered area's bounds, compute
## where they should land on the opposite edge.
##
## The "one tile inward" offset is measured from the entry edge's
## PLAYABLE-FACING boundary (the same boundary _edge_rect()/build_perimeter_
## walls() uses to place a wall or trigger on that edge) — not always the raw
## painted edge of `new_bounds`. These coincide for south/east/west, but not
## north: the north edge's playable boundary sits NORTH_WALL_HEADROOM_INSET_PX
## further in than the true edge, and its trigger zone spans that entire
## gap (design doc §12.4). Using _playable_boundary() for every edge — rather
## than new_bounds's raw position/end directly — is what keeps this uniform
## across all four edges instead of a north-specific branch in the offset
## maths itself.
##
## The tangential (carried-over) coordinate is clamped into the new area's
## valid range when it doesn't already fit (e.g. a smaller destination area),
## kept clear of that area's own corner dead zones (design doc §12.5's
## clamp-toward-midpoint note).
static func compute_entry_position(exit_coordinate: float, exit_edge: Edge, new_bounds: Rect2) -> Vector2:
	var entry_edge: Edge = opposite_edge(exit_edge)
	var boundary: float = _playable_boundary(entry_edge, new_bounds)

	# Two actual shapes, not four per-edge branches: the crossed axis gets the
	# playable boundary plus/minus the "one tile inward" offset (sign points
	# INTO the area — west/north entries add, east/south subtract); the
	# tangential axis carries the exit coordinate over, clamped clear of this
	# area's own corner dead zones.
	if entry_edge == Edge.WEST or entry_edge == Edge.EAST:
		var direction_sign: float = 1.0 if entry_edge == Edge.WEST else -1.0
		var crossed: float = boundary + direction_sign * ENTRY_OFFSET_EAST_WEST_PX
		var tangential: float = clampf(exit_coordinate,
				new_bounds.position.y + CORNER_DEAD_ZONE_PX,
				new_bounds.end.y - CORNER_DEAD_ZONE_PX)
		return Vector2(crossed, tangential)
	else:
		var direction_sign: float = 1.0 if entry_edge == Edge.NORTH else -1.0
		var crossed: float = boundary + direction_sign * ENTRY_OFFSET_NORTH_SOUTH_PX
		var tangential: float = clampf(exit_coordinate,
				new_bounds.position.x + CORNER_DEAD_ZONE_PX,
				new_bounds.end.x - CORNER_DEAD_ZONE_PX)
		return Vector2(tangential, crossed)


# ---------------------------------------------------------------------------
# Private methods
# ---------------------------------------------------------------------------

## The playable-facing boundary line for `edge` of `bounds` — the coordinate
## a wall's or trigger's player-facing surface sits at. Identical to the raw
## painted edge for south/east/west; inset NORTH_WALL_HEADROOM_INSET_PX for
## north (see _edge_rect()'s doc comment). Shared by _edge_rect() (wall/
## trigger placement) and compute_entry_position() (spawn placement) so both
## agree on where each edge's "real" boundary is without duplicating the
## north special-case in two places.
static func _playable_boundary(edge: Edge, bounds: Rect2) -> float:
	match edge:
		Edge.NORTH:
			return bounds.position.y + NORTH_WALL_HEADROOM_INSET_PX
		Edge.SOUTH:
			return bounds.end.y
		Edge.WEST:
			return bounds.position.x
		Edge.EAST:
			return bounds.end.x
	return 0.0


## The rect a wall or trigger occupies on `edge` of `bounds` — identical
## geometry for either, per design doc §12.4 ("the open-edge trigger occupies
## the exact same rect a wall would have occupied on that edge").
##
## The north/south rects each run the full width PLUS one thickness past
## each side (west/east), while the west/east rects run only the exact
## bounds height. That asymmetry is deliberate: it is what makes the four
## corners gap-free without any wall/trigger needing to know about its
## neighbours — the extended north/south ends already cover the corner
## squares the west/east ones stop short of.
##
## The north rect carries a SECOND, unrelated asymmetry: its player-facing
## surface is inset NORTH_WALL_HEADROOM_INSET_PX south of the true painted
## edge, rather than sitting flush on it like the other three do. This
## exists because the player is feet-anchored
## (AnimatedSprite2D.offset = Vector2(0, -16), player/player.tscn) while
## Camera2D.limit_top (world.gd's _set_camera_limits()) clamps the camera's
## VIEW RECT — not the camera node — to the exact same bounds.position.y.
## With a wall/trigger flush against that edge, stopping the player there
## put their entire sprite above the clamped view rect: zero pixels of the
## character visible (confirmed empirically). Insetting gives the camera a
## permanent sprite-height of headroom above the player no matter how far
## north they walk. The strip of painted ground between the true edge and
## the inset boundary becomes a visual-only backdrop the player can see but
## never stand on — a common convention in three-quarter/isometric views.
## South/east/west don't have this problem (south already leaves headroom
## below the player; east/west only clip a few px of the sprite's
## transparent side padding), so only north gets the inset.
static func _edge_rect(edge: Edge, bounds: Rect2) -> Rect2:
	match edge:
		Edge.NORTH:
			return Rect2(
					bounds.position.x - PERIMETER_WALL_THICKNESS_PX,
					bounds.position.y - PERIMETER_WALL_THICKNESS_PX + NORTH_WALL_HEADROOM_INSET_PX,
					bounds.size.x + PERIMETER_WALL_THICKNESS_PX * 2.0,
					PERIMETER_WALL_THICKNESS_PX)
		Edge.SOUTH:
			return Rect2(
					bounds.position.x - PERIMETER_WALL_THICKNESS_PX,
					bounds.end.y,
					bounds.size.x + PERIMETER_WALL_THICKNESS_PX * 2.0,
					PERIMETER_WALL_THICKNESS_PX)
		Edge.WEST:
			return Rect2(
					bounds.position.x - PERIMETER_WALL_THICKNESS_PX,
					bounds.position.y,
					PERIMETER_WALL_THICKNESS_PX,
					bounds.size.y)
		Edge.EAST:
			return Rect2(
					bounds.end.x,
					bounds.position.y,
					PERIMETER_WALL_THICKNESS_PX,
					bounds.size.y)
	return Rect2()


## Split `edge`'s full rect (_edge_rect() above — the same one an unlinked
## wall would occupy) into three pieces along its tangential axis (x for
## north/south, y for east/west), carving the CORNER_DEAD_ZONE_PX-wide
## exclusion at each end into its own small piece and leaving the active
## (open) middle stretch for the Area2D trigger (design doc §12.4's corner
## dead zones, made structural — see build_perimeter_walls()'s doc comment).
##
## The three returned rects exactly tile the full edge rect with no gap and
## no overlap: rects[0] ∪ rects[1] ∪ rects[2] == _edge_rect(edge, bounds).
## Order is [first-end stub, middle trigger, second-end stub] — west→east for
## a horizontal edge (north/south), north→south for a vertical edge
## (east/west).
##
## For north/south, the full rect already extends PERIMETER_WALL_THICKNESS_PX
## past `bounds` on each side to close the corner (see _edge_rect()'s doc
## comment on that asymmetry) — the corner dead zone is a SEPARATE, additional
## inset measured from `bounds` itself (not from the already-extended full
## rect), so each stub spans from the full rect's own end to
## bounds.position.x/end.x ± CORNER_DEAD_ZONE_PX. For east/west, the full rect
## already runs flush with bounds' top/bottom (those two edges are never
## corner-extended), so both stubs sit entirely inside it.
static func _linked_edge_rects(edge: Edge, bounds: Rect2) -> Array[Rect2]:
	var full: Rect2 = _edge_rect(edge, bounds)
	if edge == Edge.NORTH or edge == Edge.SOUTH:
		var west_end: float = bounds.position.x + CORNER_DEAD_ZONE_PX
		var east_end: float = bounds.end.x - CORNER_DEAD_ZONE_PX
		var west_stub := Rect2(full.position.x, full.position.y, west_end - full.position.x, full.size.y)
		var middle := Rect2(west_end, full.position.y, east_end - west_end, full.size.y)
		var east_stub := Rect2(east_end, full.position.y, full.end.x - east_end, full.size.y)
		return [west_stub, middle, east_stub]
	else:
		# The north end is measured from the north edge's PLAYABLE-FACING
		# boundary (_playable_boundary()), not the raw painted bounds.position.y
		# — the north wall/trigger's own player-facing surface already sits
		# NORTH_WALL_HEADROOM_INSET_PX south of the true edge (see
		# _edge_rect()'s doc comment), so a dead zone measured from the raw
		# edge would double-count that inset as walkable space it isn't: the
		# player's collider bottoms out inside the still-solid headroom strip
		# before ever reaching a coordinate the naive dead-zone band covered,
		# leaving the NE/NW corners with zero px of actual exclusion (a
		# transition could start right at those corners). South has no such
		# inset, so south_end is still measured from the raw bounds.end.y.
		var north_end: float = _playable_boundary(Edge.NORTH, bounds) + CORNER_DEAD_ZONE_PX
		var south_end: float = bounds.end.y - CORNER_DEAD_ZONE_PX
		var north_stub := Rect2(full.position.x, full.position.y, full.size.x, north_end - full.position.y)
		var middle := Rect2(full.position.x, north_end, full.size.x, south_end - north_end)
		var south_stub := Rect2(full.position.x, south_end, full.size.x, full.end.y - south_end)
		return [north_stub, middle, south_stub]


## Build whichever of a wall or a stub/trigger/stub split `edge` needs, based
## on whether `neighbour_path` is set.
func _build_edge(wall_name: String, trigger_name: String, edge: Edge, neighbour_path: String, bounds: Rect2) -> void:
	if neighbour_path.is_empty():
		_add_perimeter_wall(wall_name, _edge_rect(edge, bounds))
		return

	var rects: Array[Rect2] = _linked_edge_rects(edge, bounds)
	_add_perimeter_wall(wall_name + "CornerA", rects[0])
	_add_edge_trigger(trigger_name, rects[1], edge)
	_add_perimeter_wall(wall_name + "CornerB", rects[2])


## Add one StaticBody2D + CollisionShape2D wall segment, on the "world"
## physics layer, sized and centred from `rect_px`. `rect_px` is in this
## area's local pixel space — the same space get_bounds_px() returns its
## rect in (see that method's docstring for the caveat on when those two
## spaces coincide with world/global space too).
##
## collision_mask is left at 0 for the same reason WorldProp and the Solids
## TileSet physics layer do (design doc §11): a static wall has nothing of
## its own to detect, it only needs to BE detected by whatever moves against
## it (the player).
func _add_perimeter_wall(node_name: String, rect_px: Rect2) -> void:
	var body := StaticBody2D.new()
	body.name = node_name
	body.collision_layer = WORLD_LAYER_BIT
	body.collision_mask = 0
	body.position = rect_px.get_center()
	add_child(body)

	var rect_shape := RectangleShape2D.new()
	rect_shape.size = rect_px.size

	var collision := CollisionShape2D.new()
	collision.shape = rect_shape
	body.add_child(collision)


## Add one Area2D + CollisionShape2D open-edge trigger, on the "interactable"
## physics layer, sized and centred from `rect_px` — the ACTIVE (non-corner)
## stretch of this edge, per _linked_edge_rects(). Detects the player layer
## only (design doc §11's "Interaction Area2Ds | interactable | player").
##
## The corner dead zone is enforced by geometry, not here: the two corner
## squares flanking this rect are covered by ordinary StaticBody2D stubs
## (_build_edge()), so a body can only ever enter THIS Area2D from within the
## already-excluded-corners active stretch — there is nothing left for this
## handler to suppress on that account. See build_perimeter_walls()'s doc
## comment for why this replaced an earlier handler-side suppression that
## left the corner squares physically open (a containment bug).
func _add_edge_trigger(node_name: String, rect_px: Rect2, edge: Edge) -> void:
	var trigger := Area2D.new()
	trigger.name = node_name
	trigger.collision_layer = INTERACTABLE_LAYER_BIT
	trigger.collision_mask = PLAYER_LAYER_BIT
	trigger.position = rect_px.get_center()
	add_child(trigger)

	var rect_shape := RectangleShape2D.new()
	rect_shape.size = rect_px.size

	var collision := CollisionShape2D.new()
	collision.shape = rect_shape
	trigger.add_child(collision)

	trigger.body_entered.connect(_on_edge_trigger_body_entered.bind(edge))


## Handles a body entering an open-edge trigger. Emits edge_reached unless
## the body isn't the player, or `edge` is the entry edge and the arrival
## debounce hasn't cleared yet (design doc §12.4). The corner-dead-zone rule
## no longer needs a check here — see _add_edge_trigger()'s doc comment.
func _on_edge_trigger_body_entered(body: Node2D, edge: Edge) -> void:
	if not (body is CharacterBody2D):
		return
	if edge == _debounce_edge and not _debounce_armed:
		return

	edge_reached.emit(edge)
