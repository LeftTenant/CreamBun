## test_player_scene.gd
## Integration tests for player/player.tscn — verifying scene-as-data properties
## that cannot be checked by reading project.godot alone.
##
## This file mirrors the source location: player/ → tests/integration/player/.
##
## Slice 4 (pixel-art-purist) concern: the Camera2D in player.tscn must NOT have
## position_smoothing_enabled=true. The Slice 4 design relies on Godot's
## engine default of false (smoothing off). If any editor action or merge ever
## sets it explicitly to true in the .tscn, this test will catch the regression
## before the e2e shimmer check is needed.
##
## Slice 3 concern: the player's ground anchor and collider. Node origin must
## be the FEET (ground contact point), not the body centre — this is what
## makes depth sorting (Node2D.y_sort_enabled keys off global_position.y) and
## Solids collision line up correctly in later slices. Concretely: a RectangleShape2D
## collider sized to the ground footprint, centred on the origin (unlike a
## WorldProp, whose origin is its footprint's front edge — see design.md §8.1
## vs §10); the AnimatedSprite2D offset upward so the 32x32 frame sits above
## that origin; and collision_layer/mask restricted to "player" / "world" per
## the named layers in project.godot's [layer_names] (design.md §11).
##
## Design reference:
##   docs/refactors/pixel-art-purist-size-and-theme.md §7 Step 5
##   docs/features/pixel-art-purist/slice-4-pixel-perfect-stretch-snap-test-plan.md
##   docs/features/world-collision/design.md §10 (player collider), §11 (layers)
##   docs/features/world-collision/slice-3-player-collider-test-plan.md
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

# Expected ground-footprint collider (design.md §10): a little under one tile
# wide (32px) and one tile deep (16px), in the world's 2:1 foreshortening
# ratio — sub-tile on purpose so the player can slip through a one-tile gap.
const EXPECTED_COLLIDER_SIZE: Vector2 = Vector2(20.0, 10.0)

# The AnimatedSprite2D's 32x32 frame must be offset upward so it sits above
# the origin instead of straddling it (design.md §10 — "origin at the FEET").
# -16 is half the sprite's 32x32 frame height, not a tile-depth measurement:
# AnimatedSprite2D.centered defaults to true, so the frame is drawn straddling
# its offset point; shifting by half the frame height moves the frame's top
# to where the origin used to sit, leaving the origin (now the feet) at the
# frame's bottom edge instead. It's a coincidence that -16 also equals the
# world's 16px tile depth (design.md §10) — changing the tile depth would NOT
# change this value, since it is derived from frame size, not tile geometry.
const EXPECTED_SPRITE_OFFSET: Vector2 = Vector2(0.0, -16.0)

# Physics layer bit values, per project.godot's [layer_names] section:
#   2d_physics/layer_1="world"   -> bit 0 -> value 1
#   2d_physics/layer_2="player"  -> bit 1 -> value 2
# The player collides AS "player" and collides WITH "world" only
# (design.md §11's collision layer/mask table).
const WORLD_LAYER_BIT: int = 1
const PLAYER_LAYER_BIT: int = 2

# Instantiated fresh in before_each() so every test gets an isolated player
# node, matching GUT's per-test isolation convention.
var _player: CharacterBody2D = null


func before_each() -> void:
	# Load the scene as a PackedScene resource, then instantiate and add to
	# the test's scene tree so _ready() runs. add_child_autofree ensures the
	# node is freed after each test, preventing a node-leak warning in GUT.
	# https://docs.godotengine.org/en/stable/classes/class_packedscene.html
	# https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-add-child
	var packed: PackedScene = load(PLAYER_SCENE_PATH)
	assert_not_null(packed, "player/player.tscn should load as a PackedScene")
	if packed == null:
		return

	_player = packed.instantiate() as CharacterBody2D
	assert_not_null(_player, "player.tscn's root must be a CharacterBody2D")
	if _player == null:
		return

	add_child_autofree(_player)


func after_each() -> void:
	_player = null


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
	if _player == null:
		return

	# Locate the Camera2D child by name. The plan confirms it is a direct child
	# of the Player root node named "Camera2D".
	var camera: Camera2D = _player.get_node_or_null("Camera2D") as Camera2D
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


# ---------------------------------------------------------------------------
# Ground anchor & collider (Slice 3)
# ---------------------------------------------------------------------------

func test_collision_shape_is_rectangle_sized_to_ground_footprint() -> void:
	# The old CircleShape2D(radius=16) collided with the player's whole body,
	# including their head — solid things live on the ground, so the collider
	# must be a small rectangle approximating the player's footprint instead.
	# See design.md §10 for why (20, 10) specifically (sub-tile, 2:1 ratio).
	if _player == null:
		return

	var collision: CollisionShape2D = (
		_player.get_node_or_null("CollisionShape2D") as CollisionShape2D
	)
	assert_not_null(
		collision,
		"player.tscn must have a CollisionShape2D child node"
	)
	if collision == null:
		return

	var shape: Shape2D = collision.shape
	assert_true(
		shape is RectangleShape2D,
		(
			"player.tscn's CollisionShape2D.shape must be a RectangleShape2D "
			+ "(found %s). A CircleShape2D collides with the player's whole "
			+ "body instead of just their feet — see design.md §10."
		) % [shape]
	)
	if not (shape is RectangleShape2D):
		return

	assert_eq(
		(shape as RectangleShape2D).size,
		EXPECTED_COLLIDER_SIZE,
		(
			"player.tscn's RectangleShape2D.size must be %s — "
			+ "a little under one tile wide and one tile deep, in the "
			+ "world's 2:1 foreshortening ratio (design.md §10)."
		) % [EXPECTED_COLLIDER_SIZE]
	)


func test_collision_shape_centred_on_player_origin() -> void:
	# Unlike a WorldProp (whose origin is its footprint's front edge, §8.1),
	# the player moves freely rather than snapping to a grid, so "front edge"
	# isn't a meaningful anchor — the collider stays centred on the origin
	# (design.md §10, "Why centred on the origin, not offset like props").
	if _player == null:
		return

	var collision: CollisionShape2D = (
		_player.get_node_or_null("CollisionShape2D") as CollisionShape2D
	)
	assert_not_null(
		collision,
		"player.tscn must have a CollisionShape2D child node"
	)
	if collision == null:
		return

	assert_eq(
		collision.position,
		Vector2.ZERO,
		(
			"player.tscn's CollisionShape2D.position must be Vector2(0, 0) — "
			+ "centred on the player's origin, not offset like a WorldProp "
			+ "(design.md §10)."
		)
	)


func test_animated_sprite_offset_places_frame_above_ground_anchor() -> void:
	# The node origin is now the ground anchor (the feet). The 32x32 sprite
	# frame must be pushed upward from it so Cream Bun's feet — not their
	# midriff — sit at the origin (design.md §10, §9 rule 3/4).
	if _player == null:
		return

	var sprite: AnimatedSprite2D = (
		_player.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	)
	assert_not_null(
		sprite,
		"player.tscn must have an AnimatedSprite2D child node"
	)
	if sprite == null:
		return

	assert_eq(
		sprite.offset,
		EXPECTED_SPRITE_OFFSET,
		(
			"player.tscn's AnimatedSprite2D.offset must be %s so the 32x32 "
			+ "frame sits above the origin instead of straddling it "
			+ "(design.md §10)."
		) % [EXPECTED_SPRITE_OFFSET]
	)


func test_collision_layer_is_player_only() -> void:
	# The player must declare itself on the "player" layer (project.godot
	# [layer_names] layer_2) and nothing else, so other player-layer bodies
	# (there are none yet, but the layer exists for future use) can find it
	# without also picking up "world" or "interactable" traffic
	# (design.md §11).
	if _player == null:
		return

	assert_eq(
		_player.collision_layer,
		PLAYER_LAYER_BIT,
		(
			"Player's collision_layer must be exactly the 'player' layer "
			+ "(value %d per project.godot's [layer_names]), not the "
			+ "engine default of layer 1 ('world') or any other combination."
		) % [PLAYER_LAYER_BIT]
	)


func test_collision_mask_is_world_only() -> void:
	# The player must collide WITH "world" (solid terrain + props) only — not
	# with "interactable" Area2D triggers, which detect the player rather than
	# physically block it (design.md §11's collision layer/mask table).
	if _player == null:
		return

	assert_eq(
		_player.collision_mask,
		WORLD_LAYER_BIT,
		(
			"Player's collision_mask must be exactly the 'world' layer "
			+ "(value %d per project.godot's [layer_names]), so the player "
			+ "collides with solid terrain and props and nothing else."
		) % [WORLD_LAYER_BIT]
	)
