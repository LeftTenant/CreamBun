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
## editor-time helper (e.g. a perimeter-wall preview in slice 9) can be added
## without churning the base class declaration again.
##
## Design reference: docs/features/world-collision/design.md §12.1, §12.2


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const TILE_SIZE := Vector2i(32, 16)


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
# Public methods
# ---------------------------------------------------------------------------

## Area extent in world pixels, taken from the painted floor. Designers
## never re-declare geometry they already painted (cf. design doc §5's
## collision-follows-the-asset principle, applied here to area bounds).
##
## get_used_rect() returns the tile-coordinate bounding box of painted cells;
## this scales both its position and size by TILE_SIZE to convert tile-space
## to pixel-space.
## https://docs.godotengine.org/en/stable/classes/class_tilemaplayer.html#class-tilemaplayer-method-get-used-rect
func get_bounds_px() -> Rect2:
	var cells := _ground.get_used_rect()
	return Rect2(Vector2(cells.position) * Vector2(TILE_SIZE),
			Vector2(cells.size) * Vector2(TILE_SIZE))
