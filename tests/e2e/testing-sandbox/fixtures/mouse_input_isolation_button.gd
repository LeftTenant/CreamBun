class_name MouseInputIsolationButton
extends Button
## Regression fixture for issue #41 — testing-sandbox mouse events never
## reaching a Control node.
##
## This script exists ONLY to make every stage of a click independently
## observable via `get_node_property`, without depending on screenshot
## comparison. It intentionally lives outside ui/ and outside the Notebook so
## it is never affected by Notebook.open()'s `get_tree().paused = true` —
## the isolation scenario driving this fixture is meant to prove (or
## disprove) that the sandbox's mouse commands reach a Control at all, before
## the paused-notebook case is considered.
##
## `toggle_mode` is set on the Button in mouse_input_isolation.tscn (not here)
## per the "author static structure in the .tscn" rule in ui/CLAUDE.md — this
## script is data binding / signal wiring only, even though this fixture
## itself lives outside ui/.
##
## Counters instead of booleans so a scenario can assert "happened exactly
## once" / "happened twice", catching both "never fires" and "fires on every
## frame" failure modes.
##
## BaseButton signals reference:
## https://docs.godotengine.org/en/4.4/classes/class_basebutton.html

## Bumped on Button.mouse_entered — proves mouse_move alone reaches this
## Control's hover detection, before any button is pressed. Isolates
## "pointer motion doesn't route to GUI" from "clicks specifically fail".
var hover_count: int = 0

## Bumped on Button.button_down — the press half of a click. This is the
## "purely client-side pressed visual state" issue #41 calls out: it flips
## the instant BaseButton sees a GUI mouse-button-down inside its rect, with
## no signal bus or autoload involved at all.
var button_down_count: int = 0

## Bumped on Button.button_up — the release half of a click.
var button_up_count: int = 0

## Bumped on Button.pressed — a full press+release cycle completed inside the
## button's rect. This is the same signal every real interactive Control in
## the game relies on (SettingsTab's ResetButton, OptionButton items, etc).
var click_count: int = 0


func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)
	pressed.connect(_on_pressed)


func _on_mouse_entered() -> void:
	hover_count += 1


func _on_button_down() -> void:
	button_down_count += 1


func _on_button_up() -> void:
	button_up_count += 1


func _on_pressed() -> void:
	click_count += 1
