class_name QuestsTab
extends NotebookTab
## The Quests tab of the in-game notebook.
##
## Phase 1 shows a list of quests on the left page. Clicking a quest selects
## it and populates the right page with the title, description, and an
## objective checklist derived from QuestLog progress data.
##
## The foraging book intro quest is pre-seeded as COMPLETED in _ready() so
## every new player has a non-empty quest log from the first notebook open.
##
## Quest definitions live in .tres files (one per quest) and are loaded at
## runtime. Phase 1 contains exactly one quest. Phase 2 will load all quests
## from a directory scan so new quests can be added without touching this file.
##
## Design doc: docs/features/notebook/design.md §3.3 (Quests Tab)


# ---------------------------------------------------------------------------
# Private vars
# ---------------------------------------------------------------------------

# The player's quest progress. Built in _ready() and pre-populated with the
# intro quest so the list is never empty on first open.
var _quest_log: QuestLog

# All quest definitions loaded at startup. Phase 1: one entry.
# Phase 2 will replace the hardcoded array with a directory scan.
var _quests: Array[QuestData] = []

# The quest the player last clicked. Null means "no selection" and the right
# page shows the placeholder prompt instead of quest detail.
var _selected_quest: QuestData = null

# Stored in populate_right() so _refresh_right_page() can clear and rebuild
# the right page without needing the parent passed down again.
# Null until populate_right() is first called.
var _right_page_parent: Control = null


# ---------------------------------------------------------------------------
# Built-in overrides
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Create a fresh log so this tab owns its own mutable state rather than
	# sharing a singleton. Phase 2 will replace this with a SaveManager load.
	_quest_log = QuestLog.new()

	# Seed the foraging book as COMPLETED — it is the intro quest that every
	# player receives from Doug before they start foraging. Marking it complete
	# at startup gives the player a sense of history and shows how the COMPLETED
	# visual treatment (dim + checkmark) looks in practice.
	#
	# The dictionary value mirrors the format SaveManager will use for persistence
	# so we do not need a schema migration when saving is wired up in Phase 2.
	# completed_objectives lists the indices of each objective in QuestData.objectives.
	_quest_log.states[&"the_foraging_book"] = {
		"status": QuestLog.Status.COMPLETED,
		"completed_objectives": [0, 1, 2],
	}

	# Load quest definitions. The resource is loaded once at startup and held
	# for the session lifetime — .tres files are cached by Godot's ResourceLoader
	# so subsequent loads return the same object without re-parsing the file.
	# https://docs.godotengine.org/en/stable/classes/class_resourceloader.html
	var foraging_book: QuestData = load(
			"res://resources/data/quests/the_foraging_book.tres") as QuestData
	assert(foraging_book != null,
			"Could not load the_foraging_book.tres — check the file exists and is imported")
	if foraging_book != null:
		_quests.append(foraging_book)


# ---------------------------------------------------------------------------
# Public methods (override NotebookTab)
# ---------------------------------------------------------------------------

## Populate the left page with one QuestRow per quest.
## Quests are sorted: ACTIVE entries first, then a divider, then COMPLETED.
## Each row has an invisible Button overlay so the player can click to select.
##
## @param parent - the Control that will hold the left-page content.
##                 Per NotebookTab contract: guard against null.
func populate_left(parent: Control) -> void:
	if parent == null:
		return

	# VBoxContainer stacks rows vertically with automatic spacing.
	# https://docs.godotengine.org/en/stable/classes/class_vboxcontainer.html
	var vbox: VBoxContainer = VBoxContainer.new()
	parent.add_child(vbox)
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Split quests into two buckets so ACTIVE work appears at the top and
	# COMPLETED entries are relegated to a clearly labelled section below.
	var active_quests: Array[QuestData] = []
	var completed_quests: Array[QuestData] = []

	for quest in _quests:
		var status: int = _get_status(quest.id)
		if status == QuestLog.Status.ACTIVE:
			active_quests.append(quest)
		elif status == QuestLog.Status.COMPLETED:
			completed_quests.append(quest)
		# HIDDEN quests are omitted entirely — the player has not unlocked them yet.

	# Add ACTIVE rows first.
	for quest in active_quests:
		_add_quest_row(quest, QuestLog.Status.ACTIVE, vbox)

	# Separator only appears when both buckets are non-empty, so Phase 1
	# (all quests completed) does not show an orphaned divider above the list.
	if not active_quests.is_empty() and not completed_quests.is_empty():
		var separator: Label = Label.new()
		separator.text = "— Completed —"
		separator.focus_mode = Control.FOCUS_NONE
		vbox.add_child(separator)

	# Add COMPLETED rows below the separator.
	for quest in completed_quests:
		_add_quest_row(quest, QuestLog.Status.COMPLETED, vbox)


## Store the right-page parent and render the initial state (placeholder or
## detail if a quest is already selected from a previous open).
##
## @param parent - the Control that will hold the right-page content.
##                 Per NotebookTab contract: guard against null.
func populate_right(parent: Control) -> void:
	if parent == null:
		return

	# Store so _refresh_right_page() can rebuild without an extra argument.
	_right_page_parent = parent
	_refresh_right_page()


# ---------------------------------------------------------------------------
# Private methods
# ---------------------------------------------------------------------------

## Look up the current status for a quest id.
## Quests absent from the log are treated as HIDDEN so the UI does not show
## quests the player has not yet encountered.
##
## @param quest_id - the StringName id from QuestData.id
## @return a QuestLog.Status int
func _get_status(quest_id: StringName) -> int:
	if _quest_log.states.has(quest_id):
		return _quest_log.states[quest_id]["status"] as int
	return QuestLog.Status.HIDDEN


## Build one QuestRow + a transparent selection Button and append both to vbox.
## The Button sits on top of the row (via a container trick) to capture clicks;
## in Phase 1 we keep it simple and just stack a Button after the row, relying
## on the player clicking the button text rather than the row graphic.
##
## Phase 2 will replace the Button with a proper clickable panel that highlights
## the full row on hover.
##
## @param quest  - the QuestData to display
## @param status - the QuestLog.Status int to pass to QuestRow.setup()
## @param vbox   - the VBoxContainer to append the row into
func _add_quest_row(quest: QuestData, status: int, vbox: VBoxContainer) -> void:
	# QuestRow builds its own child nodes in _ready(), so add it to the tree
	# before calling setup() — otherwise the labels do not exist yet.
	var row: QuestRow = QuestRow.new()
	vbox.add_child(row)
	row.setup(quest, status)

	# A Button below the row gives the player a clear tap target. In Phase 2
	# this will be replaced by an invisible Control covering the full row width.
	var btn: Button = Button.new()
	btn.text = "View"
	# Capture quest in a local so the lambda closure binds the correct value
	# (GDScript closures capture by reference, so using `quest` directly inside
	# a loop would bind the loop variable — which changes each iteration).
	# https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html#lambdas
	var captured_quest: QuestData = quest
	btn.pressed.connect(func() -> void: _select_quest(captured_quest))
	vbox.add_child(btn)


## Record the newly selected quest and refresh the right page to show detail.
## Called by the "View" button pressed signal for each quest row.
##
## @param quest - the QuestData the player wants to inspect
func _select_quest(quest: QuestData) -> void:
	_selected_quest = quest
	_refresh_right_page()


## Clear the right page and rebuild its content to match the current selection.
## Called by populate_right() and _select_quest() so the page stays in sync.
func _refresh_right_page() -> void:
	if _right_page_parent == null:
		return

	# Remove all existing children so we start from a blank slate.
	# We free them immediately because Control nodes are lightweight and the
	# right page is only refreshed on player interaction, not every frame.
	for child in _right_page_parent.get_children():
		child.free()

	if _selected_quest == null:
		# No quest selected — show a plain instruction so the right page is not
		# blank on first open. The text matches the test's case-insensitive check.
		var placeholder: Label = Label.new()
		placeholder.text = "Select a quest to see details."
		_right_page_parent.add_child(placeholder)
		return

	# --- Quest detail view ---

	# VBoxContainer so title, description, and objectives stack vertically.
	var vbox: VBoxContainer = VBoxContainer.new()
	_right_page_parent.add_child(vbox)
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Quest title — displayed large/bold via theme in the editor; for Phase 1
	# we set the label's text and rely on the notebook theme for styling.
	var title_label: Label = Label.new()
	title_label.text = _selected_quest.title
	title_label.focus_mode = Control.FOCUS_NONE
	# autowrap so long titles do not overflow the page width.
	# https://docs.godotengine.org/en/stable/classes/class_label.html#class-label-property-autowrap-mode
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(title_label)

	# Quest description — narrative flavour text below the title.
	var desc_label: Label = Label.new()
	desc_label.text = _selected_quest.description
	desc_label.focus_mode = Control.FOCUS_NONE
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc_label)

	# Objectives checklist — each entry shows [x] if completed or [ ] if not.
	# Phase 1 derives completion from the completed_objectives index list stored
	# in the log entry. We do not need the status int here — only the indices.
	var completed_indices: Array = []

	if _quest_log.states.has(_selected_quest.id):
		var entry: Dictionary = _quest_log.states[_selected_quest.id] as Dictionary
		if entry.has("completed_objectives"):
			completed_indices = entry["completed_objectives"] as Array

	for i in range(_selected_quest.objectives.size()):
		var objective_text: String = _selected_quest.objectives[i]
		var is_done: bool = completed_indices.has(i)

		var obj_label: Label = Label.new()
		# Prefix with a checkbox-style indicator so the checklist reads cleanly
		# in the plain-text style of the notebook aesthetic.
		obj_label.text = "[x] " + objective_text if is_done else "[ ] " + objective_text
		obj_label.focus_mode = Control.FOCUS_NONE
		obj_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(obj_label)
