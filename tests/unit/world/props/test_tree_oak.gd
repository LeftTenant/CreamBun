## test_tree_oak.gd
## Unit tests for world/props/tree_oak.tscn — Slice 7 of the world-collision
## feature ("Tree: footprint ≠ silhouette").
##
## The oak is the first prop where the design's central claim (design doc
## §8.2-§8.3) is genuinely load-bearing: a wide canopy sits over a one-tile
## trunk, and the collider must track the trunk's footprint, never the
## canopy's silhouette. WorldProp's own generation math (RectangleShape2D
## sizing/positioning from `footprint`) is already covered exhaustively by
## tests/unit/world/props/shared/test_world_prop.gd — this file does not
## repeat that. It only checks what is specific to THIS scene: the authored
## `footprint` value, and the two placeholder visual children's geometry
## (canopy wider + higher than the trunk, trunk sized to the footprint), per
## design doc §7.1's honesty rules and §8.3's rejected-alternative concern.
##
## NODE STRUCTURE (this slice's own scene deliverable — see
## tests/integration/world/props/test_tree_oak.gd and
## tests/integration/world/test_tree_placement.gd for the physics-level
## and world.tscn-placement counterparts):
##   TreeOak (WorldProp — StaticBody2D)
##   ├── Canopy            (Polygon2D — wide green blob, offset well above
##   │                       the ground anchor)
##   ├── Trunk             (Polygon2D — brown, near the ground anchor, sized
##   │                       to roughly the 1x1 footprint's screen extent)
##   └── CollisionShape2D  (auto-populated by WorldProp, never hand-edited)
## Two named visual children (rather than boulder's single "find the other
## child" trick) because this scene needs to distinguish trunk from canopy
## geometrically, not just find "the" placeholder.
##
## Design reference: docs/features/world-collision/design.md §7, §7.1, §8.1,
## §8.2, §8.3
## Test plan: docs/features/world-collision/slice-7-tree-test-plan.md
##
## Requires GUT: https://github.com/bitwes/Gut
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gselect=test_tree_oak.gd -gexit

class_name TestTreeOak
extends GutTest


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const SCENE_PATH: String = "res://world/props/tree_oak.tscn"

## Node names this slice's scene is expected to use — see the class doc's
## NODE STRUCTURE above.
const CANOPY_NODE_NAME: String = "Canopy"
const TRUNK_NODE_NAME: String = "Trunk"

## One tile's screen extent (design doc §4) — the footprint's own size, used
## as the yardstick both the trunk (should roughly match it) and the canopy
## (should clearly exceed it) are compared against.
const TILE_SIZE: Vector2 = Vector2(32.0, 16.0)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Instantiate tree_oak.tscn and add it to the tree so @onready resolves.
## Autofreed at test teardown.
## @return the instantiated TreeOak root node, or null (with a failed
## assertion already recorded) if the scene can't be loaded/instantiated.
func _make_tree() -> WorldProp:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	assert_not_null(packed,
			"world/props/tree_oak.tscn should load as a PackedScene — this is Slice 7's own "
			+ "scene deliverable")
	if packed == null:
		return null

	var instance: WorldProp = packed.instantiate() as WorldProp
	assert_not_null(instance,
			"tree_oak.tscn's root should instantiate as a WorldProp (i.e. use world_prop.gd as "
			+ "its script, per design doc §7's node tree)")
	if instance == null:
		return null

	add_child_autofree(instance)
	return instance


## Fetch a named Polygon2D child, failing with a descriptive message if it's
## missing or the wrong type.
func _get_polygon_child(tree: WorldProp, child_name: String) -> Polygon2D:
	var node: Node = tree.get_node_or_null(child_name)
	assert_not_null(node,
			(
			"tree_oak.tscn should have a child named '%s' — see this file's NODE "
			+ "STRUCTURE doc comment"
			) % [child_name])
	if node == null:
		return null

	var polygon: Polygon2D = node as Polygon2D
	assert_not_null(polygon,
			"'%s' should be a Polygon2D (design doc §7.1's placeholder-shape convention)"
			% [child_name])
	return polygon


## Compute a Polygon2D's bounding rect in ITS PARENT's local coordinate space
## (i.e. TreeOak-local), combining the polygon's own point data with the
## node's `position` offset. Mirrors
## tests/integration/world/props/test_boulder.gd's _get_local_bounding_rect()
## (duplicated rather than shared — GUT test files are standalone scripts
## with no natural place to share a helper across unit/ and integration/).
## Returns an empty Rect2 if the polygon has no points.
func _get_local_bounding_rect(polygon: Polygon2D) -> Rect2:
	var points: PackedVector2Array = polygon.polygon
	if points.size() == 0:
		return Rect2()

	var min_pt: Vector2 = points[0]
	var max_pt: Vector2 = points[0]
	for point in points:
		min_pt.x = minf(min_pt.x, point.x)
		min_pt.y = minf(min_pt.y, point.y)
		max_pt.x = maxf(max_pt.x, point.x)
		max_pt.y = maxf(max_pt.y, point.y)

	var rect := Rect2(min_pt, max_pt - min_pt)
	rect.position += polygon.position
	return rect


# ---------------------------------------------------------------------------
# Test 1 — footprint is a single tile of ground (design §8.2's oak example)
# ---------------------------------------------------------------------------

func test_footprint_is_one_by_one() -> void:
	var tree: WorldProp = _make_tree()
	if tree == null:
		return

	assert_eq(tree.footprint, Vector2i(1, 1),
			(
			"tree_oak.tscn's footprint should be Vector2i(1, 1) — an oak's trunk base occupies "
			+ "exactly one tile of ground (design doc §8.2: 'An oak tree is (1, 1): its trunk "
			+ "base.')"
			))


# ---------------------------------------------------------------------------
# Test 2 — the canopy is visibly wider than the footprint and offset above
#          the trunk (design §7.1's two honesty rules, applied to the tree
#          that makes them matter most)
# ---------------------------------------------------------------------------

func test_canopy_is_wider_than_footprint() -> void:
	# Width is translation-invariant, so this checks the polygon's own point
	# spread rather than needing to translate into parent space first.
	var tree: WorldProp = _make_tree()
	if tree == null:
		return

	var canopy: Polygon2D = _get_polygon_child(tree, CANOPY_NODE_NAME)
	if canopy == null:
		return

	var canopy_rect: Rect2 = _get_local_bounding_rect(canopy)
	assert_true(canopy_rect.size.x > 0.0,
			"Canopy's polygon should have a non-empty bounding width to compare against the "
			+ "one-tile footprint")
	if canopy_rect.size.x <= 0.0:
		return

	assert_true(canopy_rect.size.x > TILE_SIZE.x,
			(
			"Canopy's bounding width (%.1fpx) should exceed the one-tile footprint's width "
			+ "(%.1fpx) — design doc §8.2: 'The canopy is drawn far wider and the player walks "
			+ "behind it.' A canopy no wider than the footprint proves nothing about the "
			+ "footprint-vs-silhouette gap this slice exists to demonstrate."
			) % [canopy_rect.size.x, TILE_SIZE.x])


func test_canopy_is_positioned_above_trunk_not_centred_on_origin() -> void:
	# Design doc §7.1: "Anchor the placeholder exactly where the real sprite
	# will go — offset upward from the ground anchor (§8.1), never centred on
	# it." The ground anchor IS the node origin (§8.1), so the canopy's own
	# local `position.y` must be strictly negative (up-screen). Mirrors
	# tests/unit/world/props/test_boulder.gd's equivalent check.
	var tree: WorldProp = _make_tree()
	if tree == null:
		return

	var canopy: Polygon2D = _get_polygon_child(tree, CANOPY_NODE_NAME)
	if canopy == null:
		return

	assert_true(canopy.position.y < 0.0,
			(
			"Canopy's position.y (%.1f) should be strictly negative — offset up-screen from "
			+ "the ground anchor at the node origin. A value of 0.0 or positive would mean "
			+ "it's centred on (or below) the anchor, which design doc §7.1 explicitly calls "
			+ "out as dishonest."
			) % [canopy.position.y])


# ---------------------------------------------------------------------------
# Test 3 — the trunk sits at/near the ground anchor, sized to the footprint's
#          screen extent, and is distinctly smaller than the canopy
# ---------------------------------------------------------------------------

func test_trunk_is_sized_to_footprint_extent_near_origin() -> void:
	var tree: WorldProp = _make_tree()
	if tree == null:
		return

	var trunk: Polygon2D = _get_polygon_child(tree, TRUNK_NODE_NAME)
	if trunk == null:
		return

	var trunk_rect: Rect2 = _get_local_bounding_rect(trunk)
	assert_true(trunk_rect.size.x > 0.0 and trunk_rect.size.y > 0.0,
			"Trunk's polygon should have a non-empty bounding rect to compare against the "
			+ "footprint's screen extent")
	if trunk_rect.size.x <= 0.0 or trunk_rect.size.y <= 0.0:
		return

	# "Roughly" the footprint's 32x16 extent — generous tolerance since this
	# is placeholder art (design doc §7.1), not a precisely-authored shape.
	# The collider itself (WorldProp._rebuild_collider()) is exactly 32x16;
	# the trunk's VISUAL should read as "about one tile", not match to the
	# pixel.
	assert_between(trunk_rect.size.x, TILE_SIZE.x * 0.5, TILE_SIZE.x * 1.5,
			(
			"Trunk's bounding width (%.1fpx) should be roughly the footprint's one-tile width "
			+ "(%.1fpx) — a trunk drawn far wider or narrower than the ground it actually "
			+ "occupies would misrepresent the footprint to a player."
			) % [trunk_rect.size.x, TILE_SIZE.x])

	# The trunk should sit close to the anchor (origin), i.e. its bounding
	# rect should span roughly y ∈ [-16, 0] (the collider's own span, per
	# WorldProp._rebuild_collider() — TILE_SIZE.y = 16 for a 1x1 footprint),
	# not float far above (that would be canopy territory) or dip far below
	# (behind the camera-facing edge).
	assert_between(trunk_rect.position.y, -TILE_SIZE.y * 2.0, TILE_SIZE.y * 0.5,
			(
			"Trunk's bounding rect top (local y = %.1f) should sit near the ground anchor's "
			+ "collider span (y ∈ [-16, 0] for a 1x1 footprint) — a trunk drawn well above this "
			+ "would be encroaching on canopy territory instead of representing the ground "
			+ "contact point."
			) % [trunk_rect.position.y])


func test_trunk_is_distinctly_smaller_than_canopy() -> void:
	# The two placeholders must actually diverge in size — a trunk drawn as
	# large as the canopy would defeat the entire point of this slice (design
	# doc §8.3: the collider tracks the trunk/footprint, never the canopy).
	var tree: WorldProp = _make_tree()
	if tree == null:
		return

	var trunk: Polygon2D = _get_polygon_child(tree, TRUNK_NODE_NAME)
	var canopy: Polygon2D = _get_polygon_child(tree, CANOPY_NODE_NAME)
	if trunk == null or canopy == null:
		return

	var trunk_rect: Rect2 = _get_local_bounding_rect(trunk)
	var canopy_rect: Rect2 = _get_local_bounding_rect(canopy)
	assert_true(trunk_rect.size.x > 0.0 and canopy_rect.size.x > 0.0,
			"both Trunk and Canopy need non-empty bounding rects to compare sizes")
	if trunk_rect.size.x <= 0.0 or canopy_rect.size.x <= 0.0:
		return

	assert_true(canopy_rect.size.x > trunk_rect.size.x,
			(
			"Canopy's bounding width (%.1fpx) should be clearly larger than Trunk's (%.1fpx) — "
			+ "a placeholder tree must be drawn with a wide canopy over a one-tile trunk (design "
			+ "doc §7.1), not two shapes of similar size."
			) % [canopy_rect.size.x, trunk_rect.size.x])
