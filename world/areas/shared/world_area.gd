@tool
class_name WorldArea
extends Node2D
## Base class for every concrete area scene (meadow.tscn, and later
## market.tscn, a cave mouth, …).
##
## An area holds one place's `Ground` / `Solids` tile layers (design doc
## §6.1) and its props — the boulder, the trees, whatever else a designer
## drops in. `world.tscn` is the persistent shell that outlives any single
## area; it instances exactly one `WorldArea` under its `ActiveArea` node at
## a time and reparents the player into it so Y-sort has one shared scope to
## sort against (design doc §12.1).
##
## `@tool` mirrors world_prop.gd's convention: this class has no editor-time
## behavior of its own yet, but declaring it `@tool` now means a future
## editor-time helper (e.g. a perimeter-wall preview) can be added without
## churning the base class declaration again.
##
## Design reference: docs/features/world-collision/design.md §12.1, §12.2, §12.4


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const TILE_SIZE := Vector2i(32, 16)

## Physics layer bit for "world" (project.godot [layer_names] 2d_physics/
## layer_1, design doc §11). Named so the significance of the bit is legible
## at the call site rather than a bare `1`. Mirrors the identically-named,
## identically-valued constant in world/props/shared/world_prop.gd — both
## classes build StaticBody2D colliders on the same physics layer, but there
## is no natural shared base to hoist a single copy onto (a WorldProp is a
## placed object; a perimeter wall is boundary geometry with no footprint,
## sprite, or ground anchor), so the small duplication is intentional.
const WORLD_LAYER_BIT := 1

## Thickness (px) of an auto-built perimeter wall (design doc §12.4). Not
## derived from TILE_SIZE — a wall isn't a tile, it just needs to be thick
## enough to reliably stop the player (whose collider is a 20x10
## RectangleShape2D, player/player.tscn) and thin enough not to visually
## eat into the playable area from outside the map's painted edge, where it
## sits.
const PERIMETER_WALL_THICKNESS_PX: float = 32.0

## How far south of the painted floor's true north edge the north wall's
## player-facing (south) surface sits, in px — see build_perimeter_walls()'s
## doc comment for why only the north wall is inset like this. Chosen as one
## sprite-height (matching the AnimatedSprite2D's 32px frame height,
## player/player.tscn) so the camera always has a full sprite-height of
## headroom above the player's feet, even when they are stopped flush
## against the wall.
const NORTH_WALL_HEADROOM_INSET_PX: float = 32.0


# ---------------------------------------------------------------------------
# Exported variables
# ---------------------------------------------------------------------------

## The scenes reached by walking off each edge. An empty slot is a hard
## boundary (a wall, not a doorway). These are genuine new information — you
## cannot derive which area lies north — so, unlike the bounds below, they
## are declared by hand (design doc §12.2).
##
## Unused until slice 10's edge-linking work; declared now so every area
## scene authored from here on already has the slots to fill in later.
@export var neighbour_north: PackedScene
@export var neighbour_east: PackedScene
@export var neighbour_south: PackedScene
@export var neighbour_west: PackedScene


# ---------------------------------------------------------------------------
# Onready variables
# ---------------------------------------------------------------------------

@onready var _ground: TileMapLayer = $Ground


# ---------------------------------------------------------------------------
# Private variables
# ---------------------------------------------------------------------------

## True once build_perimeter_walls() has already run for this area instance.
## A plain flag rather than e.g. `has_node("PerimeterWallNorth")`: that node
## only exists when `neighbour_north == null`, so an area WITH a north
## neighbour (slice 10+) would never see a has_node guard trigger — a second
## call would then duplicate the OTHER three walls under auto-renamed names,
## which is exactly the bug the guard exists to prevent. A flag has no such
## blind spot: it is set once build_perimeter_walls() has run, full stop,
## regardless of which (if any) walls that run actually built.
var _walls_built: bool = false


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
## every area today, but not guaranteed once slice 10's neighbour areas
## exist. If that ever changes, callers needing world-space should go through
## `_ground.to_global(...)` instead of using this rect directly.
## https://docs.godotengine.org/en/stable/classes/class_tilemaplayer.html#class-tilemaplayer-method-get-used-rect
func get_bounds_px() -> Rect2:
	var cells := _ground.get_used_rect()
	return Rect2(Vector2(cells.position) * Vector2(TILE_SIZE),
			Vector2(cells.size) * Vector2(TILE_SIZE))


## Build a StaticBody2D wall along each edge of get_bounds_px() that has no
## neighbour_* scene declared — design doc §12.4's "no neighbour -> an
## invisible wall" case. Called once by world.gd's _load_starting_area()
## right after this area is instanced and added under ActiveArea.
##
## Slice 10 will extend the neighbour_* != null branch to build an Area2D
## trigger instead (§12.4's "a neighbour -> an open edge with a trigger");
## for now every meadow.tscn neighbour_* slot is empty, so all four edges
## get a wall.
##
## The four wall rects are built so the north/south walls each run the full
## width PLUS one thickness past each side (west/east), while the west/east
## walls run only the exact bounds height. That asymmetry is deliberate: it
## is what makes the four corners gap-free without any wall needing to know
## about its neighbours — the extended north/south ends already cover the
## corner squares the west/east walls stop short of.
##
## The north wall carries a SECOND, unrelated asymmetry: its player-facing
## surface is inset NORTH_WALL_HEADROOM_INSET_PX south of the true painted
## edge, rather than sitting flush on it like the other three walls do. This
## exists because the player is feet-anchored
## (AnimatedSprite2D.offset = Vector2(0, -16), player/player.tscn) while
## Camera2D.limit_top (world.gd's _set_camera_limits()) clamps the camera's
## VIEW RECT — not the camera node — to the exact same bounds.position.y.
## With the wall flush against that edge, stopping the player there put their
## entire sprite above the clamped view rect: zero pixels of the character
## visible (confirmed empirically). Insetting the north wall gives the
## camera a permanent sprite-height of headroom above the player no matter
## how far north they walk. The strip of painted ground between the true
## edge and the inset wall becomes a visual-only backdrop the player can see
## but never stand on — a common convention in three-quarter/isometric views.
## South/east/west don't have this problem (south already leaves headroom
## below the player; east/west only clip a few px of the sprite's
## transparent side padding), so only north gets the inset.
func build_perimeter_walls() -> void:
	if _walls_built:
		# Already built — guards slice 10's area-transition reloads against
		# duplicating wall nodes under auto-renamed names.
		return

	var bounds: Rect2 = get_bounds_px()

	if neighbour_north == null:
		_add_perimeter_wall("PerimeterWallNorth", Rect2(
				bounds.position.x - PERIMETER_WALL_THICKNESS_PX,
				bounds.position.y - PERIMETER_WALL_THICKNESS_PX + NORTH_WALL_HEADROOM_INSET_PX,
				bounds.size.x + PERIMETER_WALL_THICKNESS_PX * 2.0,
				PERIMETER_WALL_THICKNESS_PX))

	if neighbour_south == null:
		_add_perimeter_wall("PerimeterWallSouth", Rect2(
				bounds.position.x - PERIMETER_WALL_THICKNESS_PX,
				bounds.end.y,
				bounds.size.x + PERIMETER_WALL_THICKNESS_PX * 2.0,
				PERIMETER_WALL_THICKNESS_PX))

	if neighbour_west == null:
		_add_perimeter_wall("PerimeterWallWest", Rect2(
				bounds.position.x - PERIMETER_WALL_THICKNESS_PX,
				bounds.position.y,
				PERIMETER_WALL_THICKNESS_PX,
				bounds.size.y))

	if neighbour_east == null:
		_add_perimeter_wall("PerimeterWallEast", Rect2(
				bounds.end.x,
				bounds.position.y,
				PERIMETER_WALL_THICKNESS_PX,
				bounds.size.y))

	_walls_built = true


# ---------------------------------------------------------------------------
# Private methods
# ---------------------------------------------------------------------------

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
