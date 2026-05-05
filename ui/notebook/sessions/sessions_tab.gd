class_name SessionsTab
extends NotebookTab
## The Sessions tab of the in-game notebook.
##
## Phase 1 shows a single "Default Story" card on the left page and a
## placeholder message on the right page. The card is non-interactive beyond
## logging a warning when the switch button is pressed.
##
## In later phases this tab will list all saved story slots and let the player
## rename, delete, or switch between them.
##
## Design doc: docs/features/notebook/design.md §5 (Sessions Tab)


# The built-in "Default Story" slot that always exists even before the player
# creates any saves. Created in _ready() so it is always available.
var _default_slot: StorySlot

# Cards that were added to the left page in the most recent populate_left()
# call. Kept so a future refresh pass can remove stale cards before rebuilding.
var _left_cards: Array[StoryCard] = []


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
## @param parent - the Control node that will hold the card children.
##                 Per NotebookTab contract: guard against null in implementations.
func populate_left(parent: Control) -> void:
	if parent == null:
		return

	# Phase 1: one card for the hardcoded default slot.
	# Phase 2 will iterate SaveManager's slot list and create a card per slot.
	# TODO (Phase 2): clear _left_cards and remove stale children from parent
	# before rebuilding, so re-activating the tab does not duplicate cards.
	var card: StoryCard = StoryCard.new()
	parent.add_child(card)
	# setup() must be called after add_child so _ready() has already run and
	# the card's child labels/rects exist.
	# https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-add-child
	card.setup(_default_slot)
	_left_cards.append(card)


## Populate the right page with a placeholder message.
## Phase 2 will replace this with full slot detail (playtime, rename, delete).
## @param parent - the Control node that will hold the placeholder Label.
##                 Per NotebookTab contract: guard against null in implementations.
func populate_right(parent: Control) -> void:
	if parent == null:
		return

	var label: Label = Label.new()
	# The placeholder guides the player: clicking a card on the left will
	# eventually show its details here. For Phase 1 no card interaction exists,
	# so the text is a passive instruction rather than a prompt.
	label.text = "Select a Story to see details."
	parent.add_child(label)
