## test_camera_dead_zone_and_limits.gd
## Integration tests for Slice 9 of the world-collision feature ("Camera dead
## zone, edge lock, and perimeter walls") — the camera half of the slice.
## Perimeter wall behavior lives in the sibling file test_perimeter_walls.gd
## (kept separate: two distinct concerns, same slice, matching this suite's
## convention of one file per concern rather than one file per slice — see
## test_solids_collision.gd vs test_tile_geometry.gd).
##
## Written test-first, ahead of the implementation: at the time this suite
## was authored, world.gd did not yet read WorldArea.get_bounds_px() to set
## Camera2D.limit_*, and player.tscn's Camera2D had no drag_horizontal_enabled/
## drag_vertical_enabled/margins/position_smoothing_enabled set. That wiring
## now exists (world.gd's per-area camera-limit derivation; player.tscn's
## static drag-margin/smoothing properties), and every test below passes
## against it — this file's job now is to guard that behavior against
## regressions.
##
## This file tests the ASSEMBLED world scene (world.tscn after World._ready()
## runs), which is a different scope from
## tests/integration/player/test_player_scene.gd's standalone player.tscn
## checks — that file verifies player.tscn's own authored properties in
## isolation; this file verifies what the live camera actually ends up with
## once world.gd has had a chance to touch it (e.g. limit_left/top/right/
## bottom, which world.gd sets at runtime and cannot appear as a fixed value
## in player.tscn at all, since it's derived per-area from
## WorldArea.get_bounds_px()).
##
## Design reference: docs/features/world-collision/design.md §12.3 (camera
## dead-zone/edge-lock derivation).
## Test plan: docs/features/world-collision/slice-9-camera-perimeter-test-plan.md
##
## Requires GUT: https://github.com/bitwes/Gut
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gselect=test_camera_dead_zone_and_limits.gd -gexit

class_name TestCameraDeadZoneAndLimits
extends GutTest


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const WORLD_SCENE_PATH: String = "res://world/world.tscn"
const MEADOW_SCENE_PATH: String = "res://world/areas/meadow.tscn"

## Two-tile dead zone derivation, design.md §12.3's table:
##   horizontal: 2 tiles * 32px = 64px, over a 320px viewport's half-width
##               (160px) -> 64 / 160 = 0.4 exactly.
##   vertical:   2 tiles * 16px = 32px, over a 180px viewport's half-height
##               (90px) -> 32 / 90 ~= 0.35556 repeating (not exact in binary
##               floating point, hence the tolerance below).
const EXPECTED_DRAG_MARGIN_HORIZONTAL: float = 0.4
const EXPECTED_DRAG_MARGIN_VERTICAL: float = 32.0 / 90.0
const MARGIN_TOLERANCE: float = 0.001


# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

func before_each() -> void:
	# Player movement is gated on GameState.current_state == PLAYING
	# (player.gd). Set explicitly, matching test_perimeter_walls.gd's
	# convention, so this suite doesn't depend on GameState's default or on
	# whatever an earlier-running test file left it in — including
	# world.gd's own _load_starting_area(), which now brackets startup in
	# LOADING and can leave GameState stuck there if a test tears down
	# world.tscn before that coroutine finishes (see _load_starting_area()'s
	# doc comment in world/world.gd).
	GameState.change_state(GameState.State.PLAYING)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Instantiate world.tscn and add it to the tree so World._ready() runs
## (area instancing + Player reparent + — once implemented — camera limit/
## perimeter wiring). Autofreed at teardown. Mirrors the identically-named
## helper in test_world_area_shell.gd / test_solids_collision.gd; each
## integration test file in this suite keeps its own copy rather than sharing
## a base class, matching the existing convention across this folder.
## @return the instantiated World root, or null (with a failed assertion
## already recorded) if the scene can't be loaded/instantiated.
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


## ActiveArea's single expected child: the instanced meadow WorldArea. Fails
## (with an assertion already recorded) and returns null if ActiveArea is
## missing or empty. Mirrors test_world_area_shell.gd's helper of the same
## name/behavior.
func _get_instanced_area(world: Node) -> Node:
	var active_area: Node = world.get_node_or_null("ActiveArea")
	assert_not_null(active_area, "world.tscn should have a direct child named 'ActiveArea' (design doc §12.1)")
	if active_area == null:
		return null

	assert_gt(active_area.get_child_count(), 0,
			"ActiveArea should hold the instanced meadow WorldArea, found no children")
	if active_area.get_child_count() == 0:
		return null

	return active_area.get_child(0)


## Locate the player's Camera2D on the assembled, post-_ready() world scene.
## Returns null (with an assertion already recorded) if the Player or its
## Camera2D child can't be found.
func _get_player_camera(world: Node) -> Camera2D:
	var player: CharacterBody2D = world.find_child("Player", true, false) as CharacterBody2D
	assert_not_null(player,
			"world.tscn's instantiated tree should contain a CharacterBody2D named 'Player' (post-Slice-8 this is reparented into the instanced meadow WorldArea, not left under World's own root)")
	if player == null:
		return null

	var camera: Camera2D = player.get_node_or_null("Camera2D") as Camera2D
	assert_not_null(camera, "Player must have a Camera2D child node named 'Camera2D'")
	return camera


# ---------------------------------------------------------------------------
# Camera limits == area bounds (design doc §12.3, "Locked at the map edge")
# ---------------------------------------------------------------------------

func test_camera_limits_match_area_bounds_px() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return

	var area: Node = _get_instanced_area(world)
	if area == null:
		return
	if not (area is WorldArea):
		fail_test("the instanced ActiveArea child must be a WorldArea instance to call get_bounds_px() on it — found a %s" % [area.get_class()])
		return

	var bounds: Rect2 = (area as WorldArea).get_bounds_px()
	var camera: Camera2D = _get_player_camera(world)
	if camera == null:
		return

	# design.md §12.3's exact wiring:
	#   cam.limit_left = int(b.position.x); cam.limit_top = int(b.position.y)
	#   cam.limit_right = int(b.end.x);    cam.limit_bottom = int(b.end.y)
	assert_eq(camera.limit_left, int(bounds.position.x),
			(
			"Camera2D.limit_left must equal get_bounds_px().position.x (%d) — found %d. "
			+ "world.gd should set this from the loaded area's bounds on every area load "
			+ "(design.md §12.3)."
			) % [int(bounds.position.x), camera.limit_left])
	assert_eq(camera.limit_top, int(bounds.position.y),
			(
			"Camera2D.limit_top must equal get_bounds_px().position.y (%d) — found %d."
			) % [int(bounds.position.y), camera.limit_top])
	assert_eq(camera.limit_right, int(bounds.end.x),
			(
			"Camera2D.limit_right must equal get_bounds_px().end.x (%d) — found %d."
			) % [int(bounds.end.x), camera.limit_right])
	assert_eq(camera.limit_bottom, int(bounds.end.y),
			(
			"Camera2D.limit_bottom must equal get_bounds_px().end.y (%d) — found %d."
			) % [int(bounds.end.y), camera.limit_bottom])


func test_camera_limits_are_derived_from_live_bounds_not_a_hardcoded_rect() -> void:
	# Test plan bullet: "Camera limits ... are rebuilt correctly from
	# get_bounds_px() regardless of the meadow's specific painted extent —
	# verified by asserting the computed limits ... are a function of
	# get_bounds_px()'s actual returned Rect2, not fixed constants."
	#
	# This project has already lived through one meadow re-paint mid-feature
	# (the meadow was hand-edited into a complete rectangle after slice 8's
	# tests were written against its old irregular shape — see
	# test_solids_collision.gd's GROUND_CELLS_CSV comment for that history).
	# A camera-limits implementation that hard-codes TODAY's meadow rect would
	# pass test_camera_limits_match_area_bounds_px() above just as well as a
	# correct one, since that test also reads today's live bounds — so this
	# test independently re-derives ground-truth bounds from a SEPARATE bare
	# WorldArea instance (not going through world.tscn/world.gd at all) and
	# checks the assembled scene's camera against that. It won't, on its own,
	# distinguish "reads get_bounds_px() every load" from "hard-coded to
	# match today's numbers" (that would require actually repainting the
	# meadow, which is out of scope here) — but it does prove the two numbers
	# in play are read from the same underlying source rather than merely
	# copy-pasted into world.gd by whoever implemented this.
	var bare_meadow_packed: PackedScene = load(MEADOW_SCENE_PATH)
	assert_not_null(bare_meadow_packed, "world/areas/meadow.tscn should load as a PackedScene")
	if bare_meadow_packed == null:
		return

	var bare_meadow: WorldArea = bare_meadow_packed.instantiate() as WorldArea
	assert_not_null(bare_meadow, "meadow.tscn's root must be a WorldArea")
	if bare_meadow == null:
		return
	add_child_autofree(bare_meadow)

	var ground_truth_bounds: Rect2 = bare_meadow.get_bounds_px()

	var world: Node = _instantiate_world()
	if world == null:
		return
	var camera: Camera2D = _get_player_camera(world)
	if camera == null:
		return

	assert_eq(camera.limit_left, int(ground_truth_bounds.position.x),
			(
			"camera.limit_left (%d) must match an independently-instantiated bare "
			+ "meadow's get_bounds_px().position.x (%d)."
			) % [camera.limit_left, int(ground_truth_bounds.position.x)])
	assert_eq(camera.limit_top, int(ground_truth_bounds.position.y),
			(
			"camera.limit_top (%d) must match an independently-instantiated bare "
			+ "meadow's get_bounds_px().position.y (%d)."
			) % [camera.limit_top, int(ground_truth_bounds.position.y)])
	assert_eq(camera.limit_right, int(ground_truth_bounds.end.x),
			(
			"camera.limit_right (%d) must match an independently-instantiated bare "
			+ "meadow's get_bounds_px().end.x (%d)."
			) % [camera.limit_right, int(ground_truth_bounds.end.x)])
	assert_eq(camera.limit_bottom, int(ground_truth_bounds.end.y),
			(
			"camera.limit_bottom (%d) must match an independently-instantiated bare "
			+ "meadow's get_bounds_px().end.y (%d)."
			) % [camera.limit_bottom, int(ground_truth_bounds.end.y)])


# ---------------------------------------------------------------------------
# Two-tile dead zone: drag enabled + margins (design doc §12.3)
# ---------------------------------------------------------------------------

func test_drag_enabled_on_both_axes() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return
	var camera: Camera2D = _get_player_camera(world)
	if camera == null:
		return

	assert_true(camera.drag_horizontal_enabled,
			"Camera2D.drag_horizontal_enabled must be true for the two-tile dead zone (design.md §12.3)")
	assert_true(camera.drag_vertical_enabled,
			"Camera2D.drag_vertical_enabled must be true for the two-tile dead zone (design.md §12.3)")


func test_drag_margins_match_two_tile_dead_zone() -> void:
	# NOTE on property names: design.md §12.3 and the slice-9 test plan
	# describe the dead zone as one derived value per AXIS
	# ("drag_horizontal_margin" / "drag_vertical_margin"). Godot 4's actual
	# Camera2D API has no such properties — it exposes four independent
	# margins, one per SIDE: drag_left_margin, drag_right_margin,
	# drag_top_margin, drag_bottom_margin.
	# https://docs.godotengine.org/en/stable/classes/class_camera2d.html#class-camera2d-property-drag-left-margin
	# A symmetric dead zone (drifting the same two tiles in either direction
	# along an axis) means both margins on that axis share the derived value:
	# drag_left_margin == drag_right_margin == the horizontal value, and
	# drag_top_margin == drag_bottom_margin == the vertical value. That is
	# what this test checks — all four real properties, in symmetric pairs.
	var world: Node = _instantiate_world()
	if world == null:
		return
	var camera: Camera2D = _get_player_camera(world)
	if camera == null:
		return

	assert_almost_eq(camera.drag_left_margin, EXPECTED_DRAG_MARGIN_HORIZONTAL, MARGIN_TOLERANCE,
			(
			"Camera2D.drag_left_margin must be ~%.4f (2 tiles * 32px / 160px half-viewport "
			+ "width, design.md §12.3's table) — found %.4f."
			) % [EXPECTED_DRAG_MARGIN_HORIZONTAL, camera.drag_left_margin])
	assert_almost_eq(camera.drag_right_margin, EXPECTED_DRAG_MARGIN_HORIZONTAL, MARGIN_TOLERANCE,
			(
			"Camera2D.drag_right_margin must be ~%.4f (same derivation as drag_left_margin "
			+ "— a symmetric dead zone) — found %.4f."
			) % [EXPECTED_DRAG_MARGIN_HORIZONTAL, camera.drag_right_margin])
	assert_almost_eq(camera.drag_top_margin, EXPECTED_DRAG_MARGIN_VERTICAL, MARGIN_TOLERANCE,
			(
			"Camera2D.drag_top_margin must be ~%.4f (2 tiles * 16px / 90px half-viewport "
			+ "height, design.md §12.3's table) — found %.4f."
			) % [EXPECTED_DRAG_MARGIN_VERTICAL, camera.drag_top_margin])
	assert_almost_eq(camera.drag_bottom_margin, EXPECTED_DRAG_MARGIN_VERTICAL, MARGIN_TOLERANCE,
			(
			"Camera2D.drag_bottom_margin must be ~%.4f (same derivation as drag_top_margin "
			+ "— a symmetric dead zone) — found %.4f."
			) % [EXPECTED_DRAG_MARGIN_VERTICAL, camera.drag_bottom_margin])


# ---------------------------------------------------------------------------
# Smoothing (design doc §12.3, "cozy glide" — resolved in favor of ON)
# ---------------------------------------------------------------------------

func test_camera_smoothing_enabled_on_loaded_player_camera() -> void:
	# Complements tests/integration/player/test_player_scene.gd's
	# test_camera2d_position_smoothing_enabled(), which checks player.tscn in
	# isolation. This checks the same property on the fully assembled,
	# world-loaded scene, in case some future world.gd/WorldArea code path
	# ever touched position_smoothing_enabled at runtime (it shouldn't need
	# to — it's meant to be a static player.tscn property per design.md
	# §12.3 — but this closes that gap the same way the limit_* tests above
	# close it for the runtime-only limit_* properties).
	var world: Node = _instantiate_world()
	if world == null:
		return
	var camera: Camera2D = _get_player_camera(world)
	if camera == null:
		return

	assert_true(camera.position_smoothing_enabled,
			(
			"Camera2D.position_smoothing_enabled must be true on the loaded player camera "
			+ "— design.md §12.3's 'cozy glide' requirement, resolved in the slice-9 test "
			+ "plan to supersede the old pixel-art-purist shimmer guard."
			))
	# limit_smoothed is a SEPARATE flag from position_smoothing_enabled and
	# defaults to false: with smoothing on but limit_smoothed off, the camera
	# glides normally but SNAPS the instant it hits a limit_* edge — exactly
	# where the cozy glide matters most, since that's the map boundary the
	# player walks up to. Both must be true together.
	# https://docs.godotengine.org/en/stable/classes/class_camera2d.html#class-camera2d-property-limit-smoothed
	assert_true(camera.limit_smoothed,
			(
			"Camera2D.limit_smoothed must also be true on the loaded player camera "
			+ "— otherwise the camera snaps (rather than glides) the moment it reaches "
			+ "an area's limit_* edge, undercutting the same 'cozy glide' requirement."
			))
