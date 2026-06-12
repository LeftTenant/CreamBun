class_name QuestsTab
extends NotebookTab
## The Quests tab of the in-game notebook.
##
## Phase 1 shows a list of quests on the left page. Clicking a quest selects
## it and populates the right page with the title, description, and an
## objective checklist derived from QuestLog progress data.
##
## Quest progress is read from PlayerData.quest_log (see autoloads/player_data.gd).
## The foraging book intro quest is pre-seeded as COMPLETED by
## PlayerDataResource._seed_starter_content() — every new player has a
## non-empty quest log from the first notebook open, with exactly one
## seeding location (the design's single source of truth, see
## docs/features/game-data/design.md §9.2).
##
## Quest definitions live in .tres files (one per quest) and are loaded at
## runtime. Phase 1 contains exactly one quest. Phase 2 will load all quests
## from a directory scan so new quests can be added without touching this file.
##
## The static layout (LeftPage subtree with ActiveSection, CompletedSeparator,
## CompletedSection; RightPage subtree with Placeholder and QuestDetail) lives
## in quests_tab.tscn. populate_left() / populate_right() instantiate that
## scene once, extract and reparent the page subtrees, then bind data.
## This is the same pattern established in InventoryTab (Slice 2).
##
## Design doc: docs/features/notebook/design.md §3.3 (Quests Tab)
## Refactor:   docs/refactors/notebook-ui-scene-migration.md


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# The scene that holds the complete static layout for this tab.
# Loaded once at class parse time; Godot caches PackedScene objects so
# multiple instantiate() calls are cheap.
# https://docs.godotengine.org/en/stable/classes/class_packedscene.html
const TAB_SCENE: PackedScene = preload("res://ui/notebook/quests/quests_tab.tscn")

# Row scene instantiated once per visible quest in the left page.
# Using scene instantiation (not QuestRow.new()) so that @onready refs
# inside quest_row.gd are fully resolved when setup() writes to them.
const QUEST_ROW_SCENE: PackedScene = preload("res://ui/notebook/quests/quest_row.tscn")


# ---------------------------------------------------------------------------
# Private vars
# ---------------------------------------------------------------------------

# All quest definitions loaded at startup. Phase 1: one entry.
# Phase 2 will replace the hardcoded array with a directory scan.
var _quests: Array[QuestData] = []

# The quest the player last clicked. Null means "no selection" and the right
# page shows the placeholder prompt instead of quest detail.
var _selected_quest: QuestData = null

# The RightPage VBoxContainer extracted from TAB_SCENE.
# _refresh_right_page() frees and rebuilds children of this node so we store
# it rather than the outer parent passed to populate_right().
# Null until _ensure_pages_built() is first called.
var _right_page: VBoxContainer = null

# Cached LeftPage VBoxContainer extracted from TAB_SCENE.
# Populated on the first populate_left() or populate_right() call and reused
# for the second call so we only pay the instantiation cost once per lifetime.
var _left_page: VBoxContainer = null


# ---------------------------------------------------------------------------
# Built-in overrides
# ---------------------------------------------------------------------------

func _ready() -> void:
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

## Populate the left page with one QuestRow per quest, sorted into
## ActiveSection and CompletedSection, with CompletedSeparator shown only
## when both buckets are non-empty.
##
## Extracts the LeftPage subtree from quests_tab.tscn, reparents it into
## parent, then walks the _quests array to instantiate one QuestRow per entry
## and add each row to the appropriate named section container.
##
## @param parent - the Control that will hold the left-page content.
##                 Per NotebookTab contract: guard against null.
func populate_left(parent: Control) -> void:
	if parent == null:
		return

	_ensure_pages_built()

	# Guard against re-entry: if _left_page already has a parent (e.g. because
	# populate_left() is called twice on the same QuestsTab instance in a test),
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

	# Resolve the named section containers from the LeftPage subtree.
	# Using get_node() here (not @onready) because the tree shape is per-call —
	# the nodes live under _left_page, which is extracted in _ensure_pages_built().
	var active_section: VBoxContainer = _left_page.get_node("ActiveSection") as VBoxContainer
	var separator: Label = _left_page.get_node("CompletedSeparator") as Label
	var completed_section: VBoxContainer = _left_page.get_node("CompletedSection") as VBoxContainer

	# Guard against a renamed or missing section node in the .tscn — gives a
	# clear message pointing to exactly which node and scene file is wrong,
	# rather than a cryptic null-reference crash inside _add_quest_row().
	# Mirrors the existing separator guard below.
	if active_section == null:
		push_warning("QuestsTab.populate_left: 'ActiveSection' node not found in quests_tab.tscn — check node name matches")
		return
	if completed_section == null:
		push_warning("QuestsTab.populate_left: 'CompletedSection' node not found in quests_tab.tscn — check node name matches")
		return

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

	# Add ACTIVE rows into ActiveSection.
	for quest in active_quests:
		_add_quest_row(quest, QuestLog.Status.ACTIVE, active_section)

	# Separator only appears when both buckets are non-empty, so Phase 1
	# (all quests completed) does not show an orphaned divider above the list.
	if separator != null:
		separator.visible = (not active_quests.is_empty() and not completed_quests.is_empty())

	# Add COMPLETED rows into CompletedSection.
	for quest in completed_quests:
		_add_quest_row(quest, QuestLog.Status.COMPLETED, completed_section)


## Store the right-page parent and render the initial state (placeholder or
## detail if a quest is already selected from a previous open).
##
## Extracts the RightPage subtree from quests_tab.tscn, reparents it into
## parent, then calls _refresh_right_page() to render the initial state.
## _right_page is stored so subsequent ViewButton presses can call
## _refresh_right_page() without needing the parent passed in again.
##
## @param parent - the Control that will hold the right-page content.
##                 Per NotebookTab contract: guard against null.
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

	# Render the initial state. _refresh_right_page() operates on _right_page's
	# children, rebuilding them from scratch each call — see that method for details.
	_refresh_right_page()


# ---------------------------------------------------------------------------
# Private methods
# ---------------------------------------------------------------------------

## Instantiate TAB_SCENE once per QuestsTab lifetime, extract both page
## VBoxContainers, and discard the scene shell. Called at the start of each
## populate_* method so either method can be called first.
##
## Mirrors InventoryTab._ensure_pages_built() exactly — see that method for
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


## Build one QuestRow from the scene and append it to the given section container.
## Connects the row's view_requested signal so pressing ViewButton selects the quest.
##
## Using QUEST_ROW_SCENE.instantiate() (not QuestRow.new()) because @onready refs
## inside quest_row.gd (TitleLabel, ViewButton) only resolve when the node is
## instantiated from the scene — bare .new() would leave them null.
##
## @param quest   - the QuestData to display
## @param status  - the QuestLog.Status int to pass to QuestRow.setup()
## @param section - the VBoxContainer to append the row into
func _add_quest_row(quest: QuestData, status: int, section: VBoxContainer) -> void:
	# Instantiate from scene so @onready refs (TitleLabel, ViewButton) resolve.
	# https://docs.godotengine.org/en/stable/classes/class_packedscene.html
	var row: QuestRow = QUEST_ROW_SCENE.instantiate() as QuestRow
	section.add_child(row)
	row.setup(quest, status)

	# Connect the row's view_requested signal so pressing its ViewButton calls
	# _select_quest() with the correct quest. We capture quest in a local variable
	# so the lambda closes over the right value — GDScript closures capture by
	# reference, meaning a bare `quest` in a loop body would bind the loop variable
	# (which changes each iteration) rather than the current iteration's value.
	# https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html#lambdas
	var captured_quest: QuestData = quest
	row.view_requested.connect(func(_r: QuestRow) -> void: _select_quest(captured_quest))


## Look up the current status for a quest id.
## Quests absent from the log are treated as HIDDEN so the UI does not show
## quests the player has not yet encountered.
##
## Reads from PlayerData.quest_log — the single source of truth for quest
## progress (see docs/features/game-data/design.md §7.1: reads go straight
## through the autoload).
##
## @param quest_id - the StringName id from QuestData.id
## @return a QuestLog.Status int
func _get_status(quest_id: StringName) -> int:
	if PlayerData.quest_log.states.has(quest_id):
		return PlayerData.quest_log.states[quest_id]["status"] as int
	return QuestLog.Status.HIDDEN


## Record the newly selected quest and refresh the right page to show detail.
## Called via the view_requested signal connection made in _add_quest_row().
##
## @param quest - the QuestData the player wants to inspect
func _select_quest(quest: QuestData) -> void:
	_selected_quest = quest
	_refresh_right_page()


## Clear the right page and rebuild its content to match the current selection.
## Called by populate_right() on first open and by _select_quest() on every
## ViewButton press so the page stays in sync with the selection state.
##
## APPROACH: free all children of _right_page and rebuild from scratch each call.
## This mirrors the original quests_tab.gd approach and keeps the logic simple —
## the right page is only refreshed on player interaction, not every frame, so
## the cost of freeing lightweight Label/VBox nodes is negligible.
##
## WHY free-and-rebuild rather than hide/show the scene nodes:
## The integration tests use _find_labels() which recurses through ALL children
## including hidden ones. Hiding the Placeholder label would still leave it
## findable with "select a quest" text, failing the "placeholder is gone" assertion.
## Freeing it ensures it cannot be found.
##
## NOTE FOR FUTURE DEVELOPERS: quests_tab.tscn contains Placeholder and
## QuestDetail nodes under RightPage as an editor-visible layout contract —
## they document the intended right-page structure and are referenced by
## scene-contract tests. However, _ensure_pages_built() extracts the RightPage
## subtree from the scene shell and this method immediately frees all of its
## children on every call. This means neither Placeholder nor QuestDetail ever
## renders at runtime; they exist only as a spec visible in the Godot editor.
func _refresh_right_page() -> void:
	if _right_page == null:
		return

	# Remove all existing children so we start from a blank slate.
	# free() (not queue_free()) is intentional: Labels and VBoxes are leaf nodes
	# with no deferred logic, and we want them gone before we add new ones
	# so _find_labels() in tests sees a clean subtree.
	for child in _right_page.get_children():
		child.free()

	if _selected_quest == null:
		# No quest selected — show a plain instruction so the right page is not
		# blank on first open. The text matches the test's case-insensitive check
		# and the Placeholder node in quests_tab.tscn.
		var placeholder: Label = Label.new()
		placeholder.text = "Select a quest to see details."
		placeholder.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		placeholder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		placeholder.focus_mode = Control.FOCUS_NONE
		_right_page.add_child(placeholder)
		return

	# --- Quest detail view ---

	# VBoxContainer so title, description, and objectives stack vertically.
	# https://docs.godotengine.org/en/stable/classes/class_vboxcontainer.html
	var detail_vbox: VBoxContainer = VBoxContainer.new()
	detail_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_right_page.add_child(detail_vbox)

	# Quest title — displayed above the description.
	var title_label: Label = Label.new()
	title_label.text = _selected_quest.title
	title_label.focus_mode = Control.FOCUS_NONE
	# autowrap so long titles do not overflow the page width.
	# https://docs.godotengine.org/en/stable/classes/class_label.html#class-label-property-autowrap-mode
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_vbox.add_child(title_label)

	# Quest description — narrative flavour text below the title.
	var desc_label: Label = Label.new()
	desc_label.text = _selected_quest.description
	desc_label.focus_mode = Control.FOCUS_NONE
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_vbox.add_child(desc_label)

	# Objectives checklist — each entry shows [x] if completed or [ ] if not.
	# Phase 1 derives completion from the completed_objectives index list stored
	# in the log entry. We do not need the status int here — only the indices.
	# Read from PlayerData.quest_log — see _get_status() for the same pattern.
	var completed_indices: Array = []

	if PlayerData.quest_log.states.has(_selected_quest.id):
		var entry: Dictionary = PlayerData.quest_log.states[_selected_quest.id] as Dictionary
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
		obj_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		detail_vbox.add_child(obj_label)
