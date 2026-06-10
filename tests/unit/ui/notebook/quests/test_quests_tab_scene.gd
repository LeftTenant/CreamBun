## test_quests_tab_scene.gd
## Scene-as-data contract tests for quests_tab.tscn.
##
## WHAT THESE TESTS GUARD
## ----------------------
## quests_tab.tscn declares the full static layout as saved editor nodes:
## LeftPage with ActiveSection, CompletedSeparator, CompletedSection;
## RightPage with QuestDetail (TitleLabel, DescriptionLabel, ObjectivesContainer)
## and a Placeholder label. These tests load the .tscn and walk the instantiated
## tree to confirm every named node is present and typed correctly.
##
## WHY SCENE-AS-DATA TESTS MATTER
## --------------------------------
## The contract between quests_tab.gd and quests_tab.tscn is not enforced by
## the type system. find_child("Placeholder", true, false) returns null at
## runtime with no editor warning if a node is accidentally renamed or deleted.
## A test that loads the PackedScene and walks the tree catches that breakage at
## CI time rather than during manual QA.
##
## Requires GUT: https://github.com/bitwes/Gut
## Install via Godot Asset Library (search "GUT - Godot Unit Testing").
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd -gselect=test_quests_tab_scene.gd -gexit

class_name TestQuestsTabScene
extends GutTest


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Canonical path for the scene under test. A constant makes it easy to update
# if the file moves and ensures every test in this file references the same path.
const SCENE_PATH: String = "res://ui/notebook/quests/quests_tab.tscn"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Instantiate SCENE_PATH and add it to the scene tree so @onready vars and
## child nodes are fully resolved. The instance is autofreed after the test.
##
## @return the instantiated QuestsTab root node added as a child of the test
func _make_scene_instance() -> Control:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	var instance: Control = packed.instantiate() as Control
	add_child_autofree(instance)
	return instance


# ---------------------------------------------------------------------------
# Test 1 — Scene file loads as a valid PackedScene
# ---------------------------------------------------------------------------

func test_scene_loads_without_error() -> void:
	# Gate test: if the .tscn is corrupt, mis-formatted, or references a missing
	# resource, load() returns null and every subsequent test would crash rather
	# than fail cleanly. Run this first to get a single clear signal.
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	assert_not_null(packed,
			"quests_tab.tscn must load as a non-null PackedScene")


# ---------------------------------------------------------------------------
# Test 2 — Root is a QuestsTab / NotebookTab
# ---------------------------------------------------------------------------

func test_root_is_quests_tab_and_notebook_tab() -> void:
	# The root must have quests_tab.gd attached so the notebook controller can
	# call populate_left / populate_right polymorphically. Checking is NotebookTab
	# covers both the script and the inheritance chain in one assertion.
	var instance: Control = _make_scene_instance()

	assert_true(instance is QuestsTab,
			"quests_tab.tscn root must be a QuestsTab")
	assert_true(instance is NotebookTab,
			"quests_tab.tscn root must be a NotebookTab (QuestsTab must extend NotebookTab)")


# ---------------------------------------------------------------------------
# Test 3 — Scene declares a LeftPage Control
# ---------------------------------------------------------------------------

func test_scene_declares_left_page() -> void:
	# LeftPage is the subtree root that populate_left() reparents into the
	# notebook's page. If it is renamed or deleted the left side will be
	# permanently blank with no runtime error — silent layout regression.
	var instance: Control = _make_scene_instance()

	var node: Node = instance.find_child("LeftPage", true, false)
	assert_not_null(node,
			"quests_tab.tscn must declare a node named 'LeftPage'")
	if node == null:
		return
	assert_true(node is Control,
			"'LeftPage' must be a Control (or subclass), got %s" % node.get_class())


# ---------------------------------------------------------------------------
# Test 4 — LeftPage contains ActiveSection and CompletedSection VBoxContainers
# ---------------------------------------------------------------------------

func test_left_page_contains_active_and_completed_sections() -> void:
	# ActiveSection holds ACTIVE quest rows; CompletedSection holds COMPLETED.
	# Both must be VBoxContainers so the rows stack vertically with automatic
	# spacing. A missing or mistyped container silently produces an empty section.
	var instance: Control = _make_scene_instance()

	var left: Node = instance.find_child("LeftPage", true, false)
	if left == null:
		pending("LeftPage not found — covered by test_scene_declares_left_page")
		return

	for section_name: String in ["ActiveSection", "CompletedSection"]:
		var node: Node = left.find_child(section_name, true, false)
		assert_not_null(node,
				"LeftPage must contain a node named '%s'" % section_name)
		if node == null:
			continue
		assert_true(node is VBoxContainer,
				"'%s' must be a VBoxContainer, got %s" % [section_name, node.get_class()])


# ---------------------------------------------------------------------------
# Test 5 — LeftPage contains a CompletedSeparator Label
# ---------------------------------------------------------------------------

func test_left_page_contains_completed_separator_label() -> void:
	# CompletedSeparator is the divider Label between ACTIVE and COMPLETED
	# sections. It is shown/hidden in code based on whether both buckets are
	# non-empty. The node must be a Label so the tab can toggle its visibility.
	var instance: Control = _make_scene_instance()

	var left: Node = instance.find_child("LeftPage", true, false)
	if left == null:
		pending("LeftPage not found — covered by test_scene_declares_left_page")
		return

	var node: Node = left.find_child("CompletedSeparator", true, false)
	assert_not_null(node,
			"LeftPage must contain a node named 'CompletedSeparator'")
	if node == null:
		return
	assert_true(node is Label,
			"'CompletedSeparator' must be a Label, got %s" % node.get_class())


# ---------------------------------------------------------------------------
# Test 6 — Scene declares a RightPage Control
# ---------------------------------------------------------------------------

func test_scene_declares_right_page() -> void:
	# RightPage is the subtree root that populate_right() reparents into the
	# notebook's right page. Without this node the detail view has nowhere to
	# render, silently leaving the right page blank.
	var instance: Control = _make_scene_instance()

	var node: Node = instance.find_child("RightPage", true, false)
	assert_not_null(node,
			"quests_tab.tscn must declare a node named 'RightPage'")
	if node == null:
		return
	assert_true(node is Control,
			"'RightPage' must be a Control (or subclass), got %s" % node.get_class())


# ---------------------------------------------------------------------------
# Test 7 — RightPage contains a QuestDetail VBoxContainer
# ---------------------------------------------------------------------------

func test_right_page_contains_quest_detail_vbox() -> void:
	# QuestDetail is the VBoxContainer that holds TitleLabel, DescriptionLabel,
	# and ObjectivesContainer. It must be a VBoxContainer so its children stack
	# vertically. The script references it via @onready rather than building it in
	# _refresh_right_page().
	var instance: Control = _make_scene_instance()

	var right: Node = instance.find_child("RightPage", true, false)
	if right == null:
		pending("RightPage not found — covered by test_scene_declares_right_page")
		return

	var node: Node = right.find_child("QuestDetail", true, false)
	assert_not_null(node,
			"RightPage must contain a node named 'QuestDetail'")
	if node == null:
		return
	assert_true(node is VBoxContainer,
			"'QuestDetail' must be a VBoxContainer, got %s" % node.get_class())


# ---------------------------------------------------------------------------
# Test 8 — QuestDetail contains TitleLabel, DescriptionLabel, ObjectivesContainer
# ---------------------------------------------------------------------------

func test_quest_detail_contains_title_description_objectives() -> void:
	# TitleLabel and DescriptionLabel are the Labels that populate_right() fills
	# with quest.title and quest.description. ObjectivesContainer is the VBox
	# into which objective lines are added dynamically. All three must exist as
	# named nodes so the script can reference them by @onready.
	var instance: Control = _make_scene_instance()

	var detail: Node = instance.find_child("QuestDetail", true, false)
	if detail == null:
		pending("QuestDetail not found — covered by test_right_page_contains_quest_detail_vbox")
		return

	for label_name: String in ["TitleLabel", "DescriptionLabel"]:
		var node: Node = detail.find_child(label_name, true, false)
		assert_not_null(node,
				"QuestDetail must contain a node named '%s'" % label_name)
		if node == null:
			continue
		assert_true(node is Label,
				"'%s' must be a Label, got %s" % [label_name, node.get_class()])

	var objectives: Node = detail.find_child("ObjectivesContainer", true, false)
	assert_not_null(objectives,
			"QuestDetail must contain a node named 'ObjectivesContainer'")
	if objectives == null:
		return
	assert_true(objectives is VBoxContainer,
			"'ObjectivesContainer' must be a VBoxContainer, got %s" % objectives.get_class())


# ---------------------------------------------------------------------------
# Test 9 — RightPage contains a Placeholder Label with "select a quest" text
# ---------------------------------------------------------------------------

func test_right_page_contains_placeholder_label_with_select_text() -> void:
	# Placeholder is the editor-defined "no selection" prompt so the right page
	# is never blank before the player picks a quest. The text must contain
	# "select a quest" (case-insensitive) to match the existing test's predicate
	# and the player-facing copy confirmed during design sign-off.
	var instance: Control = _make_scene_instance()

	var right: Node = instance.find_child("RightPage", true, false)
	if right == null:
		pending("RightPage not found — covered by test_scene_declares_right_page")
		return

	var node: Node = right.find_child("Placeholder", true, false)
	assert_not_null(node,
			"RightPage must contain a node named 'Placeholder'")
	if node == null:
		return
	assert_true(node is Label,
			"'Placeholder' must be a Label, got %s" % node.get_class())

	var lbl: Label = node as Label
	assert_true(lbl.text.to_lower().contains("select a quest"),
			"Placeholder Label text must contain 'select a quest' (case-insensitive), got: '%s'" % lbl.text)


# ---------------------------------------------------------------------------
# Test 10 — Placeholder is visible and QuestDetail is hidden by default
# ---------------------------------------------------------------------------

func test_placeholder_visible_and_quest_detail_hidden_by_default() -> void:
	# DECISION: the saved scene has Placeholder visible and QuestDetail hidden
	# so a freshly instantiated tab shows the "select a quest" prompt immediately,
	# before any code runs. Reversed defaults would produce a brief blank-or-stale
	# right page on every notebook open until populate_right() fires.
	#
	# This is a static-scene property test: if a scene author accidentally flips
	# these visibility flags in the editor, this test catches it before QA.
	var instance: Control = _make_scene_instance()

	var placeholder: Node = instance.find_child("Placeholder", true, false)
	var detail: Node = instance.find_child("QuestDetail", true, false)

	if placeholder == null or detail == null:
		pending("Placeholder or QuestDetail not found — covered by earlier scene-contract tests")
		return

	assert_true((placeholder as CanvasItem).visible,
			"Placeholder must be visible by default in quests_tab.tscn")
	assert_false((detail as CanvasItem).visible,
			"QuestDetail must be hidden by default in quests_tab.tscn")


# ---------------------------------------------------------------------------
# Test 11 — populate_left(null) does not crash
# ---------------------------------------------------------------------------

func test_populate_left_with_null_parent_does_not_crash() -> void:
	# NotebookTab's contract requires populate_left / populate_right to guard
	# against null. The notebook controller may pass null if a page node has not
	# yet been parented (e.g. during loading screens or test setups).
	var instance: Control = _make_scene_instance()
	var tab: QuestsTab = instance as QuestsTab
	assert_not_null(tab,
			"quests_tab.tscn root must be castable to QuestsTab")
	if tab == null:
		return
	# No assertion beyond "no crash" — GUT records an error automatically if an
	# uncaught exception is thrown inside a test.
	tab.populate_left(null)
	assert_true(true, "populate_left(null) completed without error")


# ---------------------------------------------------------------------------
# Test 12 — populate_right(null) does not crash
# ---------------------------------------------------------------------------

func test_populate_right_with_null_parent_does_not_crash() -> void:
	# Mirrors test 11 for the right-page populate method.
	var instance: Control = _make_scene_instance()
	var tab: QuestsTab = instance as QuestsTab
	assert_not_null(tab,
			"quests_tab.tscn root must be castable to QuestsTab")
	if tab == null:
		return
	tab.populate_right(null)
	assert_true(true, "populate_right(null) completed without error")
