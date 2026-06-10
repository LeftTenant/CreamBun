## test_quest_row_scene.gd
## Scene-as-data contract tests for quest_row.tscn.
##
## WHAT THESE TESTS GUARD
## ----------------------
## quest_row.tscn declares TitleLabel and ViewButton as saved editor nodes
## rather than building them in _ready(). These tests confirm those named nodes
## exist and have the correct types, so @onready refs in quest_row.gd never
## silently produce null.
##
## WHY SCENE-AS-DATA TESTS MATTER
## --------------------------------
## A bare find_child("ViewButton", true, false) returns null with no editor
## warning if the node was accidentally renamed or deleted. A test that loads
## the PackedScene and walks the tree catches that at CI time rather than
## during manual QA — at which point the Quests tab would silently show rows
## that cannot be selected.
##
## Requires GUT: https://github.com/bitwes/Gut
## Install via Godot Asset Library (search "GUT - Godot Unit Testing").
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd -gselect=test_quest_row_scene.gd -gexit

class_name TestQuestRowScene
extends GutTest


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Canonical path for the scene under test. A constant makes it easy to update
# if the file moves and ensures every test in this file references the same path.
const SCENE_PATH: String = "res://ui/notebook/quests/quest_row.tscn"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Instantiate SCENE_PATH and add it to the scene tree so @onready vars and
## child nodes are fully resolved. The instance is autofreed after the test.
##
## @return the instantiated QuestRow root node
func _make_scene_instance() -> Control:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	var instance: Control = packed.instantiate() as Control
	add_child_autofree(instance)
	return instance


# ---------------------------------------------------------------------------
# Test 1 — Scene file loads as a valid PackedScene
# ---------------------------------------------------------------------------

func test_scene_loads_without_error() -> void:
	# Gate test: if the .tscn is corrupt or references a missing resource,
	# load() returns null and every subsequent instantiation test would crash
	# rather than fail cleanly. Run this first to get one clear signal.
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	assert_not_null(packed,
			"quest_row.tscn must load as a non-null PackedScene")


# ---------------------------------------------------------------------------
# Test 2 — Root is a QuestRow
# ---------------------------------------------------------------------------

func test_root_is_quest_row() -> void:
	# The root must have quest_row.gd attached so quests_tab.gd can call
	# setup(quest, status) after instantiation without a type error.
	# https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html#inheritance
	var instance: Control = _make_scene_instance()

	assert_true(instance is QuestRow,
			"quest_row.tscn root must be a QuestRow")


# ---------------------------------------------------------------------------
# Test 3 — Scene declares a TitleLabel Label
# ---------------------------------------------------------------------------

func test_scene_declares_title_label() -> void:
	# TitleLabel is the Label that setup() fills with quest.title. The script
	# references it via @onready rather than assigning it in _ready(). A missing or
	# mistyped node would silently leave every row's title blank — a regression
	# invisible to unit tests that only inspect data structures.
	var instance: Control = _make_scene_instance()

	var node: Node = instance.find_child("TitleLabel", true, false)
	assert_not_null(node,
			"quest_row.tscn must declare a node named 'TitleLabel'")
	if node == null:
		return
	assert_true(node is Label,
			"'TitleLabel' must be a Label, got %s" % node.get_class())


# ---------------------------------------------------------------------------
# Test 4 — Scene declares a ViewButton Button
# ---------------------------------------------------------------------------

func test_scene_declares_view_button() -> void:
	# ViewButton is the per-row select affordance that the player presses to
	# open quest detail. It lives in the row scene rather than being built per-row
	# inside _add_quest_row() in quests_tab.gd. A missing button
	# would silently make every quest row un-selectable — a critical regression
	# that would not produce any runtime error or logged warning.
	var instance: Control = _make_scene_instance()

	var node: Node = instance.find_child("ViewButton", true, false)
	assert_not_null(node,
			"quest_row.tscn must declare a node named 'ViewButton'")
	if node == null:
		return
	assert_true(node is Button,
			"'ViewButton' must be a Button, got %s" % node.get_class())
