## test_world_scene.gd
## Integration tests for world/world.tscn — verifying scene-as-data behavior
## after World._ready() has run, which cannot be checked by reading the .tscn
## or world.gd source alone.
##
## This file mirrors the source location: world/ → tests/integration/world/.
##
## Issue #36 regression: world.gd._ready() unconditionally called
## _place_player_at_viewport_centre(), which overwrote the scene-authored
## Player.position (Vector2(288, 176) in world.tscn) with the viewport centre
## on every launch. The fix removes that call so the Player keeps whatever
## position world.tscn gives it. This test instantiates the real world.tscn
## (not a mock) so it exercises the actual _ready() call chain, not just the
## math in isolation.
##
## SLICE 8 UPDATE: world.gd's _ready() now reparents Player out of World and
## into the freshly-instanced WorldArea (design doc §12.1's
## `_player.reparent(area)`), so `world.get_node_or_null("Player")` returns
## null once _ready() has run — Player is no longer World's direct child.
## The fix below grabs the Player reference from the freshly-instantiated
## (not-yet-in-tree) scene BEFORE add_child_autofree() triggers _ready(),
## while it is still a plain child of World per the .tscn's authored
## structure. Node identity survives reparent() (it is the same node, moved —
## design doc §12.1), so that reference stays valid afterwards; only its
## parent changes. This keeps the Issue #36 regression coverage working
## across the shell/area restructure without assuming anything about the
## instanced WorldArea's node name. The structural assertions about WHERE
## Player ends up (and that it shares a Y-sort scope with the slice 6/7
## props) live in the sibling file test_world_area_shell.gd, kept separate
## since they target Slice 8's own new behavior rather than this file's
## original Issue #36 scope.
##
## Design reference: GitHub issue #36,
##   "Player spawns at viewport centre instead of the scene-placed position".
## Design reference (reparent): docs/features/world-collision/design.md §12.1.
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
const EXPECTED_SPAWN_POSITION: Vector2 = Vector2(288, 176)


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
# Spawn position guard (Issue #36)
# ---------------------------------------------------------------------------

func test_player_spawns_at_scene_authored_position() -> void:
	# Load the scene as a PackedScene resource (does not add to tree, does not
	# run _ready() yet).
	var packed: PackedScene = load(WORLD_SCENE_PATH)
	assert_not_null(packed, "world/world.tscn should load as a PackedScene")
	if packed == null:
		return

	# Instantiate WITHOUT adding to the tree yet — at this point _ready() has
	# not run, so Player is still exactly where world.tscn authors it: a
	# direct child of World (design doc §12.1's shell layout puts Player as a
	# sibling of ActiveArea, not nested under it, until the runtime reparent
	# happens). Grabbing the reference here means this test does not need to
	# know or guess the instanced WorldArea's node name — the same Node
	# instance is what gets reparented, so the reference stays valid for the
	# position check below regardless of where _ready() subsequently moves it.
	var world: Node = packed.instantiate()
	var player: Node2D = world.get_node_or_null("Player") as Node2D
	assert_not_null(player, "world.tscn must have a child node named 'Player' prior to _ready()")
	if player == null:
		return

	# NOW add to the test's scene tree so World._ready() runs — this is what
	# triggers the Slice 8 reparent (_player.reparent(area)), same as it
	# previously triggered the Issue #36 bug's viewport-centre overwrite.
	# add_child_autofree ensures the node (and its children, including
	# Player, wherever _ready() ends up moving it to) is freed when the test
	# ends, preventing a node-leak warning in GUT.
	# https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-add-child
	add_child_autofree(world)

	# The critical assertion: after _ready() has run (and Player has been
	# reparented into the WorldArea per design doc §12.1), Player must still
	# be at the position authored in world.tscn. Before the Issue #36 fix,
	# World._ready() called _place_player_at_viewport_centre(), which
	# overwrote this with get_viewport_rect().size / 2.0 — clobbering the
	# scene-authored spawn point on every launch. reparent()'s default
	# keep_global_transform=true preserves global position across the move;
	# since the shell's ActiveArea/WorldArea wrapper nodes introduce no
	# offset of their own, Player's LOCAL position should still read as the
	# original authored value even parented under the new WorldArea.
	# https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-reparent
	assert_eq(
		player.position,
		EXPECTED_SPAWN_POSITION,
		(
		"Player.position must remain the scene-authored spawn point "
		+ "(%s) after World._ready() runs (and Player has been reparented "
		+ "into the active WorldArea), not the viewport centre and not "
		+ "shifted by the reparent. If this fails, either world.gd is still "
		+ "clobbering the authored position (see Issue #36), or the "
		+ "reparent introduced an unexpected offset (check ActiveArea/the "
		+ "WorldArea instance for a non-zero position)."
		) % [EXPECTED_SPAWN_POSITION]
	)
