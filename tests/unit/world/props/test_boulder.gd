## test_boulder.gd
## Unit tests for world/props/boulder.tscn — Slice 6 of the world-collision
## feature ("Boulder: first real prop, proven end-to-end").
##
## Boulder is the first CONCRETE WorldProp (world/props/shared/world_prop.gd,
## Slice 5). WorldProp's own generation math (RectangleShape2D sizing/
## positioning from `footprint`) is already covered exhaustively by
## tests/unit/world/props/shared/test_world_prop.gd — this file does not
## repeat that. It only checks what is specific to THIS scene: the authored
## `footprint` value, and the placeholder visual child's anchoring, per design
## doc §7.1's two rules for honest placeholders.
##
## Written test-first, ahead of world/props/boulder.tscn (this slice's own
## implementation deliverable) — the scene now exists and all tests below
## pass against it.
##
## Design reference: docs/features/world-collision/design.md §7, §7.1, §8.1
## Test plan: docs/features/world-collision/slice-6-boulder-test-plan.md
##
## Requires GUT: https://github.com/bitwes/Gut
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gselect=test_boulder.gd -gexit

class_name TestBoulder
extends GutTest


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const SCENE_PATH: String = "res://world/props/boulder.tscn"

## Node name WorldProp's @onready _collision lookup expects
## ($CollisionShape2D — world_prop.gd line ~59). The placeholder visual is
## whatever OTHER child the scene has, per design doc §7's node tree:
## Boulder (WorldProp) -> [visual child, CollisionShape2D].
const COLLISION_NODE_NAME: String = "CollisionShape2D"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Instantiate boulder.tscn and add it to the tree so @onready resolves.
## Autofreed at test teardown.
## @return the instantiated Boulder root node, or null (with a failed
## assertion already recorded) if the scene can't be loaded/instantiated.
func _make_boulder() -> WorldProp:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	assert_not_null(packed,
			"world/props/boulder.tscn should load as a PackedScene — this is Slice 6's own "
			+ "scene deliverable")
	if packed == null:
		return null

	var instance: WorldProp = packed.instantiate() as WorldProp
	assert_not_null(instance,
			"boulder.tscn's root should instantiate as a WorldProp (i.e. use world_prop.gd "
			+ "as its script, per design doc §7's node tree)")
	if instance == null:
		return null

	add_child_autofree(instance)
	return instance


## Find the scene's placeholder visual child — the one child of Boulder that
## is NOT the CollisionShape2D WorldProp itself manages. Per design doc §7's
## node tree, boulder.tscn has exactly two children: the visual and the
## (auto-populated) collider.
##
## Returns null (with no assertion recorded — callers assert on the result
## themselves, since "which case failed" gives a more specific message) if no
## such child exists.
func _find_visual_child(boulder: WorldProp) -> CanvasItem:
	for child in boulder.get_children():
		if child.name == COLLISION_NODE_NAME:
			continue
		if child is CanvasItem:
			return child as CanvasItem
	return null


# ---------------------------------------------------------------------------
# Test 1 — footprint is a single tile of ground (design §7's concrete values)
# ---------------------------------------------------------------------------

func test_footprint_is_one_by_one() -> void:
	var boulder: WorldProp = _make_boulder()
	if boulder == null:
		return

	assert_eq(boulder.footprint, Vector2i(1, 1),
			(
			"boulder.tscn's footprint should be Vector2i(1, 1) — a boulder occupies exactly "
			+ "one tile of ground (design doc §7's concrete values, slices.md Slice 6)."
			))


# ---------------------------------------------------------------------------
# Test 2 — the placeholder visual is anchored above the ground anchor, never
#          centred on it (design §7.1's first honesty rule)
# ---------------------------------------------------------------------------

func test_placeholder_visual_is_anchored_above_origin_not_centred() -> void:
	# Design doc §7.1: "Anchor the placeholder exactly where the real sprite
	# will go — offset upward from the ground anchor (§8.1), never centred on
	# it." The ground anchor IS the node origin (§8.1), so the visual child's
	# local `position.y` must be strictly negative (up-screen) — 0.0 would
	# mean it's centred on the anchor, which is exactly what §7.1 forbids.
	# This mirrors how test_world_prop.gd checks the generated collider's
	# position.y the same way (a node-position offset, not baked into
	# authored geometry).
	var boulder: WorldProp = _make_boulder()
	if boulder == null:
		return

	var visual: CanvasItem = _find_visual_child(boulder)
	assert_not_null(visual,
			(
			"boulder.tscn should have exactly one non-CollisionShape2D child — the "
			+ "placeholder visual (a Polygon2D or ColorRect grey ellipse, per design doc §7.1)"
			))
	if visual == null:
		return

	# CanvasItem itself declares no `position` (Node2D and Control each add their
	# own), so branch by type rather than reach for it dynamically via Object.get().
	var position_y: float
	if visual is Node2D:
		position_y = (visual as Node2D).position.y
	elif visual is Control:
		position_y = (visual as Control).position.y
	else:
		fail_test(
				"placeholder visual child is a %s — expected a Node2D-derived node "
				% [visual.get_class()]
				+ "(e.g. Polygon2D) or a Control (e.g. ColorRect) so its position.y is "
				+ "checkable, per design doc §7.1.")
		return

	assert_true(position_y < 0.0,
			(
			"the placeholder visual's position.y (%.1f) should be strictly negative — offset "
			+ "up-screen from the ground anchor at the node origin. A value of 0.0 or positive "
			+ "would mean it's centred on (or below) the anchor, which design doc §7.1 "
			+ "explicitly calls out as dishonest: real art would then sort differently once it "
			+ "replaces this placeholder."
			) % [position_y])
