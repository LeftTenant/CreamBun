## test_sessions_tab.gd
## TDD contract tests for the Phase 1 Sessions Tab.
##
## Covers SessionsTab (ui/notebook/sessions/sessions_tab.gd) and
## StoryCard (ui/notebook/sessions/story_card.gd).
##
## These tests define the expected API. They will FAIL until the implementation
## files exist — that is by design. Run them after implementing each class to
## confirm the contract is met.
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
# Helpers
# ---------------------------------------------------------------------------

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
	# Phase 1 does not assert display output — just that the call is safe.
	var slot: StorySlot = _make_slot("test", "Test Story", Color.BLUE)
	autofree(slot)

	# Add to the tree so _ready() runs and child nodes exist before setup() is called.
	var card: StoryCard = add_child_autofree(StoryCard.new())

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
	var slot: StorySlot = _make_slot("slot_1", "My Story", Color.RED)
	autofree(slot)

	var card: StoryCard = add_child_autofree(StoryCard.new())
	card.setup(slot)

	assert_eq(card._slot, slot,
			"setup() must store the StorySlot in _slot so the card knows its data")
