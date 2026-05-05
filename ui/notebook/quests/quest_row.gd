class_name QuestRow
extends HBoxContainer
## A single row in the Quests tab list representing one quest entry.
##
## The row shows a status icon on the left (✓ / •) and the quest title to
## the right. Call setup() after adding this node to the tree so that
## _ready() has already run and child nodes exist.
##
## Visual treatment by status:
##   ACTIVE    — bullet "•", full opacity
##   COMPLETED — checkmark "✓", dimmed to 0.6 alpha (still readable but
##               visually separated from active work)
##   HIDDEN    — blank icon, full opacity (quest is known internally but
##               not yet revealed to the player)
##
## Phase 2 will add a pressed signal and selection highlight.


# The quest this row represents. Set by setup().
var _quest: QuestData

# The raw QuestLog.Status int for this entry. Set by setup().
var _status: int

# Child label references — assigned in _ready() so setup() can update them
# without calling find_child() on every refresh.
var _status_icon: Label
var _title_label: Label


# ---------------------------------------------------------------------------
# Built-in overrides
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Build child nodes here so the scene file stays a minimal stub.
	# Both children are created and added left-to-right (HBoxContainer order).
	# https://docs.godotengine.org/en/stable/classes/class_hboxcontainer.html

	_status_icon = Label.new()
	# Fixed width keeps the title column aligned across all rows regardless of
	# which icon character is used. 16 px is enough for a single glyph at our
	# target font sizes.
	_status_icon.custom_minimum_size = Vector2(16.0, 0.0)
	# Suppress focus so Tab moves to the quest title, not the icon.
	# https://docs.godotengine.org/en/stable/classes/class_control.html#enum-control-focusmode
	_status_icon.focus_mode = Control.FOCUS_NONE
	add_child(_status_icon)

	_title_label = Label.new()
	# Allow the title to expand horizontally and fill remaining row space.
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.focus_mode = Control.FOCUS_NONE
	add_child(_title_label)


# ---------------------------------------------------------------------------
# Public methods
# ---------------------------------------------------------------------------

## Populate the row with data from quest and apply the matching visual style.
## Must be called after the node is in the scene tree (so _ready() has run).
##
## @param quest  - the QuestData resource this row represents
## @param status - a QuestLog.Status int (ACTIVE=0, COMPLETED=1, HIDDEN=2)
func setup(quest: QuestData, status: int) -> void:
	_quest = quest
	_status = status

	_title_label.text = quest.title

	# Choose the icon based on completion state.
	# HIDDEN uses an empty string — the quest is internally tracked but the
	# player has not encountered it yet, so no indicator is shown.
	match status:
		QuestLog.Status.COMPLETED:
			_status_icon.text = "✓"  # ✓ check mark
		QuestLog.Status.ACTIVE:
			_status_icon.text = "•"  # • bullet
		_:
			_status_icon.text = ""

	# Dim completed quests so active work stands out, but keep them legible.
	# modulate.a controls the whole row's transparency including the icon.
	# https://docs.godotengine.org/en/stable/classes/class_canvasitem.html#class-canvasitem-property-modulate
	if status == QuestLog.Status.COMPLETED:
		modulate.a = 0.6
	else:
		modulate.a = 1.0
