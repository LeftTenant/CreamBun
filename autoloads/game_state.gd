extends Node
## Global game state machine.
## Player movement is disabled outside the PLAYING state.

enum State {
	MAIN_MENU,
	PLAYING,
	DIALOGUE,
	INVENTORY,
	COMBAT,
	PAUSED,
	LOADING,
}

var current_state: State = State.PLAYING


func change_state(new_state: State) -> void:
	if new_state == current_state:
		return
	var old_state := current_state
	current_state = new_state
	GameEvents.game_state_changed.emit(old_state, new_state)
