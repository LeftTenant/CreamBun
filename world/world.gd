extends Node2D
## World scene orchestrator — wires the scene graph from autoloads and
## sets up initial world-level state.
##
## Per CLAUDE.md, the world scene is the natural owner of scene-wiring from
## autoloads (dependency injection point). Direct autoload access is acceptable
## here specifically because this node's job is orchestration.

# @onready resolves $Player before _ready() runs, giving us a typed reference
# without an explicit get_node() call in _ready().
# https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html#onready-annotation
@onready var _player: CharacterBody2D = $Player


func _ready() -> void:
	_place_player_at_viewport_centre()
	_set_minimum_window_size()


## Position the player at the centre of the current render viewport so the
## spawn point stays correct regardless of the configured viewport resolution.
##
## We read the live viewport size at runtime rather than hard-coding a constant
## (e.g. Vector2(160, 90)) so that if the render resolution changes again the
## spawn automatically follows without a code edit.
##
## get_viewport_rect() returns the viewport's Rect2 in local-space pixels.
## https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-get-viewport-rect
func _place_player_at_viewport_centre() -> void:
	_player.position = get_viewport_rect().size / 2.0


## Prevent the OS window from being dragged smaller than the 2× scale size.
##
## The smallest selectable scale in the Settings tab is 2×, which gives a
## 640×360 window. Below that the stretched viewport becomes illegibly small.
## Setting Window.min_size to 2× the base viewport enforces the same floor the
## Settings UI offers.
##
## Units note: the project runs with `allow_hidpi=false`, so Godot measures the
## window in logical points (matching what macOS reports and what the Settings
## scale labels show). This is deliberate — on HiDPI "scaled" displays Godot
## cannot reliably detect the backing scale factor (DisplayServer.screen_get_scale
## returns the wrong value), so physical-pixel sizing would make every window
## appear at roughly half its intended on-screen size. See the pixel-art-purist
## refactor notes.
##
## We derive the base viewport size from ProjectSettings rather than
## hard-coding (640, 360) so this stays correct if the viewport resolution
## is ever changed in project.godot without touching this script.
##
## Window.min_size docs:
## https://docs.godotengine.org/en/stable/classes/class_window.html#class-window-property-min-size
func _set_minimum_window_size() -> void:
	const MINIMUM_SCALE: int = 2
	var viewport_width: int = ProjectSettings.get_setting(
			"display/window/size/viewport_width", 320) as int
	var viewport_height: int = ProjectSettings.get_setting(
			"display/window/size/viewport_height", 180) as int
	get_window().min_size = Vector2i(
			viewport_width * MINIMUM_SCALE,
			viewport_height * MINIMUM_SCALE)
