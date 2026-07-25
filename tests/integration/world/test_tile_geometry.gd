## test_tile_geometry.gd
## Integration tests for the Slice 2 tile-geometry rescale in world/world.tscn
## — verifying the *instantiated* scene's TileSet, not just the raw .tscn
## text, since a TileSet's sub-resources (atlas sources, tile_size) are only
## reliably inspectable through the live TileSet API once the scene graph
## exists.
##
## This file mirrors the source location: world/ → tests/integration/world/.
## It is a sibling of test_world_scene.gd (the Issue #36 spawn-position
## regression test) — kept as a separate file because it targets a different
## slice with a different set of assertions (TileSet geometry vs. Player
## spawn position), not because either file is wrong on its own.
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
##     -gselect=test_tile_geometry.gd -gexit

class_name TestTileGeometry
extends GutTest


const WORLD_SCENE_PATH: String = "res://world/world.tscn"

# The Slice 2 tile size (design doc §4): the grid stays square
# (TileSet.tile_shape defaults to SQUARE, unchanged), but each cell shrinks
# from 64×32 to 32×16 to double on-screen tile density at the 320×180
# viewport.
const EXPECTED_TILE_SIZE: Vector2i = Vector2i(32, 16)

# Text fragment that must not appear anywhere in world.tscn once the
# placeholder ground texture is dropped (design doc §4.1). Checked against
# both the raw file text and every atlas source's texture path, so a stale
# ext_resource declaration is caught even if no TileSetAtlasSource still
# points at it.
const PLACEHOLDER_TEXTURE_NAME: String = "ground_placeholder.png"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Instantiate world.tscn under the test tree (add_child_autofree frees it
## automatically at test teardown) and return the root node, or null (with a
## failed assertion already recorded) if the scene cannot be loaded or
## instantiated.
func _instantiate_world() -> Node:
	var packed: PackedScene = load(WORLD_SCENE_PATH)
	assert_not_null(packed, "world/world.tscn should load as a PackedScene")
	if packed == null:
		return null

	var world: Node = packed.instantiate()
	assert_not_null(world, "world/world.tscn should instantiate without errors")
	if world == null:
		return null

	add_child_autofree(world)
	return world


## Recursively find the first TileMapLayer under `root`. Written as a search
## rather than a fixed node path (e.g. "TileMapLayer") so this test survives
## the Ground/Solids layer-structure rework described in design doc §6.1,
## which is a later slice, not this one — only the tile geometry is in scope
## here.
func _find_tile_map_layer(root: Node) -> TileMapLayer:
	if root is TileMapLayer:
		return root as TileMapLayer
	for child in root.get_children():
		var found: TileMapLayer = _find_tile_map_layer(child)
		if found != null:
			return found
	return null


## Return every TileSetAtlasSource in `tile_set`. world.tscn currently has
## only atlas sources, but this skips any other TileSetSource subtype rather
## than assuming that stays true.
func _atlas_sources(tile_set: TileSet) -> Array[TileSetAtlasSource]:
	var sources: Array[TileSetAtlasSource] = []
	for i in tile_set.get_source_count():
		var source_id: int = tile_set.get_source_id(i)
		var source: TileSetSource = tile_set.get_source(source_id)
		if source is TileSetAtlasSource:
			sources.append(source as TileSetAtlasSource)
	return sources


## Read the raw text of world.tscn off disk — used only for the
## placeholder-texture-reference and dependency-existence checks below, which
## are textual questions ("is this string gone", "does this path exist") more
## directly answered by reading the file than by walking the TileSet API.
func _read_world_tscn_text() -> String:
	var file: FileAccess = FileAccess.open(WORLD_SCENE_PATH, FileAccess.READ)
	assert_not_null(file, "world/world.tscn should exist and be readable")
	if file == null:
		return ""
	var contents: String = file.get_as_text()
	file.close()
	return contents


## Shared setup for the TileSet-inspection tests below: instantiate the
## world scene and pull out its TileMapLayer's TileSet. Returns null (with a
## failed assertion already recorded) if any step along the way fails.
func _get_world_tile_set() -> TileSet:
	var world: Node = _instantiate_world()
	if world == null:
		return null

	var layer: TileMapLayer = _find_tile_map_layer(world)
	assert_not_null(layer, "world.tscn should contain a TileMapLayer")
	if layer == null:
		return null

	var tile_set: TileSet = layer.tile_set
	assert_not_null(tile_set, "the TileMapLayer should have a TileSet assigned")
	return tile_set


# ---------------------------------------------------------------------------
# TileSet.tile_size
# ---------------------------------------------------------------------------

func test_tile_set_tile_size_is_32x16() -> void:
	# Design doc §4: TILE_SIZE becomes Vector2i(32, 16), replacing the old
	# 64×32 tiles.
	var tile_set: TileSet = _get_world_tile_set()
	if tile_set == null:
		return
	assert_eq(tile_set.tile_size, EXPECTED_TILE_SIZE,
			"world.tscn's TileSet.tile_size should be Vector2i(32, 16) — design doc §4")


# ---------------------------------------------------------------------------
# Atlas source texture_region_size
# ---------------------------------------------------------------------------

func test_all_atlas_sources_have_32x16_texture_region_size() -> void:
	# Every TileSetAtlasSource must agree with the TileSet's own tile_size, or
	# the atlas slices its texture into the wrong cell size regardless of what
	# TileSet.tile_size says (design doc §4.1).
	var tile_set: TileSet = _get_world_tile_set()
	if tile_set == null:
		return

	var sources: Array[TileSetAtlasSource] = _atlas_sources(tile_set)
	assert_gt(sources.size(), 0, "the TileSet should have at least one TileSetAtlasSource")

	for source in sources:
		var texture_path: String = source.texture.resource_path if source.texture != null else "<no texture>"
		assert_eq(source.texture_region_size, EXPECTED_TILE_SIZE,
				(
				"every TileSetAtlasSource's texture_region_size should be "
				+ "Vector2i(32, 16) (source texture: %s)"
				) % texture_path)


# ---------------------------------------------------------------------------
# ground_placeholder.png removal
# ---------------------------------------------------------------------------

func test_no_atlas_source_references_ground_placeholder_texture() -> void:
	# Design doc §4.1: ground_placeholder.png is throwaway placeholder art and
	# should be dropped from the TileSet entirely, not just left unused by it.
	var tile_set: TileSet = _get_world_tile_set()
	if tile_set == null:
		return

	for source in _atlas_sources(tile_set):
		var texture_path: String = source.texture.resource_path if source.texture != null else ""
		assert_false(texture_path.contains(PLACEHOLDER_TEXTURE_NAME),
				(
				"no TileSetAtlasSource should reference %s (source texture: %s)"
				) % [PLACEHOLDER_TEXTURE_NAME, texture_path])


func test_world_tscn_has_no_ground_placeholder_reference() -> void:
	# Belt-and-braces textual check: even a stale, unused ext_resource line
	# referencing ground_placeholder.png should be gone from the file, not
	# just unreferenced by any TileSetAtlasSource.
	var contents: String = _read_world_tscn_text()
	if contents.is_empty():
		return
	assert_false(contents.contains(PLACEHOLDER_TEXTURE_NAME),
			"world.tscn should contain no reference to %s" % PLACEHOLDER_TEXTURE_NAME)


# ---------------------------------------------------------------------------
# Scene instantiates without errors or missing-dependency warnings
# ---------------------------------------------------------------------------

func test_world_scene_instantiates_with_all_dependencies_present() -> void:
	# A missing-dependency warning happens when an ext_resource path in
	# world.tscn points at a file that no longer exists on disk (e.g. left
	# dangling after the texture/TileSet edits this slice makes). Parse every
	# ext_resource path out of the raw text and confirm the file backing it
	# still exists, then confirm the scene actually instantiates.
	var contents: String = _read_world_tscn_text()
	if contents.is_empty():
		return

	# https://docs.godotengine.org/en/stable/classes/class_regex.html
	var regex := RegEx.new()
	regex.compile("path=\"(res://[^\"]+)\"")
	var matches: Array[RegExMatch] = regex.search_all(contents)
	assert_gt(matches.size(), 0, "world.tscn should declare at least one ext_resource path")

	for regex_match in matches:
		var res_path: String = regex_match.get_string(1)
		assert_true(FileAccess.file_exists(res_path),
				"ext_resource path %s referenced by world.tscn should exist on disk" % res_path)

	# Complements the file-existence check above with an actual instantiate()
	# call — confirms the scene loads and builds its node tree cleanly, not
	# just that its listed dependency paths resolve.
	var world: Node = _instantiate_world()
	assert_not_null(world,
			"world.tscn should instantiate cleanly with all dependencies present")
