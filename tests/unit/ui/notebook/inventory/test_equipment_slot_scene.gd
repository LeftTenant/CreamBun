## test_equipment_slot_scene.gd
## Scene-as-data contract tests for equipment_slot.tscn.
##
## WHAT THESE TESTS GUARD
## ----------------------
## equipment_slot.tscn declares the static children SlotLabel and IconRect as
## saved editor nodes. These tests confirm those named nodes exist and have the
## correct types so that @onready refs in the script can never silently produce
## null references.
##
## --- ISSUE #7 ADDITIONS ---
## Equipping an item used to hide SlotLabel entirely (replaced by the icon),
## so the slot-name heading disappeared once filled. The fix keeps SlotLabel
## visible as a permanent heading and adds three more named nodes:
##   - IconFrame      — a framed container beside the heading that holds IconRect
##   - ItemNameLabel  — shows the equipped item's display name, but only while
##                       the slot is selected
##   - SelectionRect  — the selection highlight, mirroring inventory_row.tscn's
##                       SelectionRect convention
## These tests currently FAIL because equipment_slot.tscn does not yet declare
## IconFrame, ItemNameLabel, or SelectionRect.
##
## Requires GUT: https://github.com/bitwes/Gut
## Install via Godot Asset Library (search "GUT - Godot Unit Testing").
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd -gselect=test_equipment_slot_scene.gd -gexit

class_name TestEquipmentSlotScene
extends GutTest


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const SCENE_PATH: String = "res://ui/notebook/inventory/equipment_slot.tscn"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Instantiate SCENE_PATH and add it to the scene tree so @onready vars and
## child nodes are fully resolved. The instance is autofreed after the test.
##
## @return the instantiated EquipmentSlot root node
func _make_scene_instance() -> Control:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	var instance: Control = packed.instantiate() as Control
	add_child_autofree(instance)
	return instance


# ---------------------------------------------------------------------------
# Test 1 — Scene file loads as a valid PackedScene
# ---------------------------------------------------------------------------

func test_scene_loads_without_error() -> void:
	# If the .tscn is corrupt or references a missing resource, load() returns
	# null. This gate test must pass before any instantiation tests can run.
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	assert_not_null(packed,
			"equipment_slot.tscn must load as a non-null PackedScene")


# ---------------------------------------------------------------------------
# Test 2 — Scene declares a node named SlotLabel of type Label
# ---------------------------------------------------------------------------

func test_scene_declares_slot_label() -> void:
	# SlotLabel is the slot-name heading ("Boots", "Gloves", etc.). Per issue #7
	# it must remain visible at all times — including once an item is equipped —
	# so the player never loses track of which body region a filled slot
	# represents. The script references it via @onready; if the name is wrong
	# or the node is absent, _update_display() will silently do nothing and the
	# heading will never appear.
	var instance: Control = _make_scene_instance()

	var node: Node = instance.find_child("SlotLabel", true, false)
	assert_not_null(node,
			"equipment_slot.tscn must declare a node named 'SlotLabel'")
	if node == null:
		return
	assert_true(node is Label,
			"'SlotLabel' must be a Label, got %s" % node.get_class())


# ---------------------------------------------------------------------------
# Test 3 — Scene declares a node named IconRect of type TextureRect
# ---------------------------------------------------------------------------

func test_scene_declares_icon_rect() -> void:
	# IconRect shows the item icon when a slot is filled. _update_display() sets
	# its texture and toggles its visibility. A missing or mistyped node means
	# equipped items will never show their icon — a silent regression that would
	# only surface during visual QA.
	var instance: Control = _make_scene_instance()

	var node: Node = instance.find_child("IconRect", true, false)
	assert_not_null(node,
			"equipment_slot.tscn must declare a node named 'IconRect'")
	if node == null:
		return
	assert_true(node is TextureRect,
			"'IconRect' must be a TextureRect, got %s" % node.get_class())


# ---------------------------------------------------------------------------
# Test 4 — Scene declares a persistent framed icon area, IconFrame, that
#          contains IconRect (issue #7)
# ---------------------------------------------------------------------------

func test_scene_declares_icon_frame_containing_icon_rect() -> void:
	# Per issue #7's desired behavior, the equipped item's icon lives in a
	# persistent FRAMED area beside the heading — it no longer replaces
	# SlotLabel. IconFrame is that container; IconRect renders inside it.
	#
	# We don't prescribe IconFrame's exact Control subclass (PanelContainer,
	# Panel, etc. are all reasonable "frame" choices) — only that it exists,
	# is some kind of Control, and contains IconRect as a descendant.
	var instance: Control = _make_scene_instance()

	var frame: Node = instance.find_child("IconFrame", true, false)
	assert_not_null(frame,
			"equipment_slot.tscn must declare a node named 'IconFrame' (the framed icon area beside the heading)")
	if frame == null:
		return
	assert_true(frame is Control,
			"'IconFrame' must be a Control, got %s" % frame.get_class())

	var icon: Node = frame.find_child("IconRect", true, false)
	assert_not_null(icon,
			"'IconFrame' must contain 'IconRect' so the framed area can show the equipped item's icon")


# ---------------------------------------------------------------------------
# Test 5 — Scene declares ItemNameLabel, shown only while selected (issue #7)
# ---------------------------------------------------------------------------

func test_scene_declares_item_name_label_hidden_by_default() -> void:
	# ItemNameLabel appears UNDER the heading only while the slot is selected
	# (per issue #7's desired behavior). It must exist as a Label and start
	# hidden — set_selected(true) is what reveals it.
	var instance: Control = _make_scene_instance()

	var node: Node = instance.find_child("ItemNameLabel", true, false)
	assert_not_null(node,
			"equipment_slot.tscn must declare a node named 'ItemNameLabel'")
	if node == null:
		return
	assert_true(node is Label,
			"'ItemNameLabel' must be a Label, got %s" % node.get_class())
	assert_false((node as Label).visible,
			"'ItemNameLabel' must be hidden by default — set_selected(true) reveals it")


# ---------------------------------------------------------------------------
# Test 6 — Scene declares SelectionRect, the selection highlight (issue #7)
# ---------------------------------------------------------------------------

func test_scene_declares_selection_rect_hidden_by_default() -> void:
	# SelectionRect mirrors inventory_row.tscn's SelectionRect: a highlight
	# shown when set_selected(true) is called, hidden otherwise.
	var instance: Control = _make_scene_instance()

	var node: Node = instance.find_child("SelectionRect", true, false)
	assert_not_null(node,
			"equipment_slot.tscn must declare a node named 'SelectionRect'")
	if node == null:
		return
	assert_true(node is ColorRect,
			"'SelectionRect' must be a ColorRect, got %s" % node.get_class())
	assert_false((node as ColorRect).visible,
			"'SelectionRect' must be hidden by default — set_selected(true) reveals it")
