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
##   collider), §12.3 (camera limits) — history for §12.4/§12.5 (north
##   headroom inset, corner dead zones, opposite-edge spawn), which World
##   Thresholds Slice 4 deletes; see below.
## Test plan: docs/features/world-collision/player-collider-capsule-test-plan.md
##
## World Thresholds Slice 4 (docs/features/world-thresholds/design.md §7-§9)
## deletes the north-edge camera-headroom inset and the corner dead zone
## outright — every edge's perimeter wall is now unconditional and symmetric,
## and a Threshold sitting inset from it is what keeps the character on
## screen where a designer wants that (design §8). This file's Invariant 1
## (north headroom inset) and the corner-dead-zone half of Invariant 2 are
## removed along with the WorldArea API they measured
## (north_headroom_inset(), CORNER_DEAD_ZONE_PX) — see the deletion notes
## inline below for exactly what went and why what remains still stands.
##
## Invariants 4 and 5 below are a second feature's addition to this file:
## world-thresholds Slice 1 (docs/features/world-thresholds/design.md §6).
##
## Invariant 4 adds exactly ONE test — that ThresholdBounds's authored rect
## still covers the art — because that check, and only that check, needs this
## file's _drawn_character_extent() helper and exists for the identical
## reason Invariant 1 does (an authored number and the art it was sized
## against must be checked against each other, not just restated). Every
## other fact about ThresholdBounds (that it exists, its exact shape/
## position, its layer, its mask) is scene-as-data, not a relationship
## between independently-authored facts — those tests live in
## tests/integration/player/test_player_scene.gd instead, per this file's own
## rule against mirroring.
##
## Invariant 5 adds one more test, unrelated to ThresholdBounds: that the
## north perimeter wall stops the player's MOVEMENT collider exactly at its
## own computed face. It rides along with this slice because adding
## ThresholdBounds to the player's scene tree is what first raised the
## question of whether a second collider could perturb the first — but the
## invariant it protects (a wall stops movement exactly where its geometry
## says) is a standing one, kept for its own sake, not scoped to this slice.
## Test plan: docs/features/world-thresholds/slice-1-threshold-bounds-test-plan.md
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

	# The union across EVERY frame of EVERY animation — measuring only the
	# idle pose would be wrong and dangerously reassuring: this sprite sheet's
	# padding is not uniform (idle frame 0 has 5px above the character, but
	# walk frames have only 1px), so an idle-only measurement under-reports
	# the character's real height by 4px and would bless a ThresholdBounds
	# rect (Invariant 4 below) that doesn't actually cover the art.
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
# Invariant 1 — removed (World Thresholds Slice 4)
# ---------------------------------------------------------------------------
#
# This banner used to guard the north-edge camera-headroom inset:
# test_north_headroom_inset_keeps_the_whole_character_on_screen(),
# test_north_headroom_inset_is_the_tightest_whole_tile_row(),
# test_north_headroom_inset_responds_to_geometry_rather_than_being_fixed(),
# and test_the_built_north_boundary_actually_uses_the_derived_inset(), plus
# the get_visual_extent() half of test_player_publishes_extents_matching_an_
# independent_measurement() below. World Thresholds Slice 4
# (docs/features/world-thresholds/design.md §7-§9) deletes
# WorldArea.north_headroom_inset() and Player.get_visual_extent() outright —
# the north edge may clip the character by default now (design §8), a
# content decision a designer makes per area (paint terrain, place a
# Threshold, or accept it), not a computed one this file needs to verify.


func test_player_publishes_extents_matching_an_independent_measurement() -> void:
	# player.gd's get_collider_extent() is a number other systems (this file,
	# CollisionProbe) read rather than re-deriving, so it's worth measuring a
	# second way: this file computes it from the scene's raw contents
	# independently of player.gd's implementation, and the two must agree.
	var player: CharacterBody2D = _instantiate_player()
	if player == null:
		return

	assert_eq(player.get_collider_extent(), CollisionProbe.player_collider_extent(player),
			"player.gd's published collider extent must match the extent measured from its own CollisionShape2D")


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


# ---------------------------------------------------------------------------
# Invariant 4 — ThresholdBounds covers the player's drawn extent
# (world-thresholds design.md §6)
# ---------------------------------------------------------------------------

## `player`'s ThresholdBounds child, typed and existence-checked, or null with
## the failure already recorded. Shared by the tests below so a missing node
## produces one clear failure rather than a chain of null derefs.
func _get_threshold_bounds(player: CharacterBody2D) -> Area2D:
	var node: Node = player.get_node_or_null("ThresholdBounds")
	assert_not_null(node,
			("player.tscn must have a child named 'ThresholdBounds' — the player's second " +
			"collider, used only for Threshold detection (world-thresholds design.md §6)."))
	if node == null:
		return null

	assert_true(node is Area2D,
			("player.tscn's ThresholdBounds must be an Area2D (found %s) — " +
			"world-thresholds design.md §6.") % [node.get_class()])
	if not (node is Area2D):
		return null

	return node as Area2D


## ThresholdBounds's CollisionShape2D child, or null with the failure already
## recorded if it's missing.
func _get_threshold_bounds_collision_shape(bounds: Area2D) -> CollisionShape2D:
	var collision: CollisionShape2D = (
			bounds.get_node_or_null("CollisionShape2D") as CollisionShape2D)
	assert_not_null(collision,
			"ThresholdBounds must have a CollisionShape2D child (world-thresholds design.md §6)")
	return collision


## `player`'s ThresholdBounds authored rect, in the player's local space —
## derived from its CollisionShape2D.position and RectangleShape2D.size, with
## the "is it actually a RectangleShape2D" preamble collapsed into one place.
## Returns an empty Rect2 (size == Vector2.ZERO) with the failure already
## recorded on any lookup or type failure.
func _get_threshold_bounds_rect(player: CharacterBody2D) -> Rect2:
	var bounds: Area2D = _get_threshold_bounds(player)
	if bounds == null:
		return Rect2()
	var collision: CollisionShape2D = _get_threshold_bounds_collision_shape(bounds)
	if collision == null:
		return Rect2()

	var shape: RectangleShape2D = collision.shape as RectangleShape2D
	assert_not_null(shape,
			("ThresholdBounds's CollisionShape2D.shape must be a RectangleShape2D " +
			"(found %s) — world-thresholds design.md §6.") % [collision.shape])
	if shape == null:
		return Rect2()

	# A zero-size shape is itself a failure worth asserting on, not just a
	# "helper couldn't find anything" signal — callers use Vector2.ZERO as
	# exactly that signal (see their own guards), so an authored (0, 0) rect
	# would otherwise look identical to a lookup failure and let the coverage
	# check below pass vacuously on a ThresholdBounds that could never detect
	# anything.
	assert_ne(shape.size, Vector2.ZERO,
			"ThresholdBounds's RectangleShape2D.size must not be zero — a zeroed rect would never overlap a Threshold, silently disabling every future transition.")

	return Rect2(collision.position - shape.size / 2.0, shape.size)


func test_threshold_bounds_rect_contains_the_drawn_character_union() -> void:
	# THE invariant world-thresholds design.md §6 exists for: "the size is
	# authored, not derived — and this is deliberate ... a test asserts it
	# still contains the art's union bbox." This is Invariant 4's counterpart
	# to Invariant 1's north-headroom-inset check above, and follows this
	# file's usual philosophy for the same reason: measure the art
	# independently (_drawn_character_extent(), reused verbatim — it already
	# unions across EVERY frame of EVERY animation) and relate it to the
	# authored rect, rather than mirroring a constant.
	#
	# On failure this reports the measured bbox and exactly how far short each
	# side of the authored rect falls, so a human knows what to type — it must
	# NEVER recompute or auto-size the rect. Doing so would silently readmit
	# the exact bug this feature exists to retire: sprite art quietly
	# changing map geometry.
	var player: CharacterBody2D = _instantiate_player()
	if player == null:
		return

	var authored: Rect2 = _get_threshold_bounds_rect(player)
	if authored.size == Vector2.ZERO:
		return
	var measured: Rect2 = _drawn_character_extent(player)
	if measured.size == Vector2.ZERO:
		return

	# Positive only when the authored rect falls short on that side — zero
	# when it already covers (or exceeds) the measured union there.
	var left_shortfall: float = maxf(0.0, authored.position.x - measured.position.x)
	var top_shortfall: float = maxf(0.0, authored.position.y - measured.position.y)
	var right_shortfall: float = maxf(0.0, measured.end.x - authored.end.x)
	var bottom_shortfall: float = maxf(0.0, measured.end.y - authored.end.y)

	var fully_contains: bool = (
			left_shortfall <= 0.0 and top_shortfall <= 0.0
			and right_shortfall <= 0.0 and bottom_shortfall <= 0.0)

	assert_true(fully_contains,
			("ThresholdBounds's authored rect %s does not fully contain the measured " +
			"opaque-pixel union %s (the union across EVERY frame of EVERY animation). " +
			"Shortfalls — how much to grow each side of the authored RectangleShape2D in " +
			"player.tscn to cover the art — left %.1fpx, top %.1fpx, right %.1fpx, " +
			"bottom %.1fpx. Fix this by a human resizing ThresholdBounds's CollisionShape2D " +
			"directly (world-thresholds design.md §6: \"the size is authored, not derived\") " +
			"— never by deriving the rect from this measurement.")
					% [authored, measured, left_shortfall, top_shortfall,
							right_shortfall, bottom_shortfall])


# ---------------------------------------------------------------------------
# Invariant 5 — the north wall stops the player exactly where its own
# geometry says it will
# ---------------------------------------------------------------------------

func test_player_stops_flush_against_the_north_wall_face() -> void:
	# RENAMED from test_movement_into_a_solid_wall_is_unperturbed_by_threshold_bounds
	# and given its own banner (was mis-filed under "Invariant 4" above, which
	# is specifically about ThresholdBounds vs. the art — this test never
	# touches ThresholdBounds; it drives the MOVEMENT capsule, via
	# CollisionProbe.player_collider_extent()). The old name described a
	# one-time migration check ("unchanged by adding ThresholdBounds"), not
	# the standing invariant this test actually protects, and framed the
	# value backwards for anyone reading it later.
	#
	# The standing invariant: driving into the meadow's north perimeter wall
	# stops the player's leading collider edge within 1px of the wall's own
	# player-facing surface (computed the same way
	# test_the_built_north_boundary_actually_uses_the_derived_inset() computes
	# it, in Invariant 1 above). That is meaningfully stronger than
	# test_perimeter_walls.gd's loose "travelled less than 90% of the
	# unobstructed distance" check, and worth keeping in its own right — not
	# just as a slice-1 regression guard, which is why it isn't grouped with
	# either ThresholdBounds invariant.
	#
	# It also happens to prove, empirically rather than by argument, that
	# ThresholdBounds (an Area2D with collision_mask = 0, so by construction it
	# can never affect move_and_slide()) doesn't perturb the movement capsule
	# now that the player's scene tree carries a second collider — but that is
	# a corollary of the invariant above, not what makes this test worth
	# keeping.
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

	var wall: StaticBody2D = area.get_node_or_null("PerimeterWallNorth") as StaticBody2D
	assert_not_null(wall,
			("the meadow's north edge has no neighbour, so it should build a StaticBody2D " +
			"named 'PerimeterWallNorth'"))
	if wall == null:
		return

	var wall_collision: CollisionShape2D = null
	for child in wall.get_children():
		wall_collision = child as CollisionShape2D
		if wall_collision != null:
			break
	assert_not_null(wall_collision, "the north perimeter wall must have a CollisionShape2D child")
	if wall_collision == null:
		return

	var wall_shape: RectangleShape2D = wall_collision.shape as RectangleShape2D
	if wall_shape == null:
		fail_test("the north perimeter wall's shape should be a RectangleShape2D")
		return

	# The wall's player-facing (south) surface — same derivation as
	# test_the_built_north_boundary_actually_uses_the_derived_inset() above.
	var facing_surface: float = (
			wall.position.y + wall_collision.position.y + wall_shape.size.y / 2.0)

	var collider: Rect2 = CollisionProbe.player_collider_extent(player)
	var bounds: Rect2 = area.get_bounds_px()

	await wait_physics_frames(2)

	# Search only the short band just south of the wall face — APPROACH_OFFSET_PX
	# plus a little slack — rather than the area's full height: this needs a
	# lane that's clear for a 48px approach, not a lane clear top-to-bottom,
	# and searching the smaller band is far less likely to be defeated by
	# unrelated clutter elsewhere on the map.
	var clear_x: float = CollisionProbe.find_clear_column(
			area, collider, facing_surface, facing_surface + APPROACH_OFFSET_PX + 20.0,
			bounds.position.x + 16.0, bounds.end.x - 16.0)
	assert_false(is_nan(clear_x),
			("no obstacle-free column exists in the %.0fpx band south of the north wall — " +
			"cannot attribute a stop to the wall without a clean approach to it.")
					% [APPROACH_OFFSET_PX + 20.0])
	if is_nan(clear_x):
		return

	var start := Vector2(clear_x, facing_surface + APPROACH_OFFSET_PX)
	var result: Dictionary = _drive_from(player, start, "move_up")

	var leading_edge: float = player.global_position.y + collider.position.y
	assert_almost_eq(leading_edge, facing_surface, 1.0,
			("driving north into the meadow's perimeter wall stopped the player's leading " +
			"collider edge at y=%.2f, but the wall's own geometry says it should be y=%.2f " +
			"(travelled %.1fpx of an unobstructed %.1fpx). A movement collider must stop " +
			"exactly at the wall face it collides with, regardless of what else is on the " +
			"player's scene tree.")
					% [leading_edge, facing_surface, result["traveled_px"], result["unobstructed_px"]])
