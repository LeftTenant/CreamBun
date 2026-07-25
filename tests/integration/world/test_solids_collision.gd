## test_solids_collision.gd
## Integration tests for the Slice 4 TileSet physics layer + Ground/Solids
## Y-sort restructure in world/world.tscn.
##
## This file mirrors the source location: world/ -> tests/integration/world/.
## It is a sibling of test_tile_geometry.gd (Slice 2 tile-geometry rescale)
## and test_world_scene.gd (Issue #36 spawn-position regression) — kept as a
## separate file because it targets a different slice with a different set
## of assertions (Ground/Solids layer structure + physics-layer collision
## response), not because either existing file is wrong on its own.
##
## Design reference: docs/features/world-collision/design.md §6, §6.1, §11.
## Test plan: docs/features/world-collision/slice-4-tileset-physics-test-plan.md
##
## Requires GUT: https://github.com/bitwes/Gut
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gselect=test_solids_collision.gd -gexit

class_name TestSolidsCollision
extends GutTest


const WORLD_SCENE_PATH: String = "res://world/world.tscn"

# "world" physics layer bit value, per project.godot's [layer_names] section
# (2d_physics/layer_1 = "world"). Mirrors the constant of the same name in
# tests/integration/player/test_player_scene.gd.
const WORLD_LAYER_BIT: int = 1

# Snapshot of every cell painted on world.tscn's single pre-Slice-4
# TileMapLayer, captured via a throwaway probe test immediately before this
# slice's Ground/Solids split (i.e. the Slice 3 state: 268 cells on one
# layer, no Solids layer yet). Design doc §6.1 says the split moves the
# existing terrain onto `Ground` unchanged and adds `Solids` as a new,
# separate layer for collidable tiles — it does not redistribute any of this
# data onto Solids. So after the split, Ground's used cells must be exactly
# this set: same count, same coordinates. Stored as a "x,y" CSV instead of a
# literal Array[Vector2i] (which would be 268 repeated `Vector2i(...)` calls)
# to keep this fixture data reading as data, not code — see
# _parse_expected_ground_cells() below for how it's decoded.
const GROUND_CELLS_CSV: String = (
		"-3,8;-2,7;-2,8;-1,4;-1,6;-1,7;-1,8;0,4;0,6;0,7;0,8;0,12;0,13;1,4;1,5;1,6;1,7;1,8;1,9;1,10;1,12;" +
		"1,13;1,14;2,4;2,5;2,6;2,7;2,8;2,9;2,10;2,11;2,12;2,13;2,14;2,18;3,4;3,5;3,6;3,7;3,8;3,9;3,10;" +
		"3,11;3,12;3,13;3,14;3,16;3,17;3,18;4,4;4,5;4,6;4,7;4,8;4,9;4,10;4,11;4,12;4,13;4,14;4,15;4,16;" +
		"4,17;4,18;4,19;4,20;4,21;5,4;5,5;5,6;5,7;5,8;5,9;5,10;5,11;5,12;5,13;5,14;5,15;5,16;5,17;5,18;" +
		"5,19;6,4;6,5;6,6;6,7;6,8;6,9;6,10;6,11;6,12;6,13;6,14;6,15;6,16;6,17;6,18;6,19;6,20;7,4;7,5;7,6;" +
		"7,7;7,8;7,9;7,10;7,11;7,12;7,13;7,14;7,15;7,16;7,17;7,18;7,19;7,20;8,4;8,5;8,6;8,7;8,8;8,9;8,10;" +
		"8,11;8,12;8,13;8,14;8,15;8,16;8,17;8,18;8,19;9,4;9,5;9,6;9,7;9,8;9,9;9,10;9,11;9,12;9,13;9,14;" +
		"9,15;9,16;9,17;9,18;9,19;10,4;10,5;10,6;10,7;10,8;10,9;10,10;10,11;10,12;10,13;10,14;10,15;" +
		"10,16;10,17;10,18;10,19;11,3;11,4;11,5;11,6;11,7;11,8;11,9;11,10;11,11;11,12;11,13;11,14;11,15;" +
		"11,16;11,17;11,18;11,19;12,3;12,4;12,5;12,6;12,7;12,8;12,9;12,10;12,11;12,12;12,13;12,14;12,15;" +
		"12,16;12,17;12,18;13,3;13,4;13,5;13,6;13,7;13,8;13,9;13,10;13,11;13,12;13,13;13,14;13,15;13,16;" +
		"13,17;13,18;14,5;14,6;14,7;14,8;14,9;14,10;14,11;14,12;14,13;14,14;14,15;14,16;14,17;14,18;15,5;" +
		"15,6;15,7;15,8;15,9;15,10;15,11;15,12;15,13;15,14;15,15;15,16;15,17;16,5;16,7;16,8;16,9;16,10;" +
		"16,11;16,12;16,13;16,14;16,16;17,7;17,9;17,10;17,11;17,12;17,13;17,14;17,16;18,9;18,10;18,11;" +
		"18,12;18,13;18,14;18,16;19,13;19,14;"
)

# Movement-simulation tuning for the two collision-response tests. The
# player starts this many pixels "before" (screen-left of) the target cell
# and holds move_right for SIMULATION_TICKS physics ticks. 48px is 1.5 tile
# widths (design doc §4's 32px tile width) — close enough that nothing else
# painted on the map is likely to sit between start and target, but far
# enough to give a clean "blocked early / travelled the full distance"
# contrast. At speed 200px/s and 60 physics ticks (~1 real second at the
# default 60Hz physics rate), the unobstructed distance is ~200px, several
# times the 48px gap, so a genuinely-blocked run stops far short of it while
# an unblocked run comfortably covers it.
const APPROACH_OFFSET_PX: float = 48.0
const SIMULATION_TICKS: int = 60


func before_each() -> void:
	# Player movement is gated on GameState.current_state == PLAYING
	# (player.gd). GameState already defaults to PLAYING, but set it
	# explicitly so this suite doesn't depend on that default or on
	# whatever an earlier-running test file left GameState in.
	GameState.change_state(GameState.State.PLAYING)


func after_each() -> void:
	# Defensive belt-and-braces: if a test errors out before its own
	# Input.action_release("move_right") call, don't leak a held key into
	# whatever test runs next.
	Input.action_release("move_right")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Instantiate world.tscn under the test tree (add_child_autofree frees it
## automatically at test teardown) and return the root node, or null (with a
## failed assertion already recorded) if the scene cannot be loaded or
## instantiated.
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


## Decode GROUND_CELLS_CSV into an Array[Vector2i].
func _parse_expected_ground_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for pair in GROUND_CELLS_CSV.split(";", false):
		var parts: PackedStringArray = pair.split(",")
		cells.append(Vector2i(int(parts[0]), int(parts[1])))
	return cells


## Build a Dictionary keyed by Vector2i for O(1) "is this cell used" checks —
## Array.has() on a few hundred entries is fine too, but a set reads clearer
## at the call sites below (`_used.has(cell)` vs `_used.find(cell) != -1`).
func _as_cell_set(cells: Array[Vector2i]) -> Dictionary:
	var set: Dictionary = {}
	for cell in cells:
		set[cell] = true
	return set


## Find the first used cell on `layer` whose TileData has at least one
## collision polygon defined on physics layer 0. Returns null if none do
## (with no assertion recorded — callers assert on the result themselves,
## since "no such tile exists" is itself the interesting failure here).
##
## This is a pure structural check — "does at least one such tile exist at
## all" — used only by test_at_least_one_solids_tile_has_a_collision_polygon,
## which never drives the player toward the result. Movement tests must use
## _find_collision_cell_with_clear_approach() instead (see its docstring for
## why picking a candidate by get_used_cells() order alone isn't safe once
## movement is involved).
func _find_cell_with_collision_polygon(layer: TileMapLayer) -> Variant:
	for cell in layer.get_used_cells():
		var tile_data: TileData = layer.get_cell_tile_data(cell)
		if tile_data == null:
			continue
		if tile_data.get_collision_polygons_count(0) > 0:
			return cell
	return null


## True if a player travelling in a straight horizontal line from
## `travel_px` pixels west of `target_global` up to `target_global` itself
## would not be intercepted by any OTHER collidable cell on `layer` (besides
## `exclude_cell`, if given, which lets a candidate's own collision polygon
## be excluded from checking against itself).
##
## `travel_px` must match however far the caller is actually going to drive
## the player past this check — it defaults to APPROACH_OFFSET_PX (the
## blocked-case corridor, from the start position up to the target itself),
## but _find_ground_only_cell() below passes the full unobstructed travel
## distance instead, since that test drives the player well past the target
## cell, not just up to it.
##
## Collision polygons in this project are always the full-tile rectangle
## (-16,-8, 16,-8, 16,8, -16,8) in tile-local coordinates (see the
## TileSetAtlasSource sub_resource in world.tscn). The player itself is
## approximated here as a point, ignoring its actual 20x10 RectangleShape2D
## half-extents (see player/player.tscn) — that simplification is only safe
## because the current map has just two widely-spaced Solids cells; it is
## not a general guarantee and would need tightening (inflating the corridor
## by the player's half-extents) if Solids tiles are ever painted close
## together.
##
## Guards against two mirror-image failures a naive "take get_used_cells()'s
## first match" selection is exposed to: a "blocked" candidate whose approach
## window already overlaps a NEIGHBOURING collidable tile (the player would
## spawn already touching the wrong tile and get blocked by it instead of
## the intended target — the test would still pass, but for the wrong
## reason), and an "unblocked" candidate whose approach window overlaps a
## Solids tile it was never meant to be near (the player would get stopped
## early by that unrelated tile instead of crossing freely, for the same
## underlying reason in reverse).
func _is_approach_corridor_clear(layer: TileMapLayer, target_global: Vector2, exclude_cell: Variant = null, travel_px: float = APPROACH_OFFSET_PX) -> bool:
	const HALF_WIDTH: float = 16.0
	const HALF_HEIGHT: float = 8.0

	var corridor_min_x: float = target_global.x - APPROACH_OFFSET_PX
	var corridor_max_x: float = target_global.x - APPROACH_OFFSET_PX + travel_px

	for cell in layer.get_used_cells():
		if exclude_cell != null and cell == exclude_cell:
			continue

		var tile_data: TileData = layer.get_cell_tile_data(cell)
		if tile_data == null or tile_data.get_collision_polygons_count(0) == 0:
			continue

		var cell_global: Vector2 = _cell_to_global(layer, cell)
		var same_row: bool = absf(cell_global.y - target_global.y) <= HALF_HEIGHT
		var overlaps_corridor: bool = (
				corridor_min_x <= cell_global.x + HALF_WIDTH
				and corridor_max_x >= cell_global.x - HALF_WIDTH)
		if same_row and overlaps_corridor:
			return false

	return true


## Like _find_cell_with_collision_polygon(), but additionally rejects any
## candidate whose approach corridor (_is_approach_corridor_clear()) is
## contaminated by a different collidable cell on the same layer. Used by
## the "player stops at a Solids tile" movement test, where WHICH tile the
## player is driven toward matters — not just that some tile with a
## collision polygon exists somewhere. Returns null (with no assertion
## recorded, same convention as _find_cell_with_collision_polygon()) if no
## candidate has both a collision polygon and a clear approach corridor.
func _find_collision_cell_with_clear_approach(layer: TileMapLayer) -> Variant:
	for cell in layer.get_used_cells():
		var tile_data: TileData = layer.get_cell_tile_data(cell)
		if tile_data == null or tile_data.get_collision_polygons_count(0) == 0:
			continue

		var target_global: Vector2 = _cell_to_global(layer, cell)
		if _is_approach_corridor_clear(layer, target_global, cell):
			return cell
		# else: a different collidable cell sits in this candidate's own
		# approach corridor — skip it and keep looking, so the movement
		# test can unambiguously attribute the resulting block to the tile
		# it was actually driven toward.

	return null


## Find a cell painted on `ground` but not on `solids` — a tile with no
## collision, for the "walks straight across" contrast test. Also rejects
## any candidate whose approach corridor (_is_approach_corridor_clear()) is
## contaminated by a Solids tile, so the "crosses uninterrupted" test isn't
## driven at a Ground-only tile that happens to sit right next to an
## unrelated collidable tile.
##
## Unlike the blocked-case caller (_find_collision_cell_with_clear_approach()),
## this test drives the player the FULL unobstructed distance past the
## target (speed * SIMULATION_TICKS physics ticks), not just up to it — so
## the corridor check here must cover that same full distance, or a Solids
## tile sitting past the target but still within the drive could block the
## player without the check ever noticing. `player` is only used to read its
## "speed" property (matching _drive_player_right_toward()'s own math) — it
## is never moved by this function.
func _find_ground_only_cell(ground: TileMapLayer, solids: TileMapLayer, player: CharacterBody2D) -> Variant:
	# Matches the "unobstructed_px" math in _drive_player_right_toward() —
	# the actual distance the player will be driven for this test.
	var speed: float = player.get("speed")
	var travel_px: float = speed * SIMULATION_TICKS / float(Engine.physics_ticks_per_second)

	var solid_cells: Dictionary = _as_cell_set(solids.get_used_cells())
	for cell in ground.get_used_cells():
		if solid_cells.has(cell):
			continue

		var target_global: Vector2 = _cell_to_global(ground, cell)
		if _is_approach_corridor_clear(solids, target_global, null, travel_px):
			return cell
		# else: a Solids tile with collision sits in this candidate's
		# approach corridor — skip it and keep looking, so a genuine
		# "blocked early" bug can't be confused with an unrelated tile
		# getting in the way.

	return null


## A TileMapLayer cell's centre, in global (world) coordinates. Goes through
## the layer's own to_global()/map_to_local() rather than assuming the layer
## sits at a zero offset from World, so this stays correct even if Ground/
## Solids ever gain a non-zero position.
func _cell_to_global(layer: TileMapLayer, cell: Vector2i) -> Vector2:
	return layer.to_global(layer.map_to_local(cell))


## Position `player` APPROACH_OFFSET_PX to the left of `target_global`, hold
## move_right for SIMULATION_TICKS physics ticks, then release.
##
## Returns a Dictionary with the observed horizontal travel distance and the
## theoretical distance the player would cover over the same ticks with
## nothing in the way — comparing the two is how the caller tells "blocked"
## from "unobstructed" without needing to know the exact collision polygon
## shape. Uses Input.action_press/release (the real Input singleton) so the
## test exercises player.gd's actual Input.get_vector() -> velocity ->
## move_and_slide() pipeline, not a hand-rolled substitute.
func _drive_player_right_toward(player: CharacterBody2D, target_global: Vector2) -> Dictionary:
	var start_global: Vector2 = target_global - Vector2(APPROACH_OFFSET_PX, 0.0)
	player.global_position = start_global
	player.velocity = Vector2.ZERO

	# CharacterBody2D.move_and_slide() (Godot 4) always advances by the
	# engine's real physics-tick delta, regardless of the `delta` argument
	# passed into _physics_process() — so this is what the "unobstructed
	# distance" math below must use too, not SIMULATION_TICKS on its own.
	var physics_delta: float = 1.0 / Engine.physics_ticks_per_second

	Input.action_press("move_right")
	simulate(player, SIMULATION_TICKS, physics_delta)
	Input.action_release("move_right")
	player.velocity = Vector2.ZERO

	# player.speed is read dynamically (Object.get) rather than assumed,
	# since player.gd has no class_name to cast the CharacterBody2D-typed
	# `player` argument to.
	var speed: float = player.get("speed")

	return {
		"start_x": start_global.x,
		"target_x": target_global.x,
		"traveled_px": player.global_position.x - start_global.x,
		"unobstructed_px": speed * SIMULATION_TICKS * physics_delta,
	}


# ---------------------------------------------------------------------------
# Ground / Solids layer structure (design doc §6.1)
# ---------------------------------------------------------------------------

func test_root_node_still_y_sort_enabled() -> void:
	# The World root was already y_sort_enabled = true before this slice
	# (it's the area's Y-sort scope, design doc §6.1) — this slice must not
	# regress that while restructuring the tile layers underneath it.
	var world: Node2D = _instantiate_world() as Node2D
	if world == null:
		return

	assert_true(world.y_sort_enabled,
			(
			"world.tscn's root Node2D should keep y_sort_enabled == true "
			+ "after the Ground/Solids restructure"
			))


func test_ground_layer_exists_and_is_not_y_sorted() -> void:
	# Ground is the floor — it always draws underneath everything and has no
	# depth relationship to resolve, so it stays un-sorted (design doc §6.1).
	var world: Node = _instantiate_world()
	if world == null:
		return

	var ground: TileMapLayer = world.get_node_or_null("Ground") as TileMapLayer
	assert_not_null(ground, "world.tscn should contain a TileMapLayer named 'Ground'")
	if ground == null:
		return

	assert_false(ground.y_sort_enabled,
			(
			"Ground should have y_sort_enabled == false — it is the floor "
			+ "and never sorts against anything (design doc §6.1)"
			))


func test_solids_layer_exists_and_is_y_sorted() -> void:
	# Solids are objects (cliff faces, walls) the player can stand in front
	# of or behind, so their tiles must sort against the player and props
	# (design doc §6.1).
	var world: Node = _instantiate_world()
	if world == null:
		return

	var solids: TileMapLayer = world.get_node_or_null("Solids") as TileMapLayer
	assert_not_null(solids, "world.tscn should contain a TileMapLayer named 'Solids'")
	if solids == null:
		return

	assert_true(solids.y_sort_enabled,
			(
			"Solids should have y_sort_enabled == true — its tiles are "
			+ "objects that sort against the player (design doc §6.1)"
			))


func test_ground_preserves_all_originally_painted_tiles() -> void:
	# The restructure moves the pre-Slice-4 single layer's data onto Ground
	# unchanged; it must not drop any of it. See GROUND_CELLS_CSV's comment
	# for how the expected set was captured.
	var world: Node = _instantiate_world()
	if world == null:
		return

	var ground: TileMapLayer = world.get_node_or_null("Ground") as TileMapLayer
	assert_not_null(ground, "world.tscn should contain a TileMapLayer named 'Ground'")
	if ground == null:
		return

	var expected_cells: Array[Vector2i] = _parse_expected_ground_cells()
	var actual_cells: Array[Vector2i] = ground.get_used_cells()

	assert_eq(actual_cells.size(), expected_cells.size(),
			(
			"Ground should have exactly %d used cells (the pre-Slice-4 tile "
			+ "count) — found %d. If this is lower, the restructure dropped "
			+ "tiles instead of just moving them."
			) % [expected_cells.size(), actual_cells.size()])

	var actual_set: Dictionary = _as_cell_set(actual_cells)
	var missing: Array[Vector2i] = []
	for cell in expected_cells:
		if not actual_set.has(cell):
			missing.append(cell)

	assert_eq(missing.size(), 0,
			(
			"Ground is missing %d cell(s) that were painted on the original "
			+ "pre-Slice-4 layer (e.g. %s) — the restructure should move "
			+ "tile data, not drop any of it (design doc §6.1)."
			) % [missing.size(), missing.slice(0, 5)])


# ---------------------------------------------------------------------------
# TileSet physics layer (design doc §6, §11)
# ---------------------------------------------------------------------------

func test_tileset_has_physics_layer_with_world_collision_layer_only() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return

	var solids: TileMapLayer = world.get_node_or_null("Solids") as TileMapLayer
	assert_not_null(solids, "world.tscn should contain a TileMapLayer named 'Solids'")
	if solids == null:
		return

	var tile_set: TileSet = solids.tile_set
	assert_not_null(tile_set, "Solids should have a TileSet assigned")
	if tile_set == null:
		return

	assert_gt(tile_set.get_physics_layers_count(), 0,
			"the shared TileSet should have at least one physics layer (design doc §6)")
	if tile_set.get_physics_layers_count() == 0:
		return

	# Design doc §6/§11: the physics layer collides on "world" (bit 1) and
	# nothing else — the same layer Solids/WorldProp/Player all agree on.
	assert_eq(tile_set.get_physics_layer_collision_layer(0), WORLD_LAYER_BIT,
			(
			"TileSet physics layer 0's collision_layer should be exactly "
			+ "the 'world' bit (%d per project.godot's [layer_names]) and "
			+ "nothing else (design doc §11)."
			) % [WORLD_LAYER_BIT])

	# Design doc §11: Solids' collision_mask should be empty — static terrain
	# has nothing of its own to detect, it only needs to BE detected by
	# whoever is moving (the player, WorldProp). world.tscn's Solids node
	# already has collision_mask = 0, but per this project's convention
	# (CLAUDE.md/agent memory) a zero/default .tscn value is only "intentional"
	# if a test asserts it — otherwise a future edit could silently change it
	# without anything failing.
	assert_eq(tile_set.get_physics_layer_collision_mask(0), 0,
			(
			"TileSet physics layer 0's collision_mask should be 0 — static "
			+ "terrain like Solids should not itself detect anything; it "
			+ "only needs to be detected by moving bodies (design doc §11)."
			))


func test_at_least_one_solids_tile_has_a_collision_polygon() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return

	var solids: TileMapLayer = world.get_node_or_null("Solids") as TileMapLayer
	assert_not_null(solids, "world.tscn should contain a TileMapLayer named 'Solids'")
	if solids == null:
		return

	assert_gt(solids.get_used_cells().size(), 0,
			"Solids should have at least one tile painted on it to test collision against")

	var collidable_cell: Variant = _find_cell_with_collision_polygon(solids)
	assert_not_null(collidable_cell,
			(
			"at least one tile painted on Solids should have a TileData "
			+ "collision polygon on physics layer 0 (design doc §6) — none "
			+ "of Solids's painted cells reported one."
			))


# ---------------------------------------------------------------------------
# Collision response: Solids blocks, Ground-only does not (design doc §6, §9)
# ---------------------------------------------------------------------------

func test_player_stops_at_a_solids_tile_with_collision() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return

	var solids: TileMapLayer = world.get_node_or_null("Solids") as TileMapLayer
	var player: CharacterBody2D = world.get_node_or_null("Player") as CharacterBody2D
	assert_not_null(solids, "world.tscn should contain a TileMapLayer named 'Solids'")
	assert_not_null(player, "world.tscn must have a child node named 'Player'")
	if solids == null or player == null:
		return

	var solid_cell: Variant = _find_collision_cell_with_clear_approach(solids)
	assert_not_null(solid_cell,
			(
			"Solids needs at least one tile with a collision polygon AND a "
			+ "clear 48px approach corridor to its west for this test to "
			+ "drive the player toward — if a collision tile exists but "
			+ "this still fails, every candidate's approach is contaminated "
			+ "by a neighbouring collidable tile (see "
			+ "_is_approach_corridor_clear())."
			))
	if solid_cell == null:
		return

	# Give the freshly-instantiated TileMapLayer's static bodies a couple of
	# physics frames to register with the physics server before we start
	# querying it via move_and_slide().
	await wait_physics_frames(2)

	var target_global: Vector2 = _cell_to_global(solids, solid_cell)
	var result: Dictionary = _drive_player_right_toward(player, target_global)

	# The critical checks: the player travelled meaningfully less than the
	# unobstructed distance (it was actually stopped, not merely slowed —
	# design doc §6 phasing item 2: "the player is blocked by a painted
	# tile"), and its final position never reached the solid tile's centre
	# (it stopped at the edge, not inside it).
	assert_lt(result.traveled_px, result.unobstructed_px * 0.5,
			(
			"player should be blocked well short of the unobstructed "
			+ "distance by a Solids tile with collision (travelled %.1fpx "
			+ "of an unobstructed %.1fpx) — if this fails, check the "
			+ "TileSet physics layer's collision polygon and collision_mask/"
			+ "collision_layer values."
			) % [result.traveled_px, result.unobstructed_px])

	assert_lt(player.global_position.x, result.target_x,
			(
			"player's final x position (%.1f) should be less than the "
			+ "solid tile's centre x (%.1f) — the player must stop at the "
			+ "tile's edge, not advance into or across it."
			) % [player.global_position.x, result.target_x])


func test_player_crosses_a_ground_only_tile_uninterrupted() -> void:
	var world: Node = _instantiate_world()
	if world == null:
		return

	var ground: TileMapLayer = world.get_node_or_null("Ground") as TileMapLayer
	var solids: TileMapLayer = world.get_node_or_null("Solids") as TileMapLayer
	var player: CharacterBody2D = world.get_node_or_null("Player") as CharacterBody2D
	assert_not_null(ground, "world.tscn should contain a TileMapLayer named 'Ground'")
	assert_not_null(solids, "world.tscn should contain a TileMapLayer named 'Solids'")
	assert_not_null(player, "world.tscn must have a child node named 'Player'")
	if ground == null or solids == null or player == null:
		return

	var ground_only_cell: Variant = _find_ground_only_cell(ground, solids, player)
	assert_not_null(ground_only_cell,
			(
			"Ground needs at least one cell that is not also painted on "
			+ "Solids, with a clear 48px approach corridor to its west, for "
			+ "this contrast test — if a Ground-only cell exists but this "
			+ "still fails, every candidate's approach is contaminated by a "
			+ "nearby Solids tile (see _is_approach_corridor_clear())."
			))
	if ground_only_cell == null:
		return

	await wait_physics_frames(2)

	var target_global: Vector2 = _cell_to_global(ground, ground_only_cell)
	var result: Dictionary = _drive_player_right_toward(player, target_global)

	# For contrast with the blocked case above: the player should cover
	# essentially the full unobstructed distance and end up past the
	# tile's centre — nothing stopped it.
	assert_gt(result.traveled_px, result.unobstructed_px * 0.9,
			(
			"player should travel close to the unobstructed distance across "
			+ "a Ground-only tile (travelled %.1fpx of an unobstructed "
			+ "%.1fpx) — if this fails, something is unexpectedly blocking "
			+ "movement over a tile with no Solids collision."
			) % [result.traveled_px, result.unobstructed_px])

	assert_gt(player.global_position.x, result.target_x,
			(
			"player's final x position (%.1f) should be greater than the "
			+ "Ground-only tile's centre x (%.1f) — the player should "
			+ "advance onto AND across it, not stop at or before it."
			) % [player.global_position.x, result.target_x])
