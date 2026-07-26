extends Node2D
## World scene orchestrator — wires the scene graph from autoloads and
## sets up initial world-level state.
##
## Per CLAUDE.md, the world scene is the natural owner of scene-wiring from
## autoloads (dependency injection point). Direct autoload access is acceptable
## here specifically because this node's job is orchestration.
##
## Slice 8 (world-collision design doc §12.1) splits world.tscn into a
## persistent shell — this script's node — and a swappable WorldArea scene
## instanced under ActiveArea. The player is a permanent child of the shell
## but gets reparented into the active area on load so Y-sort has one shared
## scope to interleave the player against the area's tiles and props (§9).


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## The area loaded into ActiveArea on startup. Slice 8 only supports a single
## hard-coded starting area; slice 10 adds edge-triggered switching between
## areas via the neighbour_* slots declared on WorldArea.
const STARTING_AREA_SCENE: PackedScene = preload("res://world/areas/meadow.tscn")


# ---------------------------------------------------------------------------
# Onready variables
# ---------------------------------------------------------------------------

@onready var _active_area: Node2D = $ActiveArea
@onready var _player: CharacterBody2D = $Player


# ---------------------------------------------------------------------------
# Built-in overrides
# ---------------------------------------------------------------------------

func _ready() -> void:
	_set_minimum_window_size()
	_load_starting_area()


# ---------------------------------------------------------------------------
# Private methods
# ---------------------------------------------------------------------------

## Instance the starting WorldArea under ActiveArea and reparent the
## persistent Player into it (design doc §12.1):
##
##     _active_area.add_child(area)   # `area` is the freshly-instanced WorldArea
##     _player.reparent(area)         # move the persistent player into the sort scope
##
## The reparent is not optional bookkeeping — it is what makes depth sorting
## work. Y-sort only interleaves nodes that share one Y-sorted parent (§9);
## the area's Ground/Solids layers and props all live under the WorldArea
## root, so the player must join that scope to sort against them.
## reparent() preserves the node and all its state (including its child
## Camera2D), so nothing about the player is rebuilt — it is the same node,
## moved.
## https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-reparent
func _load_starting_area() -> void:
	var area: WorldArea = STARTING_AREA_SCENE.instantiate()
	_active_area.add_child(area)
	_player.reparent(area)


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
