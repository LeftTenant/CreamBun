## test_boulder_placement.gd
## Integration test for world/world.tscn — Slice 6 of the world-collision
## feature ("Boulder: first real prop, proven end-to-end").
##
## This file mirrors the source location: world/ -> tests/integration/world/.
## It is a sibling of test_solids_collision.gd, test_tile_geometry.gd, and
## test_world_scene.gd — kept as a separate file because it targets Slice 6's
## own change (placing a Boulder instance in the scene), not any of theirs.
##
## Per design doc §6.1, props must be DIRECT children of the area's Y-sorted
## root, never nested under an intermediate node — Y-sort only interleaves a
## node's direct children, so a props sub-node would sort as one block
## against the player instead of prop-by-prop (§9).
##
## SLICE 8 UPDATE: world.tscn is now the persistent shell (design doc §12.1);
## the Boulder instance placed here in Slice 6 moved, unchanged, into
## world/areas/meadow.tscn as part of the Slice 8 shell/area extraction. The
## Y-sorted root Boulder must be a direct child of is therefore the instanced
## WorldArea (meadow) reachable through World's ActiveArea node, not World
## itself. This file's own Slice 6 scope — "is there a Boulder instance, and
## is it a direct (not nested) child of the Y-sort scope" — is unchanged; only
## WHICH node is the Y-sort scope has moved.
##
## Written test-first, ahead of the Boulder instance being placed in
## world.tscn (that placement, alongside boulder.tscn itself, is part of this
## slice's own implementation) — the instance now exists and this test passes
## against it.
##
## Design reference: docs/features/world-collision/design.md §6.1, §9, §12.1
## Test plan: docs/features/world-collision/slice-6-boulder-test-plan.md
##
## Requires GUT: https://github.com/bitwes/Gut
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gselect=test_boulder_placement.gd -gexit

class_name TestBoulderPlacement
extends GutTest


const WORLD_SCENE_PATH: String = "res://world/world.tscn"

## Node name assumed for the placed instance, per design doc §6.1's node tree
## comment ("props placed here directly: Boulder, TreeOak, …") and slices.md
## Slice 6 ("Place one `Boulder` instance...").
const BOULDER_NODE_NAME: String = "Boulder"


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


## ActiveArea's single expected child: the instanced meadow WorldArea, which
## is the Y-sort scope after the Slice 8 shell/area extraction (design doc
## §12.1). Returns null (with a failed assertion already recorded) if
## ActiveArea is missing or empty.
func _get_instanced_area(world: Node) -> Node:
	var active_area: Node = world.get_node_or_null("ActiveArea")
	assert_not_null(active_area, "world.tscn should have a direct child named 'ActiveArea' (design doc §12.1)")
	if active_area == null:
		return null

	assert_gt(active_area.get_child_count(), 0,
			"ActiveArea should hold the instanced WorldArea (the meadow) — found no children")
	if active_area.get_child_count() == 0:
		return null

	return active_area.get_child(0)


func test_boulder_instance_is_a_direct_child_of_the_world_area_root() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return

	var area: Node = _get_instanced_area(world)
	if area == null:
		return

	# Search only the area's DIRECT children (get_children() never reaches
	# through a nested node) — this is the assertion itself, not just a
	# lookup convenience: if a future edit nested the boulder under a
	# "Props" node, it would not be found here, and the test would fail with
	# the message below rather than silently passing on a `get_node("Props/
	# Boulder")`-style path that would tolerate the very structure design
	# doc §6.1 forbids.
	var boulder: Node = null
	for child in area.get_children():
		if child.name == BOULDER_NODE_NAME:
			boulder = child
			break

	assert_not_null(boulder,
			(
			"the instanced WorldArea (meadow) should have a direct child named '%s' — Slice 6 "
			+ "places one Boulder instance for manual/e2e verification (design doc §6.1, "
			+ "slices.md Slice 6), moved into meadow.tscn unchanged by the Slice 8 extraction "
			+ "(design doc §12.1). If a node named '%s' exists elsewhere in the tree but not as "
			+ "a direct child of the WorldArea, it has been nested under an intermediate node, "
			+ "which breaks Y-sort (§6.1, §9: Y-sort only interleaves a node's DIRECT children)."
			) % [BOULDER_NODE_NAME, BOULDER_NODE_NAME])
	if boulder == null:
		return

	# Sanity check: confirm it's actually a WorldProp instance (i.e. really
	# boulder.tscn, using world_prop.gd as its script), not some unrelated
	# node that happens to share the name.
	assert_true(boulder is WorldProp,
			(
			"world.tscn's '%s' node should be a WorldProp instance (i.e. an instance of "
			+ "world/props/boulder.tscn, which uses world_prop.gd as its script) — found a "
			+ "plain %s instead."
			) % [BOULDER_NODE_NAME, boulder.get_class()])
