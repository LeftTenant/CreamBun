## test_world_area_shell.gd
## Integration tests for Slice 8 of the world-collision feature ("WorldArea
## extraction and the persistent shell") — verifies world/world.tscn's
## post-restructure shape after World._ready() has run: a persistent shell
## (ActiveArea / Player / Notebook / Transition) with the meadow WorldArea
## instanced under ActiveArea and the Player reparented into it.
##
## This file is deliberately separate from test_world_scene.gd, which keeps
## its original, narrower Issue #36 spawn-position scope (updated only enough
## to keep working once Player's parent changes — see that file's own
## SLICE 8 UPDATE note). This file is a sibling of test_boulder_placement.gd,
## test_tree_placement.gd, test_solids_collision.gd, and test_tile_geometry.gd
## — kept separate because it targets Slice 8's own new structural behavior,
## not any of theirs.
##
## Written test-first, ahead of world/areas/shared/world_area.gd,
## world/areas/meadow.tscn, and the world.tscn/world.gd restructure — the
## implementation now exists and these tests pass against it.
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
##     -gselect=test_world_area_shell.gd -gexit

class_name TestWorldAreaShell
extends GutTest


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const WORLD_SCENE_PATH: String = "res://world/world.tscn"
const MEADOW_SCENE_PATH: String = "res://world/areas/meadow.tscn"
const BOULDER_SCENE_PATH: String = "res://world/props/boulder.tscn"
const TREE_SCENE_PATH: String = "res://world/props/tree_oak.tscn"

## Expected value of Node.process_mode, per CLAUDE.md's "UI during pause"
## rule ("Set process_mode = ALWAYS (value 3) on all CanvasLayer nodes so UI
## remains responsive when the game is paused") — Transition is a CanvasLayer
## overlay, so it must follow the same rule as Notebook already does.
##
## Named EXPECTED_PROCESS_MODE rather than PROCESS_MODE_ALWAYS: that name
## collides with Node's own native enum member of the same name (Node
## already defines PROCESS_MODE_ALWAYS = 3), and GDScript raises a parse
## error ("Member ... redefined") on a class-level constant that shadows an
## inherited native member.
const EXPECTED_PROCESS_MODE: int = 3


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Instantiate world.tscn and add it to the tree so World._ready() runs
## (area instancing + Player reparent). Autofreed at teardown.
## @return the instantiated World root, or null (with a failed assertion
## already recorded) if the scene can't be loaded/instantiated.
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


## ActiveArea's single expected child: the instanced meadow WorldArea. Fails
## (with an assertion already recorded) and returns null if ActiveArea is
## missing or holds anything other than exactly one child.
func _get_instanced_area(world: Node) -> Node:
	var active_area: Node = world.get_node_or_null("ActiveArea")
	assert_not_null(active_area, "world.tscn should have a direct child named 'ActiveArea' (design doc §12.1)")
	if active_area == null:
		return null

	assert_eq(active_area.get_child_count(), 1,
			(
			"ActiveArea should hold exactly one instanced WorldArea (the meadow) — found %d "
			+ "children. Design doc §12.1: areas are loaded and unloaded one at a time."
			) % [active_area.get_child_count()])
	if active_area.get_child_count() == 0:
		return null

	return active_area.get_child(0)


## Recursively search `root`'s subtree (not just direct children) for a node
## whose scene_file_path matches `path` — identifies an instance by WHAT it
## is rather than by a guessed node name, matching the technique already used
## by test_tree_placement.gd's _find_tree_instance(). Returns null (no
## assertion recorded — callers give a more specific message) if none found.
func _find_instance_by_scene_path(root: Node, path: String) -> Node:
	for child in root.get_children():
		if child.scene_file_path == path:
			return child
		var found: Node = _find_instance_by_scene_path(child, path)
		if found != null:
			return found
	return null


# ---------------------------------------------------------------------------
# Test 1 — Player is reparented into the instanced WorldArea, not left on
#          World (design doc §12.1)
# ---------------------------------------------------------------------------

func test_player_is_reparented_into_the_instanced_world_area() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return

	var area: Node = _get_instanced_area(world)
	if area == null:
		return

	# After the Slice 8 reparent, world.get_node_or_null("Player") is expected
	# to return null — Player is no longer World's direct child. Look it up
	# via the area directly, which is where design doc §12.1 says it must end
	# up (the very next assertion below requires the parent to be `area`
	# anyway, so a World-rooted fallback lookup could never contribute to a
	# pass).
	var player: Node = area.get_node_or_null("Player")

	assert_not_null(player,
			"Player should exist as a direct child of the instanced WorldArea after World._ready() runs.")
	if player == null:
		return

	assert_eq(player.get_parent(), area,
			(
			"Player's parent must be the instanced WorldArea (the meadow), not World itself, "
			+ "after World._ready() runs — design doc §12.1: '_player.reparent(area)' moves the "
			+ "persistent player into the area's Y-sort scope. Found parent '%s' instead."
			) % [player.get_parent().name if player.get_parent() else "<no parent>"])

	assert_ne(player.get_parent(), world,
			"Player must no longer be a direct child of World once reparented into the WorldArea")

	assert_true(area is WorldArea,
			(
			"the node Player was reparented into should be a WorldArea instance (i.e. an "
			+ "instance of world/areas/meadow.tscn, using world_area.gd as its script) — found a "
			+ "plain %s instead."
			) % [area.get_class()])


# ---------------------------------------------------------------------------
# Test 2 — the Slice 6/7 Boulder and TreeOak instances share that same
#          WorldArea with the Player (design doc §6.1, §9 — one Y-sort scope)
# ---------------------------------------------------------------------------

func test_boulder_and_tree_remain_direct_children_of_the_shared_world_area() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return

	var area: Node = _get_instanced_area(world)
	if area == null:
		return

	var boulder: Node = _find_instance_by_scene_path(world, BOULDER_SCENE_PATH)
	assert_not_null(boulder,
			"world.tscn's tree should contain a boulder.tscn instance carried over from Slice 6")
	var tree: Node = _find_instance_by_scene_path(world, TREE_SCENE_PATH)
	assert_not_null(tree,
			"world.tscn's tree should contain a tree_oak.tscn instance carried over from Slice 7")
	if boulder == null or tree == null:
		return

	# Direct children specifically — not merely "somewhere under the area" —
	# because Y-sort only interleaves a node's DIRECT children (design doc
	# §6.1, §9). If either prop ended up nested under an intermediate node
	# during the extraction into meadow.tscn, it would stop sorting against
	# the player correctly even though it's still "in" the area.
	assert_eq(boulder.get_parent(), area,
			(
			"the Boulder instance must be a DIRECT child of the instanced WorldArea after the "
			+ "Slice 8 extraction — found it parented under '%s' instead. Y-sort only "
			+ "interleaves direct children (design doc §6.1, §9)."
			) % [boulder.get_parent().name if boulder.get_parent() else "<no parent>"])
	assert_eq(tree.get_parent(), area,
			(
			"the TreeOak instance must be a DIRECT child of the instanced WorldArea after the "
			+ "Slice 8 extraction — found it parented under '%s' instead. Y-sort only "
			+ "interleaves direct children (design doc §6.1, §9)."
			) % [tree.get_parent().name if tree.get_parent() else "<no parent>"])

	# And the point of all this: the Player must share that SAME parent, so
	# the three of them are all Y-sorted against one another as one scope.
	var player: Node = area.get_node_or_null("Player")
	assert_not_null(player, "Player should be a direct child of the instanced WorldArea (see the reparent test above)")
	if player == null:
		return
	assert_eq(player.get_parent(), boulder.get_parent(),
			"Player and the Boulder/TreeOak props must share the exact same parent node to be Y-sorted against each other")


# ---------------------------------------------------------------------------
# Test 3 — ActiveArea holds exactly one instanced meadow WorldArea, whose
#          Ground/Solids layers are its direct children (design doc §6.1)
# ---------------------------------------------------------------------------

func test_active_area_holds_one_meadow_instance_with_direct_ground_and_solids_layers() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return

	var area: Node = _get_instanced_area(world)
	if area == null:
		return

	assert_eq(area.scene_file_path, MEADOW_SCENE_PATH,
			(
			"ActiveArea's single child should be an instance of %s specifically — found "
			+ "scene_file_path '%s'."
			) % [MEADOW_SCENE_PATH, area.scene_file_path])

	var ground: Node = area.get_node_or_null("Ground")
	assert_not_null(ground, "the instanced WorldArea should have a direct child named 'Ground'")
	if ground != null:
		assert_true(ground is TileMapLayer,
				"the WorldArea's 'Ground' child should be a TileMapLayer, found a %s" % [ground.get_class()])

	var solids: Node = area.get_node_or_null("Solids")
	assert_not_null(solids, "the instanced WorldArea should have a direct child named 'Solids'")
	if solids != null:
		assert_true(solids is TileMapLayer,
				"the WorldArea's 'Solids' child should be a TileMapLayer, found a %s" % [solids.get_class()])


# ---------------------------------------------------------------------------
# Test 4 — the Transition CanvasLayer exists and processes while paused
#          (design doc §12.1; CLAUDE.md's "UI during pause" convention)
# ---------------------------------------------------------------------------

func test_transition_canvas_layer_present_and_processes_always() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return

	var transition: Node = world.get_node_or_null("Transition")
	assert_not_null(transition,
			(
			"world.tscn should have a direct child named 'Transition' — the fade overlay "
			+ "CanvasLayer described in design doc §12.1, present now even though unused until "
			+ "slice 10's edge transitions."
			))
	if transition == null:
		return

	assert_true(transition is CanvasLayer,
			"Transition should be a CanvasLayer, found a %s instead" % [transition.get_class()])

	assert_eq(transition.process_mode, EXPECTED_PROCESS_MODE,
			(
			"Transition's process_mode must be ALWAYS (%d) so the fade overlay keeps working "
			+ "while GameState.current_state == LOADING freezes everything else — same "
			+ "CanvasLayer convention CLAUDE.md already requires for Notebook."
			) % [EXPECTED_PROCESS_MODE])
