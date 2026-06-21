## test_player_scene.gd
## Integration tests for player/player.tscn — verifying scene-as-data properties
## that cannot be checked by reading project.godot alone.
##
## This file mirrors the source location: player/ → tests/integration/player/.
##
## Slice 4 concern: the Camera2D in player.tscn must NOT have
## position_smoothing_enabled=true. The Slice 4 design relies on Godot's
## engine default of false (smoothing off). If any editor action or merge ever
## sets it explicitly to true in the .tscn, this test will catch the regression
## before the e2e shimmer check is needed.
##
## Design reference:
##   docs/refactors/pixel-art-purist-size-and-theme.md §7 Step 5
##   docs/features/pixel-art-purist/slice-4-pixel-perfect-stretch-snap-test-plan.md
##
## Requires GUT: https://github.com/bitwes/Gut
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gselect=test_player_scene.gd -gexit

class_name TestPlayerScene
extends GutTest


# Path to the player scene — loaded as a PackedScene so we can inspect the
# node tree without entering the scene tree. This keeps the test hermetic;
# no autoloads need to be live.
# https://docs.godotengine.org/en/stable/classes/class_packedscene.html
const PLAYER_SCENE_PATH: String = "res://player/player.tscn"


# ---------------------------------------------------------------------------
# Camera2D position-smoothing guard (Slice 4)
# ---------------------------------------------------------------------------

func test_camera2d_position_smoothing_not_enabled() -> void:
	# Slice 4 relies on Camera2D.position_smoothing_enabled being false so that
	# the camera tracks the player at exact pixel positions each frame. If
	# smoothing is on, the camera lags behind and sub-pixel offsets cause
	# shimmer on world sprites — exactly what the snap flags in project.godot
	# are designed to prevent.
	#
	# Godot's engine default for position_smoothing_enabled is false, so the
	# property should NOT appear explicitly in the .tscn as true. This test
	# instantiates the scene and reads the live property value to catch any
	# accidental editor override.
	#
	# If this test ever fails, the fix is a single scene property set:
	#   Camera2D.position_smoothing_enabled = false (explicit, documented)
	# That one-liner is not in scope for Slice 4 unless this test regresses.

	# Load the scene as a PackedScene resource (does not add to tree).
	var packed: PackedScene = load(PLAYER_SCENE_PATH)
	assert_not_null(packed, "player/player.tscn should load as a PackedScene")
	if packed == null:
		return

	# Instantiate and add to a temporary parent so _ready() can run safely.
	# add_child_autofree ensures the node is freed when the test ends, preventing
	# a node-leak warning in GUT.
	# https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-add-child
	var player: Node = packed.instantiate()
	add_child_autofree(player)

	# Locate the Camera2D child by name. The plan confirms it is a direct child
	# of the Player root node named "Camera2D".
	var camera: Camera2D = player.get_node_or_null("Camera2D") as Camera2D
	assert_not_null(
		camera,
		"player.tscn must have a Camera2D child node named 'Camera2D'"
	)
	if camera == null:
		return

	# The critical assertion: smoothing must not be active.
	# Checking the live property catches both an explicit true and any future
	# script logic that might set it in _ready().
	assert_false(
		camera.position_smoothing_enabled,
		(
			"Camera2D.position_smoothing_enabled must be false — "
			+ "smoothing causes sub-pixel shimmer on pixel art. "
			+ "If this fails, add 'position_smoothing_enabled = false' "
			+ "explicitly to the Camera2D node in player.tscn."
		)
	)
