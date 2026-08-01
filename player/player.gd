extends CharacterBody2D
## Player movement controller for Cream Bun.
## Reads directional input and moves in screen space.
## The Camera2D child follows automatically.
##
## Also publishes the player's own geometry — get_collider_extent() and
## get_visual_extent() — so the world can derive boundary geometry from it
## instead of hard-coding a copy. See those methods for why.

@export var speed: float = 200.0

## Cached results of the two extent getters below. Both are pure functions of
## the scene's own contents, which never change at runtime, so they are
## computed on first use and kept. Rect2() is the "not computed yet" sentinel;
## a real extent always has a non-zero size.
var _collider_extent := Rect2()
var _visual_extent := Rect2()


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
## Published rather than left for callers to dig out of the scene tree because
## the world's boundary geometry depends on it: `WorldArea` needs to know how
## far above the ground anchor the player's collider reaches in order to place
## the north edge correctly (design doc §12.4). Reading it from here means that
## re-shaping the collider in player.tscn moves the world's geometry with it,
## rather than silently invalidating a constant in another file.
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


## The extent of the DRAWN character relative to this node's origin, in px —
## the bounding box of actually-opaque pixels, not of the sprite frame.
##
## The two differ by a lot here: the frames are 32x32 but carry 5px of
## transparent padding on every side, so the character occupies only the middle
## 22x22. `WorldArea` uses this to work out how much headroom the camera needs
## above the player at a map's north edge (design doc §12.4) — measuring the
## frame instead would over-estimate by 5px and cost every map in the game an
## extra non-walkable tile row.
##
## Computed as the union across EVERY frame of every animation, not just the
## idle pose: a walk frame that leans further than the idle one still has to
## fit on screen. That is ~36 tiny images decoded once, on first call.
##
## Trade-off worth knowing: because this reads alpha, any opaque pixel counts —
## a stray particle or a tall hat added to a single frame will widen this box
## and can push the north headroom inset up a whole tile row for every area in
## the game. That is arguably correct (the new pixels *should* stay on screen),
## but it is a real coupling from art to map layout, and the alternative is to
## measure the frame rectangle instead and accept the looser inset.
## https://docs.godotengine.org/en/stable/classes/class_image.html#class-image-method-get-used-rect
func get_visual_extent() -> Rect2:
	if _visual_extent.size != Vector2.ZERO:
		return _visual_extent

	var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite == null or sprite.sprite_frames == null:
		push_error("Player.get_visual_extent: no AnimatedSprite2D with SpriteFrames found")
		return Rect2()

	var frames: SpriteFrames = sprite.sprite_frames
	var union := Rect2()
	var found_any: bool = false

	for animation in frames.get_animation_names():
		for index in frames.get_frame_count(animation):
			var texture: Texture2D = frames.get_frame_texture(animation, index)
			if texture == null:
				continue

			# get_image() on the already-loaded texture, rather than
			# Image.load() on a res:// path, avoids Godot's "Loaded resource as
			# image file" warning on assets that have a texture import.
			var image: Image = texture.get_image()
			if image == null:
				continue
			var opaque: Rect2i = image.get_used_rect()
			if opaque.size.x <= 0 or opaque.size.y <= 0:
				continue

			# AnimatedSprite2D draws each frame centred on `offset` when
			# `centered` is true (the default), so the frame's top-left corner
			# in this node's local space is offset - frame_size / 2.
			var frame_size := Vector2(texture.get_width(), texture.get_height())
			var frame_origin: Vector2 = sprite.offset
			if sprite.centered:
				frame_origin -= frame_size / 2.0

			var frame_extent := Rect2(
					frame_origin + Vector2(opaque.position), Vector2(opaque.size))
			union = frame_extent if not found_any else union.merge(frame_extent)
			found_any = true

	if not found_any:
		push_error("Player.get_visual_extent: no frame contained any opaque pixels")
		return Rect2()

	_visual_extent = union
	return _visual_extent
