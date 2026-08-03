extends CharacterBody2D
## Player movement controller for Cream Bun.
## Reads directional input and moves in screen space.
## The Camera2D child follows automatically.
##
## Also publishes the player's own geometry — get_collider_extent() — so
## other systems can derive geometry from it instead of hard-coding a copy.
## See that method for why.
##
## World Thresholds Slice 4 (docs/features/world-thresholds/design.md §9)
## deletes get_visual_extent(), the sibling getter that used to feed
## WorldArea's north-edge camera-headroom inset — that inset is gone (design
## §8: the north edge may clip the character by default, a content decision
## now, not a code one), and get_visual_extent() had no other caller.

@export var speed: float = 200.0

## Cached result of the extent getter below — a pure function of the scene's
## own contents, which never change at runtime, so it is computed on first
## use and kept. Rect2() is the "not computed yet" sentinel; a real extent
## always has a non-zero size.
var _collider_extent := Rect2()


func _physics_process(_delta: float) -> void:
	if GameState.current_state != GameState.State.PLAYING:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input_dir * speed
	move_and_slide()

	if velocity.length() > 0:
		GameEvents.player_moved.emit(global_position)


## The player's collision shape's extent relative to this node's origin, in px.
##
## Published rather than left for callers to dig out of the scene tree so
## anything that needs to reason about the movement collider's real geometry
## (tests, `tests/integration/world/shared/collision_probe.gd`) reads it from
## one place rather than re-deriving or hard-coding a copy. Re-shaping the
## collider in player.tscn moves every caller's answer with it automatically.
##
## Handles both shapes this scene has used — the current CapsuleShape2D and the
## earlier RectangleShape2D — so trying a different collider shape doesn't also
## require editing this method.
func get_collider_extent() -> Rect2:
	if _collider_extent.size != Vector2.ZERO:
		return _collider_extent

	var collision: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null:
		push_error("Player.get_collider_extent: no CollisionShape2D child found")
		return Rect2()

	var half := Vector2.ZERO
	if collision.shape is CapsuleShape2D:
		var capsule: CapsuleShape2D = collision.shape as CapsuleShape2D
		# A CapsuleShape2D is authored with its long axis on Y; this scene
		# rotates the CollisionShape2D 90° to lay it on its side, so which of
		# height/radius maps to which world axis depends on that rotation.
		var lengthwise: float = capsule.height / 2.0
		var across: float = capsule.radius
		var horizontal: bool = absf(sin(collision.rotation)) > 0.5
		half = Vector2(lengthwise, across) if horizontal else Vector2(across, lengthwise)
	elif collision.shape is RectangleShape2D:
		half = (collision.shape as RectangleShape2D).size / 2.0
	else:
		push_error("Player.get_collider_extent: unsupported shape %s" % [collision.shape])
		return Rect2()

	_collider_extent = Rect2(collision.position - half, half * 2.0)
	return _collider_extent
