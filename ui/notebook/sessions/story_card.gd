class_name StoryCard
extends VBoxContainer
## A single card in the Sessions tab representing one saved story slot.
##
## The card is a vertical column of:
##   1. A Label showing the story's display name.
##   2. A ColorRect showing the story's cover colour (16×16 px swatch).
##   3. A Label showing the last-played date (hardcoded "N/A" in Phase 1).
##   4. A Button labelled "Switch to this Story" — emits
##      GameEvents.story_switch_requested(slot_id) when pressed (Slice 6).
##
## The static layout (NameLabel, CoverRect, LastPlayedLabel, SwitchButton)
## lives in story_card.tscn as saved editor nodes. This script handles only
## data binding (setup()) and signal wiring. This mirrors the pattern
## established by QuestRow in quest_row.gd / quest_row.tscn.
##
## Call setup(slot) after adding this node to the tree to populate it with
## data from a StorySlot resource.
##
## See: docs/features/notebook/design.md §5 (Sessions Tab)
## See: docs/features/game-data/design.md §6, §10 (save/load wiring)


# ---------------------------------------------------------------------------
# Private vars
# ---------------------------------------------------------------------------

# The slot this card represents. Set by setup().
var _slot: StorySlot


# ---------------------------------------------------------------------------
# @onready vars
# ---------------------------------------------------------------------------

# The label that shows the story's display name. Declared in story_card.tscn.
# setup() writes slot.display_name into this label after the node is in the tree.
# https://docs.godotengine.org/en/stable/classes/class_label.html
@onready var _name_label: Label = $NameLabel

# The colour swatch giving the player a quick visual handle for recognising
# their story. 16×16 px matches the low-res aesthetic; declared in story_card.tscn.
# https://docs.godotengine.org/en/stable/classes/class_colorrect.html
@onready var _cover_rect: ColorRect = $CoverRect

# Intentionally NOT written by setup() in Phase 1 — the "Last played: N/A"
# default text is baked into story_card.tscn as an editor property.
# Phase 2 will write a formatted last-played timestamp (e.g. "Last played: 3 Apr 2026") here.
@onready var _last_played_label: Label = $LastPlayedLabel

# The switch-story button. Pressing it emits GameEvents.story_switch_requested
# with this card's slot id (Slice 6). Declared in story_card.tscn.
# https://docs.godotengine.org/en/stable/classes/class_button.html
@onready var _switch_button: Button = $SwitchButton


# ---------------------------------------------------------------------------
# Built-in overrides
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Wire the pressed signal so the button is not a dead widget.
	# https://docs.godotengine.org/en/stable/classes/class_signal.html#class-signal-method-connect
	_switch_button.pressed.connect(_on_switch_pressed)


# ---------------------------------------------------------------------------
# Public methods
# ---------------------------------------------------------------------------

## Populate the card with data from slot.
## Must be called after the node is in the scene tree (so _ready() has run
## and @onready refs are guaranteed non-null before data is written).
## @param slot - the StorySlot resource this card represents.
func setup(slot: StorySlot) -> void:
	_slot = slot
	_name_label.text = slot.display_name
	_cover_rect.color = slot.cover_color
	# _last_played_label stays "Last played: N/A" in Phase 1 regardless of
	# slot.last_played — the Phase-1 copy is saved as an editor property
	# in story_card.tscn rather than set here.


# ---------------------------------------------------------------------------
# Private methods
# ---------------------------------------------------------------------------

## Called when the player presses "Switch to this Story".
## Emits GameEvents.story_switch_requested with this card's slot id so a
## listener (the Sessions tab) can call SaveManager.load_slot()/new_game()
## and rebind the rest of the UI via player_data_loaded/story_loaded.
## https://docs.godotengine.org/en/stable/classes/class_signal.html#class-signal-method-emit
func _on_switch_pressed() -> void:
	GameEvents.story_switch_requested.emit(_slot.slot_id)
