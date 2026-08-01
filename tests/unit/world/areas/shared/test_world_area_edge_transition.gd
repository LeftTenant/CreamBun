## test_world_area_edge_transition.gd
## Unit tests for Slice 10 of the world-collision feature ("Edge transition
## (fade) and a second area") — the four PURE-FUNCTION pieces of the
## opposite-edge spawn mechanism, tested independently of any scene tree
## (design doc §12.4–§12.5, condensed in slice-10-edge-transition-test-plan.md's
## "Unit" section).
##
## IMPLEMENTED — this suite now runs against a real implementation.
## =========================================================================
## world_area.gd declares the `Edge` enum and all four static pure functions
## below exactly as originally proposed here (see the JUDGMENT CALL note
## retained below for the reasoning on why WorldArea, not World, owns them).
## `_edge_rect()` and `_linked_edge_rects()` — the private helpers that build
## on CORNER_DEAD_ZONE_PX to split a linked edge into a stub/trigger/stub —
## are covered instead by the integration suite (test_edge_triggers.gd),
## since they need a live scene tree to assert collider geometry against.
##
## An `is_in_corner_dead_zone()` pure function shipped alongside these four
## early in this slice, but round 2 of code review found it had no production
## caller left once the corner exclusion moved into the stub/trigger/stub
## split above (geometry, not a handler-side coordinate check) — it and its
## six unit tests were removed as dead code. See _linked_edge_rects()'s doc
## comment in world_area.gd for where the corner-exclusion logic actually
## lives now.
##
## JUDGMENT CALL (kept for context): the test plan's own closing bullet
## (slice-10-edge-transition-test-plan.md, last "Unit" line) anticipated that
## these four behaviors might ship as isolable pure functions OR inlined into
## world.gd/world_area.gd. They shipped as STATIC functions on WorldArea
## (world/areas/shared/world_area.gd), alongside a nested `Edge` enum, with
## these exact signatures:
##
##   enum Edge { NORTH, EAST, SOUTH, WEST }
##   static func opposite_edge(edge: Edge) -> Edge
##   static func area_id_from_scene_path(scene_path: String) -> StringName
##   static func is_debounce_armed(edge: Edge, distance_from_edge_px: float) -> bool
##   static func compute_entry_position(exit_coordinate: float, exit_edge: Edge, new_bounds: Rect2) -> Vector2
##
## Why WorldArea and not World (world.gd): every one of these functions
## operates purely on Edge/geometry concepts WorldArea already owns
## (TILE_SIZE, get_bounds_px(), the forthcoming Edge enum/edge_reached signal
## per the integration test plan) — none of them need world.gd's live
## ActiveArea/Player/Transition node references. world.gd also has no
## `class_name` today, which would make it awkward to call static functions
## on it from a test without instantiating the whole scene. If the coder
## instead inlines this logic directly into world.gd's transition handler
## (plausible, since that's the one place all four get *used* together),
## this file's assertions become inapplicable and its coverage should move to
## the integration suite (test_area_transition.gd in this same slice) per the
## test plan's own escape clause — this is a real, live judgment call, not a
## settled contract.
##
## `is_debounce_armed()`/`compute_entry_position()` deliberately test values
## comfortably clear of the exact 32px/16px/8px boundary itself (e.g.
## 32px - 22px = 10px inside, 32px + 16px = 48px outside), rather than the
## boundary value exactly — whether the boundary itself counts as "in" or
## "out" is an inclusive/exclusive judgment call the design doc does not
## settle, so asserting a specific answer there would be testing an
## implementation detail, not design doc §12.4's stated behavior.
##
## Design reference: docs/features/world-collision/design.md §12.4 (corner
## dead zones, arrival debounce), §12.5 (opposite-edge table, spawn maths).
## Test plan: docs/features/world-collision/slice-10-edge-transition-test-plan.md
##
## Requires GUT: https://github.com/bitwes/Gut
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gselect=test_world_area_edge_transition.gd -gexit

class_name TestWorldAreaEdgeTransition
extends GutTest


# ---------------------------------------------------------------------------
# Constants — mirrored from design.md §12.4/§12.5 rather than read off
# WorldArea's own (not-yet-written) constants, so a wrong constant value in
# the implementation can't also make its own test pass (same convention as
# test_camera_dead_zone_and_limits.gd's EXPECTED_DRAG_MARGIN_* locals).
# ---------------------------------------------------------------------------

const CORNER_DEAD_ZONE_PX: float = 32.0
const DEBOUNCE_EAST_WEST_PX: float = 16.0   # 0.5 tile * 32px tile width
const DEBOUNCE_NORTH_SOUTH_PX: float = 8.0  # 0.5 tile * 16px tile height
const ENTRY_OFFSET_EAST_WEST_PX: float = 32.0   # one tile inward, E/W entry
const ENTRY_OFFSET_NORTH_SOUTH_PX: float = 16.0  # one tile inward, N/S entry
## Design.md §12.5's correction: "one tile inward" on a NORTH entry is
## measured from the north edge's PLAYABLE-FACING boundary
## (bounds.position.y + this inset), not the raw painted edge — because the
## north edge's playable boundary itself sits this far in from the true
## edge (§12.4's headroom fix for the feet-anchored player under
## Camera2D.limit_top).
##
## No longer mirrors a WorldArea constant — there isn't one any more. The inset
## is now derived per build from the player's real geometry
## (WorldArea.north_headroom_inset()), and compute_entry_position() takes it as
## an argument. This file therefore passes an inset IN rather than matching one:
## 16.0 is what the project's current player works out to, and the tests below
## check that compute_entry_position() honours whatever it is handed. The
## derivation itself is checked separately, against the live player scene, by
## tests/integration/world/test_collision_geometry_invariants.gd.
const HEADROOM_INSET_PX: float = 16.0

## How far above the player's origin their collider's top edge sits, in px —
## CollisionShape2D.position.y (-9) minus the capsule's 5px radius, from
## player/player.tscn (design.md §10). Mirrored here, same convention as
## above, purely so the north-entry clearance test below can be written as
## real arithmetic instead of a magic number.
const PLAYER_COLLIDER_TOP_OFFSET_PX: float = 14.0


# ---------------------------------------------------------------------------
# opposite_edge() — design.md §12.5's table
# ---------------------------------------------------------------------------

func test_opposite_edge_east_is_west() -> void:
	assert_eq(WorldArea.opposite_edge(WorldArea.Edge.EAST), WorldArea.Edge.WEST,
			"design.md §12.5's table: exiting EAST enters the neighbour's WEST edge")


func test_opposite_edge_west_is_east() -> void:
	assert_eq(WorldArea.opposite_edge(WorldArea.Edge.WEST), WorldArea.Edge.EAST,
			"design.md §12.5's table: exiting WEST enters the neighbour's EAST edge")


func test_opposite_edge_north_is_south() -> void:
	assert_eq(WorldArea.opposite_edge(WorldArea.Edge.NORTH), WorldArea.Edge.SOUTH,
			"design.md §12.5's table: exiting NORTH enters the neighbour's SOUTH edge")


func test_opposite_edge_south_is_north() -> void:
	assert_eq(WorldArea.opposite_edge(WorldArea.Edge.SOUTH), WorldArea.Edge.NORTH,
			"design.md §12.5's table: exiting SOUTH enters the neighbour's NORTH edge")


# ---------------------------------------------------------------------------
# area_id_from_scene_path() — design.md §12.5 step 5
# ---------------------------------------------------------------------------

func test_area_id_from_scene_path_strips_tscn_extension() -> void:
	var area_id: StringName = WorldArea.area_id_from_scene_path("res://world/areas/meadow.tscn")
	assert_eq(area_id, StringName("meadow"),
			"area_id should be the scene file's name with no path and no .tscn extension (design.md §12.5)")


func test_area_id_from_scene_path_works_for_any_area_file_name() -> void:
	# A second, differently-named path, so this test can't pass by having
	# accidentally hard-coded "meadow" as a special case rather than
	# genuinely stripping the path/extension.
	var area_id: StringName = WorldArea.area_id_from_scene_path("res://world/areas/orchard.tscn")
	assert_eq(area_id, StringName("orchard"),
			"area_id derivation must work for any area scene path, not just meadow.tscn's")


# ---------------------------------------------------------------------------
# is_debounce_armed() — design.md §12.4's 0.5-tile distance check
# ---------------------------------------------------------------------------

func test_debounce_inert_just_under_east_west_threshold() -> void:
	# 16px is the E/W threshold (0.5 * 32px tile width); 10px is comfortably
	# under it.
	assert_false(WorldArea.is_debounce_armed(WorldArea.Edge.EAST, 10.0),
			"an east/west edge's debounce must still be INERT at 10px away — under the 16px threshold")


func test_debounce_armed_clearly_over_east_west_threshold() -> void:
	assert_true(WorldArea.is_debounce_armed(WorldArea.Edge.EAST, 24.0),
			"an east/west edge's debounce must be ARMED at 24px away — clearly over the 16px threshold")


func test_debounce_inert_just_under_north_south_threshold() -> void:
	# 8px is the N/S threshold (0.5 * 16px tile height); 4px is comfortably
	# under it.
	assert_false(WorldArea.is_debounce_armed(WorldArea.Edge.SOUTH, 4.0),
			"a north/south edge's debounce must still be INERT at 4px away — under the 8px threshold")


func test_debounce_armed_clearly_over_north_south_threshold() -> void:
	assert_true(WorldArea.is_debounce_armed(WorldArea.Edge.SOUTH, 14.0),
			"a north/south edge's debounce must be ARMED at 14px away — clearly over the 8px threshold")


func test_debounce_stays_inert_indefinitely_not_just_briefly() -> void:
	# design.md §12.4: "a plain distance check, not a timer ... stays inert
	# indefinitely if they never [walk far enough]." A huge simulated "time
	# elapsed" has no meaning to this pure function at all — only distance
	# does — so passing the same too-small distance again must give the same
	# inert answer, proving there's no hidden timer/counter state involved.
	assert_false(WorldArea.is_debounce_armed(WorldArea.Edge.EAST, 10.0),
			"first call at 10px (under threshold) must be inert")
	assert_false(WorldArea.is_debounce_armed(WorldArea.Edge.EAST, 10.0),
			"a second call at the SAME 10px distance must still be inert — a timer-based implementation might " +
			"instead have armed by now if enough wall-clock/frame time passed between calls, which this pure " +
			"function has no way to observe and must not depend on")


# ---------------------------------------------------------------------------
# compute_entry_position() — design.md §12.5's opposite-edge spawn maths
# ---------------------------------------------------------------------------

func test_entry_position_east_west_preserves_coordinate_when_already_in_range() -> void:
	# Exiting a EAST edge at Y=200 (comfortably inside a destination area's
	# valid, non-corner range on that axis) must carry Y over VERBATIM and
	# land on the opposite (WEST) edge, offset one tile (32px) inward from
	# the new area's own west edge.
	var new_bounds := Rect2(Vector2(0.0, 0.0), Vector2(448.0, 256.0))  # e.g. orchard.tscn's bounds
	var entry: Vector2 = WorldArea.compute_entry_position(200.0, WorldArea.Edge.EAST, new_bounds, HEADROOM_INSET_PX)

	assert_eq(entry.y, 200.0,
			"the exit Y coordinate must be carried over verbatim when it already fits the new area's range")
	assert_eq(entry.x, new_bounds.position.x + ENTRY_OFFSET_EAST_WEST_PX,
			"entering from the WEST edge must sit exactly one tile (32px) inward from the new area's west edge")


func test_entry_position_north_south_preserves_coordinate_when_already_in_range() -> void:
	# Exiting a SOUTH edge at X=200 must carry X over verbatim and land on
	# the opposite (NORTH) edge, offset one tile (16px) inward.
	var new_bounds := Rect2(Vector2(0.0, 0.0), Vector2(448.0, 256.0))
	var entry: Vector2 = WorldArea.compute_entry_position(200.0, WorldArea.Edge.SOUTH, new_bounds, HEADROOM_INSET_PX)

	assert_eq(entry.x, 200.0,
			"the exit X coordinate must be carried over verbatim when it already fits the new area's range")
	assert_eq(entry.y, new_bounds.position.y + HEADROOM_INSET_PX + ENTRY_OFFSET_NORTH_SOUTH_PX,
			("entering from the NORTH edge must sit exactly one tile (16px) inward from the north edge's " +
			"PLAYABLE-FACING boundary, which itself sits %.0fpx south of the true painted edge (design.md " +
			"§12.5's fix for the naive 16px-only reading that landed the player inside the north trigger " +
			"zone) — bounds.position.y + %.0fpx") % [HEADROOM_INSET_PX, HEADROOM_INSET_PX + ENTRY_OFFSET_NORTH_SOUTH_PX])


func test_north_entry_lands_clear_of_the_north_triggers_own_zone() -> void:
	# The tightest margin in the whole transition system, written down as an
	# assertion so it can't quietly close up (design.md §12.5's margin note).
	#
	# A north entry must not merely land at the right coordinate — the
	# player's COLLIDER must end up entirely south of the north trigger's
	# inner face, or the trigger they just arrived through re-fires and bounces
	# them straight back. The two are different points now that the collider
	# sits above the origin rather than straddling it (design.md §10):
	#
	#   trigger's inner face   = bounds.position.y + HEADROOM_INSET_PX
	#   player's collider top  = entry.y - PLAYER_COLLIDER_TOP_OFFSET_PX
	#
	# With today's numbers that clears by 2px (16 + 16 - 14 vs 16). Raising the
	# collider further, or shrinking the inset, eats those 2px directly — and
	# this test is what says so before a playtest does.
	var new_bounds := Rect2(Vector2(0.0, 0.0), Vector2(448.0, 256.0))
	var entry: Vector2 = WorldArea.compute_entry_position(200.0, WorldArea.Edge.SOUTH, new_bounds, HEADROOM_INSET_PX)

	var trigger_inner_face: float = new_bounds.position.y + HEADROOM_INSET_PX
	var collider_top: float = entry.y - PLAYER_COLLIDER_TOP_OFFSET_PX

	assert_gt(collider_top, trigger_inner_face,
			("a north-entering player's collider top (y=%.1f) must sit strictly SOUTH of the north " +
			"trigger's inner face (y=%.1f) — landing on or inside it means the just-crossed edge " +
			"re-fires and bounces the player back the way they came (design.md §12.5). If this " +
			"fails, either the headroom inset shrank or the player's collider moved further up " +
			"its own origin; re-derive both, don't nudge one.")
					% [collider_top, trigger_inner_face])


func test_entry_position_west_exit_enters_on_the_east_edge() -> void:
	# The mirror image of the EAST-exit test above, pinning the opposite sign
	# of the same E/W branch: exiting a WEST edge at Y=150 must carry Y over
	# verbatim and land on the opposite (EAST) edge, offset one tile (32px)
	# inward from the new area's own east edge (south has no headroom inset,
	# and neither does east, so this is a plain boundary-minus-offset case).
	var new_bounds := Rect2(Vector2(0.0, 0.0), Vector2(448.0, 256.0))
	var entry: Vector2 = WorldArea.compute_entry_position(150.0, WorldArea.Edge.WEST, new_bounds, HEADROOM_INSET_PX)

	assert_eq(entry.y, 150.0,
			"the exit Y coordinate must be carried over verbatim when it already fits the new area's range")
	assert_eq(entry.x, new_bounds.end.x - ENTRY_OFFSET_EAST_WEST_PX,
			"entering from the EAST edge must sit exactly one tile (32px) inward from the new area's east edge")


func test_entry_position_north_exit_enters_on_the_south_edge() -> void:
	# The mirror image of the SOUTH-exit test above: exiting a NORTH edge at
	# X=200 must carry X over verbatim and land on the opposite (SOUTH) edge,
	# offset one tile (16px) inward. South has no headroom inset, so this is
	# a plain boundary-minus-offset case, unlike the NORTH-entry test above.
	var new_bounds := Rect2(Vector2(0.0, 0.0), Vector2(448.0, 256.0))
	var entry: Vector2 = WorldArea.compute_entry_position(200.0, WorldArea.Edge.NORTH, new_bounds, HEADROOM_INSET_PX)

	assert_eq(entry.x, 200.0,
			"the exit X coordinate must be carried over verbatim when it already fits the new area's range")
	assert_eq(entry.y, new_bounds.end.y - ENTRY_OFFSET_NORTH_SOUTH_PX,
			"entering from the SOUTH edge must sit exactly one tile (16px) inward from the new area's south edge")


func test_entry_position_clamps_when_new_area_is_smaller_on_the_crossed_axis() -> void:
	# design.md §12.5: "If the new area is smaller than the one departed and
	# the carried-over coordinate would fall outside it, clamp it into the
	# new area's valid range on that axis — but keep it outside the corner
	# dead zones." A synthetic small new_bounds (150px tall) makes an exit Y
	# of 300px clearly out of range on purpose.
	var new_bounds := Rect2(Vector2(0.0, 0.0), Vector2(200.0, 150.0))
	var entry: Vector2 = WorldArea.compute_entry_position(300.0, WorldArea.Edge.EAST, new_bounds, HEADROOM_INSET_PX)

	assert_eq(entry.x, new_bounds.position.x + ENTRY_OFFSET_EAST_WEST_PX,
			"the fixed (crossed-axis) coordinate must still be exactly one tile inward regardless of clamping " +
			"on the OTHER axis")
	assert_true(entry.y <= new_bounds.end.y,
			"the clamped Y must not exceed the new area's own bottom edge")
	assert_true(
			entry.y >= new_bounds.position.y + CORNER_DEAD_ZONE_PX
			and entry.y <= new_bounds.end.y - CORNER_DEAD_ZONE_PX,
			(
			"the clamped Y (%.1f) must land outside BOTH corner dead zones of the new area's west edge — "
			+ "i.e. within [%.1f, %.1f], not exactly on a boundary or inside an excluded corner (design.md §12.4/§12.5)"
			) % [entry.y, new_bounds.position.y + CORNER_DEAD_ZONE_PX, new_bounds.end.y - CORNER_DEAD_ZONE_PX])
