## test_story_card_scene.gd
## Scene-as-data contract tests for story_card.tscn (Slice 4).
##
## WHAT THESE TESTS GUARD
## ----------------------
## After the Slice 4 migration, story_card.tscn declares the full card layout as
## saved editor nodes: NameLabel (Label), CoverRect (ColorRect),
## LastPlayedLabel (Label), and SwitchButton (Button) — previously built in
## _ready(). These tests load the .tscn and walk the instantiated tree to confirm
## every named node is present and typed correctly.
##
## WHY SCENE-AS-DATA TESTS MATTER
## --------------------------------
## The contract between story_card.gd and story_card.tscn is not enforced by
## the type system. find_child("NameLabel", true, false) returns null at runtime
## with no editor warning if a node is accidentally renamed or deleted. A test
## that loads the PackedScene and walks the tree catches that breakage at CI time
## rather than during manual QA — at which point the Sessions tab would silently
## show blank or broken cards with no runtime error.
##
## These tests are EXPECTED TO FAIL until godot-coder builds the scene in Slice 4.
## That is by design — they define the contract that the implementation must meet.
##
## Requires GUT: https://github.com/bitwes/Gut
## Install via Godot Asset Library (search "GUT - Godot Unit Testing").
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd -gselect=test_story_card_scene.gd -gexit

class_name TestStoryCardScene
extends GutTest


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Canonical path for the scene under test. A constant makes it easy to update
# if the file moves and ensures every test in this file references the same path.
const SCENE_PATH: String = "res://ui/notebook/sessions/story_card.tscn"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Instantiate SCENE_PATH and add it to the scene tree so @onready vars and
## child nodes are fully resolved. The instance is autofreed after the test.
##
## @return the instantiated StoryCard root node added as a child of the test
func _make_scene_instance() -> StoryCard:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	var instance: StoryCard = packed.instantiate() as StoryCard
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
			"story_card.tscn must load as a non-null PackedScene")


# ---------------------------------------------------------------------------
# Test 2 — Root is a StoryCard / VBoxContainer
# ---------------------------------------------------------------------------

func test_root_is_story_card_and_vbox_container() -> void:
	# The root must have story_card.gd attached so sessions_tab.gd can call
	# setup(slot) after instantiation without a type error. Checking is VBoxContainer
	# covers both the script and the base class in one assertion — StoryCard arranges
	# its children vertically so VBoxContainer is the correct base.
	var instance: StoryCard = _make_scene_instance()

	assert_true(instance is StoryCard,
			"story_card.tscn root must be a StoryCard")
	assert_true(instance is VBoxContainer,
			"story_card.tscn root must be a VBoxContainer (StoryCard must extend VBoxContainer)")


# ---------------------------------------------------------------------------
# Test 3 — Scene declares a NameLabel Label
# ---------------------------------------------------------------------------

func test_scene_declares_name_label() -> void:
	# NameLabel is the Label that setup() fills with slot.display_name. After the
	# Slice 4 migration the script references it via @onready rather than building
	# it in _ready(). A missing or mistyped node would silently leave every card's
	# title blank — a regression invisible to tests that only inspect data structures.
	var instance: StoryCard = _make_scene_instance()

	var node: Node = instance.find_child("NameLabel", true, false)
	assert_not_null(node,
			"story_card.tscn must declare a node named 'NameLabel'")
	if node == null:
		return
	assert_true(node is Label,
			"'NameLabel' must be a Label, got %s" % node.get_class())


# ---------------------------------------------------------------------------
# Test 4 — Scene declares a CoverRect ColorRect
# ---------------------------------------------------------------------------

func test_scene_declares_cover_rect() -> void:
	# CoverRect is the colour swatch that setup() fills with slot.cover_color.
	# It must be a ColorRect so the color property can be set at runtime.
	# A missing or wrongly-typed node would silently leave the swatch invisible
	# or white — the player would lose their visual story identifier.
	var instance: StoryCard = _make_scene_instance()

	var node: Node = instance.find_child("CoverRect", true, false)
	assert_not_null(node,
			"story_card.tscn must declare a node named 'CoverRect'")
	if node == null:
		return
	assert_true(node is ColorRect,
			"'CoverRect' must be a ColorRect, got %s" % node.get_class())


# ---------------------------------------------------------------------------
# Test 5 — Scene declares a LastPlayedLabel Label
# ---------------------------------------------------------------------------

func test_scene_declares_last_played_label() -> void:
	# LastPlayedLabel is the Phase-1 hardcoded "last played" field. After the
	# migration it lives in the .tscn as a saved editor node with its default
	# text pre-set. A missing node would silently drop the last-played field
	# from every card with no runtime error.
	var instance: StoryCard = _make_scene_instance()

	var node: Node = instance.find_child("LastPlayedLabel", true, false)
	assert_not_null(node,
			"story_card.tscn must declare a node named 'LastPlayedLabel'")
	if node == null:
		return
	assert_true(node is Label,
			"'LastPlayedLabel' must be a Label, got %s" % node.get_class())


# ---------------------------------------------------------------------------
# Test 6 — Scene declares a SwitchButton Button
# ---------------------------------------------------------------------------

func test_scene_declares_switch_button() -> void:
	# SwitchButton is the no-op Phase-1 switch affordance. In Phase 2 it will
	# be wired to GameEvents.story_switch_requested. It must be a Button so the
	# pressed signal is available for future connection. A missing node would
	# silently remove the switch affordance from every card without a runtime error.
	var instance: StoryCard = _make_scene_instance()

	var node: Node = instance.find_child("SwitchButton", true, false)
	assert_not_null(node,
			"story_card.tscn must declare a node named 'SwitchButton'")
	if node == null:
		return
	assert_true(node is Button,
			"'SwitchButton' must be a Button, got %s" % node.get_class())


# ---------------------------------------------------------------------------
# Test 7 — CoverRect preserves the 16×16 minimum size
# ---------------------------------------------------------------------------

func test_cover_rect_has_16x16_minimum_size() -> void:
	# The 16×16 custom_minimum_size matches the low-res aesthetic of the
	# 320×180 viewport and was established in the pre-migration _ready() code.
	# After the migration this value must survive as an editor-saved property.
	# If it is lost, the swatch collapses to zero-height and becomes invisible.
	var instance: StoryCard = _make_scene_instance()

	var node: Node = instance.find_child("CoverRect", true, false)
	if node == null:
		pending("CoverRect not found — covered by test_scene_declares_cover_rect")
		return

	var rect: ColorRect = node as ColorRect
	assert_eq(rect.custom_minimum_size, Vector2(16.0, 16.0),
			"CoverRect.custom_minimum_size must be Vector2(16, 16) to preserve the low-res swatch aesthetic")


# ---------------------------------------------------------------------------
# Test 8 — LastPlayedLabel text contains "N/A"
# ---------------------------------------------------------------------------

func test_last_played_label_text_contains_na() -> void:
	# The Phase-1 copy "Last played: N/A" must be saved as an editor property on
	# LastPlayedLabel so the card shows it immediately when instantiated, before
	# any code runs. If the text is empty after the migration, the last-played
	# field silently disappears from every card.
	#
	# We check for "N/A" (case-sensitive) rather than the full string so that minor
	# copy changes (e.g. "Last Played: N/A") do not break this structural test.
	var instance: StoryCard = _make_scene_instance()

	var node: Node = instance.find_child("LastPlayedLabel", true, false)
	if node == null:
		pending("LastPlayedLabel not found — covered by test_scene_declares_last_played_label")
		return

	var lbl: Label = node as Label
	assert_true(lbl.text.contains("N/A"),
			"LastPlayedLabel.text must contain 'N/A' (Phase-1 hardcoded copy), got: '%s'" % lbl.text)
