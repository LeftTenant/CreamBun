## test_world_area.gd
## Unit tests for WorldArea (world/areas/shared/world_area.gd) — Slice 8 of
## the world-collision feature ("WorldArea extraction and the persistent
## shell").
##
## WorldArea is the base class every concrete area scene (meadow.tscn, and
## later market.tscn, …) uses as its root. This slice's designer-facing
## surface is small: four neighbour_* PackedScene export slots (declared now,
## wired up in slice 10 — design doc §12.2) and get_bounds_px(), which
## derives the area's pixel extent from whatever the level designer has
## already painted onto its Ground TileMapLayer child, rather than making
## anyone re-declare geometry the art already encodes (design doc §12.2's
## "designers never re-declare geometry they already painted").
##
## FIXTURE SCENE
## -------------
## world_area.gd is `@tool` + `Node2D` and expects a TileMapLayer child named
## "Ground" (the @onready `_ground` lookup in the class).
## tests/unit/world/areas/shared/fixtures/test_world_area.tscn stands in for
## a real area: a bare Node2D with world_area.gd attached and a Ground
## TileMapLayer with a one-source TileSet assigned but NOTHING painted at
## rest — each test paints a known region onto it at runtime via
## TileMapLayer.set_cell() instead of baking tile_map_data into the fixture
## .tscn, so the painted region stays legible as data in this file rather
## than opaque PackedByteArray bytes in the scene resource. Mirrors the
## fixture convention from tests/unit/world/props/shared/fixtures/
## test_world_prop.tscn (Slice 5), and get_used_rect()/set_cell():
## https://docs.godotengine.org/en/stable/classes/class_tilemaplayer.html#class-tilemaplayer-method-set-cell
## https://docs.godotengine.org/en/stable/classes/class_tilemaplayer.html#class-tilemaplayer-method-get-used-rect
##
## Written test-first, ahead of world/areas/shared/world_area.gd — that
## script (and its `class_name WorldArea`) now exists and these tests pass
## against it. Design doc §12.2 gives the exact script this class matches.
##
## Design reference: docs/features/world-collision/design.md §12.1, §12.2
## Test plan: docs/features/world-collision/slice-8-world-area-test-plan.md
##
## Requires GUT: https://github.com/bitwes/Gut
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gselect=test_world_area.gd -gexit

class_name TestWorldArea
extends GutTest


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const SCENE_PATH: String = "res://tests/unit/world/areas/shared/fixtures/test_world_area.tscn"

## TILE_SIZE per design doc §4/§12.2 — duplicated locally (rather than
## referencing WorldArea.TILE_SIZE) so the expected scaling is legible here
## without cross-referencing the production script, matching the convention
## in tests/unit/world/props/shared/test_world_prop.gd.
const TILE_SIZE: Vector2i = Vector2i(32, 16)

## The atlas source id the fixture's TileSet registers its one source under
## (see the fixture .tscn's `sources/1 = SubResource(...)` line).
const FIXTURE_SOURCE_ID: int = 1

## A known painted region, deliberately offset from the origin on BOTH axes
## (not a (0,0)-anchored rectangle) so this test would also catch a bug that
## used get_used_rect().size alone without adding its .position — 4 tiles
## wide (x: 2..5), 2 tiles deep (y: 3..4). The two axes also differ in count
## (4 vs 2) so an x/y swap in the scaling maths would be caught too.
const REGION_ORIGIN_CELL: Vector2i = Vector2i(2, 3)
const REGION_SIZE_CELLS: Vector2i = Vector2i(4, 2)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Instantiate the fixture scene and add it to the tree so @onready _ground
## resolves before the test body runs. The instance is autofreed after the
## test.
## https://github.com/bitwes/Gut/wiki/Double,-Stub,-Spy,-and-More#autofree
##
## @return the instantiated WorldArea fixture root
func _make_area() -> WorldArea:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	var instance: WorldArea = packed.instantiate() as WorldArea
	add_child_autofree(instance)
	return instance


## Paint REGION_ORIGIN_CELL .. REGION_ORIGIN_CELL + REGION_SIZE_CELLS - 1 onto
## `area`'s Ground layer, using the fixture TileSet's one registered source.
func _paint_known_region(area: WorldArea) -> void:
	var ground: TileMapLayer = area.get_node("Ground") as TileMapLayer
	for x in range(REGION_SIZE_CELLS.x):
		for y in range(REGION_SIZE_CELLS.y):
			var cell: Vector2i = REGION_ORIGIN_CELL + Vector2i(x, y)
			ground.set_cell(cell, FIXTURE_SOURCE_ID, Vector2i(0, 0))


# ---------------------------------------------------------------------------
# Test 1 — get_bounds_px() scales the painted region's used-rect by TILE_SIZE
# ---------------------------------------------------------------------------

func test_get_bounds_px_scales_used_rect_by_tile_size() -> void:
	var area: WorldArea = _make_area()
	_paint_known_region(area)

	var bounds: Rect2 = area.get_bounds_px()

	var expected_position: Vector2 = Vector2(REGION_ORIGIN_CELL) * Vector2(TILE_SIZE)
	var expected_size: Vector2 = Vector2(REGION_SIZE_CELLS) * Vector2(TILE_SIZE)

	assert_eq(bounds.position, expected_position,
			(
			"get_bounds_px().position should be $Ground.get_used_rect().position (%s) scaled "
			+ "by TILE_SIZE (%s) = %s (design doc §12.2). If this fails while .size passes, "
			+ "the position component of the scaling was dropped or computed from the wrong "
			+ "rect."
			) % [REGION_ORIGIN_CELL, TILE_SIZE, expected_position])
	assert_eq(bounds.size, expected_size,
			(
			"get_bounds_px().size should be $Ground.get_used_rect().size (%s) scaled by "
			+ "TILE_SIZE (%s) = %s (design doc §12.2). REGION_SIZE_CELLS is 4x2 (not square) "
			+ "specifically so an x/y axis swap in the scaling maths would show up here."
			) % [REGION_SIZE_CELLS, TILE_SIZE, expected_size])


# ---------------------------------------------------------------------------
# Test 2 — the four neighbour_* slots are unset by default
# ---------------------------------------------------------------------------

func test_neighbour_slots_are_unset_by_default() -> void:
	# Design doc §12.2: an empty neighbour slot means a hard boundary wall,
	# and filling one in is genuinely new information a designer declares by
	# hand per edge — it is never derived. Slice 8 only declares these four
	# export slots; nothing populates them until slice 10's edge-linking
	# work, so a fresh area must expose all four as unset (null).
	var area: WorldArea = _make_area()

	assert_null(area.neighbour_north,
			"neighbour_north should be unset (null) by default — slice 10 wires edge-linking, not this slice")
	assert_null(area.neighbour_east,
			"neighbour_east should be unset (null) by default — slice 10 wires edge-linking, not this slice")
	assert_null(area.neighbour_south,
			"neighbour_south should be unset (null) by default — slice 10 wires edge-linking, not this slice")
	assert_null(area.neighbour_west,
			"neighbour_west should be unset (null) by default — slice 10 wires edge-linking, not this slice")
