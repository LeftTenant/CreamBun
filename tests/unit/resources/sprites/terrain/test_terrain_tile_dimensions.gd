## test_terrain_tile_dimensions.gd
## Unit tests for the terrain textures under resources/sprites/terrain/ —
## verifying the Slice 2 rescale from 64×32 to 32×16 pixels.
##
## Slice 2 halves TILE_SIZE from Vector2i(64, 32) to Vector2i(32, 16) (design
## doc §4) to double on-screen tile density at the 320×180 viewport. The two
## flat terrain textures are a "trivial rescale" per §4.1 — no content change,
## just half the pixel dimensions.
##
## These tests load the PNGs through Godot's normal imported-resource path
## (`load()`, returning a CompressedTexture2D backed by the existing .import
## file) rather than reading the file bytes directly with Image.load(). The
## engine warns "Loaded resource as image file, this will not work on
## export" whenever Image.load() is pointed at a res:// path that already
## has a texture import — GUT's default policy fails any test that logs an
## unexpected engine warning, so Image.load() must be avoided here even
## though its pixel-size result would otherwise be equivalent.
## https://docs.godotengine.org/en/stable/classes/class_resourceloader.html#class-resourceloader-method-load
## https://docs.godotengine.org/en/stable/classes/class_compressedtexture2d.html
##
## Design reference: docs/features/world-collision/design.md §4, §4.1
## Test plan: docs/features/world-collision/slice-2-tile-geometry-test-plan.md
##
## Requires GUT: https://github.com/bitwes/Gut
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gselect=test_terrain_tile_dimensions.gd -gexit

class_name TestTerrainTileDimensions
extends GutTest


# The Slice 2 tile size (design doc §4). A TileSetAtlasSource slices its
# texture into cells of exactly this size starting at (0, 0), so a terrain
# texture whose dimensions aren't a whole multiple of it misaligns every tile
# in the atlas after the first.
const EXPECTED_SIZE: Vector2i = Vector2i(32, 16)

const GRASS_PATH: String = "res://resources/sprites/terrain/grass.png"
# Filename has a literal space — this is the actual on-disk name (see
# resources/sprites/terrain/), not a typo.
const FLOWER_GRASS_PATH: String = "res://resources/sprites/terrain/flower grass.png"


# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------

## Load a texture through the normal imported-resource path (using the
## existing .import file, same as any scene would) and return its pixel
## size. Fails the test and returns Vector2i.ZERO if the resource cannot be
## loaded.
func _load_texture_size(path: String) -> Vector2i:
	var texture: CompressedTexture2D = load(path)
	assert_not_null(texture, "load() should succeed for %s" % path)
	if texture == null:
		return Vector2i.ZERO
	return Vector2i(texture.get_width(), texture.get_height())


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_grass_png_tiles_cleanly_at_32x16() -> void:
	# RENAMED from test_grass_png_is_32x16(). grass.png is no longer a single
	# tile: it is now a horizontal strip of a plain grass tile plus eight
	# boundary-edge variants (atlas coords 1:0-8:0 in meadow.tscn's TileSet),
	# each carrying a thin collision polygon along one or two of its borders
	# (design doc §6.1). The invariant worth guarding was never "this file is
	# exactly one tile" — it is "this file slices into whole 32x16 cells", so
	# that is what is asserted now. Asserting the old exact size would fail
	# every time an artist adds a variant, which is not a defect.
	var size: Vector2i = _load_texture_size(GRASS_PATH)
	if size == Vector2i.ZERO:
		return

	assert_eq(size.y, EXPECTED_SIZE.y,
			"grass.png must be exactly %dpx tall — it is a single-row atlas strip, so a taller image would make the second row's cells silently unreachable (got %s)"
					% [EXPECTED_SIZE.y, size])
	assert_eq(size.x % EXPECTED_SIZE.x, 0,
			"grass.png's width (%dpx) must be a whole multiple of the %dpx tile width — a partial trailing cell misaligns nothing on its own but leaves an unusable sliver tile in the atlas"
					% [size.x, EXPECTED_SIZE.x])
	assert_gt(size.x, 0,
			"grass.png must contain at least one 32x16 tile")


func test_flower_grass_png_is_32x16() -> void:
	# Unlike grass.png above, this one is still a single tile (plus an
	# alternative tile, which lives in the TileSet rather than the texture) —
	# so the exact-size assertion still describes the real invariant here.
	# See design doc §4.1.
	var size: Vector2i = _load_texture_size(FLOWER_GRASS_PATH)
	assert_eq(size, EXPECTED_SIZE,
			"'flower grass.png' should be 32×16 after the Slice 2 tile-size rescale (got %s)" % size)
