extends Node
## Central signal bus for cross-system communication.
## Use GameEvents only for events that cross scene boundaries.
## For parent/child communication within a scene, use direct $Node references.

# Player
signal player_moved(position: Vector2)

# Game state
signal game_state_changed(old_state: int, new_state: int)
