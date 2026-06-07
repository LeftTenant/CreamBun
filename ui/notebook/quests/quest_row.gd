class_name QuestRow
extends HBoxContainer
## A single row in the Quests tab list representing one quest entry.
##
## The row shows a status icon on the left (✓ / •) and the quest title to
## the right. Call setup() after adding this node to the tree so that
## @onready refs are guaranteed non-null before data is written.
##
## Static layout (TitleLabel, ViewButton) lives in quest_row.tscn — this
## script only handles data binding, dimming, and the view_requested signal
## that quests_tab.gd connects to when building the row list.
##
## Visual treatment by status:
##   ACTIVE    — bullet "•", full opacity
##   COMPLETED — checkmark "✓", dimmed to 0.6 alpha (still readable but
##               visually separated from active work)
##   HIDDEN    — blank icon, full opacity (quest is known internally but
##               not yet revealed to the player)
##
## Design doc: docs/features/notebook/design.md §3.3 (Quests Tab)
## Refactor:   docs/refactors/notebook-ui-scene-migration/design.md


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted when the player presses this row's ViewButton.
## quests_tab.gd connects to this signal after instantiating each row so
## it can call _select_quest() without the row knowing about the tab.
## Using a signal here (rather than the tab connecting to the Button directly)
## keeps QuestRow self-contained and matches the InventoryRow.selected pattern.
signal view_requested(row: QuestRow)


# ---------------------------------------------------------------------------
# Private vars
# ---------------------------------------------------------------------------

# The quest this row represents. Set by setup().
var _quest: QuestData

# The raw QuestLog.Status int for this entry. Set by setup().
var _status: int

# Status icon built in _ready() because it is not an editor-visible node.
# The icon character changes based on status (✓ / •) and lives to the left
# of TitleLabel inside the HBoxContainer. This remains a code-built node
# because quest_row.tscn only formalises TitleLabel and ViewButton as the
# two named nodes the tab needs by name.
var _status_icon: Label


# ---------------------------------------------------------------------------
# @onready vars
# ---------------------------------------------------------------------------

# The label that shows the quest title. Declared in quest_row.tscn as a
# named child so quests_tab.gd can reference it after B3 without find_child.
# SIZE_EXPAND_FILL lets it claim the horizontal space between the icon and
# the ViewButton; autowrap handles long titles gracefully.
# https://docs.godotengine.org/en/stable/classes/class_label.html
@onready var _title_label: Label = $TitleLabel

# The button the player presses to inspect this quest's details on the right page.
# Declared in quest_row.tscn so the scene is self-describing — a beginner
# opening the scene in the editor can see and restyle the button without
# reading GDScript.
# https://docs.godotengine.org/en/stable/classes/class_button.html
@onready var _view_button: Button = $ViewButton


# ---------------------------------------------------------------------------
# Built-in overrides
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Build the status-icon label and insert it before TitleLabel so the visual
	# left-to-right order is: icon | title | view-button.
	# We keep this in code rather than in the .tscn because the icon is an
	# implementation detail of the status rendering, not a named node the tab
	# needs to address. TitleLabel and ViewButton are the two named nodes that
	# quests_tab.gd addresses by name.
	# https://docs.godotengine.org/en/stable/classes/class_hboxcontainer.html
	_status_icon = Label.new()
	# Fixed width keeps the title column aligned across all rows regardless of
	# which icon character is used. 16 px is enough for a single glyph at our
	# target font sizes.
	_status_icon.custom_minimum_size = Vector2(16.0, 0.0)
	# Suppress focus so Tab moves to the quest title, not the icon.
	# https://docs.godotengine.org/en/stable/classes/class_control.html#enum-control-focusmode
	_status_icon.focus_mode = Control.FOCUS_NONE
	# Insert at index 0 so it appears left of TitleLabel in the HBoxContainer.
	# https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-add-child
	add_child(_status_icon)
	move_child(_status_icon, 0)

	# Wire the ViewButton so pressing it emits view_requested on this row.
	# quests_tab.gd connects to view_requested after instantiation and calls
	# _select_quest() with the quest this row represents.
	_view_button.pressed.connect(_on_view_button_pressed)


# ---------------------------------------------------------------------------
# Public methods
# ---------------------------------------------------------------------------

## Populate the row with data from quest and apply the matching visual style.
## Must be called after the node is in the scene tree (so _ready() has run
## and @onready refs are non-null).
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


# ---------------------------------------------------------------------------
# Private methods
# ---------------------------------------------------------------------------

## Called when the player presses the ViewButton on this row.
## Emits view_requested so quests_tab.gd (which connected to this signal
## during row construction) can call _select_quest() with our quest.
## The row intentionally does not know about the tab — the signal is the
## only coupling, which mirrors the InventoryRow.selected pattern.
func _on_view_button_pressed() -> void:
	view_requested.emit(self)
