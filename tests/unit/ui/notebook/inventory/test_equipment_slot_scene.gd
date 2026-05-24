## test_equipment_slot_scene.gd
## Scene-as-data contract tests for equipment_slot.tscn (Slice 2).
##
## WHAT THESE TESTS GUARD
## ----------------------
## equipment_slot.tscn declares the static children SlotLabel and IconRect as
## saved editor nodes. These tests confirm those named nodes exist and have the
## correct types so that @onready refs in the script can never silently produce
## null references.
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
	# SlotLabel shows the slot name ("Boots", "Gloves", etc.) when the slot is
	# empty. _update_display() toggles its visibility. After the migration the
	# script will reference it via @onready or a named-node lookup rather than
	# building it in _ready() — if the name is wrong or the node is absent,
	# _update_display() will silently do nothing and the slot will always appear
	# blank regardless of whether it is empty or filled.
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
	# equipped items will never show their icon — a silent regression that only
	# becomes apparent during visual QA long after the migration PR lands.
	var instance: Control = _make_scene_instance()

	var node: Node = instance.find_child("IconRect", true, false)
	assert_not_null(node,
			"equipment_slot.tscn must declare a node named 'IconRect'")
	if node == null:
		return
	assert_true(node is TextureRect,
			"'IconRect' must be a TextureRect, got %s" % node.get_class())
