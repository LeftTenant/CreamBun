extends CharacterBody2D
## Player movement controller for Cream Bun.
## Reads directional input and moves in screen space.
## The Camera2D child follows automatically.

@export var speed: float = 200.0


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
