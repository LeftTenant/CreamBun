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


# The Slice 2 tile size (design doc §4). Both terrain textures must match
# this exactly — a TileSetAtlasSource slices its texture assuming every tile
# cell is this size, so a mismatched source image misaligns the whole atlas.
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

func test_grass_png_is_32x16() -> void:
	# Rescaled from 64×32 to 32×16 to match the new TILE_SIZE (design doc
	# §4.1). Fails until the art file itself is resized on disk.
	var size: Vector2i = _load_texture_size(GRASS_PATH)
	assert_eq(size, EXPECTED_SIZE,
			"grass.png should be 32×16 after the Slice 2 tile-size rescale (got %s)" % size)


func test_flower_grass_png_is_32x16() -> void:
	# Same rescale as grass.png — see design doc §4.1.
	var size: Vector2i = _load_texture_size(FLOWER_GRASS_PATH)
	assert_eq(size, EXPECTED_SIZE,
			"'flower grass.png' should be 32×16 after the Slice 2 tile-size rescale (got %s)" % size)
