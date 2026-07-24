## test_world_scene.gd
## Integration tests for world/world.tscn — verifying scene-as-data behavior
## after World._ready() has run, which cannot be checked by reading the .tscn
## or world.gd source alone.
##
## This file mirrors the source location: world/ → tests/integration/world/.
##
## Issue #36 regression: world.gd._ready() unconditionally called
## _place_player_at_viewport_centre(), which overwrote the scene-authored
## Player.position (Vector2(576, 352) in world.tscn) with the viewport centre
## on every launch. The fix removes that call so the Player keeps whatever
## position world.tscn gives it. This test instantiates the real world.tscn
## (not a mock) so it exercises the actual _ready() call chain, not just the
## math in isolation.
##
## Design reference: GitHub issue #36,
##   "Player spawns at viewport centre instead of the scene-placed position".
##
## Requires GUT: https://github.com/bitwes/Gut
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gselect=test_world_scene.gd -gexit

class_name TestWorldScene
extends GutTest


# Path to the world scene — loaded as a PackedScene and instantiated so
# _ready() actually runs, since the bug only manifests after World._ready()
# executes (it is not visible from reading world.tscn's authored position
# alone).
# https://docs.godotengine.org/en/stable/classes/class_packedscene.html
const WORLD_SCENE_PATH: String = "res://world/world.tscn"

# The Player position authored in world.tscn (node "Player", property
# "position"). Hard-coded here — rather than reading it back out of the
# .tscn file — so this test independently pins the expected spawn point; if
# someone changes the authored position in the editor without updating this
# constant, the test will fail and flag the drift for review.
const EXPECTED_SPAWN_POSITION: Vector2 = Vector2(576, 352)


# ---------------------------------------------------------------------------
# Spawn position guard (Issue #36)
# ---------------------------------------------------------------------------

func test_player_spawns_at_scene_authored_position() -> void:
	# Load the scene as a PackedScene resource (does not add to tree, does not
	# run _ready() yet).
	var packed: PackedScene = load(WORLD_SCENE_PATH)
	assert_not_null(packed, "world/world.tscn should load as a PackedScene")
	if packed == null:
		return

	# Instantiate and add to the test's scene tree so World._ready() runs —
	# add_child_autofree ensures the node (and its children, including
	# Player) is freed when the test ends, preventing a node-leak warning
	# in GUT.
	# https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-add-child
	var world: Node = packed.instantiate()
	add_child_autofree(world)

	var player: Node2D = world.get_node_or_null("Player") as Node2D
	assert_not_null(player, "world.tscn must have a child node named 'Player'")
	if player == null:
		return

	# The critical assertion: after _ready() has run, the Player must still be
	# at the position authored in world.tscn. Before the Issue #36 fix,
	# World._ready() called _place_player_at_viewport_centre(), which
	# overwrote this with get_viewport_rect().size / 2.0 — clobbering the
	# scene-authored spawn point on every launch.
	assert_eq(
		player.position,
		EXPECTED_SPAWN_POSITION,
		(
		"Player.position must remain the scene-authored spawn point "
		+ "(%s) after World._ready() runs, not the viewport centre. "
		+ "If this fails, world.gd is still calling "
		+ "_place_player_at_viewport_centre() (or similar) in _ready() "
		+ "and clobbering the authored position — see Issue #36."
		) % [EXPECTED_SPAWN_POSITION]
	)
