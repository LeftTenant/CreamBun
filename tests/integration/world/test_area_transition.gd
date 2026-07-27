## test_area_transition.gd
## Integration tests for Slice 10 of the world-collision feature ("Edge
## transition (fade) and a second area") — the full freeze/fade/swap/spawn/
## reveal SEQUENCE (design.md §12.5), as opposed to the static trigger
## geometry covered by the sibling file test_edge_triggers.gd (Edge enum,
## wall-vs-trigger branching, corner dead zones, reciprocal wiring — see
## that file's header for why the split).
##
## IMPLEMENTED — this suite now runs against a real implementation.
## =========================================================================
## world.gd connects to the active area's edge_reached signal
## (_activate_area()) and drives the freeze -> cover -> swap -> place ->
## reveal sequence from _on_edge_reached(). GameEvents.area_changed is
## emitted after the reveal fade completes and GameState is back to PLAYING
## (design.md §12.5 step 5's ordering), and world.tscn's Transition
## CanvasLayer holds a full-screen ColorRect built in world.gd's
## _build_transition_overlay() that a Tween fades to/from opaque.
##
## JUDGMENT CALL (flag for review) — the Transition fade visual: design.md
## §12.5 step 2 says only "a Tween on a full-screen ColorRect," without
## naming it. This suite does NOT assume a specific child node name — it
## looks for "some CanvasItem child of Transition" generically (any node with
## a `modulate` property) and reads its alpha, so it doesn't over-specify an
## implementation detail the design doc left open. If the coder's fade
## mechanism turns out not to be a direct CanvasItem child of Transition (e.g.
## a shader/viewport effect instead), the fade-opacity assertions below will
## need revisiting — flagged here rather than discovered silently.
##
## Design reference: docs/features/world-collision/design.md §12.5 (the
## freeze/cover/swap/place/reveal sequence, opposite-edge spawn maths).
## Test plan: docs/features/world-collision/slice-10-edge-transition-test-plan.md
##
## Requires GUT: https://github.com/bitwes/Gut
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gselect=test_area_transition.gd -gexit

class_name TestAreaTransition
extends GutTest


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const WORLD_SCENE_PATH: String = "res://world/world.tscn"
const ORCHARD_SCENE_PATH: String = "res://world/areas/orchard.tscn"

const WORLD_LAYER_BIT: int = 1

## How many REAL physics frames to hold movement input while walking into a
## trigger. See test_edge_triggers.gd's _drive_player() docstring for why
## this suite uses real frames (wait_physics_frames), not GUT's simulate().
const DRIVE_TICKS: int = 300

## Upper bound on how long the freeze/fade/swap/spawn/reveal sequence is
## allowed to take before this suite gives up waiting and fails with a clear
## timeout message, rather than hanging indefinitely. Polled in small
## increments (see _wait_until_playing_or_timeout()) so a fast
## implementation doesn't pay this cost — this is a ceiling, not a fixed
## sleep.
const TRANSITION_TIMEOUT_TICKS: int = 300  # ~5s at 60Hz

## Arrival debounce distance (design.md §12.4), mirrored here so
## test_immediate_walk_back_to_just_entered_edge_does_not_bounce() can size
## its "small nudge" from the player's actual speed rather than a hardcoded
## tick count (see that test for why the hardcoded version was wrong).
const DEBOUNCE_EAST_WEST_PX: float = 16.0


# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

func before_each() -> void:
	GameState.change_state(GameState.State.PLAYING)


func after_each() -> void:
	Input.action_release("move_up")
	Input.action_release("move_down")
	Input.action_release("move_left")
	Input.action_release("move_right")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _instantiate_world() -> Node:
	var packed: PackedScene = load(WORLD_SCENE_PATH)
	assert_not_null(packed, "world/world.tscn should load as a PackedScene")
	if packed == null:
		return null
	var world: Node = packed.instantiate()
	assert_not_null(world, "world/world.tscn should instantiate without errors")
	if world == null:
		return null
	add_child_autofree(world)
	return world


func _get_instanced_area(world: Node) -> WorldArea:
	var active_area: Node = world.get_node_or_null("ActiveArea")
	assert_not_null(active_area, "world.tscn should have a direct child named 'ActiveArea'")
	if active_area == null:
		return null
	assert_gt(active_area.get_child_count(), 0, "ActiveArea should hold the instanced meadow WorldArea")
	if active_area.get_child_count() == 0:
		return null
	var area: Node = active_area.get_child(0)
	if not (area is WorldArea):
		fail_test("the instanced ActiveArea child must be a WorldArea instance — found a %s" % [area.get_class()])
		return null
	return area as WorldArea


func _get_player(world: Node) -> CharacterBody2D:
	var player: CharacterBody2D = world.find_child("Player", true, false) as CharacterBody2D
	assert_not_null(player, "world.tscn's instantiated tree should contain a CharacterBody2D named 'Player'")
	return player


## Hold `action` for up to `max_ticks` real physics frames, releasing EARLY —
## the instant GameState leaves PLAYING — rather than always holding the
## full duration. `max_ticks` is now an upper-bound safety net for edges that
## should never transition at all (GameState then never leaves PLAYING, so
## the loop runs the whole way), not a fixed hold length chosen to outlast a
## transition regardless of when the crossing happens.
##
## Test-authoring history: this used to be an unconditional
## `await wait_physics_frames(ticks)`. Holding the input for the full 300
## ticks (~5s) left the player still walking for ~4.4s AFTER the freeze/
## fade/swap/spawn/reveal sequence (design.md §12.5) — a ~0.6s round trip at
## world.gd's FADE_DURATION_SEC — had already completed, silently carrying
## them well past the intended "one tile inward" spawn point and stranding
## GameState back at PLAYING by the time tests asserting "immediately after
## crossing" state sampled it. Releasing input as soon as the crossing is
## detected (GameState.current_state leaving PLAYING is set synchronously in
## world.gd's _on_edge_reached(), the same frame edge_reached fires) removes
## that race without slowing down the real transition to accommodate a test
## artifact.
func _drive_player(player: CharacterBody2D, action: String, max_ticks: int) -> void:
	Input.action_press(action)
	var waited: int = 0
	while waited < max_ticks and GameState.current_state == GameState.State.PLAYING:
		await wait_physics_frames(1)
		waited += 1
	Input.action_release(action)
	player.velocity = Vector2.ZERO


## Poll in small increments until GameState.current_state == PLAYING again
## (the transition sequence has fully completed) or TRANSITION_TIMEOUT_TICKS
## is exceeded. Returns true if PLAYING was reached, false on timeout — a
## bounded poll rather than an unbounded wait, so an unimplemented sequence
## fails this suite promptly instead of hanging it.
func _wait_until_playing_or_timeout() -> bool:
	var waited: int = 0
	while waited < TRANSITION_TIMEOUT_TICKS:
		if GameState.current_state == GameState.State.PLAYING:
			return true
		await wait_physics_frames(10)
		waited += 10
	return GameState.current_state == GameState.State.PLAYING


## The first direct child of `transition` that exposes a `modulate` property
## (i.e. any CanvasItem — Control, ColorRect, etc.) — generic on purpose, see
## this file's header JUDGMENT CALL note. Returns null if Transition has no
## such child yet.
func _find_fade_canvas_item(transition: Node) -> CanvasItem:
	for child in transition.get_children():
		if child is CanvasItem:
			return child as CanvasItem
	return null


## Walk the player to the clear middle of meadow's linked east edge (clear of
## both corner dead zones) and hold movement long enough to cross it.
## Returns the WorldArea (meadow) instance and the exact exit Y coordinate
## used, so callers can compute the expected entry position.
func _cross_meadow_east_edge(world: Node, area: WorldArea, player: CharacterBody2D) -> float:
	var bounds: Rect2 = area.get_bounds_px()
	var exit_y: float = (bounds.position.y + bounds.end.y) / 2.0
	player.global_position = Vector2(bounds.end.x - 96.0, exit_y)
	player.velocity = Vector2.ZERO
	await wait_physics_frames(2)
	await _drive_player(player, "move_right", DRIVE_TICKS)
	return exit_y


# ---------------------------------------------------------------------------
# GameState sequencing (design.md §12.5 steps 1 and 5)
# ---------------------------------------------------------------------------

func test_game_state_becomes_loading_immediately_on_edge_reached() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var area: WorldArea = _get_instanced_area(world)
	if area == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return

	await _cross_meadow_east_edge(world, area, player)

	# Sampled promptly after the crossing input — the freeze step (design.md
	# §12.5 step 1) is meant to happen BEFORE the fade even starts, so
	# GameState should already be LOADING well before the whole sequence
	# finishes.
	assert_eq(GameState.current_state, GameState.State.LOADING,
			"GameState.current_state must become LOADING as soon as edge_reached fires, before the fade/swap/spawn sequence runs (design.md §12.5 step 1)")


func test_game_state_returns_to_playing_only_after_the_full_sequence() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var area: WorldArea = _get_instanced_area(world)
	if area == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return

	await _cross_meadow_east_edge(world, area, player)
	var reached_playing: bool = await _wait_until_playing_or_timeout()

	assert_true(reached_playing,
			(
			"GameState.current_state should return to PLAYING once the freeze/fade/swap/spawn/reveal "
			+ "sequence completes (design.md §12.5 step 5) — it did not within %d physics frames "
			+ "(~%.0fs). Current state: %d"
			) % [TRANSITION_TIMEOUT_TICKS, TRANSITION_TIMEOUT_TICKS / 60.0, GameState.current_state])


# ---------------------------------------------------------------------------
# Transition overlay fade ordering (design.md §12.5 step 2, 5)
# ---------------------------------------------------------------------------

func test_transition_overlay_is_not_fully_transparent_while_loading() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var area: WorldArea = _get_instanced_area(world)
	if area == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return

	var transition: Node = world.get_node_or_null("Transition")
	assert_not_null(transition, "world.tscn should have a direct child named 'Transition'")
	if transition == null:
		return

	await _cross_meadow_east_edge(world, area, player)
	# Give the fade-in Tween a moment to progress before sampling — not
	# asserting it's fully opaque yet (timing-dependent), just that it has
	# started covering the screen while the swap is presumably still hidden
	# behind it.
	await wait_physics_frames(20)

	var fade: CanvasItem = _find_fade_canvas_item(transition)
	assert_not_null(fade,
			"Transition should have at least one CanvasItem child (e.g. a full-screen ColorRect) used for the cover fade (design.md §12.5 step 2)")
	if fade == null:
		return

	assert_gt(fade.modulate.a, 0.0,
			"the Transition overlay's fade child should have started becoming opaque (modulate.a > 0) shortly after edge_reached, while GameState is LOADING")


func test_transition_overlay_returns_to_transparent_after_reveal() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var area: WorldArea = _get_instanced_area(world)
	if area == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return

	var transition: Node = world.get_node_or_null("Transition")
	if transition == null:
		return

	await _cross_meadow_east_edge(world, area, player)
	await _wait_until_playing_or_timeout()

	var fade: CanvasItem = _find_fade_canvas_item(transition)
	if fade == null:
		return

	assert_almost_eq(fade.modulate.a, 0.0, 0.05,
			"the Transition overlay's fade child must be back to fully transparent once the sequence completes and GameState is PLAYING again (design.md §12.5 step 5, 'reveal')")


# ---------------------------------------------------------------------------
# Area swap: free old area, instance neighbour, reparent, rebuild perimeter
# and camera (design.md §12.5 step 3)
# ---------------------------------------------------------------------------

func test_old_area_is_freed_and_orchard_is_instanced_in_its_place() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var area: WorldArea = _get_instanced_area(world)
	if area == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return

	await _cross_meadow_east_edge(world, area, player)
	var reached_playing: bool = await _wait_until_playing_or_timeout()
	if not reached_playing:
		fail_test("transition never completed (GameState stuck at %d) — cannot check area swap" % [GameState.current_state])
		return

	assert_true(not is_instance_valid(area) or not area.is_inside_tree(),
			"the old meadow WorldArea instance must be freed (or at least removed from the tree) after the transition completes")

	var active_area: Node = world.get_node_or_null("ActiveArea")
	assert_not_null(active_area, "world.tscn should still have a direct child named 'ActiveArea'")
	if active_area == null:
		return
	assert_eq(active_area.get_child_count(), 1,
			"ActiveArea should hold exactly one WorldArea after the swap — found %d children" % [active_area.get_child_count()])
	if active_area.get_child_count() == 0:
		return

	var new_area: Node = active_area.get_child(0)
	assert_eq(new_area.scene_file_path, ORCHARD_SCENE_PATH,
			"ActiveArea's child after crossing meadow's east edge should be an instance of %s — found '%s'" % [ORCHARD_SCENE_PATH, new_area.scene_file_path])


func test_player_is_reparented_into_the_new_area() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var area: WorldArea = _get_instanced_area(world)
	if area == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return

	await _cross_meadow_east_edge(world, area, player)
	var reached_playing: bool = await _wait_until_playing_or_timeout()
	if not reached_playing:
		fail_test("transition never completed — cannot check reparenting")
		return

	var active_area: Node = world.get_node_or_null("ActiveArea")
	if active_area == null or active_area.get_child_count() == 0:
		fail_test("no instanced area found under ActiveArea after the transition")
		return
	var new_area: Node = active_area.get_child(0)

	assert_eq(player.get_parent(), new_area,
			"the Player must be reparented into the newly-instanced area (same Y-sort-scope pattern as slice 8's test) — found parent '%s'" % [player.get_parent().name if player.get_parent() else "<none>"])


func test_new_area_perimeter_is_rebuilt_after_the_swap() -> void:
	# The new area (orchard) should get its OWN perimeter: a wall on its
	# unlinked edges (east, south — orchard declares no neighbours there) and
	# the reciprocal trigger back to meadow on its west edge.
	var world: Node = _instantiate_world()
	if world == null:
		return
	var area: WorldArea = _get_instanced_area(world)
	if area == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return

	await _cross_meadow_east_edge(world, area, player)
	var reached_playing: bool = await _wait_until_playing_or_timeout()
	if not reached_playing:
		fail_test("transition never completed — cannot check perimeter rebuild")
		return

	var active_area: Node = world.get_node_or_null("ActiveArea")
	if active_area == null or active_area.get_child_count() == 0:
		fail_test("no instanced area found under ActiveArea after the transition")
		return
	var new_area: WorldArea = active_area.get_child(0) as WorldArea
	assert_not_null(new_area, "the newly-instanced area must be a WorldArea")
	if new_area == null:
		return

	var new_bounds: Rect2 = new_area.get_bounds_px()
	var found_east_wall: bool = false
	for child in new_area.get_children():
		if child is StaticBody2D and (child as StaticBody2D).collision_layer == WORLD_LAYER_BIT:
			found_east_wall = true
			break
	assert_true(found_east_wall,
			(
			"orchard's own perimeter must be rebuilt after becoming the active area — it declares no "
			+ "neighbour on its east/south edges, so it should have at least one StaticBody2D wall on "
			+ "the world layer, same as meadow's own unlinked edges."
			))


func test_camera_limits_are_reset_to_the_new_areas_bounds() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var area: WorldArea = _get_instanced_area(world)
	if area == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return

	await _cross_meadow_east_edge(world, area, player)
	var reached_playing: bool = await _wait_until_playing_or_timeout()
	if not reached_playing:
		fail_test("transition never completed — cannot check camera limits")
		return

	var active_area: Node = world.get_node_or_null("ActiveArea")
	if active_area == null or active_area.get_child_count() == 0:
		fail_test("no instanced area found under ActiveArea after the transition")
		return
	var new_area: WorldArea = active_area.get_child(0) as WorldArea
	if new_area == null:
		return
	var new_bounds: Rect2 = new_area.get_bounds_px()

	var camera: Camera2D = player.get_node_or_null("Camera2D") as Camera2D
	assert_not_null(camera, "Player must still have a Camera2D child after the transition")
	if camera == null:
		return

	assert_eq(camera.limit_left, int(new_bounds.position.x),
			"Camera2D.limit_left must be reset to the NEW area's bounds (%.1f), not left at the meadow's stale value" % [new_bounds.position.x])
	assert_eq(camera.limit_top, int(new_bounds.position.y),
			"Camera2D.limit_top must be reset to the new area's bounds")
	assert_eq(camera.limit_right, int(new_bounds.end.x),
			"Camera2D.limit_right must be reset to the new area's bounds")
	assert_eq(camera.limit_bottom, int(new_bounds.end.y),
			"Camera2D.limit_bottom must be reset to the new area's bounds")


# ---------------------------------------------------------------------------
# Opposite-edge spawn placement (design.md §12.5 step 4)
# ---------------------------------------------------------------------------

func test_player_enters_orchards_west_edge_at_the_preserved_y_offset_inward() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var area: WorldArea = _get_instanced_area(world)
	if area == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return

	var exit_y: float = await _cross_meadow_east_edge(world, area, player)
	var reached_playing: bool = await _wait_until_playing_or_timeout()
	if not reached_playing:
		fail_test("transition never completed — cannot check spawn placement")
		return

	var active_area: Node = world.get_node_or_null("ActiveArea")
	if active_area == null or active_area.get_child_count() == 0:
		fail_test("no instanced area found under ActiveArea after the transition")
		return
	var new_area: WorldArea = active_area.get_child(0) as WorldArea
	if new_area == null:
		return
	var new_bounds: Rect2 = new_area.get_bounds_px()

	# design.md §12.5: the exit Y is carried over verbatim (176px, the middle
	# of meadow's east edge, comfortably fits orchard's [0, 256] range with
	# no clamping needed), offset one tile (32px) inward from orchard's own
	# west edge.
	assert_almost_eq(player.global_position.y, exit_y, 2.0,
			(
			"the player's Y on arrival (%.1f) should match the Y they exited meadow's east edge at "
			+ "(%.1f), carried over verbatim (design.md §12.5 step 4)"
			) % [player.global_position.y, exit_y])
	assert_almost_eq(player.global_position.x, new_bounds.position.x + 32.0, 2.0,
			(
			"the player's X on arrival should sit exactly one tile (32px) inward from orchard's own "
			+ "west edge (%.1f) — found %.1f"
			) % [new_bounds.position.x + 32.0, player.global_position.x])


# ---------------------------------------------------------------------------
# GameEvents.area_changed (design.md §12.5 step 5)
# ---------------------------------------------------------------------------

func test_area_changed_emitted_once_with_the_new_areas_id() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var area: WorldArea = _get_instanced_area(world)
	if area == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return

	watch_signals(GameEvents)
	await _cross_meadow_east_edge(world, area, player)
	var reached_playing: bool = await _wait_until_playing_or_timeout()
	if not reached_playing:
		fail_test("transition never completed — cannot check area_changed")
		return

	assert_signal_emit_count(GameEvents, "area_changed", 1,
			"GameEvents.area_changed must be emitted exactly once per transition")
	# NOTE: assert_signal_emitted_with_parameters()'s 4th positional argument
	# is an emission INDEX, not a failure message (see addons/gut/test.gd's
	# doc comment above the function) — a trailing message string here
	# previously broke the assertion's internal comparison (comparing that
	# string to -1). Dropped, matching the convention already used elsewhere
	# in this codebase (e.g. test_player_data_foundation.gd).
	assert_signal_emitted_with_parameters(GameEvents, "area_changed", [StringName("orchard")])


func test_area_changed_emitted_only_after_swap_reparent_and_rebuilds_complete() -> void:
	# Rather than trusting emission ORDER implicitly, capture the live scene
	# state AT THE MOMENT area_changed fires (via a directly-connected
	# lambda) and assert on that snapshot — proving the swap/reparent/
	# perimeter/camera work was already done by the time listeners see the
	# signal, not merely "eventually, at some point after."
	var world: Node = _instantiate_world()
	if world == null:
		return
	var area: WorldArea = _get_instanced_area(world)
	if area == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return

	var snapshot: Dictionary = {"captured": false, "player_parent_was_new_area": false, "camera_limits_were_set": false}
	var active_area: Node = world.get_node("ActiveArea")
	var on_area_changed := func(_area_id: StringName) -> void:
		snapshot["captured"] = true
		if active_area.get_child_count() > 0:
			var current_area: Node = active_area.get_child(0)
			snapshot["player_parent_was_new_area"] = (player.get_parent() == current_area)
		var camera: Camera2D = player.get_node_or_null("Camera2D") as Camera2D
		if camera != null:
			snapshot["camera_limits_were_set"] = (camera.limit_left != -10000000)
	GameEvents.area_changed.connect(on_area_changed)

	await _cross_meadow_east_edge(world, area, player)
	var reached_playing: bool = await _wait_until_playing_or_timeout()
	GameEvents.area_changed.disconnect(on_area_changed)
	if not reached_playing:
		fail_test("transition never completed — cannot check area_changed ordering")
		return

	assert_true(snapshot["captured"], "GameEvents.area_changed should have fired at least once during the transition")
	assert_true(snapshot["player_parent_was_new_area"],
			"at the moment area_changed fired, the Player must ALREADY be reparented into the new area — not before the swap")
	assert_true(snapshot["camera_limits_were_set"],
			"at the moment area_changed fired, Camera2D.limit_left must already be something other than Godot's default (-10000000) — the camera rebuild must have already run")


# ---------------------------------------------------------------------------
# Re-entry guard: a transition already underway must not double-fire
# ---------------------------------------------------------------------------

func test_a_second_edge_reached_during_an_in_progress_transition_does_not_double_transition() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var area: WorldArea = _get_instanced_area(world)
	if area == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return

	watch_signals(GameEvents)
	await _cross_meadow_east_edge(world, area, player)

	# Simulate residual trigger overlap: re-emit edge_reached a second time
	# immediately, while GameState is still (presumably) LOADING from the
	# first crossing — before waiting for the sequence to finish.
	# NOTE: is_instance_valid() must be checked FIRST — calling has_signal()
	# on an already-freed instance throws an engine error rather than
	# returning false (GDScript doesn't short-circuit safety here the way
	# the original ordering assumed).
	if is_instance_valid(area) and area.has_signal("edge_reached"):
		area.edge_reached.emit(WorldArea.Edge.EAST)

	var reached_playing: bool = await _wait_until_playing_or_timeout()
	if not reached_playing:
		fail_test("transition never completed — cannot check the re-entry guard")
		return

	assert_signal_emit_count(GameEvents, "area_changed", 1,
			"a second edge_reached fired while a transition was already underway (GameState == LOADING) must not start an overlapping second transition or double-emit area_changed")

	var active_area: Node = world.get_node("ActiveArea")
	assert_eq(active_area.get_child_count(), 1,
			"ActiveArea must hold exactly one WorldArea even after a residual/duplicate edge_reached — a double transition would risk freeing an already-freed area or instancing a second one")


# ---------------------------------------------------------------------------
# Regression: an unlinked edge behaves exactly like slice 9 (no transition)
# ---------------------------------------------------------------------------

func test_unlinked_west_edge_still_just_walls_the_player_with_no_transition() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var area: WorldArea = _get_instanced_area(world)
	if area == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return
	var bounds: Rect2 = area.get_bounds_px()

	watch_signals(GameEvents)
	await wait_physics_frames(2)
	player.global_position = Vector2(bounds.position.x + 48.0, (bounds.position.y + bounds.end.y) / 2.0)
	player.velocity = Vector2.ZERO
	await _drive_player(player, "move_left", DRIVE_TICKS)

	assert_eq(GameState.current_state, GameState.State.PLAYING,
			"walking into meadow's UNLINKED west edge must never change GameState away from PLAYING — no neighbour means no transition (design.md §12.4 regression, slice 9 behavior)")
	assert_signal_not_emitted(GameEvents, "area_changed",
			"walking into an unlinked edge must never emit GameEvents.area_changed")
	assert_gt(player.global_position.x, bounds.position.x - 1.0,
			"the player must still be stopped by the west perimeter wall, same as slice 9")


# ---------------------------------------------------------------------------
# Arrival debounce (design.md §12.4/§12.5)
# ---------------------------------------------------------------------------
#
# RESOLVED (was an open question during test-first authoring): the debounce
# is measured as CURRENT distance from the entry edge's playable-facing
# boundary (WorldArea._playable_boundary(), the same boundary
# _edge_rect()/compute_entry_position() use), not distance moved since
# arriving — WorldArea._physics_process() re-checks
# absf(player.global_position.<axis> - boundary) every physics frame against
# is_debounce_armed()'s threshold. This matches design.md §12.4's prose ("a
# plain distance check, not a timer") and its own note that, under CORRECT
# spawn geometry, the debounce should never actually be load-bearing: the
# "one tile inward" spawn offset (§12.5) is already measured from the same
# playable-facing boundary and already clears the debounce threshold on
# arrival (32px offset vs. a 16px east/west threshold, 16px offset vs. an 8px
# north/south threshold) — the debounce exists as a safety margin against
# physics-timing/reparenting jitter on the transition frame, not as the
# mechanism the spawn math relies on. Both tests below still use margins wide
# enough to be unambiguous either way (a few px of travel for "does not fire
# yet"; a clearly-large excursion — several tiles — before re-approaching for
# "now it fires").

func test_immediate_walk_back_to_just_entered_edge_does_not_bounce() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var area: WorldArea = _get_instanced_area(world)
	if area == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return

	await _cross_meadow_east_edge(world, area, player)
	var reached_playing: bool = await _wait_until_playing_or_timeout()
	if not reached_playing:
		fail_test("initial transition into orchard never completed — cannot check the debounce")
		return

	watch_signals(GameEvents)
	# Walk directly back toward the just-entered west edge for only a
	# HANDFUL of physics ticks — computed from the player's own speed
	# (mirrors test_perimeter_walls.gd's identical
	# `speed * ticks / Engine.physics_ticks_per_second` convention) rather
	# than a hardcoded tick count, targeting roughly half the 16px east/west
	# debounce threshold (a few px of travel — "nowhere near a full tile,"
	# well under the threshold under EITHER reading above).
	#
	# TEST-AUTHORING BUG FOUND AND FIXED HERE: a hardcoded 20 ticks at the
	# player's actual 200px/s, 60Hz-default speed covers ~66.7px — more than
	# TWO tiles, well past the 32px entry offset and deep INTO the trigger
	# zone this test means to stay clear of. That went unnoticed while
	# _cross_meadow_east_edge() (see _drive_player()'s doc comment) still had
	# its own overshoot bug: the player wasn't actually spawning near the
	# entry edge at all, so a 20-tick walk-back never got anywhere near it
	# either, and this test passed for the wrong reason. Fixing the overshoot
	# bug exposed this one — the player now genuinely starts one tile in, and
	# 20 ticks of "move_left" walks it straight back through the boundary and
	# into the trigger, correctly re-firing a transition this test asserts
	# should NOT happen.
	var speed: float = player.get("speed")
	var physics_rate: float = float(Engine.physics_ticks_per_second)
	var nudge_ticks: int = int(ceil((DEBOUNCE_EAST_WEST_PX * 0.5) / (speed / physics_rate)))
	await _drive_player(player, "move_left", nudge_ticks)
	# A short settle window — long enough to notice a bounce-back transition
	# if one wrongly started, nowhere near TRANSITION_TIMEOUT_TICKS.
	await wait_physics_frames(30)

	assert_signal_not_emitted(GameEvents, "area_changed",
			"walking back toward the just-entered west edge immediately after arrival — without first covering the debounce distance — must NOT bounce the player back to meadow")
	assert_eq(GameState.current_state, GameState.State.PLAYING,
			"GameState must remain PLAYING throughout — an incorrectly-armed debounce would have kicked off a second (unwanted) transition, flipping this to LOADING")


func test_walking_well_away_then_back_rearms_the_entry_edge() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var area: WorldArea = _get_instanced_area(world)
	if area == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return

	await _cross_meadow_east_edge(world, area, player)
	var reached_playing: bool = await _wait_until_playing_or_timeout()
	if not reached_playing:
		fail_test("initial transition into orchard never completed — cannot check re-arming")
		return

	# Walk CLEARLY away from the entry edge first — several tiles deep into
	# orchard, comfortably beyond any plausible debounce distance under
	# either reading above.
	await _drive_player(player, "move_right", 120)

	watch_signals(GameEvents)
	# Now walk all the way back through the west edge — a real, deliberate
	# return trip, matching the test plan's "leaving and re-entering through
	# the same edge later works normally" bullet.
	await _drive_player(player, "move_left", DRIVE_TICKS)
	var reached_playing_again: bool = await _wait_until_playing_or_timeout()

	assert_true(reached_playing_again,
			"re-crossing orchard's west edge after having walked well away first should trigger a normal transition back to meadow")
	assert_signal_emit_count(GameEvents, "area_changed", 1,
			"re-approaching the entry edge after moving well away must fire exactly one (re-armed) transition")


# ---------------------------------------------------------------------------
# North/south link symmetry (design.md's "identical on all four edges")
# ---------------------------------------------------------------------------

func test_north_south_link_transitions_meadow_south_to_orchard_north() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var area: WorldArea = _get_instanced_area(world)
	if area == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return

	var bounds: Rect2 = area.get_bounds_px()
	var exit_x: float = (bounds.position.x + bounds.end.x) / 2.0
	player.global_position = Vector2(exit_x, bounds.end.y - 96.0)
	player.velocity = Vector2.ZERO
	await wait_physics_frames(2)
	await _drive_player(player, "move_down", DRIVE_TICKS)

	var reached_playing: bool = await _wait_until_playing_or_timeout()
	assert_true(reached_playing,
			"crossing meadow's linked south edge must trigger the same fade-swap-spawn sequence as the east/west link — the mechanism must not be east/west-only")
	if not reached_playing:
		return

	var active_area: Node = world.get_node("ActiveArea")
	if active_area.get_child_count() == 0:
		fail_test("no instanced area found under ActiveArea after the north/south transition")
		return
	var new_area: WorldArea = active_area.get_child(0) as WorldArea
	assert_eq(new_area.scene_file_path if new_area else "", ORCHARD_SCENE_PATH,
			"crossing meadow's south edge should instance the second area (orchard.tscn)")
	if new_area == null:
		return
	var new_bounds: Rect2 = new_area.get_bounds_px()

	assert_almost_eq(player.global_position.x, exit_x, 2.0,
			"the player's X on arrival should match the X they exited meadow's south edge at, carried over verbatim")
	# design.md §12.5's correction: "one tile inward" on a NORTH entry is
	# measured from the north edge's PLAYABLE-FACING boundary
	# (bounds.position.y + NORTH_WALL_HEADROOM_INSET_PX, 32px), not the raw
	# painted edge — landing only 16px in from the true edge (the naive
	# reading) would leave the player still inside the north trigger's own
	# 32px-deep zone, an immediate involuntary bounce back the way they came.
	assert_almost_eq(player.global_position.y, new_bounds.position.y + 32.0 + 16.0, 2.0,
			"the player's Y on arrival should sit exactly one tile (16px) inward from orchard's north edge's playable-facing boundary (32px south of the true painted edge, design.md §12.5) — i.e. bounds.position.y + 48px")


# ---------------------------------------------------------------------------
# Reverse trip: orchard's west edge back to meadow's east edge
# ---------------------------------------------------------------------------

func test_reverse_trip_from_orchards_west_edge_back_to_meadow() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var area: WorldArea = _get_instanced_area(world)
	if area == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return

	await _cross_meadow_east_edge(world, area, player)
	var reached_playing: bool = await _wait_until_playing_or_timeout()
	if not reached_playing:
		fail_test("initial transition into orchard never completed — cannot check the reverse trip")
		return

	# Walk well away from the entry edge first (see the debounce judgment
	# call above), then walk all the way back through it.
	await _drive_player(player, "move_right", 120)
	watch_signals(GameEvents)
	await _drive_player(player, "move_left", DRIVE_TICKS)
	var reached_playing_again: bool = await _wait_until_playing_or_timeout()

	assert_true(reached_playing_again,
			"walking back through orchard's west edge should trigger a normal reverse transition to meadow")
	if not reached_playing_again:
		return

	var active_area: Node = world.get_node("ActiveArea")
	if active_area.get_child_count() == 0:
		fail_test("no instanced area found under ActiveArea after the reverse transition")
		return
	var new_area: Node = active_area.get_child(0)
	assert_eq(new_area.scene_file_path, "res://world/areas/meadow.tscn",
			"the reverse trip through orchard's west edge must land back in meadow.tscn")
	# See test_area_changed_emitted_once_with_the_new_areas_id()'s note above
	# for why the trailing message argument was dropped.
	assert_signal_emitted_with_parameters(GameEvents, "area_changed", [StringName("meadow")])
