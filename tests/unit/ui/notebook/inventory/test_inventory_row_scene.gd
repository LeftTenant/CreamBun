## test_inventory_row_scene.gd
## Scene-as-data contract tests for inventory_row.tscn.
##
## WHAT THESE TESTS GUARD
## ----------------------
## inventory_row.tscn declares the static children SelectionRect, HBox, NameLabel,
## CountLabel, and WeightLabel as saved editor nodes. These tests confirm those
## named nodes exist and have the correct types, ensuring that @onready refs in
## the script never silently produce null.
##
## Requires GUT: https://github.com/bitwes/Gut
## Install via Godot Asset Library (search "GUT - Godot Unit Testing").
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd -gselect=test_inventory_row_scene.gd -gexit

class_name TestInventoryRowScene
extends GutTest


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const SCENE_PATH: String = "res://ui/notebook/inventory/inventory_row.tscn"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Instantiate SCENE_PATH and add it to the scene tree so @onready vars and
## child nodes are fully resolved. The instance is autofreed after the test.
##
## @return the instantiated InventoryRow root node
func _make_scene_instance() -> Control:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	var instance: Control = packed.instantiate() as Control
	add_child_autofree(instance)
	return instance


# ---------------------------------------------------------------------------
# Test 1 — Scene file loads as a valid PackedScene
# ---------------------------------------------------------------------------

func test_scene_loads_without_error() -> void:
	# Gate test: if the .tscn is corrupt or missing a resource, load() returns null
	# and every subsequent instantiation test would crash instead of failing cleanly.
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	assert_not_null(packed,
			"inventory_row.tscn must load as a non-null PackedScene")


# ---------------------------------------------------------------------------
# Test 2 — Scene declares a node named SelectionRect of type ColorRect
# ---------------------------------------------------------------------------

func test_scene_declares_selection_rect() -> void:
	# SelectionRect is the warm-cream highlight that set_selected(true) makes
	# visible. The script references it via @onready rather than assigning it in
	# _ready(). A missing or mistyped node means clicking a
	# row produces no visual feedback — a silent regression invisible to unit tests
	# that only check data changes.
	var instance: Control = _make_scene_instance()

	var node: Node = instance.find_child("SelectionRect", true, false)
	assert_not_null(node,
			"inventory_row.tscn must declare a node named 'SelectionRect'")
	if node == null:
		return
	assert_true(node is ColorRect,
			"'SelectionRect' must be a ColorRect, got %s" % node.get_class())


# ---------------------------------------------------------------------------
# Test 3 — Scene declares a node named HBox of type HBoxContainer
# ---------------------------------------------------------------------------

func test_scene_declares_hbox() -> void:
	# HBox is the horizontal layout container that holds NameLabel, CountLabel,
	# and WeightLabel side by side. Without it the three labels have no container
	# to anchor their horizontal arrangement and will stack vertically or collapse.
	var instance: Control = _make_scene_instance()

	var node: Node = instance.find_child("HBox", true, false)
	assert_not_null(node,
			"inventory_row.tscn must declare a node named 'HBox'")
	if node == null:
		return
	assert_true(node is HBoxContainer,
			"'HBox' must be an HBoxContainer, got %s" % node.get_class())


# ---------------------------------------------------------------------------
# Test 4 — Scene declares NameLabel, CountLabel, WeightLabel inside HBox
# ---------------------------------------------------------------------------

func test_scene_declares_name_count_weight_labels_inside_hbox() -> void:
	# These three Labels are the visible data content of every inventory row.
	# setup() writes to them directly by name — a misspelled or relocated node
	# would silently leave the row blank. We assert all three in one test because
	# they form a single named-node group: all must exist inside HBox.
	var instance: Control = _make_scene_instance()

	var hbox: Node = instance.find_child("HBox", true, false)
	if hbox == null:
		# If HBox itself is absent, fail with a clear message and stop here — the
		# individual label assertions below would all fail with confusing messages.
		assert_not_null(hbox,
				"Cannot verify label children — 'HBox' node is missing from inventory_row.tscn")
		return

	for label_name: String in ["NameLabel", "CountLabel", "WeightLabel"]:
		# search=true, owned=false so we find nodes at any depth inside HBox
		var node: Node = hbox.find_child(label_name, true, false)
		assert_not_null(node,
				"inventory_row.tscn must declare a node named '%s' inside HBox" % label_name)
		if node == null:
			continue
		assert_true(node is Label,
				"'%s' must be a Label, got %s" % [label_name, node.get_class()])


# ---------------------------------------------------------------------------
# Test 5 — CountLabel is hidden by default
# ---------------------------------------------------------------------------

func test_count_label_is_hidden_by_default() -> void:
	# CountLabel is only shown when stack.count > 1. setup() controls its visibility
	# explicitly, but the default (scene-defined) state should be hidden so single-
	# item stacks don't flash a stale count badge before setup() is called.
	#
	# This is a static-scene property test, not a runtime behavior test — if the
	# scene author accidentally enables CountLabel in the editor, this test catches
	# it before it reaches QA.
	var instance: Control = _make_scene_instance()

	var node: Node = instance.find_child("CountLabel", true, false)
	if node == null:
		# Node absence is already caught by test 4; skip the visibility check to
		# avoid a redundant failure message.
		pending("CountLabel not found — covered by test_scene_declares_name_count_weight_labels_inside_hbox")
		return
	assert_false((node as Label).visible,
			"CountLabel must be hidden by default in inventory_row.tscn (setup() controls visibility)")
