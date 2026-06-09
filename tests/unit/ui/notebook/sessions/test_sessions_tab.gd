## test_sessions_tab.gd
## Behavior contract tests for SessionsTab and StoryCard (Phase 1 / Slice 4).
##
## Covers SessionsTab (ui/notebook/sessions/sessions_tab.gd) and
## StoryCard (ui/notebook/sessions/story_card.gd).
##
## --- SLICE 4 EDIT NOTE ---
## Tests 8 and 9 previously used StoryCard.new() to construct cards. They now
## instantiate from story_card.tscn via add_child_autofree(load(...).instantiate()).
##
## WHY: After Slice 4, story_card.gd will use @onready references to named children
## (NameLabel, CoverRect, LastPlayedLabel, SwitchButton) that only exist when the
## node is instantiated from the scene. Bare StoryCard.new() would leave those
## refs null and setup() would null-crash. Switching to scene instantiation here
## means these tests PASS today (the scene still triggers _ready() which builds
## the children), and they will continue to pass after Slice 4 removes that
## _ready() build code in favour of @onready refs.
##
## Test 7 (is VBoxContainer) is the one exception: it never calls setup() or
## accesses children, so bare .new() is safe and avoids the overhead of loading
## and instantiating the full scene just for a type check.
##
## Tests 5 and 6 keep SessionsTab.new() because populate_left / populate_right
## load the card scene internally — bare tab construction still works.
##
## Three new tests added in Slice 4:
##   test_populate_left_called_twice_yields_one_card   — guards D1 duplicate-card bug
##   test_story_card_setup_writes_display_name_to_label — guards NameLabel @onready binding
##   test_story_card_setup_sets_cover_rect_color        — guards CoverRect @onready binding
##
## Requires GUT: https://github.com/bitwes/Gut
## Install via Godot Asset Library (search "GUT - Godot Unit Testing").
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI (once GUT is installed):
##   godot --headless -s addons/gut/gut_cmdln.gd

class_name TestSessionsTab
extends GutTest


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Use scene instantiation (not bare .new()) so @onready refs in story_card.gd
# resolve correctly after Slice 4.  See SLICE 4 EDIT NOTE in the file header.
# Declared as PackedScene with preload() to mirror production sessions_tab.gd
# and let the engine verify the path at parse time rather than at runtime.
# https://docs.godotengine.org/en/stable/classes/class_packedscene.html
const STORY_CARD_SCENE: PackedScene = preload("res://ui/notebook/sessions/story_card.tscn")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Walk the full subtree of root and return every Label whose text matches.
## Needed because setup() writes into named child labels that are grandchildren
## (or deeper) of the card root.
##
## @param root      - the node whose subtree to search
## @param predicate - a Callable(Label) -> bool that returns true for a match
## @return Array of matching Label nodes, in depth-first order
func _find_labels(root: Node, predicate: Callable) -> Array[Label]:
	var result: Array[Label] = []
	for child in root.get_children():
		if child is Label and predicate.call(child as Label):
			result.append(child as Label)
		result.append_array(_find_labels(child, predicate))
	return result


## Instantiate a StoryCard from the .tscn so @onready refs resolve correctly.
## Adds it to the tree via add_child_autofree so _ready() fires immediately.
##
## @return the instantiated StoryCard
func _make_card() -> StoryCard:
	# STORY_CARD_SCENE is a preloaded PackedScene constant, so instantiate()
	# can be called directly without a runtime load() call.
	# add_child_autofree ensures _ready() fires and the instance is freed after
	# each test without leaks.
	# https://docs.godotengine.org/en/stable/classes/class_packedscene.html#class-packedscene-method-instantiate
	return add_child_autofree(STORY_CARD_SCENE.instantiate()) as StoryCard


## Build a minimal StorySlot resource for tests that need one.
## We create a fresh instance each time so tests cannot pollute each other.
func _make_slot(id: String, name: String, color: Color) -> StorySlot:
	var slot: StorySlot = StorySlot.new()
	slot.slot_id = id
	slot.display_name = name
	slot.cover_color = color
	return slot  # caller is responsible for autofree if needed


# ---------------------------------------------------------------------------
# Test 1 — SessionsTab inherits NotebookTab
# ---------------------------------------------------------------------------

func test_sessions_tab_is_a_notebook_tab() -> void:
	# SessionsTab must extend NotebookTab so the notebook controller can call
	# populate_left / populate_right polymorphically.
	# https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html#inheritance
	var tab: SessionsTab = SessionsTab.new()
	autofree(tab)

	assert_true(tab is NotebookTab,
			"SessionsTab must be a NotebookTab (extend NotebookTab)")


# ---------------------------------------------------------------------------
# Test 2 — SessionsTab is a Control (because NotebookTab extends Control)
# ---------------------------------------------------------------------------

func test_sessions_tab_is_a_control() -> void:
	# NotebookTab extends Control, so SessionsTab should also be a Control.
	# This guards against accidentally changing the inheritance chain.
	var tab: SessionsTab = SessionsTab.new()
	autofree(tab)

	assert_true(tab is Control,
			"SessionsTab must be a Control (NotebookTab extends Control)")


# ---------------------------------------------------------------------------
# Test 3 — _default_slot is created in _ready() and is non-null
# ---------------------------------------------------------------------------

func test_sessions_tab_has_default_slot() -> void:
	# _ready() must create _default_slot so the tab always has at least one
	# card to show — even before the player creates a story. Without this
	# the Sessions page would be blank on first launch.
	var tab: SessionsTab = add_child_autofree(SessionsTab.new())

	# Accessing _default_slot directly — GDScript does not enforce access
	# control on leading-underscore vars, so this is fine in tests.
	assert_not_null(tab._default_slot,
			"_default_slot must be non-null after _ready() runs")


# ---------------------------------------------------------------------------
# Test 4 — _default_slot has a non-empty display_name
# ---------------------------------------------------------------------------

func test_sessions_tab_default_slot_has_display_name() -> void:
	# A blank display_name would render as an empty label on the card, which
	# would look broken to the player. Guard against an accidentally empty string.
	var tab: SessionsTab = add_child_autofree(SessionsTab.new())

	assert_ne(tab._default_slot.display_name, "",
			"_default_slot.display_name must not be empty")


# ---------------------------------------------------------------------------
# Test 5 — populate_left() adds at least one child to the parent Control
# ---------------------------------------------------------------------------

func test_sessions_tab_populate_left_creates_at_least_one_card() -> void:
	# populate_left() must add one StoryCard per known story slot.
	# Phase 1 always has exactly one (the default slot), so the parent should
	# gain at least one child after the call.
	var tab: SessionsTab = add_child_autofree(SessionsTab.new())
	var parent: Control = add_child_autofree(Control.new())

	tab.populate_left(parent)

	assert_true(parent.get_child_count() >= 1,
			"populate_left() must add at least one child to the parent Control")


# ---------------------------------------------------------------------------
# Test 6 — populate_right() adds at least one child to the parent Control
# ---------------------------------------------------------------------------

func test_sessions_tab_populate_right_adds_a_label() -> void:
	# populate_right() shows placeholder text in Phase 1.
	# The parent must have at least one child (a Label) so the right page is
	# not visually empty.
	var tab: SessionsTab = add_child_autofree(SessionsTab.new())
	var parent: Control = add_child_autofree(Control.new())

	tab.populate_right(parent)

	assert_true(parent.get_child_count() >= 1,
			"populate_right() must add at least one child (the placeholder Label) to the parent")


# ---------------------------------------------------------------------------
# Test 7 — StoryCard inherits VBoxContainer
# ---------------------------------------------------------------------------

func test_story_card_is_a_vbox_container() -> void:
	# StoryCard arranges its children (name label, colour swatch, last-played,
	# switch button) in a vertical column, so it must extend VBoxContainer.
	var card: StoryCard = StoryCard.new()
	autofree(card)

	assert_true(card is VBoxContainer,
			"StoryCard must extend VBoxContainer")


# ---------------------------------------------------------------------------
# Test 8 — StoryCard.setup() does not crash with a valid StorySlot
# ---------------------------------------------------------------------------

func test_story_card_setup_does_not_crash() -> void:
	# setup() is the main entry point for wiring a card to its data.
	# This test confirms it runs without throwing an error for a well-formed slot.
	# Card instantiated from scene so @onready refs resolve correctly (Slice 4).
	var slot: StorySlot = _make_slot("test", "Test Story", Color.BLUE)
	autofree(slot)

	# Instantiate from scene so _ready() fires and @onready refs are valid before
	# setup() is called. See SLICE 4 EDIT NOTE in the file header.
	var card: StoryCard = _make_card()

	# If this line raises an error, GUT records a test failure automatically.
	card.setup(slot)

	assert_true(true, "setup() must not crash with a valid StorySlot")


# ---------------------------------------------------------------------------
# Test 9 — StoryCard.setup() stores the slot reference
# ---------------------------------------------------------------------------

func test_story_card_setup_stores_slot() -> void:
	# setup() must save the slot so other methods (e.g. a future "play" button
	# handler) can reference it. If _slot is null after setup(), the card is
	# effectively disconnected from its data source.
	# Card instantiated from scene so @onready refs resolve correctly (Slice 4).
	var slot: StorySlot = _make_slot("slot_1", "My Story", Color.RED)
	autofree(slot)

	var card: StoryCard = _make_card()
	card.setup(slot)

	assert_eq(card._slot, slot,
			"setup() must store the StorySlot in _slot so the card knows its data")


# ---------------------------------------------------------------------------
# Test 10 — populate_left called twice yields exactly one StoryCard (D1)
# ---------------------------------------------------------------------------

func test_populate_left_called_twice_yields_one_card() -> void:
	# D1 regression guard: the pre-migration populate_left() never clears
	# _left_cards or removes stale children, so each call accumulates a duplicate
	# card. The Slice 4 implementation must clear before rebuilding.
	#
	# We search for CardsContainer inside the subtree that populate_left adds to
	# parent — after the migration the tab reparents its LeftPage (which contains
	# CardsContainer) rather than adding cards directly to parent.
	var tab: SessionsTab = add_child_autofree(SessionsTab.new())
	var parent: Control = add_child_autofree(Control.new())

	tab.populate_left(parent)
	tab.populate_left(parent)

	# Locate CardsContainer anywhere under parent (it lives inside LeftPage).
	var container: Node = parent.find_child("CardsContainer", true, false)
	assert_not_null(container,
			"CardsContainer must be reachable under parent after populate_left()")
	if container == null:
		return

	# Count only direct StoryCard children of CardsContainer — not grandchildren —
	# because cards are added directly into this VBoxContainer.
	var card_count: int = 0
	for child in container.get_children():
		if child is StoryCard:
			card_count += 1

	assert_eq(card_count, 1,
			"populate_left called twice must yield exactly 1 StoryCard in CardsContainer, got %d (D1: stale cards not cleared)" % card_count)


# ---------------------------------------------------------------------------
# Test 11 — setup() writes slot.display_name into a Label in the card subtree
# ---------------------------------------------------------------------------

func test_story_card_setup_writes_display_name_to_label() -> void:
	# After the Slice 4 migration, setup() writes slot.display_name into the
	# @onready NameLabel. A recursive Label search guards that the binding
	# survives the @onready migration — a broken ref would leave the name label
	# blank with no runtime error.
	#
	# We use _find_labels() rather than find_child("NameLabel") so the test also
	# passes if the implementation nests NameLabel inside an intermediate container.
	var slot: StorySlot = _make_slot("display_test", "My Story Display", Color.GREEN)
	autofree(slot)

	var card: StoryCard = _make_card()
	card.setup(slot)

	var matches: Array[Label] = _find_labels(card,
			func(lbl: Label) -> bool: return lbl.text == slot.display_name)

	assert_true(matches.size() >= 1,
			"setup() must write slot.display_name into a Label in the card subtree; no Label with text '%s' found" % slot.display_name)


# ---------------------------------------------------------------------------
# Test 12 — setup() sets CoverRect.color to slot.cover_color
# ---------------------------------------------------------------------------

func test_story_card_setup_sets_cover_rect_color() -> void:
	# After the Slice 4 migration, setup() sets the CoverRect @onready ref's color
	# to slot.cover_color. This guard ensures the colour-swatch binding survives
	# the @onready migration — a broken ref would silently leave every swatch white
	# (Color.WHITE default) regardless of the slot's configured colour.
	var expected_color: Color = Color(0.2, 0.8, 0.4)
	var slot: StorySlot = _make_slot("color_test", "Color Test Story", expected_color)
	autofree(slot)

	var card: StoryCard = _make_card()
	card.setup(slot)

	var node: Node = card.find_child("CoverRect", true, false)
	assert_not_null(node,
			"CoverRect must exist in the card subtree after setup() (requires story_card.tscn to declare it)")
	if node == null:
		return

	var rect: ColorRect = node as ColorRect
	assert_eq(rect.color, expected_color,
			"CoverRect.color must equal slot.cover_color after setup()")
