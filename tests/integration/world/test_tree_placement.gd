## test_tree_placement.gd
## Integration test for Slice 7 of the world-collision feature ("Tree:
## footprint ≠ silhouette") — verifies world/world.tscn actually places a
## TreeOak instance, and places it correctly relative to the Y-sorted area
## root.
##
## This file is deliberately separate from
## tests/integration/world/props/test_tree_oak.gd: that file exercises
## tree_oak.tscn in isolation (the scene's own physics/collision behaviour);
## this one exercises world.tscn (mirrors the source location: world.tscn ->
## tests/integration/world/, matching test_solids_collision.gd's sibling
## structure for the same slice pattern).
##
## PLACEMENT: Vector2(208, 176) — 80px (2.5
## tiles) west of the player spawn (Vector2(288, 176)). This sits exactly on
## tile (6, 10)'s front (south) edge, so the trunk's generated 1x1 footprint
## occupies exactly tile (6, 10) (pixel rect x:[192,224], y:[160,176]) with
## no partial-tile straddling. Verified against the tile data actually
## painted in world.tscn's Ground/Solids TileMapLayers:
##   - Column x=6 is painted on Ground from row y=4 through y=20 (pixel y
##     64-320) with NO Solids tiles anywhere in that column — full runway on
##     all four sides for both the trunk-blocks approach and the
##     canopy-overhang approach (design doc §8.2, §8.3).
##   - Slice 4's Solids test cells sit at tile (11, 11) and (12, 11) — pixel
##     rect x:[352,416], y:[176,192] — 128px+ east of this spot, no overlap.
##   - Slice 6's Boulder sits at Vector2(288, 240) — footprint pixel rect
##     x:[272,304], y:[224,240] — well south and east, no overlap.
##   - The straight walk from spawn (288, 176) west to (208, 176) crosses
##     tiles (7,10)/(7,11), (8,10)/(8,11), which are Ground-only (no Solids),
##     so the tree is reachable from spawn with nothing else in the way.
## This exact position is not itself asserted by this file — the plan only
## requires the instance be a direct child of the Y-sorted root and reachable
## from spawn on all four sides (design doc §12.3/§9), which holds for any
## position with this column's clearance.
##
## SLICE 8 UPDATE: world.tscn is now the persistent shell (design doc §12.1);
## the TreeOak instance placed here in Slice 7 moved, unchanged, into
## world/areas/meadow.tscn as part of the Slice 8 shell/area extraction. The
## Y-sorted root the instance must be a direct child of is therefore the
## instanced WorldArea (meadow) reachable through World's ActiveArea node,
## not World itself. This file's own Slice 7 scope is otherwise unchanged.
##
## Design reference: docs/features/world-collision/design.md §6.1, §9, §12.1
## Test plan: docs/features/world-collision/slice-7-tree-test-plan.md
##
## Requires GUT: https://github.com/bitwes/Gut
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gselect=test_tree_placement.gd -gexit

class_name TestTreePlacement
extends GutTest


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const WORLD_SCENE_PATH: String = "res://world/world.tscn"
const TREE_SCENE_PATH: String = "res://world/props/tree_oak.tscn"

## "world" physics layer bit value, per project.godot's [layer_names] section
## (2d_physics/layer_1 = "world"). Mirrors the constant of the same name in
## tests/integration/world/test_solids_collision.gd and
## tests/integration/world/props/test_tree_oak.gd.
const WORLD_LAYER_BIT: int = 1


# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

func before_each() -> void:
	# Player movement is gated on GameState.current_state == PLAYING
	# (player.gd). Set explicitly, matching test_perimeter_walls.gd's
	# convention, so this suite doesn't depend on GameState's default or on
	# whatever an earlier-running test file left it in — including
	# world.gd's own _load_starting_area(), which now brackets startup in
	# LOADING and can leave GameState stuck there if a test tears down
	# world.tscn before that coroutine finishes (see _load_starting_area()'s
	# doc comment in world/world.gd).
	GameState.change_state(GameState.State.PLAYING)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Instantiate world.tscn and add it to the tree. Autofreed at teardown.
## @return the instantiated World root, or null (with a failed assertion
## already recorded) if the scene can't be loaded/instantiated.
func _instantiate_world() -> Node2D:
	var packed: PackedScene = load(WORLD_SCENE_PATH) as PackedScene
	assert_not_null(packed, "world/world.tscn should load as a PackedScene")
	if packed == null:
		return null

	var world: Node2D = packed.instantiate() as Node2D
	assert_not_null(world, "world/world.tscn should instantiate without errors")
	if world == null:
		return null

	add_child_autofree(world)
	return world


## Search the whole world.tscn tree (not just direct children) for a node
## whose `scene_file_path` is tree_oak.tscn — this identifies a TreeOak
## instance by WHAT it is (an instance of tree_oak.tscn) rather than by name,
## so this test doesn't depend on godot-coder choosing any particular node
## name. Returns null (with no assertion recorded — the caller gives a more
## specific message) if none is found anywhere in the tree.
func _find_tree_instance(root: Node) -> Node:
	for child in root.get_children():
		if child.scene_file_path == TREE_SCENE_PATH:
			return child
		var found: Node = _find_tree_instance(child)
		if found != null:
			return found
	return null


# ---------------------------------------------------------------------------
# Test 1 — a TreeOak instance exists, as a DIRECT child of the Y-sorted root
# ---------------------------------------------------------------------------

func test_tree_instance_is_direct_child_of_the_world_area_root() -> void:
	var world: Node2D = _instantiate_world()
	if world == null:
		return

	var tree_instance: Node = _find_tree_instance(world)
	assert_not_null(tree_instance,
			(
			"world.tscn should contain a tree_oak.tscn instance somewhere in its tree — none "
			+ "found. This is Slice 7's own placement deliverable; see this file's "
			+ "PLACEMENT doc comment for a clear, reachable spot: Vector2(208, 176)."
			))
	if tree_instance == null:
		return

	# Searched recursively above (so this test still finds the instance if
	# it's nested), but design doc §6.1 requires it be a DIRECT child of the
	# Y-sorted area root — Y-sort only interleaves a node's direct children,
	# so a tree instance placed under an intermediate "Props" node would sort
	# as one block against the player instead of correctly, per-prop.
	#
	# SLICE 8: the Y-sorted area root is the instanced WorldArea (meadow),
	# not World itself — the Ground/Solids/props all moved into meadow.tscn
	# during the Slice 8 shell/area extraction (design doc §12.1). world.tscn
	# is now the persistent shell; ActiveArea holds exactly one WorldArea
	# instance, which is what "direct child of the Y-sorted root" refers to
	# here.
	var active_area: Node = world.get_node_or_null("ActiveArea")
	assert_not_null(active_area, "world.tscn should have a direct child named 'ActiveArea' (design doc §12.1)")
	if active_area == null:
		return
	var area: Node = active_area.get_child(0) if active_area.get_child_count() > 0 else null
	assert_not_null(area, "ActiveArea should hold the instanced WorldArea (the meadow) — found no children")
	if area == null:
		return

	assert_eq(tree_instance.get_parent(), area,
			(
			"the tree_oak.tscn instance must be a DIRECT child of the instanced WorldArea "
			+ "(meadow), not nested under an intermediate node (e.g. a 'Props' container) — "
			+ "design doc §6.1: 'Y-sort only interleaves a node's direct children, so a props "
			+ "sub-node would sort as one block against the player instead of tile-by-tile, "
			+ "prop-by-prop.' Found it parented under '%s' instead."
			) % [tree_instance.get_parent().name if tree_instance.get_parent() else "<no parent>"])


# ---------------------------------------------------------------------------
# Test 2 — the placed instance still carries WorldProp's "world" static-solid
#          collision convention (design §11) once instanced inside world.tscn
#          — defence-in-depth alongside the isolated-scene check in
#          tests/integration/world/props/test_tree_oak.gd, in case
#          world.tscn's instance ever overrides layer/mask locally.
# ---------------------------------------------------------------------------

func test_placed_tree_collision_layer_is_world_and_mask_is_empty() -> void:
	var world: Node2D = _instantiate_world()
	if world == null:
		return

	var tree_instance: Node = _find_tree_instance(world)
	assert_not_null(tree_instance,
			"world.tscn should contain a tree_oak.tscn instance (see test above) to check its "
			+ "collision layer/mask against")
	if tree_instance == null:
		return

	var body: StaticBody2D = tree_instance as StaticBody2D
	assert_not_null(body,
			"the tree_oak.tscn instance's root should be a StaticBody2D (WorldProp extends "
			+ "StaticBody2D, design doc §7)")
	if body == null:
		return

	assert_eq(body.collision_layer, WORLD_LAYER_BIT,
			"the placed tree's collision_layer must be exactly the 'world' layer (bit %d)"
			% [WORLD_LAYER_BIT])
	assert_eq(body.collision_mask, 0,
			(
			"the placed tree's collision_mask must be 0 — a static solid collides with nothing "
			+ "itself (design doc §11)."
			))
