## test_sessions_tab_scene.gd
## Scene-as-data contract tests for sessions_tab.tscn.
##
## WHAT THESE TESTS GUARD
## ----------------------
## sessions_tab.tscn declares the full static layout as saved editor nodes:
## LeftPage (Control) containing CardsContainer (VBoxContainer);
## RightPage (Control) containing Placeholder (Label) with "select a story" text.
## These tests load the .tscn and walk the instantiated tree to confirm every named
## node is present and typed correctly.
##
## WHY SCENE-AS-DATA TESTS MATTER
## --------------------------------
## The contract between sessions_tab.gd and sessions_tab.tscn is not enforced by
## the type system. find_child("CardsContainer", true, false) returns null at
## runtime with no editor warning if a node is accidentally renamed or deleted.
## A test that loads the PackedScene and walks the tree catches that breakage at
## CI time rather than during manual QA — at which point the Sessions tab would
## show a blank left page with no runtime error.
##
## Requires GUT: https://github.com/bitwes/Gut
## Install via Godot Asset Library (search "GUT - Godot Unit Testing").
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd -gselect=test_sessions_tab_scene.gd -gexit

class_name TestSessionsTabScene
extends GutTest


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Canonical path for the scene under test. A constant makes it easy to update
# if the file moves and ensures every test in this file references the same path.
const SCENE_PATH: String = "res://ui/notebook/sessions/sessions_tab.tscn"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Instantiate SCENE_PATH and add it to the scene tree so @onready vars and
## child nodes are fully resolved. The instance is autofreed after the test.
##
## @return the instantiated SessionsTab root node added as a child of the test
func _make_scene_instance() -> SessionsTab:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	var instance: SessionsTab = packed.instantiate() as SessionsTab
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
			"sessions_tab.tscn must load as a non-null PackedScene")


# ---------------------------------------------------------------------------
# Test 2 — Root is a SessionsTab / NotebookTab
# ---------------------------------------------------------------------------

func test_root_is_sessions_tab_and_notebook_tab() -> void:
	# The root must have sessions_tab.gd attached so the notebook controller can
	# call populate_left / populate_right polymorphically. Checking is NotebookTab
	# covers both the script and the inheritance chain in one assertion.
	var instance: SessionsTab = _make_scene_instance()

	assert_true(instance is SessionsTab,
			"sessions_tab.tscn root must be a SessionsTab")
	assert_true(instance is NotebookTab,
			"sessions_tab.tscn root must be a NotebookTab (SessionsTab must extend NotebookTab)")


# ---------------------------------------------------------------------------
# Test 3 — LeftPage Control contains a CardsContainer VBoxContainer
# ---------------------------------------------------------------------------

func test_left_page_contains_cards_container() -> void:
	# LeftPage is the subtree root that populate_left() reparents into the
	# notebook's page. CardsContainer is the VBoxContainer into which populate_left
	# adds StoryCard instances — now editor-declared rather than code-built.
	# If either is missing or mistyped the entire left page will be silently blank.
	var instance: SessionsTab = _make_scene_instance()

	var left: Node = instance.find_child("LeftPage", true, false)
	assert_not_null(left,
			"sessions_tab.tscn must declare a node named 'LeftPage'")
	if left == null:
		return
	assert_true(left is VBoxContainer,
			"'LeftPage' must be a VBoxContainer, got %s" % left.get_class())

	var container: Node = left.find_child("CardsContainer", true, false)
	assert_not_null(container,
			"LeftPage must contain a node named 'CardsContainer'")
	if container == null:
		return
	assert_true(container is VBoxContainer,
			"'CardsContainer' must be a VBoxContainer, got %s" % container.get_class())


# ---------------------------------------------------------------------------
# Test 4 — RightPage Control contains a Placeholder Label with "select a story"
# ---------------------------------------------------------------------------

func test_right_page_contains_placeholder_label_with_select_text() -> void:
	# D2: the right page is purely static — one fixed Placeholder Label showing
	# "select a story" (case-insensitive match). This guards that the static copy
	# is preserved as an editor property, and that no further right-page logic is
	# required for Phase 1.
	var instance: SessionsTab = _make_scene_instance()

	var right: Node = instance.find_child("RightPage", true, false)
	assert_not_null(right,
			"sessions_tab.tscn must declare a node named 'RightPage'")
	if right == null:
		return
	assert_true(right is VBoxContainer,
			"'RightPage' must be a VBoxContainer, got %s" % right.get_class())

	var node: Node = right.find_child("Placeholder", true, false)
	assert_not_null(node,
			"RightPage must contain a node named 'Placeholder'")
	if node == null:
		return
	assert_true(node is Label,
			"'Placeholder' must be a Label, got %s" % node.get_class())

	var lbl: Label = node as Label
	assert_true(lbl.text.to_lower().contains("select a story"),
			"Placeholder Label text must contain 'select a story' (case-insensitive), got: '%s'" % lbl.text)


# ---------------------------------------------------------------------------
# Test 5 — populate_left(null) does not crash
# ---------------------------------------------------------------------------

func test_populate_left_with_null_parent_does_not_crash() -> void:
	# NotebookTab's contract requires populate_left / populate_right to guard
	# against null. The notebook controller may pass null if a page node has not
	# yet been parented (e.g. during loading screens or test setups).
	var instance: SessionsTab = _make_scene_instance()
	var tab: SessionsTab = instance
	assert_not_null(tab,
			"sessions_tab.tscn root must be castable to SessionsTab")
	if tab == null:
		return
	# No assertion beyond "no crash" — GUT records an error automatically if an
	# uncaught exception is thrown inside a test.
	tab.populate_left(null)
	assert_true(true, "populate_left(null) completed without error")


# ---------------------------------------------------------------------------
# Test 6 — populate_right(null) does not crash
# ---------------------------------------------------------------------------

func test_populate_right_with_null_parent_does_not_crash() -> void:
	# Mirrors test 5 for the right-page populate method.
	var instance: SessionsTab = _make_scene_instance()
	var tab: SessionsTab = instance
	assert_not_null(tab,
			"sessions_tab.tscn root must be castable to SessionsTab")
	if tab == null:
		return
	tab.populate_right(null)
	assert_true(true, "populate_right(null) completed without error")
