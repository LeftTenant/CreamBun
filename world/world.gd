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
## World Thresholds (docs/features/world-thresholds/design.md §4-§5) drives
## every area-to-area transition off placed `Threshold` nodes: every area this
## script activates has every Threshold found under it (now and later — see
## _connect_all_thresholds()) connected to _on_threshold_entered(), which
## drives a freeze -> fade -> swap -> place -> reveal sequence — resolving the
## destination scene and its named Arrival BEFORE touching the old area
## (resolve-before-destroy, design §5) — and lands the player exactly on the
## Arrival's position, not a computed offset.
##
## Slice 4 of that feature deleted the older, edge-derived mechanism this
## script used to run alongside it (a filled `neighbour_*` slot on WorldArea,
## an `edge_reached` signal, and opposite-edge spawn arithmetic — world-
## collision design doc §12.4-§12.5, kept there as history) and migrated
## `meadow.tscn`/`orchard.tscn` to placed Threshold/Arrival pairs. The
## Threshold-driven sequence below is unchanged by that migration — it was
## already proven against fixture scenes before real content ever used it.


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

## The set of Thresholds currently ignored by _on_threshold_entered() because
## the player's ThresholdBounds was already overlapping them at the moment
## they arrived in the area (World Thresholds design.md §5's re-entry guard).
## A Dictionary used as a set — Threshold keys, values unused — cleared per
## entry by _on_ignored_threshold_exited() once that specific Threshold's
## area_exited fires, i.e. once the player has fully left it.
##
## This lives here rather than on Threshold itself so Threshold stays the
## bare two-export node design §4 promises: world.gd is the only thing that
## knows "the moment of arrival", so it is the only thing that can know which
## Thresholds need ignoring (design §5).
##
## Defence-in-depth note: today, GameState's LOADING-state early-return in
## _on_threshold_entered() already suppresses the spawned-into Threshold's
## first area_entered (the whole freeze -> fade -> swap -> place -> reveal
## sequence runs synchronously-enough that GameState is still LOADING when
## that signal would fire), so this guard is not currently load-bearing for
## the test suite at all — test_threshold_transition.gd's re-entry tests pass
## even with _ignore_threshold() neutered to a no-op. It stays
## here anyway because that coincidence isn't a guarantee: if LOADING's
## window ever stops being synchronous with arrival (a future await inserted
## earlier in the sequence, e.g.), or Slice 4's real content has different
## timing, this guard is what keeps "a Threshold the player spawned into
## stays inert" true regardless of where a designer placed the Arrival —
## which is the actual design §5 requirement, not an artifact of today's
## timing.
var _ignored_thresholds: Dictionary = {}


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

## Instance the starting WorldArea and activate it (see _activate_area()),
## then arm the re-entry guard (_arm_reentry_guards(), design doc §5) against
## the starting area's own Thresholds — exactly as every later
## Threshold-driven arrival does. This is load-bearing, not speculative:
## meadow.tscn (World Thresholds Slice 4) now has two real Thresholds placed
## in it, and a Threshold ever placed overlapping the authored spawn point
## must not fire on the very first physics frame at game start.
##
## GameState is set to LOADING before _activate_area() runs and only
## restored to PLAYING once _arm_reentry_guards() has fully returned — the
## same shape _on_threshold_entered() already uses for every later arrival.
## This isn't optional here: _arm_reentry_guards() must await two
## get_tree().physics_frame signals before it can query
## get_overlapping_areas() (Area2D monitoring pairs are only recomputed once
## per physics step — see that function's doc comment), and a Threshold's own
## area_entered fires on that very first physics recompute, before the guard
## has had a chance to arm. On the Threshold-driven transition path that race
## is invisible because LOADING is already covering the whole window; on this
## startup path nothing else sets LOADING, so without holding it here
## ourselves the signal always wins the race and the guard arms too late to
## matter. The cost is ~2 physics frames of non-interactivity at boot —
## negligible next to FADE_DURATION_SEC's 0.3s transitions elsewhere in this
## file.
##
## async (this function awaits _arm_reentry_guards()), but _ready() below
## calls it without awaiting — a fire-and-forget start, same as
## _on_threshold_entered() is never awaited by whatever connects it. The
## synchronous part (instantiate + _activate_area()) still completes within
## this same call, before the first `await` inside _arm_reentry_guards() ever
## suspends it.
##
## Test-suite consequence: because GameState is a global autoload that
## outlives any one world.tscn instance, a test that instantiates world.tscn
## and tears it down (e.g. via add_child_autofree()) before these ~2 physics
## frames elapse cancels the coroutine mid-flight — GDScript has no `finally`
## — and leaves GameState.current_state stuck at LOADING for whatever test
## runs next. Every world.tscn instantiation is now exposed to this, not just
## tests that actively drive a transition, so integration test files that
## instantiate world.tscn should reset GameState.current_state to PLAYING in
## before_each() (see e.g. test_area_transition.gd).
func _load_starting_area() -> void:
	GameState.current_state = GameState.State.LOADING
	var area: WorldArea = STARTING_AREA_SCENE.instantiate()
	_activate_area(area)
	await _arm_reentry_guards(area)
	GameState.current_state = GameState.State.PLAYING


## Add a freshly-instanced WorldArea under ActiveArea and wire it up as the
## live area: reparent the persistent Player into it (world-collision design
## doc §12.1), build its perimeter (world-thresholds design.md §7 — every
## edge, unconditionally), set the camera limits (world-collision design doc
## §12.3), and connect every Threshold found under it (World Thresholds
## design.md §4-§5) so crossing one starts a transition. Used both for the
## startup load and for every area entered via _on_threshold_entered() below.
##
## reparent() preserves the node and all its state (including its child
## Camera2D), so nothing about the player is rebuilt — it is the same node,
## moved.
## https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-reparent
func _activate_area(area: WorldArea) -> void:
	_active_area.add_child(area)
	_player.reparent(area)
	area.build_perimeter_walls()
	_set_camera_limits(area)
	_connect_all_thresholds(area)


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


# ---------------------------------------------------------------------------
# Threshold-driven transition (World Thresholds design doc §4-§5)
# ---------------------------------------------------------------------------

## Find and connect every Threshold currently under `area` (recursively) to
## _on_threshold_entered(), then keep watching for Thresholds added to `area`
## AFTER this runs (design doc §5's fixture-injection proof strategy adds one
## as a runtime child post-activation — a plain one-time scan here would miss
## it). child_entered_tree only reports direct children of the node it's
## connected to, which matches every place a Threshold is actually placed in
## this project (a direct child of an area's root, alongside its props) —
## see Threshold's own doc comment ("placed as a direct child of the area
## root").
func _connect_all_thresholds(area: WorldArea) -> void:
	for threshold in _find_thresholds(area):
		_connect_threshold(threshold, area)
	area.child_entered_tree.connect(_on_area_child_entered_tree.bind(area))


## Every Threshold found anywhere under `node`, walked recursively. A manual
## walk rather than Node.find_children(pattern, type, ...): that method's
## `owned` parameter defaults to true, which prunes owner-less nodes — exactly
## the runtime-injected-Threshold pattern this slice's own tests rely on (a
## Threshold added via add_child() with no matching set_owner() call). Passing
## `owned: false` would dodge that, but find_children() also returns a plain
## Array[Node], not the properly-typed Array[Threshold] this function's
## callers want — the manual walk below gets both fixes at once with `is
## Threshold`, a normal GDScript type check.
func _find_thresholds(node: Node) -> Array[Threshold]:
	var found: Array[Threshold] = []
	for child in node.get_children():
		if child is Threshold:
			found.append(child as Threshold)
		found.append_array(_find_thresholds(child))
	return found


## Connect one Threshold's area_entered signal to _on_threshold_entered(),
## binding the Threshold itself and the area it was found under (needed so
## the handler knows which area to tear down on a successful crossing — see
## _activate_area()).
func _connect_threshold(threshold: Threshold, area: WorldArea) -> void:
	threshold.area_entered.connect(_on_threshold_entered.bind(threshold, area))


## _connect_all_thresholds()'s child_entered_tree handler: a Threshold added
## to `area` after activation (design doc §5's proof strategy; also how a
## designer's own placed Threshold would show up if an area were ever
## authored/edited live) gets wired up exactly like one that was already
## there.
func _on_area_child_entered_tree(child: Node, area: WorldArea) -> void:
	if child is Threshold:
		_connect_threshold(child as Threshold, area)


## Drive the freeze -> fade -> swap -> place -> reveal sequence (design doc
## §5) once the player's ThresholdBounds enters a placed Threshold. `threshold`
## and `area` (bound at connect time) are the Threshold crossed and the area
## it belongs to.
##
## Guarded against a residual second firing by GameState.current_state
## itself: it is set to LOADING synchronously as the first action, so
## anything that fires while a transition is already underway sees LOADING
## already set and returns immediately.
##
## The re-entry guard (design §5) is checked FIRST, before the LOADING guard:
## a Threshold the player spawned into/onto should never start a transition
## at all, whether or not one happens to be in flight — see
## _arm_reentry_guards().
##
## Resolve-before-destroy (design §5's numbered order): destination and
## Arrival are loaded and validated BEFORE anything about the old area is
## touched — see _load_threshold_area()'s doc comment for why.
func _on_threshold_entered(_entered_area: Area2D, threshold: Threshold, area: WorldArea) -> void:
	if _ignored_thresholds.has(threshold):
		return
	if GameState.current_state == GameState.State.LOADING:
		return
	GameState.current_state = GameState.State.LOADING

	await _fade_transition(1.0)

	# Captured into locals rather than re-read from `threshold` later: once
	# the old area (threshold's own parent) is freed below, `threshold`
	# itself is a freed object by the time the final steps of this sequence
	# run — the several awaits between here and the end (the reveal fade, the
	# re-entry guard's physics-frame waits) are more than enough time for its
	# queue_free() to actually take effect. Reading threshold.destination
	# again after that point is a use-after-free.
	var destination_path: String = threshold.destination
	var arrival_name: String = String(threshold.arrival)

	# Load and validate BEFORE destroying anything: at this point the OLD
	# area is still fully live in the tree (player still its child, area not
	# yet removed), so a failure here can fade back to transparent and hand
	# control straight back with nothing having moved.
	var new_area: WorldArea = _load_threshold_area(destination_path)
	var arrival: Marker2D = null
	if new_area != null:
		arrival = new_area.find_child(arrival_name, true, false) as Marker2D

	if new_area == null or arrival == null:
		if new_area == null:
			push_error("World._on_threshold_entered: '%s' did not load/instantiate as a WorldArea — check Threshold.destination" % [destination_path])
		else:
			push_error("World._on_threshold_entered: '%s' has no Arrival named '%s' — check Threshold.arrival" % [destination_path, arrival_name])
			# new_area loaded fine but is being discarded — it was never
			# added under ActiveArea, so nothing else will ever free it.
			new_area.queue_free()
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
	# leaving a brief window where ActiveArea.get_child(0) is still the stale
	# outgoing area, not the one the player was just placed into. This also
	# frees `threshold` itself, once the deferred queue_free() actually runs
	# — see the doc comment on the captured locals above.
	_active_area.remove_child(area)
	area.queue_free()

	_activate_area(new_area)
	_player.global_position = arrival.global_position

	# Arm the re-entry guard (design §5) before handing control back: any
	# Threshold the player is now standing on/in must stay inert until they
	# leave it. Must happen before GameState returns to PLAYING below so the
	# guard is in place before the player (or a residual signal) can act on
	# it — see _arm_reentry_guards()'s own doc comment for the physics-timing
	# reason it awaits.
	await _arm_reentry_guards(new_area)

	# design doc §5: the reveal fade and PLAYING restoration happen BEFORE
	# area_changed fires, so any listener observes a fully-resumed game, not
	# one still frozen behind an opaque screen.
	await _fade_transition(0.0)
	GameState.current_state = GameState.State.PLAYING

	GameEvents.area_changed.emit(_area_id_from_destination(destination_path))


## Load `destination_path` and instantiate it as a WorldArea, or return null
## if either step fails (a missing/moved/renamed/non-WorldArea scene). Split
## out of _on_threshold_entered() so that function reads as a single "load,
## then either bail out clean or proceed" shape, with no intermediate state
## to unwind — called before anything is destroyed, so a failure here is
## always safe to recover from.
##
## Checks ResourceLoader.exists() before calling load(): load() on a path
## with no resource behind it logs its own pair of low-level engine errors
## (ResourceLoader's internal "err != OK" / "found" checks) IN ADDITION to
## whatever error the caller pushes for the failure — exists() reports the
## same "no" without that noise, so _on_threshold_entered()'s single
## push_error() stays the only error this failure path produces (design.md
## §5).
func _load_threshold_area(destination_path: String) -> WorldArea:
	if not ResourceLoader.exists(destination_path, "PackedScene"):
		return null
	var new_scene: PackedScene = load(destination_path) as PackedScene
	if new_scene == null:
		return null
	return new_scene.instantiate() as WorldArea


## The StringName GameEvents.area_changed expects, computed from a
## Threshold's destination path (e.g. "res://.../fixture_a.tscn" ->
## "fixture_a"). A private one-liner here rather than a call to
## WorldArea.area_id_from_scene_path() — World Thresholds design.md §7 retires
## that static once WorldArea collapses to bounds-and-walls in Slice 4, and
## this is the first place the new mechanism needs an area id, so the
## replacement is introduced here rather than deferred (slices.md's Slice 4
## "area_id — settled" note).
func _area_id_from_destination(destination_path: String) -> StringName:
	return StringName(destination_path.get_file().get_basename())


## Re-entry guard (design doc §5): mark every Threshold under `area` that the
## player's ThresholdBounds is ALREADY overlapping — i.e. the one(s) they just
## spawned into/onto — as ignored, so _on_threshold_entered() treats a
## residual/duplicate area_entered for it as a no-op. Cleared per-Threshold by
## _on_ignored_threshold_exited() once the player has fully left it.
##
## Awaits two physics frames before querying overlap state: Area2D monitoring
## pairs are recomputed once per physics step, not synchronously the instant
## a transform changes, so querying immediately after _player.global_position
## is set (this function is called right after that assignment) would still
## see the PRE-move overlap state. GameState is already LOADING for the
## entire duration of this wait, so nothing the player does during it can
## race the guard being armed.
func _arm_reentry_guards(area: WorldArea) -> void:
	# Clear any entries left over from a previous area — this is the only
	# function that ever writes to _ignored_thresholds, and it runs after
	# every area swap, so this is also the only place a stale entry could be
	# dropped. Without this, a Threshold whose area is torn down by
	# queue_free() (rather than the player ever triggering its area_exited —
	# e.g. a second transition starting before the player fully left the
	# first Threshold they arrived on) would leave its now-freed key in the
	# dictionary forever: not a correctness bug (a fresh node never collides
	# with a freed one), just an unbounded per-crossing leak.
	_ignored_thresholds.clear()

	var bounds_area: Area2D = _player.get_node_or_null("ThresholdBounds") as Area2D
	if bounds_area == null:
		return
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Cheap insurance: nothing in this file frees `area` mid-await today, but
	# two consecutive physics-frame awaits is a long enough window that a
	# future caller easily could (a second transition racing this one, e.g.).
	# Bail out rather than querying/iterating a freed WorldArea.
	if not is_instance_valid(area):
		return

	for threshold in _find_thresholds(area):
		if threshold.get_overlapping_areas().has(bounds_area):
			_ignore_threshold(threshold)


## Add `threshold` to the ignore set and connect a one-shot listener that
## clears it the moment the player's ThresholdBounds fully leaves it — design
## doc §5: "ignores crossings from those until each reports the player has
## left." CONNECT_ONE_SHOT means no matching disconnect is needed here: the
## connection removes itself after firing once, and if `threshold` is freed
## first (its area was swapped out before the player ever left it) the
## connection simply goes away with it.
func _ignore_threshold(threshold: Threshold) -> void:
	if _ignored_thresholds.has(threshold):
		return
	_ignored_thresholds[threshold] = true
	threshold.area_exited.connect(_on_ignored_threshold_exited.bind(threshold), CONNECT_ONE_SHOT)


## See _ignore_threshold() above.
func _on_ignored_threshold_exited(_exited_area: Area2D, threshold: Threshold) -> void:
	_ignored_thresholds.erase(threshold)


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
