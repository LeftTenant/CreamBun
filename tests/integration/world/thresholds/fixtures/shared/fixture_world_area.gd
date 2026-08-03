class_name FixtureWorldArea
extends WorldArea
## Base script for the tiny WorldArea fixtures under
## tests/integration/world/thresholds/fixtures/ — used ONLY by
## test_threshold_transition.gd (World Thresholds Slice 3) to prove
## world.gd's Threshold-driven transition sequence without touching real
## content (meadow.tscn/orchard.tscn stay untouched on disk — see that test
## file's header and docs/features/world-thresholds/slices.md's Slice 3 "how
## to prove this without touching real content" note).
##
## Paints a plain rectangular Ground TileMapLayer in _ready() rather than
## hand-encoding a TileMapLayer's binary tile_map_data inside a .tscn by
## hand — that format is an unreadable PackedByteArray blob, fine for the
## editor to write but not something a human (or a test-authoring pass) should
## hand-edit, unlike the handful of Threshold/Arrival nodes these fixtures
## actually exist to test. Real area content keeps painting Ground by hand in
## the editor; this is a test-fixture-only convenience, not a pattern used
## anywhere else in the project.
##
## Ground still needs a TileSet with at least one valid source for
## set_cell()'s painted cells to register with get_used_rect() (the method
## get_bounds_px(), inherited unchanged from WorldArea, reads) — each fixture
## .tscn declares its own minimal TileSet, mirroring orchard.tscn's own
## (a single flat TileSetAtlasSource, no physics layer: these fixtures don't
## need floor collision, only a painted rect for get_bounds_px() to measure).
##
## Sized fixture_width_tiles x fixture_height_tiles, exported so each fixture
## .tscn can declare its own footprint from the Inspector rather than every
## fixture needing its own script. World Thresholds slices.md's Slice 3 sets
## the floor at >= 10x12 tiles (>= one 320x180px viewport — the same
## "camera-limit assertions are meaningful" reasoning the world-collision
## design put on real content, design.md §6.3's equivalent for this feature).
##
## Design reference: docs/features/world-thresholds/design.md §4-§5
## Test plan: docs/features/world-thresholds/slice-3-world-driven-threshold-test-plan.md
## Slice breakdown: docs/features/world-thresholds/slices.md, Slice 3


# ---------------------------------------------------------------------------
# Exported variables
# ---------------------------------------------------------------------------

## Fixture footprint, in tiles. Defaults already clear the >= 10x12 floor
## slices.md's Slice 3 sets; every fixture .tscn in this suite uses the
## default rather than overriding it, since none of these tests need a
## larger area than the minimum.
@export var fixture_width_tiles: int = 10
@export var fixture_height_tiles: int = 12


# ---------------------------------------------------------------------------
# Built-in overrides
# ---------------------------------------------------------------------------

## Skipped in the editor (Engine.is_editor_hint()) for the same reason
## WorldArea's own _physics_process() skips it — there is no reason to paint
## a fixture's floor at edit time, since nobody ever opens these fixtures in
## the editor; they exist only to be load()ed and instantiate()d by
## test_threshold_transition.gd.
func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_paint_ground()


# ---------------------------------------------------------------------------
# Private methods
# ---------------------------------------------------------------------------

## Paint every cell in [0, fixture_width_tiles) x [0, fixture_height_tiles)
## with this fixture's TileSet's single flat tile (atlas coord (0, 0) of the
## TileSet's first declared source — every fixture .tscn's TileSet declares
## exactly one). get_bounds_px() (inherited from WorldArea) reads the result
## back via $Ground.get_used_rect(), exactly as it would a hand-painted real
## area.
##
## The source id passed to set_cell() must be looked up via
## tile_set.get_source_id(0) (the source at INDEX 0 in the TileSet's source
## list), not assumed to be 0 itself: Godot numbers TileSet sources starting
## at 1 by default (every fixture .tscn here declares `sources/1 =
## SubResource(...)`), and set_cell() does not validate its source id
## argument — passing a nonexistent id (e.g. a hardcoded 0) silently leaves
## the cell blank while get_used_rect()/get_bounds_px() still report the
## correct extent (they're derived from the cell coordinates written, not
## from whether a valid tile was actually placed there), so the bug produces
## no visible test failure on its own. See the get_cell_tile_data() check
## below, which exists specifically to catch this class of mistake.
func _paint_ground() -> void:
	if _ground.tile_set == null:
		push_error("FixtureWorldArea._paint_ground: %s's Ground has no TileSet assigned — cannot paint the fixture floor" % [scene_file_path])
		return
	var source_id: int = _ground.tile_set.get_source_id(0)
	for x in range(fixture_width_tiles):
		for y in range(fixture_height_tiles):
			_ground.set_cell(Vector2i(x, y), source_id, Vector2i.ZERO)

	# Regression guard for the exact trap described above: if the source id
	# lookup ever again resolves to something that doesn't actually paint
	# tiles (e.g. a future fixture with a differently-numbered source), a
	# painted cell's tile data would come back null even though
	# get_used_rect() still reports the cell as "used". Fail loudly instead of
	# leaving a silently-blank floor.
	if _ground.get_cell_tile_data(Vector2i.ZERO) == null:
		push_error("FixtureWorldArea._paint_ground: %s's Ground cell (0, 0) has no tile data after painting — source id %d did not resolve to a real TileSet source" % [scene_file_path, source_id])
