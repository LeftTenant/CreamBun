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
##
## Slice 10 adds the edge-transition sequence (design doc §12.5): every area
## this script activates has its edge_reached signal connected here, and
## crossing an open edge drives the freeze -> cover -> swap -> place ->
## reveal sequence that lands the player in the neighbouring area.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## The area loaded into ActiveArea on startup.
const STARTING_AREA_SCENE: PackedScene = preload("res://world/areas/meadow.tscn")

## How long each half (cover / reveal) of the transition fade takes, in
## seconds. Short and "cozy" per design doc §12.5 ("a short transition
## carries them") rather than a long cinematic wipe.
const FADE_DURATION_SEC: float = 0.3


# ---------------------------------------------------------------------------
# Onready variables
# ---------------------------------------------------------------------------

@onready var _active_area: Node2D = $ActiveArea
@onready var _player: CharacterBody2D = $Player
@onready var _transition: CanvasLayer = $Transition


# ---------------------------------------------------------------------------
# Private variables
# ---------------------------------------------------------------------------

## The full-screen ColorRect that fades to opaque and back during a
## transition (design doc §12.5 step 2). Built once in _ready() rather than
## hand-authored in world.tscn, since nothing else needs to reference it by
## name in the editor.
var _fade_rect: ColorRect


# ---------------------------------------------------------------------------
# Built-in overrides
# ---------------------------------------------------------------------------

func _ready() -> void:
	_set_minimum_window_size()
	_build_transition_overlay()
	_load_starting_area()


# ---------------------------------------------------------------------------
# Private methods
# ---------------------------------------------------------------------------

## Instance the starting WorldArea and activate it (see _activate_area()).
func _load_starting_area() -> void:
	var area: WorldArea = STARTING_AREA_SCENE.instantiate()
	_activate_area(area)


## Add a freshly-instanced WorldArea under ActiveArea and wire it up as the
## live area: reparent the persistent Player into it (design doc §12.1),
## build its perimeter (§12.4), set the camera limits (§12.3), and connect
## its edge_reached signal (§12.4/§12.5) so crossing an open edge starts a
## transition. Used both for the startup load and for every area entered via
## _on_edge_reached() below.
##
## reparent() preserves the node and all its state (including its child
## Camera2D), so nothing about the player is rebuilt — it is the same node,
## moved.
## https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-reparent
func _activate_area(area: WorldArea) -> void:
	_active_area.add_child(area)
	_player.reparent(area)
	area.build_perimeter_walls(_north_headroom_inset())
	_set_camera_limits(area)
	area.edge_reached.connect(_on_edge_reached.bind(area))


## How far in from a map's true north edge that edge's wall/trigger must sit,
## for the player currently in the world (design doc §12.4).
##
## This is the one place the player's geometry and the world's boundary
## geometry are connected, and it is deliberately here rather than inside
## WorldArea: this scene is the orchestrator, so reading from one node to
## configure another is its job, while WorldArea stays a pure function of the
## numbers it is handed (CLAUDE.md's dependency-injection rule).
##
## Recomputed per activation rather than cached, so it stays correct if the
## player scene is ever swapped mid-game (a different playable character, a
## temporary vehicle/mount). player.gd caches the underlying measurements, so
## the repeat cost is a subtraction.
func _north_headroom_inset() -> float:
	return WorldArea.north_headroom_inset(
			_player.get_visual_extent(), _player.get_collider_extent())


## Build the Transition overlay's fade visual: a full-screen ColorRect,
## fully transparent at rest, that _fade_transition() tweens to/from opaque.
## world.tscn's Transition CanvasLayer already has process_mode = ALWAYS
## (set in the scene), matching the notebook's convention for UI that must
## keep working while the game is otherwise frozen (CLAUDE.md).
func _build_transition_overlay() -> void:
	_fade_rect = ColorRect.new()
	_fade_rect.name = "Fade"
	_fade_rect.color = Color.BLACK
	_fade_rect.modulate.a = 0.0
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_transition.add_child(_fade_rect)


## Drive the freeze -> cover -> swap -> place -> reveal sequence (design doc
## §12.5) once the player crosses an open edge. `area` (bound at connect
## time in _activate_area()) is the area the player just exited.
##
## Guarded by GameState.current_state itself rather than a separate flag: it
## is set to LOADING as the very first, synchronous action below, so any
## edge_reached that fires while a transition is already underway (e.g.
## residual trigger overlap) sees LOADING already set and returns
## immediately — no overlapping second transition, no double free, no
## double GameEvents.area_changed.
##
## The neighbour scene is loaded and validated BEFORE anything about the old
## area is touched (before the player is reparented out of it, before it is
## removed/freed) — see _load_neighbour_area()'s doc comment for why: this is
## what makes the failure path actually recoverable instead of a soft-lock in
## a different guise.
func _on_edge_reached(direction: WorldArea.Edge, area: WorldArea) -> void:
	if GameState.current_state == GameState.State.LOADING:
		return
	GameState.current_state = GameState.State.LOADING

	var neighbour_path: String = area.neighbour_for_edge(direction)
	if neighbour_path.is_empty():
		# A trigger should only ever exist on an edge whose neighbour_* slot
		# is filled (WorldArea.build_perimeter_walls()) — this is a defensive
		# guard against that invariant breaking, not an expected path. Bail
		# out to PLAYING rather than leaving the game stuck frozen.
		push_error("World._on_edge_reached: edge_reached fired for an edge with no neighbour path set")
		GameState.current_state = GameState.State.PLAYING
		return

	# Capture the exit coordinate before anything moves — the player's exact
	# perpendicular position at the moment they crossed (design doc §12.5
	# step 4: "carried over verbatim").
	var exit_position: Vector2 = _player.global_position
	var exit_coordinate: float = (
			exit_position.y if (direction == WorldArea.Edge.EAST or direction == WorldArea.Edge.WEST)
			else exit_position.x)

	await _fade_transition(1.0)

	# Load and validate the neighbour BEFORE destroying anything: at this
	# point the OLD area is still fully live in the tree (player still its
	# child, area not yet removed), so a failure here can fade back to
	# transparent and hand control straight back with nothing having moved.
	var new_area: WorldArea = _load_neighbour_area(neighbour_path)
	if new_area == null:
		push_error("World._on_edge_reached: '%s' did not load/instantiate as a WorldArea — check the neighbour_* path for edge %d" % [neighbour_path, direction])
		await _fade_transition(0.0)
		GameState.current_state = GameState.State.PLAYING
		return

	# Detach the player from the old area before freeing it — reparent(), not
	# remove_child(), so the player's state (including its Camera2D) survives
	# the move intact, same as _activate_area()'s own reparent.
	_player.reparent(self)

	# Remove the old area from ActiveArea SYNCHRONOUSLY before queue_free():
	# queue_free() only marks a node for deletion at the end of the current
	# frame, it does not detach it from the tree immediately. Without this
	# explicit remove_child(), _activate_area(new_area) below would add the
	# new area as a SECOND child of ActiveArea for the rest of this frame —
	# leaving a brief window where ActiveArea.get_child(0) is still the
	# stale outgoing area, not the one the player was just placed into.
	_active_area.remove_child(area)
	area.queue_free()

	_activate_area(new_area)

	var new_bounds: Rect2 = new_area.get_bounds_px()
	_player.global_position = WorldArea.compute_entry_position(
			exit_coordinate, direction, new_bounds, _north_headroom_inset())
	new_area.begin_entry_debounce(WorldArea.opposite_edge(direction))

	# design doc §12.5 step 5: the reveal fade and PLAYING restoration happen
	# BEFORE area_changed fires, so any listener (autosave, a future minimap)
	# observes a fully-resumed game, not one still frozen behind an opaque
	# screen.
	await _fade_transition(0.0)
	GameState.current_state = GameState.State.PLAYING

	GameEvents.area_changed.emit(WorldArea.area_id_from_scene_path(neighbour_path))


## Load `neighbour_path` and instantiate it as a WorldArea, or return null if
## either step fails (a moved/renamed/non-WorldArea scene). Split out of
## _on_edge_reached() so that function reads as a single "load, then either
## bail out clean or proceed" shape, with no intermediate state to unwind.
##
## Round 2 of code review on this slice caught that an earlier version did
## this load/instantiate AFTER the player had already been reparented out of
## the old area and the old area had already been removed/freed — so the
## null-check's "bail out" path left the player frozen behind an opaque fade
## with no area at all in the scene tree: a soft-lock, just moved to a
## different point in the sequence than the one round 1 fixed. Calling this
## before anything is destroyed means a failure here is always safe to
## recover from (see _on_edge_reached()'s fade-back-and-return).
func _load_neighbour_area(neighbour_path: String) -> WorldArea:
	var new_scene: PackedScene = load(neighbour_path) as PackedScene
	if new_scene == null:
		return null
	return new_scene.instantiate() as WorldArea


## Tween the transition overlay's fade ColorRect to `target_alpha` over
## FADE_DURATION_SEC and wait for it to finish. Bound to physics-frame
## processing (rather than the default idle/render-frame processing) so its
## timing is expressed in the same fixed-timestep terms as everything else
## driving this sequence (player movement, GUT's wait_physics_frames()) —
## not subject to however fast/slow idle frames happen to run headlessly.
## https://docs.godotengine.org/en/stable/classes/class_tween.html#class-tween-method-set-process-mode
func _fade_transition(target_alpha: float) -> void:
	var tween: Tween = create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_property(_fade_rect, "modulate:a", target_alpha, FADE_DURATION_SEC)
	await tween.finished


## Clamp the player's Camera2D to the loaded area's bounds (design doc
## §12.3, "Locked at the map edge") so the camera can never scroll past the
## painted floor and reveal the void beyond it. Read from get_bounds_px()
## on every call rather than a fixed rect, so this stays correct however the
## area's painted extent changes (and, from slice 10 onward, on every
## area-to-area transition, not just this initial load).
##
## int() truncation matches design doc §12.3's exact wiring snippet — camera
## limits are integer pixel coordinates
## (https://docs.godotengine.org/en/stable/classes/class_camera2d.html#class-camera2d-property-limit-left),
## while get_bounds_px() returns floats.
func _set_camera_limits(area: WorldArea) -> void:
	var bounds: Rect2 = area.get_bounds_px()
	var camera: Camera2D = _player.get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		push_error("World._set_camera_limits: Player has no Camera2D child named 'Camera2D' — camera limits not set")
		return
	camera.limit_left = int(bounds.position.x)
	camera.limit_top = int(bounds.position.y)
	camera.limit_right = int(bounds.end.x)
	camera.limit_bottom = int(bounds.end.y)


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
