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
## The static layout (NameLabel, CoverRect, LastPlayedLabel, SwitchButton)
## lives in story_card.tscn as saved editor nodes. This script handles only
## data binding (setup()) and signal wiring. This mirrors the pattern
## established by QuestRow in quest_row.gd / quest_row.tscn.
##
## Call setup(slot) after adding this node to the tree to populate it with
## data from a StorySlot resource.
##
## Phase 2 will wire the SwitchButton to GameEvents.story_switch_requested.
## See: docs/features/notebook/design.md §5 (Sessions Tab)


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

# The switch-story button. No-op in Phase 1; Phase 2 wires it to
# GameEvents.story_switch_requested. Declared in story_card.tscn.
# https://docs.godotengine.org/en/stable/classes/class_button.html
@onready var _switch_button: Button = $SwitchButton


# ---------------------------------------------------------------------------
# Built-in overrides
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Wire the pressed signal so the button is not a dead widget.
	# In Phase 1, _on_switch_pressed only logs a warning.
	# Phase 2 will emit the real GameEvents.story_switch_requested signal here.
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
## Phase 1: logs a warning so developers know the button is connected but
## not yet implemented. Phase 2: emits GameEvents.story_switch_requested.
func _on_switch_pressed() -> void:
	# push_warning() appears in the Godot editor Output panel without crashing
	# the game. It signals that this path is intentionally unfinished.
	# https://docs.godotengine.org/en/stable/classes/class_@globalscope.html#class-globalscope-method-push-warning
	push_warning("StoryCard: Switch to this Story pressed — not yet implemented (Phase 2).")
