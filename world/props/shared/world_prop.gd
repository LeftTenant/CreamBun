@tool
class_name WorldProp
extends StaticBody2D
## Base class for every solid world prop — trees, boulders, buildings.
##
## Designers place these by dragging the .tscn into the area root (design doc
## §6.1) and setting `footprint`. The ground collider is generated from that.
## There are no hand-drawn polygons and no separately-maintained "blocked
## area" — collision is authored here, once, and travels with the prop
## wherever it is placed.
##
## The node origin is the GROUND ANCHOR: the front-centre of the footprint,
## the point on the ground nearest the camera. Depth sorting keys off the
## origin (Node2D sorts on global_position.y), so the origin must sit on the
## ground. The sprite is offset upward from it.
##
## @tool means the collider rebuilds live in the editor as `footprint`
## changes, so designers see the solid area while placing.
## https://docs.godotengine.org/en/stable/tutorials/plugins/running_code_in_the_editor.html
##
## Design reference: docs/features/world-collision/design.md §7-§8


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const TILE_SIZE := Vector2i(32, 16)

## Physics layer bit for "world" (project.godot [layer_names] 2d_physics/
## layer_1, design doc §11). Named so the significance of the bit is legible
## at the call site rather than a bare `1`.
const WORLD_LAYER_BIT := 1


# ---------------------------------------------------------------------------
# Exported variables
# ---------------------------------------------------------------------------

## Ground footprint in tile units. A boulder is (1, 1); a cottage might be
## (4, 3).
##
## This is the patch of GROUND the prop occupies — not the size of its
## sprite. An oak tree is (1, 1): its trunk base. The canopy is drawn far
## wider and the player walks behind it. Front-facing art means tall things
## on small patches of ground, so footprint and silhouette are meant to
## diverge (design doc §8.3 explains why this is never auto-derived from the
## sprite).
@export var footprint: Vector2i = Vector2i.ONE:
	set(value):
		footprint = Vector2i(maxi(value.x, 1), maxi(value.y, 1))
		_rebuild_collider()


# ---------------------------------------------------------------------------
# Onready variables
# ---------------------------------------------------------------------------

@onready var _collision: CollisionShape2D = $CollisionShape2D


# ---------------------------------------------------------------------------
# Built-in overrides
# ---------------------------------------------------------------------------

func _ready() -> void:
	# All props are static solids on the "world" layer (project.godot
	# [layer_names] 2d_physics/layer_1, design doc §11). Per that table's
	# mask column, static solids detect nothing themselves — they only need
	# to BE detected by whatever masks in "world" (e.g. the player). So the
	# mask is explicitly cleared rather than left at the engine default of 1,
	# which would otherwise coincidentally equal the world layer bit and mask
	# in "world" by accident. Slice 4 applies the same explicit-zero rule to
	# the Solids TileSet physics layer for the same reason (see
	# tests/integration/world/test_solids_collision.gd).
	collision_layer = WORLD_LAYER_BIT
	collision_mask = 0
	_rebuild_collider()


# ---------------------------------------------------------------------------
# Private methods
# ---------------------------------------------------------------------------

## Regenerate the ground collider from `footprint`.
##
## The grid is square, so this is a plain rectangle — width is footprint.x
## tiles, depth is footprint.y tiles. No projection maths: screen size is
## just footprint * TILE_SIZE.
##
## The shape is offset up-screen by half its depth because the origin is the
## footprint's FRONT edge, not its centre (see class docs). So the collider
## spans y in [-depth, 0], i.e. entirely behind the anchor.
func _rebuild_collider() -> void:
	# The setter can fire before @onready resolves (e.g. when the editor
	# applies an exported value during scene load, or when a plain .new()
	# instance is configured before it ever enters the tree), so bail until
	# the child exists rather than crashing on a null lookup.
	if _collision == null:
		return
	var shape := RectangleShape2D.new()
	shape.size = Vector2(footprint) * Vector2(TILE_SIZE)
	_collision.shape = shape
	_collision.position = Vector2(0.0, -shape.size.y / 2.0)
