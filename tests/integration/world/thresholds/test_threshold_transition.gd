## test_threshold_transition.gd
## Integration tests for World Thresholds Slice 3 ("world.gd drives the
## sequence off a placed Threshold") — world.gd connecting to a Threshold's
## area_entered signal and driving the same freeze -> fade -> swap -> place
## -> reveal sequence the old edge-derived mechanism drives, but landing the
## player on a named Arrival instead of a computed offset, and failing safe
## on a bad destination path or a missing/misnamed Arrival.
##
## Covers: GameState sequencing (LOADING on crossing, back to PLAYING only
## after the full sequence, a residual second area_entered while already
## LOADING is a no-op), the fade overlay's cover/reveal timing, the area
## swap (source freed, destination instanced, player reparented, camera
## limits reset), landing exactly on the named Arrival, GameEvents.area_changed
## timing and payload, the two resolve-before-destroy failure paths (bad
## destination path, missing/misnamed Arrival), the re-entry guard (a
## Threshold the player spawned into/onto stays inert until they've fully
## left it, while an unrelated Threshold in the same area still fires
## normally), and that _activate_area() connects every Threshold under an
## area, not just the first one found. All tests in this file pass.
##
## How these tests avoid touching real content (slices.md's Slice 3 "how to
## prove this without touching real content"): world.tscn is instantiated
## exactly as it is today — it still loads the real meadow.tscn, untouched —
## and each test INJECTS a Threshold as a runtime child of the already-
## instantiated meadow (_inject_threshold() below), pointing at one of the
## small fixture WorldArea scenes under fixtures/ (each >= 10x12 tiles, the
## same one-viewport-minimum floor design.md §6.3 / world-collision design.md
## §12.3 put on real content, so camera-limit assertions stay meaningful).
## meadow.tscn/orchard.tscn are never written to. See fixtures/shared/
## fixture_world_area.gd's header for how the fixtures paint their own floor
## without hand-encoding a TileMapLayer's binary tile_map_data.
##
## Fixtures used (see fixtures/*.tscn):
##   fixture_a.tscn        - one Arrival ("ArrivalFromMeadow"), no Thresholds
##                            of its own. The plain happy-path destination.
##   fixture_reentry.tscn  - Arrival "ArrivalIntoReentry" DELIBERATELY
##                            overlapped by Threshold "ThresholdOut" (both at
##                            local (160, 96)) — the re-entry-guard fixture —
##                            plus a second, non-overlapping "ThresholdSecond"
##                            at (272, 96). Both Thresholds lead onward to
##                            fixture_a.tscn (see that file's header for why
##                            "back to meadow" isn't used: meadow.tscn has no
##                            Arrival authored, and this slice may not add
##                            one — a Threshold landing "in" meadow would just
##                            be this suite's own missing-Arrival failure
##                            case).
##   fixture_plural.tscn   - Arrival "ArrivalFromMeadow" at (160, 160), plus
##                            TWO independent Thresholds ("ThresholdToFixtureA"
##                            at (80, 32) -> fixture_a.tscn,
##                            "ThresholdToReentry" at (240, 32) ->
##                            fixture_reentry.tscn) — proves _activate_area()
##                            connects every Threshold under an area, not just
##                            the first one it finds.
##
## Teleport, not walking, per crossing (see _teleport_onto()'s doc comment):
## unlike the old edge-derived triggers (test_area_transition.gd's suite),
## Threshold detection is a plain Area2D-Area2D overlap check on ThresholdBounds
## (world-thresholds design.md §6) — it does not care how the overlapping box
## got there, only that it did. Directly placing the player is deterministic
## and sidesteps needing to walk a lane through a cramped 320x192px fixture
## (no CollisionProbe-style lane-finding needed here).
##
## Design reference: docs/features/world-thresholds/design.md §4-§5 (the
## Threshold/Arrival mechanism, resolve-before-destroy ordering, re-entry
## guard).
## Test plan: docs/features/world-thresholds/slice-3-world-driven-threshold-test-plan.md
## Slice breakdown: docs/features/world-thresholds/slices.md, Slice 3
##
## Requires GUT: https://github.com/bitwes/Gut
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gselect=test_threshold_transition.gd -gexit

class_name TestThresholdTransition
extends GutTest


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const WORLD_SCENE_PATH: String = "res://world/world.tscn"
const THRESHOLD_SCENE_PATH: String = "res://world/thresholds/threshold.tscn"

const FIXTURES_DIR: String = "res://tests/integration/world/thresholds/fixtures/"
const FIXTURE_A_PATH: String = FIXTURES_DIR + "fixture_a.tscn"
const FIXTURE_REENTRY_PATH: String = FIXTURES_DIR + "fixture_reentry.tscn"
const FIXTURE_PLURAL_PATH: String = FIXTURES_DIR + "fixture_plural.tscn"

## A path that deliberately does not resolve to any file — the "bad
## destination" fixture case doesn't need its own fixture .tscn, just a path
## that fails to load().
const BAD_DESTINATION_PATH: String = FIXTURES_DIR + "does_not_exist.tscn"

## area_id_from_scene_path()'s output for each fixture (WorldArea's static
## helper, still live this slice — it isn't removed until Slice 4), spelled
## out by hand rather than called, matching test_area_transition.gd's own
## convention of hardcoding the expected StringName
## (assert_signal_emitted_with_parameters(..., [StringName("orchard")])).
const FIXTURE_A_ID: StringName = &"fixture_a"
const FIXTURE_REENTRY_ID: StringName = &"fixture_reentry"
const FIXTURE_PLURAL_ID: StringName = &"fixture_plural"

const ARRIVAL_FROM_MEADOW: StringName = &"ArrivalFromMeadow"
const ARRIVAL_INTO_REENTRY: StringName = &"ArrivalIntoReentry"
const NO_SUCH_ARRIVAL: StringName = &"ThisArrivalDoesNotExist"

## Upper bound on how long the freeze/fade/swap/place/reveal sequence is
## allowed to take before this suite gives up waiting and fails with a clear
## timeout message. Mirrors test_area_transition.gd's identically-named
## constant and its reasoning: a ceiling, not a fixed sleep, so a fast
## implementation doesn't pay this cost and a stuck one fails promptly rather
## than hanging the run.
const TRANSITION_TIMEOUT_TICKS: int = 300  # ~5s at 60Hz


# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

func before_each() -> void:
	GameState.change_state(GameState.State.PLAYING)


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


func _get_player(world: Node) -> CharacterBody2D:
	var player: CharacterBody2D = world.find_child("Player", true, false) as CharacterBody2D
	assert_not_null(player, "world.tscn's instantiated tree should contain a CharacterBody2D named 'Player'")
	return player


## The WorldArea currently instanced under ActiveArea — meadow right after
## _instantiate_world(), or whichever fixture is active after a transition
## has completed. Named generically (not "_get_meadow") since this suite
## calls it both before and after a swap.
func _get_active_area(world: Node) -> WorldArea:
	var active_area: Node = world.get_node_or_null("ActiveArea")
	assert_not_null(active_area, "world.tscn should have a direct child named 'ActiveArea'")
	if active_area == null:
		return null
	assert_gt(active_area.get_child_count(), 0, "ActiveArea should hold an instanced WorldArea")
	if active_area.get_child_count() == 0:
		return null
	var area: Node = active_area.get_child(0)
	if not (area is WorldArea):
		fail_test("the instanced ActiveArea child must be a WorldArea instance — found a %s" % [area.get_class()])
		return null
	return area as WorldArea


## Instance threshold.tscn, configure its exports, and add it as a runtime
## child of `area` at `world_position` — the "inject a Threshold as a runtime
## child of the already-instantiated meadow" proof strategy slices.md's
## Slice 3 calls for. Position is set AFTER add_child() so it's expressed in
## world space regardless of where `area` itself sits.
func _inject_threshold(area: Node, destination: String, arrival: StringName,
		world_position: Vector2, node_name: String = "InjectedThreshold") -> Threshold:
	var packed: PackedScene = load(THRESHOLD_SCENE_PATH)
	assert_not_null(packed, "%s should load as a PackedScene" % [THRESHOLD_SCENE_PATH])
	if packed == null:
		return null
	var threshold: Threshold = packed.instantiate() as Threshold
	assert_not_null(threshold, "%s should instantiate as a Threshold" % [THRESHOLD_SCENE_PATH])
	if threshold == null:
		return null
	threshold.name = node_name
	threshold.destination = destination
	threshold.arrival = arrival
	area.add_child(threshold)
	threshold.global_position = world_position
	return threshold


## Place `player` exactly at `target_position`, guaranteed to transition from
## "not overlapping" to "overlapping" whatever Threshold sits there.
##
## Teleports to a point 2000px away first (guaranteed clear of every fixture
## in this suite — each is confined to its own <= 320x192px painted rect)
## before landing on the real target, rather than assuming the player wasn't
## already sitting on target_position from some earlier point in the test.
## Area2D-Area2D overlap detection only fires area_entered on a transition
## from clear to overlapping, so this two-step landing is what makes repeated
## calls to this helper within one test (e.g. the re-entry-guard tests) each
## produce a fresh crossing rather than a no-op.
##
## Safe to do with a plain assignment (not move_and_slide()) because
## Threshold detection cares only about the shapes' final transforms each
## physics step, not the path the player's CharacterBody2D took to get
## there — see this file's header.
func _teleport_onto(player: CharacterBody2D, target_position: Vector2) -> void:
	player.velocity = Vector2.ZERO
	player.global_position = target_position + Vector2(-2000.0, -2000.0)
	await wait_physics_frames(2)
	player.global_position = target_position
	await wait_physics_frames(2)


## Poll in small increments until GameState.current_state == PLAYING again
## (the transition sequence has fully completed) or TRANSITION_TIMEOUT_TICKS
## is exceeded. Mirrors test_area_transition.gd's identically-named helper.
func _wait_until_playing_or_timeout() -> bool:
	var waited: int = 0
	while waited < TRANSITION_TIMEOUT_TICKS:
		if GameState.current_state == GameState.State.PLAYING:
			return true
		await wait_physics_frames(10)
		waited += 10
	return GameState.current_state == GameState.State.PLAYING


## The first direct child of `transition` that exposes a `modulate` property
## (i.e. any CanvasItem). Mirrors test_area_transition.gd's identically-named
## helper and its JUDGMENT CALL note: this suite doesn't assume a specific
## fade node name, only that Transition has SOME CanvasItem child used for
## the cover fade.
func _find_fade_canvas_item(transition: Node) -> CanvasItem:
	for child in transition.get_children():
		if child is CanvasItem:
			return child as CanvasItem
	return null


# ---------------------------------------------------------------------------
# GameState sequencing (design.md §5's freeze step, mirroring the old
## _on_edge_reached()'s guard against a residual second firing)
# ---------------------------------------------------------------------------

func test_game_state_becomes_loading_immediately_on_crossing_threshold() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var meadow: WorldArea = _get_active_area(world)
	if meadow == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return

	var target: Vector2 = meadow.get_bounds_px().get_center()
	_inject_threshold(meadow, FIXTURE_A_PATH, ARRIVAL_FROM_MEADOW, target)
	await _teleport_onto(player, target)

	assert_eq(GameState.current_state, GameState.State.LOADING,
			"GameState.current_state must become LOADING as soon as the player's ThresholdBounds enters a placed Threshold, before the fade/swap/place sequence runs (design.md §5)")


func test_residual_second_area_entered_while_loading_is_a_noop() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var meadow: WorldArea = _get_active_area(world)
	if meadow == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return

	watch_signals(GameEvents)
	var target: Vector2 = meadow.get_bounds_px().get_center()
	var threshold: Threshold = _inject_threshold(meadow, FIXTURE_A_PATH, ARRIVAL_FROM_MEADOW, target)
	await _teleport_onto(player, target)

	# Simulate a residual/duplicate area_entered firing a second time,
	# immediately, while GameState is still (presumably) LOADING from the
	# first crossing — mirrors test_area_transition.gd's identical
	# re-emit-the-signal-directly technique for edge_reached.
	var bounds_area: Area2D = player.get_node_or_null("ThresholdBounds") as Area2D
	if is_instance_valid(threshold) and bounds_area != null:
		threshold.area_entered.emit(bounds_area)

	var reached_playing: bool = await _wait_until_playing_or_timeout()
	if not reached_playing:
		fail_test("transition never completed — cannot check the re-entry guard")
		return

	assert_signal_emit_count(GameEvents, "area_changed", 1,
			"a second area_entered fired while a transition was already underway (GameState == LOADING) must not start an overlapping second transition or double-emit area_changed")

	var active_area: Node = world.get_node("ActiveArea")
	assert_eq(active_area.get_child_count(), 1,
			"ActiveArea must hold exactly one WorldArea even after a residual/duplicate area_entered — a double transition would risk freeing an already-freed area or instancing a second one")


# ---------------------------------------------------------------------------
# Transition overlay fade ordering (design.md §5's fade step)
# ---------------------------------------------------------------------------

func test_fade_overlay_becomes_opaque_while_loading() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var meadow: WorldArea = _get_active_area(world)
	if meadow == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return
	var transition: Node = world.get_node_or_null("Transition")
	assert_not_null(transition, "world.tscn should have a direct child named 'Transition'")
	if transition == null:
		return

	var target: Vector2 = meadow.get_bounds_px().get_center()
	_inject_threshold(meadow, FIXTURE_A_PATH, ARRIVAL_FROM_MEADOW, target)
	await _teleport_onto(player, target)
	# Give the fade-in Tween a moment to progress — not asserting fully
	# opaque yet (timing-dependent), just that it has started covering the
	# screen while GameState is LOADING.
	await wait_physics_frames(20)

	var fade: CanvasItem = _find_fade_canvas_item(transition)
	assert_not_null(fade,
			"Transition should have at least one CanvasItem child (e.g. a full-screen ColorRect) used for the cover fade")
	if fade == null:
		return

	assert_gt(fade.modulate.a, 0.0,
			"the Transition overlay's fade child should have started becoming opaque (modulate.a > 0) shortly after crossing a Threshold, while GameState is LOADING")


func test_fade_overlay_returns_to_transparent_after_reveal() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var meadow: WorldArea = _get_active_area(world)
	if meadow == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return
	var transition: Node = world.get_node_or_null("Transition")
	if transition == null:
		return

	var target: Vector2 = meadow.get_bounds_px().get_center()
	_inject_threshold(meadow, FIXTURE_A_PATH, ARRIVAL_FROM_MEADOW, target)
	await _teleport_onto(player, target)
	await _wait_until_playing_or_timeout()

	var fade: CanvasItem = _find_fade_canvas_item(transition)
	if fade == null:
		return

	assert_almost_eq(fade.modulate.a, 0.0, 0.05,
			"the Transition overlay's fade child must be back to fully transparent once the sequence completes and GameState is PLAYING again")


func test_game_state_returns_to_playing_only_after_the_full_sequence() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var meadow: WorldArea = _get_active_area(world)
	if meadow == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return

	var target: Vector2 = meadow.get_bounds_px().get_center()
	_inject_threshold(meadow, FIXTURE_A_PATH, ARRIVAL_FROM_MEADOW, target)
	await _teleport_onto(player, target)
	var reached_playing: bool = await _wait_until_playing_or_timeout()

	assert_true(reached_playing,
			(
			"GameState.current_state should return to PLAYING once the freeze/fade/swap/place/reveal "
			+ "sequence completes — it did not within %d physics frames (~%.0fs). Current state: %d"
			) % [TRANSITION_TIMEOUT_TICKS, TRANSITION_TIMEOUT_TICKS / 60.0, GameState.current_state])


# ---------------------------------------------------------------------------
# Area swap: free source area, instance destination, reparent (design.md §5)
# ---------------------------------------------------------------------------

func test_source_area_is_freed_and_destination_is_instanced_in_its_place() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var meadow: WorldArea = _get_active_area(world)
	if meadow == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return

	var target: Vector2 = meadow.get_bounds_px().get_center()
	_inject_threshold(meadow, FIXTURE_A_PATH, ARRIVAL_FROM_MEADOW, target)
	await _teleport_onto(player, target)
	var reached_playing: bool = await _wait_until_playing_or_timeout()
	if not reached_playing:
		fail_test("transition never completed — cannot check area swap")
		return

	assert_true(not is_instance_valid(meadow) or not meadow.is_inside_tree(),
			"the source (meadow) WorldArea instance must be freed (or at least removed from the tree) after the transition completes")

	var active_area: Node = world.get_node_or_null("ActiveArea")
	if active_area == null:
		return
	assert_eq(active_area.get_child_count(), 1,
			"ActiveArea should hold exactly one WorldArea after the swap — found %d children" % [active_area.get_child_count()])
	if active_area.get_child_count() == 0:
		return

	var new_area: Node = active_area.get_child(0)
	assert_eq(new_area.scene_file_path, FIXTURE_A_PATH,
			"ActiveArea's child after crossing the injected Threshold should be an instance of %s — found '%s'" % [FIXTURE_A_PATH, new_area.scene_file_path])


func test_player_is_reparented_into_the_destination_area() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var meadow: WorldArea = _get_active_area(world)
	if meadow == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return

	var target: Vector2 = meadow.get_bounds_px().get_center()
	_inject_threshold(meadow, FIXTURE_A_PATH, ARRIVAL_FROM_MEADOW, target)
	await _teleport_onto(player, target)
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
			"the Player must be reparented into the newly-instanced destination area — found parent '%s'" % [player.get_parent().name if player.get_parent() else "<none>"])


func test_camera_limits_are_reset_to_the_destination_areas_bounds() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var meadow: WorldArea = _get_active_area(world)
	if meadow == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return

	var target: Vector2 = meadow.get_bounds_px().get_center()
	_inject_threshold(meadow, FIXTURE_A_PATH, ARRIVAL_FROM_MEADOW, target)
	await _teleport_onto(player, target)
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
			"Camera2D.limit_left must be reset to the DESTINATION area's bounds (%.1f), not left at the source area's stale value" % [new_bounds.position.x])
	assert_eq(camera.limit_top, int(new_bounds.position.y),
			"Camera2D.limit_top must be reset to the destination area's bounds")
	assert_eq(camera.limit_right, int(new_bounds.end.x),
			"Camera2D.limit_right must be reset to the destination area's bounds")
	assert_eq(camera.limit_bottom, int(new_bounds.end.y),
			"Camera2D.limit_bottom must be reset to the destination area's bounds")


# ---------------------------------------------------------------------------
# Landing at the named Arrival — not a computed offset (design.md §5)
# ---------------------------------------------------------------------------

func test_player_lands_exactly_at_the_named_arrivals_position() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var meadow: WorldArea = _get_active_area(world)
	if meadow == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return

	var target: Vector2 = meadow.get_bounds_px().get_center()
	_inject_threshold(meadow, FIXTURE_A_PATH, ARRIVAL_FROM_MEADOW, target)
	await _teleport_onto(player, target)
	var reached_playing: bool = await _wait_until_playing_or_timeout()
	if not reached_playing:
		fail_test("transition never completed — cannot check spawn placement")
		return

	var active_area: Node = world.get_node_or_null("ActiveArea")
	if active_area == null or active_area.get_child_count() == 0:
		fail_test("no instanced area found under ActiveArea after the transition")
		return
	var new_area: Node = active_area.get_child(0)
	var arrival: Marker2D = new_area.find_child(String(ARRIVAL_FROM_MEADOW), true, false) as Marker2D
	assert_not_null(arrival, "%s should contain a Marker2D named '%s'" % [FIXTURE_A_PATH, ARRIVAL_FROM_MEADOW])
	if arrival == null:
		return

	# Read the marker's position back from the live instance rather than
	# hard-coding fixture_a.tscn's authored (160, 96) — this is exactly what
	# "not a computed offset" (design.md §5) means to prove: the player's
	# landing spot must equal wherever the Arrival actually is, not a value
	# this test happens to already know.
	assert_almost_eq(player.global_position, arrival.global_position, Vector2(0.01, 0.01),
			"the player's position on arrival must exactly match the named Arrival's global position (%s) — found %s" % [arrival.global_position, player.global_position])


# ---------------------------------------------------------------------------
# GameEvents.area_changed (design.md §5)
# ---------------------------------------------------------------------------

func test_area_changed_emitted_once_with_the_destination_areas_id() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var meadow: WorldArea = _get_active_area(world)
	if meadow == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return

	watch_signals(GameEvents)
	var target: Vector2 = meadow.get_bounds_px().get_center()
	_inject_threshold(meadow, FIXTURE_A_PATH, ARRIVAL_FROM_MEADOW, target)
	await _teleport_onto(player, target)
	var reached_playing: bool = await _wait_until_playing_or_timeout()
	if not reached_playing:
		fail_test("transition never completed — cannot check area_changed")
		return

	assert_signal_emit_count(GameEvents, "area_changed", 1,
			"GameEvents.area_changed must be emitted exactly once per crossing")
	# NOTE: assert_signal_emitted_with_parameters()'s 4th positional argument
	# is an emission INDEX, not a failure message — see test_area_transition.gd's
	# identical note. No trailing message string here.
	assert_signal_emitted_with_parameters(GameEvents, "area_changed", [FIXTURE_A_ID])


func test_area_changed_emitted_only_after_swap_reparent_and_camera_work_are_done() -> void:
	# Captures live scene state AT THE MOMENT area_changed fires (via a
	# directly-connected lambda), proving the swap/reparent/camera work was
	# already done by the time listeners see the signal — mirrors
	# test_area_transition.gd's identically-purposed test.
	var world: Node = _instantiate_world()
	if world == null:
		return
	var meadow: WorldArea = _get_active_area(world)
	if meadow == null:
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

	var target: Vector2 = meadow.get_bounds_px().get_center()
	_inject_threshold(meadow, FIXTURE_A_PATH, ARRIVAL_FROM_MEADOW, target)
	await _teleport_onto(player, target)
	var reached_playing: bool = await _wait_until_playing_or_timeout()
	GameEvents.area_changed.disconnect(on_area_changed)
	if not reached_playing:
		fail_test("transition never completed — cannot check area_changed ordering")
		return

	assert_true(snapshot["captured"], "GameEvents.area_changed should have fired at least once during the transition")
	assert_true(snapshot["player_parent_was_new_area"],
			"at the moment area_changed fired, the Player must ALREADY be reparented into the destination area — not before the swap")
	assert_true(snapshot["camera_limits_were_set"],
			"at the moment area_changed fired, Camera2D.limit_left must already be something other than Godot's default (-10000000) — the camera rebuild must have already run")


# ---------------------------------------------------------------------------
# Failure path: bad destination (design.md §5's resolve-before-destroy order)
# ---------------------------------------------------------------------------

func test_bad_destination_path_leaves_game_state_playing_and_player_unmoved() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var meadow: WorldArea = _get_active_area(world)
	if meadow == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return

	var target: Vector2 = meadow.get_bounds_px().get_center()
	_inject_threshold(meadow, BAD_DESTINATION_PATH, ARRIVAL_FROM_MEADOW, target)
	await _teleport_onto(player, target)
	var reached_playing: bool = await _wait_until_playing_or_timeout()

	assert_true(reached_playing,
			"a Threshold whose destination fails to load must recover to PLAYING, not strand GameState at LOADING")
	if reached_playing:
		assert_eq(GameState.current_state, GameState.State.PLAYING,
				"GameState must be back to PLAYING after a bad destination path fails to load")
	assert_almost_eq(player.global_position, target, Vector2(0.5, 0.5),
			"the player must be exactly where they were when they crossed — a bad destination path must not move them")
	assert_push_error_count(1,
			"a bad destination path must push exactly one error, not fail silently (design.md §5)")


func test_bad_destination_path_fade_overlay_returns_to_transparent() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var meadow: WorldArea = _get_active_area(world)
	if meadow == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return
	var transition: Node = world.get_node_or_null("Transition")
	if transition == null:
		return

	var target: Vector2 = meadow.get_bounds_px().get_center()
	_inject_threshold(meadow, BAD_DESTINATION_PATH, ARRIVAL_FROM_MEADOW, target)
	await _teleport_onto(player, target)
	await _wait_until_playing_or_timeout()

	var fade: CanvasItem = _find_fade_canvas_item(transition)
	if fade == null:
		return
	assert_almost_eq(fade.modulate.a, 0.0, 0.05,
			"a bad destination path must not strand the player behind an opaque fade (design.md §5) — the overlay must return to fully transparent")
	assert_push_error_count(1, "consuming the expected push_error so it doesn't also fail this test")


func test_bad_destination_path_active_area_still_holds_the_original_source() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var meadow: WorldArea = _get_active_area(world)
	if meadow == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return

	var target: Vector2 = meadow.get_bounds_px().get_center()
	_inject_threshold(meadow, BAD_DESTINATION_PATH, ARRIVAL_FROM_MEADOW, target)
	await _teleport_onto(player, target)
	await _wait_until_playing_or_timeout()

	var active_area: Node = world.get_node("ActiveArea")
	assert_eq(active_area.get_child_count(), 1,
			"ActiveArea must still hold exactly one WorldArea after a failed transition — nothing freed, nothing duplicated")
	if active_area.get_child_count() > 0:
		assert_eq(active_area.get_child(0), meadow,
				"ActiveArea's child must still be the ORIGINAL source area instance — a bad destination path must not have freed or replaced it")
	assert_push_error_count(1, "consuming the expected push_error so it doesn't also fail this test")


# ---------------------------------------------------------------------------
# Failure path: destination loads but the named Arrival doesn't exist
# ---------------------------------------------------------------------------

func test_missing_arrival_leaves_game_state_playing_and_player_unmoved() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var meadow: WorldArea = _get_active_area(world)
	if meadow == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return

	var target: Vector2 = meadow.get_bounds_px().get_center()
	_inject_threshold(meadow, FIXTURE_A_PATH, NO_SUCH_ARRIVAL, target)
	await _teleport_onto(player, target)
	var reached_playing: bool = await _wait_until_playing_or_timeout()

	assert_true(reached_playing,
			"a Threshold whose destination loads but names no matching Arrival must recover to PLAYING, not strand GameState at LOADING")
	if reached_playing:
		assert_eq(GameState.current_state, GameState.State.PLAYING,
				"GameState must be back to PLAYING after a missing/misnamed Arrival fails")
	assert_almost_eq(player.global_position, target, Vector2(0.5, 0.5),
			"the player must be exactly where they were when they crossed — a missing Arrival must not move them")
	assert_push_error_count(1,
			"a missing/misnamed Arrival must push exactly one error, not fail silently (design.md §5)")


func test_missing_arrival_fade_overlay_returns_to_transparent() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var meadow: WorldArea = _get_active_area(world)
	if meadow == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return
	var transition: Node = world.get_node_or_null("Transition")
	if transition == null:
		return

	var target: Vector2 = meadow.get_bounds_px().get_center()
	_inject_threshold(meadow, FIXTURE_A_PATH, NO_SUCH_ARRIVAL, target)
	await _teleport_onto(player, target)
	await _wait_until_playing_or_timeout()

	var fade: CanvasItem = _find_fade_canvas_item(transition)
	if fade == null:
		return
	assert_almost_eq(fade.modulate.a, 0.0, 0.05,
			"a missing Arrival must not strand the player behind an opaque fade — the overlay must return to fully transparent")
	assert_push_error_count(1, "consuming the expected push_error so it doesn't also fail this test")


func test_missing_arrival_active_area_still_holds_the_original_source() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var meadow: WorldArea = _get_active_area(world)
	if meadow == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return

	var target: Vector2 = meadow.get_bounds_px().get_center()
	_inject_threshold(meadow, FIXTURE_A_PATH, NO_SUCH_ARRIVAL, target)
	await _teleport_onto(player, target)
	await _wait_until_playing_or_timeout()

	var active_area: Node = world.get_node("ActiveArea")
	assert_eq(active_area.get_child_count(), 1,
			"ActiveArea must still hold exactly one WorldArea after a failed transition — nothing freed, nothing duplicated")
	if active_area.get_child_count() > 0:
		assert_eq(active_area.get_child(0), meadow,
				"ActiveArea's child must still be the ORIGINAL source area instance — a missing Arrival must not have freed or replaced it")
	assert_push_error_count(1, "consuming the expected push_error so it doesn't also fail this test")


# ---------------------------------------------------------------------------
# Re-entry guard (design.md §5): a Threshold the player spawned into/onto
# stays inert until ThresholdBounds has fully left it.
# ---------------------------------------------------------------------------

func test_arrival_overlapping_a_threshold_does_not_fire_on_arrival() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var meadow: WorldArea = _get_active_area(world)
	if meadow == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return

	var target: Vector2 = meadow.get_bounds_px().get_center()
	_inject_threshold(meadow, FIXTURE_REENTRY_PATH, ARRIVAL_INTO_REENTRY, target)
	await _teleport_onto(player, target)
	var reached_playing: bool = await _wait_until_playing_or_timeout()
	if not reached_playing:
		fail_test("initial transition into fixture_reentry never completed — cannot check the re-entry guard")
		return

	# The player has just landed exactly on ArrivalIntoReentry, which
	# fixture_reentry.tscn deliberately places its own "ThresholdOut"
	# Threshold on top of (see this file's header). The re-entry guard
	# (design.md §5) must keep it inert on arrival.
	watch_signals(GameEvents)
	# A settle window — long enough to notice a wrongly-fired transition,
	# nowhere near TRANSITION_TIMEOUT_TICKS.
	await wait_physics_frames(30)

	assert_eq(GameState.current_state, GameState.State.PLAYING,
			"landing on an Arrival that overlaps a Threshold must not immediately re-fire a transition — the Threshold the player spawned into must stay inert until they've fully left it (design.md §5)")
	assert_signal_not_emitted(GameEvents, "area_changed",
			"an Arrival overlapping a Threshold must not emit area_changed on arrival")


func test_leaving_and_re_entering_an_overlapping_threshold_fires_normally() -> void:
	# Also stands in for the test plan's "reverse trip" bullet: ThresholdOut
	# is a Threshold PLACED INSIDE fixture_reentry.tscn (the destination area
	# the player just arrived in), driving onward to a different area
	# (fixture_a.tscn) — proving a Threshold sitting inside a just-entered
	# area drives a normal further transition once its guard clears, not
	# just Thresholds injected directly into the original source area.
	var world: Node = _instantiate_world()
	if world == null:
		return
	var meadow: WorldArea = _get_active_area(world)
	if meadow == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return

	var target: Vector2 = meadow.get_bounds_px().get_center()
	_inject_threshold(meadow, FIXTURE_REENTRY_PATH, ARRIVAL_INTO_REENTRY, target)
	await _teleport_onto(player, target)
	var reached_playing: bool = await _wait_until_playing_or_timeout()
	if not reached_playing:
		fail_test("initial transition into fixture_reentry never completed — cannot check leaving and re-entering")
		return

	var active_area: Node = world.get_node("ActiveArea")
	if active_area.get_child_count() == 0:
		fail_test("no instanced area found under ActiveArea after the initial transition")
		return
	var fixture: WorldArea = active_area.get_child(0) as WorldArea
	var threshold_out: Node2D = fixture.find_child("ThresholdOut", true, false) as Node2D
	assert_not_null(threshold_out, "fixture_reentry.tscn should contain a Threshold named 'ThresholdOut'")
	if threshold_out == null:
		return

	watch_signals(GameEvents)
	# _teleport_onto() itself performs "move somewhere guaranteed clear, then
	# land on the target" — exactly the "fully leave, then walk back" motion
	# this guard-clearing case needs, so no separate "walk away" step is
	# required here.
	await _teleport_onto(player, threshold_out.global_position)
	var reached_playing_again: bool = await _wait_until_playing_or_timeout()

	assert_true(reached_playing_again,
			"re-crossing ThresholdOut after having fully left it should trigger a normal transition — the guard must have cleared once ThresholdBounds reported leaving it (design.md §5)")
	assert_signal_emitted_with_parameters(GameEvents, "area_changed", [FIXTURE_A_ID])


func test_second_nonoverlapping_threshold_in_same_area_fires_on_first_crossing() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var meadow: WorldArea = _get_active_area(world)
	if meadow == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return

	var target: Vector2 = meadow.get_bounds_px().get_center()
	_inject_threshold(meadow, FIXTURE_REENTRY_PATH, ARRIVAL_INTO_REENTRY, target)
	await _teleport_onto(player, target)
	var reached_playing: bool = await _wait_until_playing_or_timeout()
	if not reached_playing:
		fail_test("initial transition into fixture_reentry never completed — cannot check the second Threshold")
		return

	var active_area: Node = world.get_node("ActiveArea")
	if active_area.get_child_count() == 0:
		fail_test("no instanced area found under ActiveArea after the initial transition")
		return
	var fixture: WorldArea = active_area.get_child(0) as WorldArea
	var threshold_second: Node2D = fixture.find_child("ThresholdSecond", true, false) as Node2D
	assert_not_null(threshold_second, "fixture_reentry.tscn should contain a Threshold named 'ThresholdSecond'")
	if threshold_second == null:
		return

	watch_signals(GameEvents)
	await _teleport_onto(player, threshold_second.global_position)
	var reached_playing_again: bool = await _wait_until_playing_or_timeout()

	assert_true(reached_playing_again,
			"a second, non-overlapping Threshold in the same area must fire on its FIRST crossing — the arm-on-arrival guard only ever suppresses the Threshold the player spawned into (design.md §5)")
	assert_signal_emitted_with_parameters(GameEvents, "area_changed", [FIXTURE_A_ID])


# ---------------------------------------------------------------------------
# Plural wiring: _activate_area() connects every Threshold under an area
# ---------------------------------------------------------------------------

func test_first_of_two_thresholds_in_a_fixture_drives_to_its_own_destination() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var meadow: WorldArea = _get_active_area(world)
	if meadow == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return

	var target: Vector2 = meadow.get_bounds_px().get_center()
	_inject_threshold(meadow, FIXTURE_PLURAL_PATH, ARRIVAL_FROM_MEADOW, target)
	await _teleport_onto(player, target)
	var reached_playing: bool = await _wait_until_playing_or_timeout()
	if not reached_playing:
		fail_test("initial transition into fixture_plural never completed — cannot check plural wiring")
		return

	var active_area: Node = world.get_node("ActiveArea")
	if active_area.get_child_count() == 0:
		fail_test("no instanced area found under ActiveArea after the initial transition")
		return
	var fixture: WorldArea = active_area.get_child(0) as WorldArea
	var threshold_a: Node2D = fixture.find_child("ThresholdToFixtureA", true, false) as Node2D
	assert_not_null(threshold_a, "fixture_plural.tscn should contain a Threshold named 'ThresholdToFixtureA'")
	if threshold_a == null:
		return

	watch_signals(GameEvents)
	await _teleport_onto(player, threshold_a.global_position)
	var reached_playing_again: bool = await _wait_until_playing_or_timeout()

	assert_true(reached_playing_again,
			"the first of two Thresholds placed in the same fixture should drive a normal transition to its OWN destination")
	assert_signal_emitted_with_parameters(GameEvents, "area_changed", [FIXTURE_A_ID])
	var new_active_area: Node = world.get_node("ActiveArea")
	if new_active_area.get_child_count() > 0:
		assert_eq(new_active_area.get_child(0).scene_file_path, FIXTURE_A_PATH,
				"crossing ThresholdToFixtureA should land in fixture_a.tscn")


func test_second_of_two_thresholds_in_a_fixture_drives_to_its_own_destination() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var meadow: WorldArea = _get_active_area(world)
	if meadow == null:
		return
	var player: CharacterBody2D = _get_player(world)
	if player == null:
		return

	var target: Vector2 = meadow.get_bounds_px().get_center()
	_inject_threshold(meadow, FIXTURE_PLURAL_PATH, ARRIVAL_FROM_MEADOW, target)
	await _teleport_onto(player, target)
	var reached_playing: bool = await _wait_until_playing_or_timeout()
	if not reached_playing:
		fail_test("initial transition into fixture_plural never completed — cannot check plural wiring")
		return

	var active_area: Node = world.get_node("ActiveArea")
	if active_area.get_child_count() == 0:
		fail_test("no instanced area found under ActiveArea after the initial transition")
		return
	var fixture: WorldArea = active_area.get_child(0) as WorldArea
	var threshold_reentry: Node2D = fixture.find_child("ThresholdToReentry", true, false) as Node2D
	assert_not_null(threshold_reentry, "fixture_plural.tscn should contain a Threshold named 'ThresholdToReentry'")
	if threshold_reentry == null:
		return

	watch_signals(GameEvents)
	await _teleport_onto(player, threshold_reentry.global_position)
	var reached_playing_again: bool = await _wait_until_playing_or_timeout()

	assert_true(reached_playing_again,
			"the second of two Thresholds placed in the same fixture should drive a normal transition to ITS OWN (different) destination — proving _activate_area() connects every Threshold under the area, not just the first one")
	assert_signal_emitted_with_parameters(GameEvents, "area_changed", [FIXTURE_REENTRY_ID])
	var new_active_area: Node = world.get_node("ActiveArea")
	if new_active_area.get_child_count() > 0:
		assert_eq(new_active_area.get_child(0).scene_file_path, FIXTURE_REENTRY_PATH,
				"crossing ThresholdToReentry should land in fixture_reentry.tscn")
