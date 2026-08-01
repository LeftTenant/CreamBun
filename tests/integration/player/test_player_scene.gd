## test_player_scene.gd
## Integration tests for player/player.tscn — verifying scene-as-data properties
## that cannot be checked by reading project.godot alone.
##
## This file mirrors the source location: player/ → tests/integration/player/.
##
## Camera2D smoothing — SUPERSEDED, see world-collision Slice 9: Slice 4
## (pixel-art-purist) originally required position_smoothing_enabled to stay
## false, relying on Godot's engine default (smoothing off) to avoid sub-pixel
## shimmer on pixel art. World-collision design.md §12.3 resolves this in favor
## of turning smoothing ON: the two-tile camera dead zone (drag margins) needs
## a soft "cozy glide" as the camera catches up once the player leaves it,
## which requires position_smoothing_enabled = true. The slice-9 test plan's
## "Decision: smoothing enabled (resolved)" section records this explicitly as
## superseding the Slice 4 shimmer guard. The test below —
## test_camera2d_position_smoothing_enabled() — was renamed from
## test_camera2d_position_smoothing_not_enabled() (which asserted the old,
## now-wrong requirement in both its name and docstring) rather than simply
## flipping its assertion, so no misleadingly-named test survives into the
## suite. See also tests/integration/world/test_camera_dead_zone_and_limits.gd,
## which checks the same property on the live, world-loaded camera.
##
## Slice 3 concern: the player's ground anchor and collider. Node origin must
## be the FEET (ground contact point), not the body centre — this is what
## makes depth sorting (Node2D.y_sort_enabled keys off global_position.y) and
## Solids collision line up correctly in later slices. The AnimatedSprite2D is
## offset upward so the 32x32 frame sits above that origin, and
## collision_layer/mask are restricted to "player" / "world" per the named
## layers in project.godot's [layer_names] (design.md §11).
##
## The collider itself has since been re-shaped (see the collider tests below
## for the full history): it is now a horizontal CapsuleShape2D lifted off the
## origin to hug the bottom of the drawn character, rather than a
## RectangleShape2D centred on it. The ANCHOR is unchanged — only the shape
## and its offset moved.
##
## Design reference:
##   docs/refactors/pixel-art-purist-size-and-theme.md §7 Step 5
##   docs/features/pixel-art-purist/slice-4-pixel-perfect-stretch-snap-test-plan.md
##   docs/features/world-collision/design.md §10 (player collider), §11 (layers)
##   docs/features/world-collision/slice-3-player-collider-test-plan.md
##   docs/features/world-collision/player-collider-capsule-test-plan.md
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

# Expected collider (design.md §10). A horizontal CapsuleShape2D, not the
# RectangleShape2D this file originally asserted: a rectangle's sharp corners
# catch on the corners of tile collision polygons, and terrain edges are
# authored per-tile so adjacent polygons don't always line up to the pixel.
# The capsule's rounded ends let move_and_slide() deflect off those staggered
# sub-pixel steps instead of snagging on every one.
#
# CapsuleShape2D.height is the FULL length along its long axis (caps
# included), and radius is half its width across — so (5, 22) is a 22x10 pill
# lying on its side once the CollisionShape2D is rotated 90°.
# https://docs.godotengine.org/en/stable/classes/class_capsuleshape2d.html
const EXPECTED_CAPSULE_RADIUS: float = 5.0
const EXPECTED_CAPSULE_HEIGHT: float = 22.0

# 90° in radians, as stored in player.tscn — the CollisionShape2D is turned on
# its side so the capsule's long axis runs along X (the player is wider than
# they are deep, matching the world's 2:1 foreshortening).
const EXPECTED_COLLIDER_ROTATION_RAD: float = PI / 2.0

# The collider does NOT straddle the origin. It is lifted to sit against the
# bottom of the DRAWN character: the sprite frames carry 5px of transparent
# padding, so a collider centred on the origin sat visibly below Cream Bun's
# feet and left a gap between them and whatever they were pressed against.
const EXPECTED_COLLIDER_POSITION: Vector2 = Vector2(0.0, -9.0)

# The collider's resulting extent relative to the player's origin:
#   x: 0 ± (height/2)  = [-11, 11]
#   y: -9 ± radius     = [-14, -4]
# Asserted as a derived rect as well as via the individual properties above,
# so a future edit that trades radius/height/rotation/position around while
# preserving each property in isolation still can't drift the actual footprint.
const EXPECTED_COLLIDER_EXTENT: Rect2 = Rect2(-11.0, -14.0, 22.0, 10.0)

# The player sprite's 32x32 frames carry 5px of fully-transparent padding on
# every side, so the drawn character is 22px wide — exactly the capsule's
# 22px length. This is the tie between the collider and the art it was
# traced from (design.md §10, "what you see is what collides").
const SPRITE_FRAME_SIZE_PX: int = 32
const SPRITE_TRANSPARENT_PADDING_PX: int = 5

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
# Camera2D position-smoothing guard (world-collision Slice 9 — supersedes the
# old pixel-art-purist Slice 4 requirement that smoothing stay OFF; see the
# test below for the full history of that reversal)
# ---------------------------------------------------------------------------

func test_camera2d_position_smoothing_enabled() -> void:
	# RENAMED from test_camera2d_position_smoothing_not_enabled() — world-collision
	# design.md §12.3 (world-collision Slice 9) supersedes the old Slice 4
	# (pixel-art-purist) shimmer guard that required smoothing to stay OFF.
	#
	# Why the reversal: Slice 9 gives the camera a two-tile "dead zone" via
	# Camera2D's drag margins (see test_camera_dead_zone_and_limits.gd) — the
	# player can drift within it before the camera starts panning to follow.
	# Without position_smoothing_enabled, the camera would snap instantly to
	# the dead-zone boundary the moment the player exits it, which reads as an
	# abrupt jerk rather than the "soft cozy glide" design.md §12.3 calls for.
	# Smoothing trades the old pixel-perfect-tracking guarantee for that glide
	# — a deliberate, resolved trade-off (see the slice-9 test plan's
	# "Decision: smoothing enabled (resolved)" section), not an oversight.
	#
	# If this test ever fails, the fix is a single scene property set:
	#   Camera2D.position_smoothing_enabled = true (explicit, documented)
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

	# The critical assertion: smoothing must be active for the cozy glide.
	# Checking the live property catches both a missing explicit override and
	# any future script logic that might turn it back off in _ready().
	assert_true(
		camera.position_smoothing_enabled,
		(
			"Camera2D.position_smoothing_enabled must be true — the two-tile "
			+ "dead zone (design.md §12.3) needs a soft glide as the camera "
			+ "catches up once the player leaves it, superseding the old "
			+ "pixel-art-purist shimmer guard. If this fails, add "
			+ "'position_smoothing_enabled = true' explicitly to the "
			+ "Camera2D node in player.tscn."
		)
	)


# ---------------------------------------------------------------------------
# Ground anchor & collider (Slice 3)
# ---------------------------------------------------------------------------

## The player's CollisionShape2D, or null (with the failure already recorded)
## if the node is missing. Shared by the four collider-shape tests below so
## none of them re-does the lookup — and so a missing node produces one clear
## failure per test rather than a null dereference.
func _get_collision_shape_node() -> CollisionShape2D:
	var collision: CollisionShape2D = (
		_player.get_node_or_null("CollisionShape2D") as CollisionShape2D
	)
	assert_not_null(
		collision,
		"player.tscn must have a CollisionShape2D child node"
	)
	return collision


func test_collision_shape_is_a_capsule() -> void:
	# RENAMED from test_collision_shape_is_rectangle_sized_to_ground_footprint().
	# Two shapes have been rejected here now, for different reasons:
	#   - CircleShape2D(radius=16), the original: collided with the player's
	#     whole body, head included. Solid things live on the ground.
	#   - RectangleShape2D(20, 10), its replacement: correct in size, but its
	#     four sharp corners catch on the corners of tile collision polygons.
	#     Terrain edges are authored per tile (design.md §7) and adjacent
	#     polygons don't always line up to the pixel, so a boundary that reads
	#     as one continuous fence is really a run of slightly staggered
	#     polygons — a rectangle snags on every step of it.
	# A capsule's rounded ends let move_and_slide() deflect off those steps.
	# The old name asserted the rejected shape in its own name, so it was
	# renamed rather than having its assertion flipped underneath it.
	if _player == null:
		return

	var collision: CollisionShape2D = _get_collision_shape_node()
	if collision == null:
		return

	var shape: Shape2D = collision.shape
	assert_true(
		shape is CapsuleShape2D,
		(
			"player.tscn's CollisionShape2D.shape must be a CapsuleShape2D "
			+ "(found %s) — a rectangle's corners catch on staggered tile-edge "
			+ "collision polygons and stop the player on nothing visible; see "
			+ "design.md §10."
		) % [shape]
	)
	if not (shape is CapsuleShape2D):
		return

	var capsule: CapsuleShape2D = shape as CapsuleShape2D
	assert_eq(
		capsule.radius,
		EXPECTED_CAPSULE_RADIUS,
		(
			"player.tscn's CapsuleShape2D.radius must be %.1f (half the "
			+ "collider's 10px depth) — design.md §10."
		) % [EXPECTED_CAPSULE_RADIUS]
	)
	assert_eq(
		capsule.height,
		EXPECTED_CAPSULE_HEIGHT,
		(
			"player.tscn's CapsuleShape2D.height must be %.1f — the drawn "
			+ "character's exact width (a 32px frame less 5px of transparent "
			+ "padding each side), design.md §10."
		) % [EXPECTED_CAPSULE_HEIGHT]
	)


func test_collision_shape_lies_horizontally() -> void:
	# A CapsuleShape2D is authored vertically (long axis on Y). The player is
	# wider than they are deep, matching the world's 2:1 foreshortening, so the
	# CollisionShape2D is rotated 90° to lay the capsule on its side. Without
	# this the same radius/height would describe a 10-wide, 22-deep collider —
	# the right numbers on the wrong axes, which the two size assertions above
	# cannot distinguish on their own.
	if _player == null:
		return

	var collision: CollisionShape2D = _get_collision_shape_node()
	if collision == null:
		return

	assert_almost_eq(
		collision.rotation,
		EXPECTED_COLLIDER_ROTATION_RAD,
		0.001,
		(
			"player.tscn's CollisionShape2D.rotation must be %.4f rad (90°) so "
			+ "the capsule's long axis runs along X — design.md §10."
		) % [EXPECTED_COLLIDER_ROTATION_RAD]
	)


func test_collision_shape_sits_against_the_bottom_of_the_drawn_character() -> void:
	# REPLACES test_collision_shape_centred_on_player_origin(), which asserted
	# position == Vector2.ZERO.
	#
	# The origin is still the ground anchor — Y-sort and the camera both key
	# off it, and that has not changed. What changed is that the COLLIDER no
	# longer straddles it. The sprite frames carry 5px of transparent padding
	# below the character, so a collider centred on the origin sat visibly
	# below Cream Bun's feet: the player stopped with a gap between themselves
	# and the wall they were pressed against. Lifting the collider to (0, -9)
	# closes that gap without moving the anchor (design.md §10).
	if _player == null:
		return

	var collision: CollisionShape2D = _get_collision_shape_node()
	if collision == null:
		return

	assert_eq(
		collision.position,
		EXPECTED_COLLIDER_POSITION,
		(
			"player.tscn's CollisionShape2D.position must be %s — lifted off "
			+ "the origin so the collider hugs the bottom of the DRAWN "
			+ "character rather than straddling the ground anchor "
			+ "(design.md §10). The anchor itself is unchanged."
		) % [EXPECTED_COLLIDER_POSITION]
	)


func test_collider_extent_relative_to_the_player_origin() -> void:
	# The load-bearing assertion of this group: the other three pin individual
	# properties, but it is the resulting EXTENT that the north headroom inset
	# (design.md §12.4) and the north-entry spawn margin (§12.5) are both
	# derived from. Computing it here means a change that swaps values between
	# radius/height/rotation/position — each still "correct" in isolation —
	# cannot silently move the footprint those two derivations depend on.
	#
	# Rebuilt from the shape and transform rather than read off a bounding box,
	# so it reflects what the physics server will actually use.
	if _player == null:
		return

	var collision: CollisionShape2D = _get_collision_shape_node()
	if collision == null:
		return
	var capsule: CapsuleShape2D = collision.shape as CapsuleShape2D
	if capsule == null:
		return

	# Rotated 90°, the capsule's height runs along X and its diameter along Y.
	var half_length: float = capsule.height / 2.0
	var half_depth: float = capsule.radius
	var extent := Rect2(
		collision.position.x - half_length,
		collision.position.y - half_depth,
		half_length * 2.0,
		half_depth * 2.0
	)

	assert_eq(
		extent,
		EXPECTED_COLLIDER_EXTENT,
		(
			"the player's collider must span %s relative to the node origin "
			+ "(found %s). This extent — not the individual shape properties — "
			+ "is what design.md §12.4's north headroom inset and §12.5's "
			+ "north-entry spawn margin are derived from; moving it means "
			+ "re-deriving both."
		) % [EXPECTED_COLLIDER_EXTENT, extent]
	)


func test_collider_width_matches_the_drawn_character_width() -> void:
	# Ties the collider back to the art it was traced from, so "what you see is
	# what collides" (design.md §10) is a checked claim rather than a comment.
	# The sprite frames are 32x32 with 5px of fully-transparent padding on every
	# side, leaving a 22px-wide character — which is exactly the capsule's
	# length. If an artist reworks the sprite with different padding, this fails
	# and points at the collider that now needs re-tracing.
	if _player == null:
		return

	var collision: CollisionShape2D = _get_collision_shape_node()
	if collision == null:
		return
	var capsule: CapsuleShape2D = collision.shape as CapsuleShape2D
	if capsule == null:
		return

	var drawn_width: int = (
		SPRITE_FRAME_SIZE_PX - SPRITE_TRANSPARENT_PADDING_PX * 2
	)
	assert_eq(
		capsule.height,
		float(drawn_width),
		(
			"the capsule's %.1fpx length must equal the drawn character's "
			+ "%dpx width (a %dpx frame less %dpx of transparent padding on "
			+ "each side) — design.md §10 traces the collider from the art, so "
			+ "the two must not drift apart."
		) % [
			capsule.height,
			drawn_width,
			SPRITE_FRAME_SIZE_PX,
			SPRITE_TRANSPARENT_PADDING_PX,
		]
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
