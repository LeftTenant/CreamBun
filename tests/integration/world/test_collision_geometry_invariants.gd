## test_collision_geometry_invariants.gd
## Cross-cutting geometric invariants of the collision + area-transition system.
##
## WHY THIS FILE EXISTS, AND WHY IT BREAKS THIS SUITE'S USUAL CONVENTION
##
## Every other world/player test in this project follows a "mirror the
## constant, don't read it" rule: a test restates the value it expects, so a
## change to the source constant fails a test rather than silently propagating.
## That convention works, and it is why a hand-tuning pass on the player
## collider surfaced as nine loud failures rather than a shipped bug.
##
## But it only catches values that CHANGED. It cannot catch a value that
## changed to something WRONG. When NORTH_WALL_HEADROOM_INSET_PX went from 32
## to 16, every mirrored test failed, got its mirror updated, and went green —
## and nothing anywhere verified that 16 was large enough to keep Cream Bun on
## screen. Picking 8 would have passed the whole suite and shipped a player
## whose head is clipped off at the north edge of every map.
##
## So this file does the opposite on purpose: it READS from the live scenes and
## the real constants, and asserts the RELATIONSHIPS between independently
## authored facts. Mirroring here would defeat the point — you would be
## comparing two copies of one number instead of two things that must agree.
##
## The facts it relates are authored in three different formats, by three
## different kinds of edit, with nothing in the engine linking them:
##   - the drawn character's size      -> a PNG's transparent padding
##   - the player's collider           -> a sub-resource in player.tscn
##   - the world's boundary geometry   -> constants in world_area.gd
## An artist re-padding a sprite, a designer re-shaping a collider, and a
## programmer retuning an inset are all "one small change" in isolation. These
## tests are what make the second of any two of them fail loudly.
##
## Design reference: docs/features/world-collision/design.md §10 (player
##   collider), §12.3 (camera limits), §12.4 (north headroom inset, corner
##   dead zones), §12.5 (opposite-edge spawn)
## Test plan: docs/features/world-collision/player-collider-capsule-test-plan.md
##
## Requires GUT: https://github.com/bitwes/Gut
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gselect=test_collision_geometry_invariants.gd -gexit

class_name TestCollisionGeometryInvariants
extends GutTest


const WORLD_SCENE_PATH: String = "res://world/world.tscn"
const PLAYER_SCENE_PATH: String = "res://player/player.tscn"

const CollisionProbe := preload("res://tests/integration/world/shared/collision_probe.gd")

## How far back from a target collider to start the player for a drive test,
## and how many physics ticks to hold input for. Mirrors
## test_solids_collision.gd's numbers so the two files' "blocked" readings are
## directly comparable; at speed 200px/s and 60 ticks the unobstructed distance
## is ~200px, several times the 48px approach.
const APPROACH_OFFSET_PX: float = 48.0
const SIMULATION_TICKS: int = 60


func before_each() -> void:
	# player.gd gates movement on GameState.current_state == PLAYING.
	GameState.change_state(GameState.State.PLAYING)


func after_each() -> void:
	for action in ["move_up", "move_down", "move_left", "move_right"]:
		Input.action_release(action)


# ---------------------------------------------------------------------------
# Helpers — deriving the three facts these invariants relate
# ---------------------------------------------------------------------------

## Instantiate world.tscn under the test tree and return its root, or null with
## the failure already recorded.
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


## Instantiate player.tscn on its own — no world, no autoload graph — for the
## pure-geometry invariants that need nothing else.
func _instantiate_player() -> CharacterBody2D:
	var packed: PackedScene = load(PLAYER_SCENE_PATH)
	assert_not_null(packed, "player/player.tscn should load as a PackedScene")
	if packed == null:
		return null

	var player: CharacterBody2D = packed.instantiate() as CharacterBody2D
	assert_not_null(player, "player.tscn's root must be a CharacterBody2D")
	if player == null:
		return null

	add_child_autofree(player)
	return player


## The DRAWN character's extent relative to the player's node origin, in px.
##
## Derived from the art itself, not declared: takes the first frame of the
## sprite's current animation, asks the Image for the bounding box of its
## non-transparent pixels (Image.get_used_rect()), and maps that box out of
## frame space into the player's local space through the AnimatedSprite2D's
## own `centered`/`offset` settings.
##
## This is deliberately the long way round. A constant saying "the character is
## 22px wide" would be one more independently-authored number to keep in sync —
## the exact problem this file exists to catch. Reading the alpha means an
## artist re-padding the sprite changes this value automatically, and whichever
## invariant that breaks is the one that needed a human decision.
## https://docs.godotengine.org/en/stable/classes/class_image.html#class-image-method-get-used-rect
func _drawn_character_extent(player: CharacterBody2D) -> Rect2:
	var sprite: AnimatedSprite2D = (
			player.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D)
	assert_not_null(sprite, "player.tscn must have an AnimatedSprite2D child")
	if sprite == null:
		return Rect2()

	var frames: SpriteFrames = sprite.sprite_frames
	assert_not_null(frames, "the player's AnimatedSprite2D must have SpriteFrames")
	if frames == null:
		return Rect2()

	# The union across EVERY frame of EVERY animation, matching what
	# player.gd's get_visual_extent() publishes. Measuring only the idle pose
	# would be wrong and dangerously reassuring: this sprite sheet's padding is
	# not uniform (idle frame 0 has 5px above the character, but walk frames
	# have only 1px), so an idle-only measurement under-reports the character's
	# real height by 4px and would bless a north inset that clips the top of
	# Cream Bun's antenna the moment they walk into the boundary.
	var union := Rect2()
	var found_any: bool = false

	for animation in frames.get_animation_names():
		for index in frames.get_frame_count(animation):
			var texture: Texture2D = frames.get_frame_texture(animation, index)
			if texture == null:
				continue

			# get_image() on an already-loaded texture (rather than
			# Image.load() on a res:// path) avoids the "Loaded resource as
			# image file" engine warning that GUT's default policy fails a test
			# for — same reasoning as
			# tests/unit/resources/sprites/terrain/test_terrain_tile_dimensions.gd.
			var image: Image = texture.get_image()
			if image == null:
				continue
			var opaque: Rect2i = image.get_used_rect()
			if opaque.size.x <= 0 or opaque.size.y <= 0:
				continue

			# AnimatedSprite2D draws each frame centred on `offset` when
			# `centered` is true (the default), so the frame's top-left corner
			# in the player's local space is offset - frame_size/2.
			var frame_size := Vector2(texture.get_width(), texture.get_height())
			var frame_origin: Vector2 = sprite.offset
			if sprite.centered:
				frame_origin -= frame_size / 2.0

			var frame_extent := Rect2(
					frame_origin + Vector2(opaque.position), Vector2(opaque.size))
			union = frame_extent if not found_any else union.merge(frame_extent)
			found_any = true

	assert_true(found_any, "at least one player frame must contain non-transparent pixels")
	return union


## Every collidable polygon painted in `area`, with its axis-aligned bounding
## box, sorted thinnest-first. Used by the thin-strip drive test below.
##
## "Thickness" is the SMALLER of a polygon's two bbox dimensions — the axis a
## fast-moving body would have to cross to pass through it. The meadow's edge
## variants include strips barely 2px across, which is well under the distance
## the player covers in a single physics tick (200px/s / 60Hz = 3.3px), so
## whether they still stop the player is a real question and not a rhetorical
## one.
##
## `thin_axis` is 0 when the polygon is thin on X (a vertical strip, crossed by
## moving horizontally) and 1 when thin on Y (a horizontal strip, crossed by
## moving vertically).
func _collision_strips_thinnest_first(area: Node2D) -> Array[Dictionary]:
	var strips: Array[Dictionary] = []
	for polygon in CollisionProbe.obstacle_polygons(area):
		if polygon.size() < 3:
			continue
		var bbox := Rect2(polygon[0], Vector2.ZERO)
		for point in polygon:
			bbox = bbox.expand(point)
		strips.append({
			"bbox": bbox,
			"thickness": minf(bbox.size.x, bbox.size.y),
			"thin_axis": 0 if bbox.size.x < bbox.size.y else 1,
		})

	strips.sort_custom(func(a, b): return a["thickness"] < b["thickness"])
	return strips


## The polygons that could obstruct an approach to a fence face, i.e. every
## obstacle EXCEPT the target fence itself and anything beyond it.
##
## This filter is the whole reason the first version of the thin-strip test
## below was worthless. Checking the approach against every obstacle rejects
## the target strip's own polygon (the player's collider necessarily reaches it
## at the end of the run), so the search fell through the genuinely thin 2px
## strips and settled on a 16px-thick full-tile polygon — thicker than a tick
## of movement, making the test trivially true.
##
## Excluding "the target and anything past it" rather than "the target polygon"
## specifically also handles the normal case that a fence is a RUN of adjacent
## strips: the meadow's east wall of the west pen is two separately authored
## polygons stacked vertically, and either may be what actually stops the
## player. What matters is that the player is stopped AT the fence line, not
## which polygon in the run did it.
func _obstacles_before_face(obstacles: Array[PackedVector2Array], axis: int,
		face: float, moving_positive: bool) -> Array[PackedVector2Array]:
	const EPSILON: float = 0.5
	var before: Array[PackedVector2Array] = []
	for polygon in obstacles:
		var bbox := Rect2(polygon[0], Vector2.ZERO)
		for point in polygon:
			bbox = bbox.expand(point)
		var beyond: bool = (
				bbox.position[axis] >= face - EPSILON if moving_positive
				else bbox.end[axis] <= face + EPSILON)
		if not beyond:
			before.append(polygon)
	return before


## Drive `player` from `start` in `action`'s direction for SIMULATION_TICKS and
## report how far they got versus how far they would have got unobstructed.
##
## Uses the real Input singleton and GUT's simulate() so the actual
## Input.get_vector() -> velocity -> move_and_slide() pipeline runs, matching
## test_solids_collision.gd's convention.
func _drive_from(player: CharacterBody2D, start: Vector2, action: String) -> Dictionary:
	player.global_position = start
	player.velocity = Vector2.ZERO

	# move_and_slide() always advances by the engine's real physics-tick delta
	# regardless of the delta passed to _physics_process(), so the unobstructed
	# distance must be computed from that same value.
	var physics_delta: float = 1.0 / Engine.physics_ticks_per_second

	Input.action_press(action)
	simulate(player, SIMULATION_TICKS, physics_delta)
	Input.action_release(action)
	player.velocity = Vector2.ZERO

	var speed: float = player.get("speed")
	return {
		"traveled_px": player.global_position.distance_to(start),
		"unobstructed_px": speed * SIMULATION_TICKS * physics_delta,
		"per_tick_px": speed * physics_delta,
	}


# ---------------------------------------------------------------------------
# Invariant 1 — the north headroom inset must actually cover the player
# ---------------------------------------------------------------------------

func test_north_headroom_inset_keeps_the_whole_character_on_screen() -> void:
	# THE invariant this file was written for.
	#
	# Camera2D.limit_top (world.gd's _set_camera_limits()) clamps the camera's
	# VIEW RECT to the painted north edge. Stopped flush against the north
	# boundary the player's origin sits at `boundary - collider.position.y`,
	# and the drawn character extends `visual.position.y` above that origin —
	# so the top of the character lands
	#
	#     collider.position.y - visual.position.y
	#
	# ABOVE the boundary. The inset has to be at least that, or the character
	# is drawn outside the clamped view and the player is invisible at the top
	# of every map (a bug that was hit for real before the inset existed).
	#
	# Note that both inputs are negative offsets above the origin, so the
	# subtraction reads backwards at a glance: -14 - -27 = 13.
	var player: CharacterBody2D = _instantiate_player()
	if player == null:
		return

	var collider: Rect2 = CollisionProbe.player_collider_extent(player)
	var visual: Rect2 = _drawn_character_extent(player)
	if collider.size == Vector2.ZERO or visual.size == Vector2.ZERO:
		return

	var needed: float = collider.position.y - visual.position.y
	var inset: float = WorldArea.north_headroom_inset(visual, collider)

	assert_gte(inset, needed,
			("north_headroom_inset() returned %.1fpx but this player needs at least %.1fpx: " +
			"their collider's top edge sits %.1fpx above their origin, while the drawn " +
			"character reaches %.1fpx above it, so stopping flush against the north boundary " +
			"puts %.1fpx of Cream Bun above Camera2D.limit_top.")
					% [inset, needed, -collider.position.y, -visual.position.y, needed])


func test_north_headroom_inset_is_the_tightest_whole_tile_row() -> void:
	# The other side of the same invariant. Design.md §12.4 makes the inset a
	# whole tile depth so the non-walkable backdrop strip is an exact row of
	# tiles a designer can see and reason about — but only ONE row. An inset
	# two rows deep would satisfy the "keeps the character on screen" check
	# above while quietly costing every map in the game a row of ground nobody
	# can stand on, which is the kind of waste that never shows up as a bug
	# report.
	var player: CharacterBody2D = _instantiate_player()
	if player == null:
		return

	var collider: Rect2 = CollisionProbe.player_collider_extent(player)
	var visual: Rect2 = _drawn_character_extent(player)
	if collider.size == Vector2.ZERO or visual.size == Vector2.ZERO:
		return

	var needed: float = collider.position.y - visual.position.y
	var tile_depth: float = float(WorldArea.TILE_SIZE.y)
	var inset: float = WorldArea.north_headroom_inset(visual, collider)

	assert_lt(inset, needed + tile_depth,
			("north_headroom_inset() returned %.1fpx for a %.1fpx requirement — a whole extra " +
			"%.0fpx tile row more than needed. Every map in the game pays that as ground the " +
			"player can see but never stand on.")
					% [inset, needed, tile_depth])
	assert_eq(fmod(inset, tile_depth), 0.0,
			("north_headroom_inset() returned %.1fpx, which is not a whole multiple of the " +
			"%.0fpx tile depth — the non-walkable backdrop strip (design.md §12.4) would end " +
			"mid-tile, which a designer cannot see or count.")
					% [inset, tile_depth])


func test_player_publishes_extents_matching_an_independent_measurement() -> void:
	# player.gd's get_visual_extent()/get_collider_extent() are the numbers the
	# whole boundary system is now derived from, so they are worth measuring a
	# second way. This file computes both from the scene's raw contents
	# independently of player.gd's implementation; if the two ever disagree,
	# every inset derived downstream is suspect.
	#
	# This is also the test that would catch the tempting "optimisation" of
	# measuring only the idle frame: the sheet's padding is uneven, so an
	# idle-only union is 4px shorter than the real one.
	var player: CharacterBody2D = _instantiate_player()
	if player == null:
		return

	assert_eq(player.get_collider_extent(), CollisionProbe.player_collider_extent(player),
			"player.gd's published collider extent must match the extent measured from its own CollisionShape2D")
	assert_eq(player.get_visual_extent(), _drawn_character_extent(player),
			("player.gd's published visual extent must match the opaque-pixel union measured " +
			"independently from its SpriteFrames — if these differ, check whether one of them " +
			"is only looking at a single animation or frame."))


func test_north_headroom_inset_responds_to_geometry_rather_than_being_fixed() -> void:
	# The two tests above check the derivation against ONE input — the project's
	# current player — which a function that ignored its arguments and returned
	# 16.0 would also satisfy. These synthetic cases pin the behaviour that
	# makes the derivation worth having: that it MOVES.
	var tile_depth: float = float(WorldArea.TILE_SIZE.y)

	# A character drawn no higher than its own collider needs no headroom.
	assert_eq(
		WorldArea.north_headroom_inset(Rect2(-11, -14, 22, 10), Rect2(-11, -14, 22, 10)),
		0.0,
		"a character whose art doesn't rise above its collider needs no headroom inset")

	# Taller art than the current player must cost more headroom, not the same.
	var current: float = WorldArea.north_headroom_inset(Rect2(-11, -27, 22, 22), Rect2(-11, -14, 22, 10))
	var taller: float = WorldArea.north_headroom_inset(Rect2(-11, -48, 22, 43), Rect2(-11, -14, 22, 10))
	assert_gt(taller, current,
			("a taller character must require a deeper inset (got %.1fpx for a 48px-tall " +
			"character vs %.1fpx for a 27px one) — if these are equal the derivation is " +
			"ignoring its inputs.") % [taller, current])

	# A requirement landing exactly on a tile boundary must not round up a
	# whole spare row. 16px of overhang is exactly one tile depth.
	assert_eq(
		WorldArea.north_headroom_inset(Rect2(-11, -30, 22, 20), Rect2(-11, -14, 22, 10)),
		tile_depth,
		"an overhang of exactly one tile depth must return one tile, not two")


func test_the_built_north_boundary_actually_uses_the_derived_inset() -> void:
	# The wiring test. Everything above checks that north_headroom_inset()
	# computes the right number; this checks that the number reaches the
	# geometry — that world.gd really does read the player's extents and hand
	# them to build_perimeter_walls(), rather than the two halves of this
	# mechanism quietly agreeing on a stale default.
	#
	# The meadow's north edge has no neighbour, so it builds a plain
	# StaticBody2D. Its player-facing (south) surface is what must land on the
	# derived boundary: _edge_rect() places the wall from
	# `bounds.top - thickness + inset` with height `thickness`, so its bottom
	# edge is exactly `bounds.top + inset`.
	var world: Node = _instantiate_world()
	if world == null:
		return

	var active_area: Node = world.get_node_or_null("ActiveArea")
	if active_area == null or active_area.get_child_count() == 0:
		fail_test("world.tscn should have an instanced WorldArea under ActiveArea")
		return
	var area: WorldArea = active_area.get_child(0) as WorldArea
	var player: CharacterBody2D = world.find_child("Player", true, false) as CharacterBody2D
	assert_not_null(area, "the instanced area must be a WorldArea")
	assert_not_null(player, "world.tscn's instantiated tree should contain a Player")
	if area == null or player == null:
		return

	var expected_inset: float = WorldArea.north_headroom_inset(
			player.get_visual_extent(), player.get_collider_extent())
	var bounds: Rect2 = area.get_bounds_px()

	var wall: StaticBody2D = area.get_node_or_null("PerimeterWallNorth") as StaticBody2D
	assert_not_null(wall,
			"the meadow's north edge has no neighbour, so it should build a StaticBody2D named 'PerimeterWallNorth'")
	if wall == null:
		return

	var collision: CollisionShape2D = null
	for child in wall.get_children():
		collision = child as CollisionShape2D
		if collision != null:
			break
	assert_not_null(collision, "the north perimeter wall must have a CollisionShape2D child")
	if collision == null:
		return

	var shape: RectangleShape2D = collision.shape as RectangleShape2D
	if shape == null:
		fail_test("the north perimeter wall's shape should be a RectangleShape2D")
		return

	# The wall's player-facing surface: its collider's southern edge.
	var facing_surface: float = wall.position.y + collision.position.y + shape.size.y / 2.0

	assert_almost_eq(facing_surface, bounds.position.y + expected_inset, 0.5,
			("the north wall's player-facing surface sits at y=%.1f, but the player's own " +
			"geometry says it should be at y=%.1f (bounds.top %.1f + a derived inset of " +
			"%.1fpx). The derivation and the geometry have come apart — check that world.gd " +
			"still passes _north_headroom_inset() into build_perimeter_walls().")
					% [facing_surface, bounds.position.y + expected_inset,
							bounds.position.y, expected_inset])


# ---------------------------------------------------------------------------
# Invariant 2 — the collider stays sub-tile
# ---------------------------------------------------------------------------

func test_player_collider_fits_through_a_one_tile_gap() -> void:
	# Design.md §10: the collider is deliberately smaller than a tile so the
	# player can walk through a one-tile opening without pixel-perfect
	# alignment — "a cozy game should not punish precision". That is a claim
	# about the RATIO of two independently-authored things (the collider in
	# player.tscn, the tile size in world_area.gd), so neither file can check
	# it alone.
	#
	# It is also the invariant most directly at risk from art changes: a
	# redrawn, chunkier Cream Bun whose collider is traced from the new art
	# could cross 32px wide without anyone thinking about map geometry, and the
	# symptom would be "some doorways just don't work sometimes".
	var player: CharacterBody2D = _instantiate_player()
	if player == null:
		return

	var collider: Rect2 = CollisionProbe.player_collider_extent(player)
	if collider.size == Vector2.ZERO:
		return

	assert_lt(collider.size.x, float(WorldArea.TILE_SIZE.x),
			("the player's collider is %.1fpx wide but a tile is only %dpx — they can no longer " +
			"fit through a one-tile gap (design.md §10).")
					% [collider.size.x, WorldArea.TILE_SIZE.x])
	assert_lt(collider.size.y, float(WorldArea.TILE_SIZE.y),
			("the player's collider is %.1fpx deep but a tile is only %dpx — they can no longer " +
			"fit through a one-tile gap on the vertical axis (design.md §10).")
					% [collider.size.y, WorldArea.TILE_SIZE.y])


func test_corner_dead_zone_is_larger_than_the_player_collider() -> void:
	# Design.md §12.4: a player standing inside a corner square must not be
	# able to trigger a transition. The corner stubs make that structural, but
	# the guarantee still depends on the dead zone being bigger than the player
	# — if the collider ever grew past CORNER_DEAD_ZONE_PX, a player centred in
	# a corner would overlap the adjacent edge's active trigger stretch and the
	# "corners are never ambiguous" rule would quietly stop holding.
	var player: CharacterBody2D = _instantiate_player()
	if player == null:
		return

	var collider: Rect2 = CollisionProbe.player_collider_extent(player)
	if collider.size == Vector2.ZERO:
		return

	var largest_half_extent: float = maxf(collider.size.x, collider.size.y) / 2.0
	assert_gt(WorldArea.CORNER_DEAD_ZONE_PX, largest_half_extent,
			("the corner dead zone is %.1fpx but the player's collider reaches %.1fpx from " +
			"their origin — a player standing in a corner square could overlap the adjacent " +
			"edge's trigger, so 'no transition ever starts from a corner' (design.md §12.4) " +
			"would no longer hold.")
					% [WorldArea.CORNER_DEAD_ZONE_PX, largest_half_extent])


# ---------------------------------------------------------------------------
# Invariant 3 — thin tile collision polygons still stop the player
# ---------------------------------------------------------------------------

func test_the_thinnest_painted_collision_strip_still_stops_the_player() -> void:
	# The tile-side counterpart to the collider invariants above, and the one
	# that answers "what happens as tile collider shapes change".
	#
	# The meadow's boundary tiles are hand-drawn strips, some barely 2px across
	# — noticeably LESS than the 3.3px the player covers in a single physics
	# tick at 200px/s and 60Hz. Whether that still stops them depends on
	# CharacterBody2D sweeping its motion rather than teleporting and testing,
	# which is engine behaviour this project has never actually verified. So
	# verify it, empirically, against whatever the thinnest painted polygon
	# happens to be right now — rather than asserting an arithmetic inequality
	# that rests on an assumption about Godot's internals.
	#
	# If someone draws a 1px strip and this fails, the answer is to thicken the
	# polygon, not to delete the test.
	var world: Node = _instantiate_world()
	if world == null:
		return

	var active_area: Node = world.get_node_or_null("ActiveArea")
	assert_not_null(active_area, "world.tscn must have an ActiveArea node")
	if active_area == null or active_area.get_child_count() == 0:
		fail_test("world.tscn should have an instanced WorldArea under ActiveArea")
		return
	var area: Node2D = active_area.get_child(0) as Node2D

	var player: CharacterBody2D = world.find_child("Player", true, false) as CharacterBody2D
	assert_not_null(player, "world.tscn's instantiated tree should contain a Player")
	if area == null or player == null:
		return

	var strips: Array[Dictionary] = _collision_strips_thinnest_first(area)
	assert_gt(strips.size(), 0, "the meadow should have at least one painted collision polygon")
	if strips.is_empty():
		return

	var collider: Rect2 = CollisionProbe.player_collider_extent(player)
	var obstacles: Array[PackedVector2Array] = CollisionProbe.obstacle_polygons(area)

	# Walk the strips thinnest-first and take the first one the player can be
	# given a clean run at. The thinnest strip in the map is the one worth
	# testing, but it is no use if something else stops the player on the way
	# — in which case the next-thinnest is still a far stronger test than an
	# arbitrarily chosen tile.
	var chosen: Dictionary = {}
	var start := Vector2.ZERO
	var action: String = ""
	var face: float = 0.0
	var axis: int = 0
	var moving_positive: bool = true

	for strip in strips:
		var bbox: Rect2 = strip["bbox"]
		var strip_axis: int = strip["thin_axis"]
		var centre: Vector2 = bbox.get_center()

		# Approach perpendicular to the thin axis, trying both sides. Each
		# candidate places the player's LEADING collider edge exactly
		# APPROACH_OFFSET_PX short of the strip's near face.
		var candidates: Array = []
		if strip_axis == 0:
			candidates = [
				[bbox.position.x, true, Vector2(bbox.position.x - APPROACH_OFFSET_PX - collider.end.x, centre.y), "move_right"],
				[bbox.end.x, false, Vector2(bbox.end.x + APPROACH_OFFSET_PX - collider.position.x, centre.y), "move_left"],
			]
		else:
			candidates = [
				[bbox.position.y, true, Vector2(centre.x, bbox.position.y - APPROACH_OFFSET_PX - collider.end.y), "move_down"],
				[bbox.end.y, false, Vector2(centre.x, bbox.end.y + APPROACH_OFFSET_PX - collider.position.y), "move_up"],
			]

		for candidate in candidates:
			var candidate_face: float = candidate[0]
			var candidate_positive: bool = candidate[1]
			var candidate_start: Vector2 = candidate[2]
			var blockers: Array[PackedVector2Array] = _obstacles_before_face(
					obstacles, strip_axis, candidate_face, candidate_positive)
			# Sweep only as far as contact with the face; anything at or past
			# it is the fence being tested, not an obstruction (see
			# _obstacles_before_face()).
			var contact := candidate_start
			contact[strip_axis] = (
					candidate_face - collider.end[strip_axis] if candidate_positive
					else candidate_face - collider.position[strip_axis])
			if CollisionProbe.is_path_clear(collider, candidate_start, contact, blockers):
				chosen = strip
				start = candidate_start
				action = candidate[3]
				face = candidate_face
				axis = strip_axis
				moving_positive = candidate_positive
				break
		if not chosen.is_empty():
			break

	assert_false(chosen.is_empty(),
			"no painted collision strip in the meadow has a clear approach from either side — cannot attribute a block to any one of them")
	if chosen.is_empty():
		return

	await wait_physics_frames(2)
	var result: Dictionary = _drive_from(player, start, action)

	# The premise, logged so a future reader can see at a glance whether this
	# test is still exercising a genuinely thin strip. If `thickness` ever
	# creeps above `per_tick_px`, the test has stopped asking a real question.
	gut.p("thinnest approachable strip: %.2fpx across; player moves %.2fpx per physics tick"
			% [chosen["thickness"], result["per_tick_px"]])

	assert_lt(chosen["thickness"], result["per_tick_px"],
			("this test is only meaningful against a strip THINNER than one tick of movement, " +
			"but the thinnest approachable one is %.2fpx against %.2fpx of per-tick travel. " +
			"Either the thin boundary tiles were removed from the meadow, or the approach " +
			"search is rejecting them and silently falling back to a thick polygon.")
					% [chosen["thickness"], result["per_tick_px"]])

	# The real assertion: the player is stopped AT the fence line. "Travelled
	# less than half the unobstructed distance" would also be satisfied by a
	# player who sailed 100px past a 2px strip and was stopped by something
	# else entirely — which is exactly the failure this test exists to catch.
	var leading_edge: float = (
			player.global_position[axis] + collider.end[axis] if moving_positive
			else player.global_position[axis] + collider.position[axis])
	var overshoot: float = (
			leading_edge - face if moving_positive else face - leading_edge)

	assert_almost_eq(overshoot, 0.0, 1.0,
			("the player's leading collider edge finished %.2fpx past the near face of a %.2fpx " +
			"collision strip (driven at %.2fpx per physics tick, travelled %.1fpx of an " +
			"unobstructed %.1fpx). A strip thinner than one tick of movement only stops the " +
			"player because CharacterBody2D sweeps its motion rather than teleporting and " +
			"testing; if that stops holding, every thin boundary tile in the game becomes a " +
			"walk-through gap.")
					% [overshoot, chosen["thickness"], result["per_tick_px"],
							result["traveled_px"], result["unobstructed_px"]])
