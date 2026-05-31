## test_map_tab_scene.gd
## Scene-as-data contract tests for the Map tab scene migration (PR 5).
##
## WHAT THESE TESTS GUARD
## ----------------------
## After the migration, map_tab.tscn is no longer an empty Control — it
## declares the full static layout as saved editor nodes:
##
##   MapTab (Control)
##   ├── LeftPage (VBoxContainer)
##   │   ├── WorldMapHeading   (Label,     text = "World Map")
##   │   ├── WorldMapPlaceholder (ColorRect, muted green, min 120×80)
##   │   └── WorldMapNote      (Label,     text contains "Phase 2")
##   └── RightPage (VBoxContainer)
##       ├── LocalAreaHeading  (Label,     text = "Local Area")
##       ├── LocalMapPlaceholder (ColorRect, darker green, min 120×80)
##       └── LocalMapNote      (Label,     text contains "Phase 2")
##
## WHY THESE FAIL BEFORE THE MIGRATION
## ------------------------------------
## map_tab.tscn currently contains only a bare Control node with no children.
## Every test that calls find_child("LeftPage", …) will receive null. That is
## intentional — these tests define exactly what the scene must contain and
## serve as the definition of done for the scene build.
##
## WHY SCENE-AS-DATA TESTS MATTER
## --------------------------------
## The contract between map_tab.gd and map_tab.tscn is invisible to the type
## system. get_node("WorldMapPlaceholder") returns null at runtime with no
## editor warning if the node is accidentally renamed or deleted. A test that
## loads the PackedScene and walks the resulting tree catches that breakage at
## CI time rather than during manual QA.
##
## HOW THESE RELATE TO test_map_tab.gd
## ------------------------------------
## test_map_tab.gd covers the public API (inheritance, populate_left/right add
## content) via MapTab.new(). These tests cover the scene file itself — named
## nodes, node types, static text values, and visual properties. Neither file
## duplicates the other.
##
## Requires GUT: https://github.com/bitwes/Gut
## Install via Godot Asset Library (search "GUT - Godot Unit Testing").
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd -gselect=test_map_tab_scene.gd -gexit

class_name TestMapTabScene
extends GutTest


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Canonical path for the scene under test. Using a constant makes it easy to
# update if the file moves and ensures every test in this file references the
# same path.
const SCENE_PATH: String = "res://ui/notebook/map/map_tab.tscn"

# The muted green used for the world-map placeholder on the left page.
# Color(0.2, 0.3, 0.2) evokes printed map territory without needing real art.
# Matches the value in map_tab.gd's populate_left().
const WORLD_MAP_COLOR: Color = Color(0.2, 0.3, 0.2)

# The darker green for the local-area placeholder on the right page.
# Color(0.15, 0.25, 0.15) is visually distinct from WORLD_MAP_COLOR so the
# player can tell the two placeholder pages apart at a glance.
# Matches the value in map_tab.gd's populate_right().
const LOCAL_MAP_COLOR: Color = Color(0.15, 0.25, 0.15)

# Minimum visible area for a placeholder ColorRect.
# 120×80 px is large enough to read as a map stand-in at the 320×180 base
# resolution without dominating the whole page.
const PLACEHOLDER_MIN_SIZE: Vector2 = Vector2(120.0, 80.0)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Instantiate SCENE_PATH and add it to the scene tree so @onready vars and
## child nodes are fully resolved. The instance is autofreed after the test.
##
## @return the instantiated MapTab root node, added as a child of the test
func _make_scene_instance() -> Control:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	var instance: Control = packed.instantiate() as Control
	add_child_autofree(instance)
	return instance


## Walk root's subtree depth-first and collect every node that satisfies
## type_check. Used because named nodes may live at any depth inside the
## VBoxContainer hierarchy rather than as direct children of the root.
##
## @param root       the node whose subtree to search
## @param type_check Callable(Node) -> bool; returns true for matching nodes
## @return Array of matching nodes in depth-first order
func _find_nodes_of_type(root: Node, type_check: Callable) -> Array[Node]:
	var result: Array[Node] = []
	for child: Node in root.get_children():
		if type_check.call(child):
			result.append(child)
		result.append_array(_find_nodes_of_type(child, type_check))
	return result


# ---------------------------------------------------------------------------
# Test 1 — Scene file loads as a valid PackedScene
# ---------------------------------------------------------------------------

func test_scene_loads_without_error() -> void:
	# If the .tscn file is corrupt, mis-formatted, or references a missing
	# resource, load() returns null. This is the cheapest possible check and
	# gates every subsequent test: if load fails, instantiation is pointless.
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	assert_not_null(packed,
			"map_tab.tscn must load as a non-null PackedScene")


# ---------------------------------------------------------------------------
# Test 2 — Scene root is castable to MapTab
# ---------------------------------------------------------------------------

func test_scene_root_is_map_tab() -> void:
	# The scene root must carry the MapTab script so that notebook.gd can call
	# populate_left() / populate_right() polymorphically. If the script
	# attachment is lost in the editor, this cast produces null and every call
	# to the public API silently does nothing.
	var instance: Control = _make_scene_instance()
	var tab: MapTab = instance as MapTab
	assert_not_null(tab,
			"map_tab.tscn root must be castable to MapTab")


# ---------------------------------------------------------------------------
# Test 3 — Scene declares a node named LeftPage of type VBoxContainer
# ---------------------------------------------------------------------------

func test_scene_declares_left_page() -> void:
	# LeftPage is the subtree root that populate_left() reparents into the
	# notebook book's left page Control. If it is renamed or deleted the entire
	# left side of the Map tab will be blank with no runtime error.
	var instance: Control = _make_scene_instance()

	var node: Node = instance.find_child("LeftPage", true, false)
	assert_not_null(node,
			"map_tab.tscn must declare a node named 'LeftPage'")
	if node == null:
		return
	assert_true(node is VBoxContainer,
			"'LeftPage' must be a VBoxContainer, got %s" % node.get_class())


# ---------------------------------------------------------------------------
# Test 4 — Scene declares a node named RightPage of type VBoxContainer
# ---------------------------------------------------------------------------

func test_scene_declares_right_page() -> void:
	# RightPage mirrors LeftPage for the right side of the spread.
	var instance: Control = _make_scene_instance()

	var node: Node = instance.find_child("RightPage", true, false)
	assert_not_null(node,
			"map_tab.tscn must declare a node named 'RightPage'")
	if node == null:
		return
	assert_true(node is VBoxContainer,
			"'RightPage' must be a VBoxContainer, got %s" % node.get_class())


# ---------------------------------------------------------------------------
# Test 5 — Scene declares a WorldMapHeading Label with text "World Map"
# ---------------------------------------------------------------------------

func test_scene_declares_world_map_heading() -> void:
	# WorldMapHeading is the section title for the left page. Baking it into
	# the .tscn rather than creating it at runtime means a developer can see
	# and edit the heading text directly in the editor. A typo here is caught
	# by this test rather than discovered during manual QA.
	var instance: Control = _make_scene_instance()

	var node: Node = instance.find_child("WorldMapHeading", true, false)
	assert_not_null(node,
			"map_tab.tscn must declare a node named 'WorldMapHeading'")
	if node == null:
		return
	assert_true(node is Label,
			"'WorldMapHeading' must be a Label, got %s" % node.get_class())
	assert_eq((node as Label).text, "World Map",
			"'WorldMapHeading' text must be 'World Map'")


# ---------------------------------------------------------------------------
# Test 6 — Scene declares a WorldMapPlaceholder ColorRect
# ---------------------------------------------------------------------------

func test_scene_declares_world_map_placeholder() -> void:
	# WorldMapPlaceholder is the green ColorRect that stands in for the real
	# GlobalMap until Phase 2 art is ready. A developer opening the scene in
	# the editor should see a coloured rectangle, not nothing.
	var instance: Control = _make_scene_instance()

	var node: Node = instance.find_child("WorldMapPlaceholder", true, false)
	assert_not_null(node,
			"map_tab.tscn must declare a node named 'WorldMapPlaceholder'")
	if node == null:
		return
	assert_true(node is ColorRect,
			"'WorldMapPlaceholder' must be a ColorRect, got %s" % node.get_class())


# ---------------------------------------------------------------------------
# Test 7 — WorldMapPlaceholder color is the muted green
# ---------------------------------------------------------------------------

func test_world_map_placeholder_color_is_muted_green() -> void:
	# The muted green (0.2, 0.3, 0.2) evokes printed map territory. This test
	# catches an accidental colour reset to white or transparent, which would
	# make the placeholder invisible against the page background.
	var instance: Control = _make_scene_instance()

	var node: Node = instance.find_child("WorldMapPlaceholder", true, false)
	if node == null:
		# Test 6 already asserts on null — skip rather than double-fail.
		pass
		return
	var rect: ColorRect = node as ColorRect
	assert_eq(rect.color, WORLD_MAP_COLOR,
			"'WorldMapPlaceholder' color must be Color(0.2, 0.3, 0.2) — the muted map green")


# ---------------------------------------------------------------------------
# Test 8 — WorldMapPlaceholder has a sufficient minimum size
# ---------------------------------------------------------------------------

func test_world_map_placeholder_minimum_size_is_sufficient() -> void:
	# custom_minimum_size guarantees the placeholder has a visible area even
	# when the parent Control has no layout constraints (e.g. in headless tests
	# where the viewport never renders). Without it the rect collapses to zero.
	var instance: Control = _make_scene_instance()

	var node: Node = instance.find_child("WorldMapPlaceholder", true, false)
	if node == null:
		return
	var rect: ColorRect = node as ColorRect
	assert_true(rect.custom_minimum_size.x >= PLACEHOLDER_MIN_SIZE.x,
			"'WorldMapPlaceholder' custom_minimum_size.x must be >= %.0f, got %.0f" % [
				PLACEHOLDER_MIN_SIZE.x, rect.custom_minimum_size.x])
	assert_true(rect.custom_minimum_size.y >= PLACEHOLDER_MIN_SIZE.y,
			"'WorldMapPlaceholder' custom_minimum_size.y must be >= %.0f, got %.0f" % [
				PLACEHOLDER_MIN_SIZE.y, rect.custom_minimum_size.y])


# ---------------------------------------------------------------------------
# Test 9 — LeftPage subtree contains a Label whose text mentions "Phase 2"
# ---------------------------------------------------------------------------

func test_left_page_declares_world_map_note() -> void:
	# The Phase 2 note tells the player (and any developer reading the scene)
	# that the real map art is coming later. Baking it into the .tscn means it
	# is visible in the editor's scene tree — not hidden inside GDScript.
	var instance: Control = _make_scene_instance()

	var left_page: Node = instance.find_child("LeftPage", true, false)
	if left_page == null:
		return

	var labels: Array[Node] = _find_nodes_of_type(left_page,
			func(n: Node) -> bool: return n is Label)

	var has_phase2_note: bool = false
	for label_node: Node in labels:
		if "Phase 2" in (label_node as Label).text:
			has_phase2_note = true
			break

	assert_true(has_phase2_note,
			"LeftPage subtree must contain a Label whose text includes 'Phase 2'")


# ---------------------------------------------------------------------------
# Test 10 — Scene declares a LocalAreaHeading Label with text "Local Area"
# ---------------------------------------------------------------------------

func test_scene_declares_local_area_heading() -> void:
	# LocalAreaHeading is the section title for the right page. Mirrors the
	# WorldMapHeading contract — static text must be present and correctly
	# spelled so the page is self-describing in the editor.
	var instance: Control = _make_scene_instance()

	var node: Node = instance.find_child("LocalAreaHeading", true, false)
	assert_not_null(node,
			"map_tab.tscn must declare a node named 'LocalAreaHeading'")
	if node == null:
		return
	assert_true(node is Label,
			"'LocalAreaHeading' must be a Label, got %s" % node.get_class())
	assert_eq((node as Label).text, "Local Area",
			"'LocalAreaHeading' text must be 'Local Area'")


# ---------------------------------------------------------------------------
# Test 11 — Scene declares a LocalMapPlaceholder ColorRect
# ---------------------------------------------------------------------------

func test_scene_declares_local_map_placeholder() -> void:
	# LocalMapPlaceholder stands in for the LocalMap SubViewport snapshot until
	# Phase 2. Mirrors the WorldMapPlaceholder contract for the right page.
	var instance: Control = _make_scene_instance()

	var node: Node = instance.find_child("LocalMapPlaceholder", true, false)
	assert_not_null(node,
			"map_tab.tscn must declare a node named 'LocalMapPlaceholder'")
	if node == null:
		return
	assert_true(node is ColorRect,
			"'LocalMapPlaceholder' must be a ColorRect, got %s" % node.get_class())


# ---------------------------------------------------------------------------
# Test 12 — LocalMapPlaceholder color is the darker green
# ---------------------------------------------------------------------------

func test_local_map_placeholder_color_is_darker_green() -> void:
	# Color(0.15, 0.25, 0.15) is visually distinct from the world-map green so
	# the player can tell the two placeholder pages apart at a glance. An
	# accidental copy-paste of the wrong colour constant would fail this test.
	var instance: Control = _make_scene_instance()

	var node: Node = instance.find_child("LocalMapPlaceholder", true, false)
	if node == null:
		return
	var rect: ColorRect = node as ColorRect
	assert_eq(rect.color, LOCAL_MAP_COLOR,
			"'LocalMapPlaceholder' color must be Color(0.15, 0.25, 0.15) — the darker map green")


# ---------------------------------------------------------------------------
# Test 13 — LocalMapPlaceholder has a sufficient minimum size
# ---------------------------------------------------------------------------

func test_local_map_placeholder_minimum_size_is_sufficient() -> void:
	# Mirrors Test 8 for the right-page placeholder.
	var instance: Control = _make_scene_instance()

	var node: Node = instance.find_child("LocalMapPlaceholder", true, false)
	if node == null:
		return
	var rect: ColorRect = node as ColorRect
	assert_true(rect.custom_minimum_size.x >= PLACEHOLDER_MIN_SIZE.x,
			"'LocalMapPlaceholder' custom_minimum_size.x must be >= %.0f, got %.0f" % [
				PLACEHOLDER_MIN_SIZE.x, rect.custom_minimum_size.x])
	assert_true(rect.custom_minimum_size.y >= PLACEHOLDER_MIN_SIZE.y,
			"'LocalMapPlaceholder' custom_minimum_size.y must be >= %.0f, got %.0f" % [
				PLACEHOLDER_MIN_SIZE.y, rect.custom_minimum_size.y])


# ---------------------------------------------------------------------------
# Test 14 — RightPage subtree contains a Label whose text mentions "Phase 2"
# ---------------------------------------------------------------------------

func test_right_page_declares_local_map_note() -> void:
	# Mirrors Test 9 for the right page. Both pages must have a note so neither
	# appears broken or unfinished when the notebook is first opened.
	var instance: Control = _make_scene_instance()

	var right_page: Node = instance.find_child("RightPage", true, false)
	if right_page == null:
		return

	var labels: Array[Node] = _find_nodes_of_type(right_page,
			func(n: Node) -> bool: return n is Label)

	var has_phase2_note: bool = false
	for label_node: Node in labels:
		if "Phase 2" in (label_node as Label).text:
			has_phase2_note = true
			break

	assert_true(has_phase2_note,
			"RightPage subtree must contain a Label whose text includes 'Phase 2'")


# ---------------------------------------------------------------------------
# Test 15 — populate_left(null) does not crash
# ---------------------------------------------------------------------------

func test_populate_left_with_null_parent_does_not_crash() -> void:
	# NotebookTab's contract requires populate_left / populate_right to guard
	# against null. The guard exists in the current GDScript code; this test
	# confirms it survives the script rewrite. A crash here would abort the
	# notebook _show_tab flow if the controller ever passes a missing page.
	var instance: Control = _make_scene_instance()
	var tab: MapTab = instance as MapTab
	assert_not_null(tab,
			"map_tab.tscn root must be castable to MapTab")
	if tab == null:
		return
	# No assertion beyond "no crash" — GUT records an error automatically if
	# an uncaught exception is thrown.
	tab.populate_left(null)
	assert_true(true, "populate_left(null) completed without error")


# ---------------------------------------------------------------------------
# Test 16 — populate_right(null) does not crash
# ---------------------------------------------------------------------------

func test_populate_right_with_null_parent_does_not_crash() -> void:
	# Mirrors Test 15 for the right-page populate method.
	var instance: Control = _make_scene_instance()
	var tab: MapTab = instance as MapTab
	assert_not_null(tab,
			"map_tab.tscn root must be castable to MapTab")
	if tab == null:
		return
	tab.populate_right(null)
	assert_true(true, "populate_right(null) completed without error")
