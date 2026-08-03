@tool
class_name WorldArea
extends Node2D
## Base class for every concrete area scene (meadow.tscn, orchard.tscn, and
## later market.tscn, a cave mouth, …).
##
## An area holds one place's `Ground` / `Solids` tile layers (world-collision
## design doc §6.1) and its props — the boulder, the trees, whatever else a
## designer drops in. `world.tscn` is the persistent shell that outlives any
## single area; it instances exactly one `WorldArea` under its `ActiveArea`
## node at a time and reparents the player into it so Y-sort has one shared
## scope to sort against (world-collision design doc §12.1).
##
## World Thresholds Slice 4 (docs/features/world-thresholds/design.md §7)
## collapses this class down to bounds-and-walls only. Everything this class
## used to own about HOW areas connect — the `neighbour_*` slots, the
## `edge_reached` signal, the corner-dead-zone/arrival-debounce machinery, the
## north-edge camera-headroom inset — is gone. Transitions are now driven
## entirely by placed `Threshold`/`Arrival` nodes (see world/thresholds/
## threshold.gd and world.gd's Threshold-driven sequence), which a designer
## places as ordinary children of an area scene, independent of this class.
##
## The one thing WorldArea still does for the transition system:
## `build_perimeter_walls()` gives EVERY edge of EVERY area an unconditional
## StaticBody2D wall, with no linked/unlinked branch. The wall is a pure
## backstop — "you can never walk off the painted floor" — that the rest of
## the system assumes holds; a placed Threshold sits inset from it so a
## designer-linked edge is always crossed before its wall is ever reached
## (design.md §7).
##
## `@tool` mirrors world_prop.gd's convention: this class has no editor-time
## behavior of its own yet, but declaring it `@tool` now means a future
## editor-time helper (e.g. a perimeter-wall preview) can be added without
## churning the base class declaration again.
##
## Design reference: docs/features/world-collision/design.md §12.1, §12.2
## (history — the neighbour-slot/edge-derived model those sections describe
## is superseded; see docs/features/world-thresholds/design.md, which
## replaces it).
## Design reference: docs/features/world-thresholds/design.md §7 (this
## class's collapsed API), §8 (the north edge may clip the character by
## default — now a content decision, not a code one), §9 (the exhaustive
## deletion table this slice implements).


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

## The four edges of get_bounds_px(). Purely an internal convenience for
## build_perimeter_walls()/_edge_rect() now — nothing outside this class
## switches on it any more (the old edge_reached signal and its Edge-typed
## payload are gone; see this class's docblock).
enum Edge { NORTH, EAST, SOUTH, WEST }


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const TILE_SIZE := Vector2i(32, 16)

## "world" physics layer bit (project.godot's [layer_names]: layer_1="world",
## layer_2="player", layer_3="interactable", layer_4="player_bounds" —
## world-thresholds design.md §6, world-collision design.md §11). Named so
## the significance of the bit is legible at the call site rather than a bare
## number. Mirrors the identically-named, identically-valued constant in
## world/props/shared/world_prop.gd — both classes build StaticBody2D
## colliders on the same physics layer, but there is no natural shared base
## to hoist a single copy onto (a WorldProp is a placed object; a perimeter
## wall is boundary geometry with no footprint, sprite, or ground anchor), so
## the small duplication is intentional.
const WORLD_LAYER_BIT: int = 1

## Thickness (px) of an auto-built perimeter wall. Not derived from
## TILE_SIZE — a wall isn't a tile, it just needs to be thick enough to
## reliably stop the player (whose collider is a 22x10 CapsuleShape2D,
## player/player.tscn) and thin enough not to visually eat into the playable
## area from outside the map's painted edge, where it sits.
const PERIMETER_WALL_THICKNESS_PX: float = 32.0


# ---------------------------------------------------------------------------
# Onready variables
# ---------------------------------------------------------------------------

@onready var _ground: TileMapLayer = $Ground


# ---------------------------------------------------------------------------
# Private variables
# ---------------------------------------------------------------------------

## True once build_perimeter_walls() has already run for this area instance.
## A plain flag rather than e.g. has_node("PerimeterWallNorth") — guards
## area-transition reloads against duplicating wall nodes under auto-renamed
## names on a second call.
var _walls_built: bool = false


# ---------------------------------------------------------------------------
# Public methods
# ---------------------------------------------------------------------------

## Area extent in world pixels, taken from the painted floor. Designers
## never re-declare geometry they already painted (cf. world-collision design
## doc §5's collision-follows-the-asset principle, applied here to area
## bounds).
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


## Build a full-span StaticBody2D wall along each of the area's four edges,
## unconditionally (world-thresholds design.md §7: "every edge always gets a
## wall ... the wall is a backstop that guarantees the player cannot leave
## the painted floor"). No branching on whether a Threshold happens to sit on
## that edge, and no north-specific camera-headroom inset — a placed
## Threshold sits inset from its wall (Threshold's own docblock) so a
## designer-linked edge is always crossed before its wall is ever reached,
## and an edge with no Threshold simply clips the character by default
## (design.md §8 — a content decision now, not a code one).
##
## Called once by world.gd right after an area is instanced and added under
## ActiveArea — both for the starting area and for every area entered via a
## transition.
func build_perimeter_walls() -> void:
	if _walls_built:
		# Already built — guards area-transition reloads against duplicating
		# wall nodes under auto-renamed names.
		return

	var bounds: Rect2 = get_bounds_px()
	_add_perimeter_wall("PerimeterWallNorth", _edge_rect(Edge.NORTH, bounds))
	_add_perimeter_wall("PerimeterWallEast", _edge_rect(Edge.EAST, bounds))
	_add_perimeter_wall("PerimeterWallSouth", _edge_rect(Edge.SOUTH, bounds))
	_add_perimeter_wall("PerimeterWallWest", _edge_rect(Edge.WEST, bounds))

	_walls_built = true


# ---------------------------------------------------------------------------
# Private methods
# ---------------------------------------------------------------------------

## The rect a wall occupies on `edge` of `bounds`. Symmetric across all four
## edges now (world-thresholds design.md §7) — the north edge no longer sits
## further in than the other three; every wall's player-facing surface is
## flush with the true painted edge.
##
## The north/south rects each run the full width PLUS one thickness past
## each side (west/east), while the west/east rects run only the exact
## bounds height. That asymmetry is deliberate and unrelated to the (now
## removed) north headroom inset: it is what makes the four corners gap-free
## without any wall needing to know about its neighbours — the extended
## north/south ends already cover the corner squares the west/east ones stop
## short of.
static func _edge_rect(edge: Edge, bounds: Rect2) -> Rect2:
	match edge:
		Edge.NORTH:
			return Rect2(
					bounds.position.x - PERIMETER_WALL_THICKNESS_PX,
					bounds.position.y - PERIMETER_WALL_THICKNESS_PX,
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


## Add one StaticBody2D + CollisionShape2D wall segment, on the "world"
## physics layer, sized and centred from `rect_px`. `rect_px` is in this
## area's local pixel space — the same space get_bounds_px() returns its
## rect in (see that method's docstring for the caveat on when those two
## spaces coincide with world/global space too).
##
## collision_mask is left at 0 for the same reason WorldProp and the Solids
## TileSet physics layer do (world-collision design doc §11): a static wall
## has nothing of its own to detect, it only needs to BE detected by
## whatever moves against it (the player).
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
