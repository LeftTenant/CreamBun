class_name StoryCard
extends VBoxContainer
## A single card in the Sessions tab representing one saved story slot.
##
## The card is a vertical column of:
##   1. A Label showing the story's display name.
##   2. A ColorRect showing the story's cover colour (16×16 px swatch).
##   3. A Label showing the last-played date (hardcoded "N/A" in Phase 1).
##   4. A Button labelled "Switch to this Story" (no-op in Phase 1).
##
## Call setup(slot) after adding this node to the tree to populate it with
## data from a StorySlot resource.
##
## Phase 2 will wire the button to GameEvents.story_switch_requested.
## See: docs/features/notebook/design.md §5 (Sessions Tab)


# The slot this card represents. Set by setup().
var _slot: StorySlot

# Child node references — assigned in _ready() so setup() can update them
# without needing to call get_node() every time.
var _name_label: Label
var _cover_rect: ColorRect
var _last_played_label: Label
var _switch_button: Button


# ---------------------------------------------------------------------------
# Built-in overrides
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Build the card's visual children here so the scene file stays minimal.
	# Each child is created and added in display order (top to bottom).
	# See: https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-add-child

	_name_label = Label.new()
	_name_label.text = ""  # populated by setup()
	add_child(_name_label)

	# The colour swatch gives the player a quick visual handle for recognising
	# their story. 16×16 px matches the low-res aesthetic of the 320×180 viewport.
	_cover_rect = ColorRect.new()
	_cover_rect.custom_minimum_size = Vector2(16.0, 16.0)
	_cover_rect.color = Color.WHITE  # overridden by setup()
	add_child(_cover_rect)

	_last_played_label = Label.new()
	# Phase 1: we do not yet read real timestamps from StorySlot.last_played,
	# so the label is hardcoded. Phase 2 will format last_played into a readable
	# date string (e.g. "Last played: 3 Apr 2026").
	_last_played_label.text = "Last played: N/A"
	add_child(_last_played_label)

	_switch_button = Button.new()
	_switch_button.text = "Switch to this Story"
	# Connect the pressed signal so the button is not a dead widget. In Phase 1
	# _on_switch_pressed only logs a warning; Phase 2 will emit the real signal.
	# https://docs.godotengine.org/en/stable/classes/class_signal.html#class-signal-method-connect
	_switch_button.pressed.connect(_on_switch_pressed)
	add_child(_switch_button)


# ---------------------------------------------------------------------------
# Public methods
# ---------------------------------------------------------------------------

## Populate the card with data from slot.
## Must be called after the node is in the scene tree (so _ready() has run
## and child labels/rects exist).
## @param slot - the StorySlot resource this card represents.
func setup(slot: StorySlot) -> void:
	_slot = slot
	_name_label.text = slot.display_name
	_cover_rect.color = slot.cover_color
	# last_played_label stays "N/A" in Phase 1 regardless of slot.last_played.


# ---------------------------------------------------------------------------
# Private methods
# ---------------------------------------------------------------------------

## Called when the player presses "Switch to this Story".
## Phase 1: logs a warning so developers know the button is connected but
## not yet implemented. Phase 2: emits GameEvents.story_switch_requested.
func _on_switch_pressed() -> void:
	# push_warning() appears in the Godot editor Output panel without crashing
	# the game. It signals that this path is intentionally unfinished.
	# https://docs.godotengine.org/en/stable/classes/class_@globalscope.html#class-globalscope-method-push-warning
	push_warning("StoryCard: Switch to this Story pressed — not yet implemented (Phase 2).")
