class_name SessionsTab
extends NotebookTab
## The Sessions tab of the in-game notebook.
##
## Phase 1 shows a single "Default Story" card on the left page and a static
## placeholder message on the right page. The card is non-interactive beyond
## logging a warning when the switch button is pressed.
##
## In later phases this tab will list all saved story slots and let the player
## rename, delete, or switch between them.
##
## The static layout (LeftPage subtree with CardsContainer; RightPage subtree
## with Placeholder) lives in sessions_tab.tscn. populate_left() /
## populate_right() instantiate that scene once, extract and reparent the page
## subtrees, then bind data. This is the same pattern established in
## QuestsTab / InventoryTab (Slices 3 and 2).
##
## Design doc: docs/features/notebook/design.md §5 (Sessions Tab)
## Refactor:   docs/refactors/notebook-ui-scene-migration.md


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# The scene that holds the complete static layout for this tab.
# Loaded once at class parse time; Godot caches PackedScene objects so
# multiple instantiate() calls are cheap.
# https://docs.godotengine.org/en/stable/classes/class_packedscene.html
const TAB_SCENE: PackedScene = preload("res://ui/notebook/sessions/sessions_tab.tscn")

# Card scene instantiated once per visible story slot in the left page.
# Using scene instantiation (not StoryCard.new()) so that @onready refs
# inside story_card.gd are fully resolved when setup() writes to them.
const STORY_CARD_SCENE: PackedScene = preload("res://ui/notebook/sessions/story_card.tscn")


# ---------------------------------------------------------------------------
# Private vars
# ---------------------------------------------------------------------------

# The built-in "Default Story" slot that always exists even before the player
# creates any saves. Created in _ready() so it is always available.
var _default_slot: StorySlot

# Cards that were added to the left page in the most recent populate_left()
# call. Cleared and rebuilt on every call so repeated calls yield exactly one
# card (D1 fix: see populate_left() below).
var _left_cards: Array[StoryCard] = []

# Cached LeftPage VBoxContainer extracted from TAB_SCENE.
# Populated on the first populate_left() or populate_right() call and reused
# for the second call so we only pay the instantiation cost once per lifetime.
# Null until _ensure_pages_built() is first called.
var _left_page: VBoxContainer = null

# Cached RightPage VBoxContainer extracted from TAB_SCENE.
# The Placeholder Label lives here as a static scene node (D2: purely static).
# Null until _ensure_pages_built() is first called.
var _right_page: VBoxContainer = null


# ---------------------------------------------------------------------------
# Built-in overrides
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Build the default slot here rather than as a class constant so that
	# StorySlot properties (which come from a Resource) are available.
	# The warm-brown colour (0.6, 0.4, 0.2) evokes a well-worn journal cover.
	_default_slot = StorySlot.new()
	_default_slot.slot_id = "default"
	_default_slot.display_name = "Default Story"
	_default_slot.cover_color = Color(0.6, 0.4, 0.2)


# ---------------------------------------------------------------------------
# Public methods (override NotebookTab)
# ---------------------------------------------------------------------------

## Populate the left page with one StoryCard for the default slot.
##
## Extracts the LeftPage subtree from sessions_tab.tscn, reparents it into
## parent, then clears any stale cards and instantiates a fresh StoryCard.
## Clearing stale children before rebuilding is the D1 fix: re-calling this
## method (e.g. when the player switches away and back) yields exactly one card,
## not an accumulating stack of duplicates.
##
## @param parent - the Control node that will hold the card children.
##                 Per NotebookTab contract: guard against null in implementations.
func populate_left(parent: Control) -> void:
	if parent == null:
		return

	_ensure_pages_built()

	# Guard against re-entry: if _left_page already has a parent (e.g. because
	# populate_left() is called twice on the same SessionsTab instance in a test),
	# detach it first so add_child does not fail.
	# https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-remove-child
	if _left_page.get_parent() != null:
		_left_page.get_parent().remove_child(_left_page)
	parent.add_child(_left_page)

	# Anchor the VBox to fill the parent page so children get a real width.
	# Without this, a plain Control parent won't resize its children automatically.
	# Negative right/bottom offsets apply a 10 px inset on all sides (rule 2, ui/CLAUDE.md).
	# https://docs.godotengine.org/en/stable/classes/class_control.html#class-control-method-set-anchors-and-offsets-preset
	_left_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_left_page.offset_left = 10
	_left_page.offset_top = 10
	_left_page.offset_right = -10
	_left_page.offset_bottom = -10

	# Resolve the CardsContainer from the LeftPage subtree.
	# Using get_node() here (not @onready) because the tree shape is per-call —
	# the node lives under _left_page, which is extracted in _ensure_pages_built().
	var cards_container: VBoxContainer = _left_page.get_node("CardsContainer") as VBoxContainer

	# Guard against a renamed or missing CardsContainer in the .tscn — gives a
	# clear message pointing to exactly which node and scene file is wrong,
	# rather than a cryptic null-reference crash.
	if cards_container == null:
		push_warning("SessionsTab.populate_left: 'CardsContainer' node not found in sessions_tab.tscn — check node name matches")
		return

	# D1 FIX: Clear stale cards from CardsContainer before rebuilding so
	# repeated populate_left() calls yield exactly one card, not duplicates.
	# This fixes the pre-migration bug where _left_cards was never cleared and
	# each call accumulated an extra StoryCard in the container.
	for stale_child in cards_container.get_children():
		stale_child.free()
	_left_cards.clear()

	# Phase 1: one card for the hardcoded default slot.
	# Phase 2 will iterate SaveManager's slot list and create a card per slot.
	# Using STORY_CARD_SCENE.instantiate() (not StoryCard.new()) so that
	# @onready refs inside story_card.gd resolve before setup() writes to them.
	# https://docs.godotengine.org/en/stable/classes/class_packedscene.html
	var card: StoryCard = STORY_CARD_SCENE.instantiate() as StoryCard
	cards_container.add_child(card)
	# setup() must be called after add_child so _ready() has already run and
	# @onready refs (_name_label, _cover_rect) are guaranteed non-null.
	# https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-add-child
	card.setup(_default_slot)
	_left_cards.append(card)


## Populate the right page with the static Placeholder Label.
##
## Extracts the RightPage subtree from sessions_tab.tscn and reparents it into
## parent. The Placeholder Label is declared as a static scene node — no dynamic
## content is added here (D2: right page is purely static for Phase 1).
##
## @param parent - the Control node that will hold the right-page content.
##                 Per NotebookTab contract: guard against null in implementations.
func populate_right(parent: Control) -> void:
	if parent == null:
		return

	_ensure_pages_built()

	# Guard against re-entry in the same way as populate_left().
	if _right_page.get_parent() != null:
		_right_page.get_parent().remove_child(_right_page)
	parent.add_child(_right_page)

	# Anchor + inset (same scheme as populate_left for consistent margins).
	_right_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_right_page.offset_left = 10
	_right_page.offset_top = 10
	_right_page.offset_right = -10
	_right_page.offset_bottom = -10

	# The Placeholder Label ("Select a Story to see details.") is a static
	# scene node in sessions_tab.tscn — nothing else is added here (D2).


# ---------------------------------------------------------------------------
# Private methods
# ---------------------------------------------------------------------------

## Instantiate TAB_SCENE once per SessionsTab lifetime, extract both page
## VBoxContainers, and discard the scene shell. Called at the start of each
## populate_* method so either method can be called first.
##
## Mirrors QuestsTab._ensure_pages_built() exactly — see that method for
## the detailed rationale on owner-clearing and queue_free.
func _ensure_pages_built() -> void:
	if _left_page != null:
		# Already extracted on a previous call; nothing to do.
		return

	# Instantiate the scene to get a fully-formed node tree with editor
	# properties (labels, size flags, visibility) already applied.
	# https://docs.godotengine.org/en/stable/classes/class_packedscene.html#class-packedscene-method-instantiate
	var instance: Control = TAB_SCENE.instantiate() as Control

	# Grab references before detaching.
	_left_page = instance.get_node("LeftPage") as VBoxContainer
	_right_page = instance.get_node("RightPage") as VBoxContainer

	# Detach both pages so they survive when the shell is freed.
	# remove_child does not free the node — it simply unparents it.
	# https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-remove-child
	instance.remove_child(_left_page)
	instance.remove_child(_right_page)

	# Clear the owner on both detached pages to prevent Godot from emitting an
	# owner-inconsistency warning when they are add_child'd into a different tree.
	# GUT counts those warnings as test failures, so we sever the link here.
	# https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-property-owner
	_left_page.owner = null
	_right_page.owner = null

	# Free the bare scene shell — we removed everything we care about.
	# queue_free defers to end-of-frame; safe because the pages are detached.
	# https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-queue-free
	instance.queue_free()
