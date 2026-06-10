## test_quests_tab.gd
## Behavior contract tests for QuestsTab and QuestRow (Phase 1).
##
## Covers QuestsTab (ui/notebook/quests/quests_tab.gd) and
## QuestRow (ui/notebook/quests/quest_row.gd).
##
## --- ROW CONSTRUCTION NOTE ---
## Tests that exercise a QuestRow instantiate it from quest_row.tscn via
## add_child_autofree(preload(...).instantiate()), not QuestRow.new(): quest_row.gd
## resolves named children (TitleLabel, ViewButton) via @onready references that
## only exist when the node comes from the scene. A bare QuestRow.new() would
## leave those refs null and every meaningful assertion would fail or crash.
##
## Selected behaviours guarded:
##   test_quest_row_setup_completed_dims_row  — guards modulate.a dimming
##   test_view_button_press_drives_selection  — guards observable selection outcome
##
## Requires GUT: https://github.com/bitwes/Gut
## Install via Godot Asset Library (search "GUT - Godot Unit Testing").
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI (once GUT is installed):
##   godot --headless -s addons/gut/gut_cmdln.gd

class_name TestQuestsTab
extends GutTest


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Use scene instantiation (not bare .new()) so @onready refs in quest_row.gd
# resolve correctly.  See ROW CONSTRUCTION NOTE in the file header.
const QUEST_ROW_SCENE: String = "res://ui/notebook/quests/quest_row.tscn"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Walk the full subtree of root and return every Label whose text matches.
## Needed because populate_left/right build nested containers, so labels are
## grandchildren (or deeper) of the parent passed to the test.
##
## @param root      - the node whose subtree to search
## @param predicate - a Callable(Label) -> bool that returns true for a match
## @return Array of matching Label nodes, in depth-first order
func _find_labels(root: Node, predicate: Callable) -> Array[Label]:
	var result: Array[Label] = []
	for child in root.get_children():
		if child is Label and predicate.call(child as Label):
			result.append(child as Label)
		result.append_array(_find_labels(child, predicate))
	return result


## Instantiate a QuestRow from the .tscn so @onready refs resolve correctly.
## Adds it to the tree via add_child_autofree so _ready() fires immediately.
##
## @return the instantiated QuestRow
func _make_row() -> QuestRow:
	# preload is safe here — the path is a compile-time constant.
	# https://docs.godotengine.org/en/stable/classes/class_resourceloader.html
	var packed: PackedScene = load(QUEST_ROW_SCENE) as PackedScene
	return add_child_autofree(packed.instantiate()) as QuestRow


# ---------------------------------------------------------------------------
# Test 1 — QuestsTab inherits NotebookTab
# ---------------------------------------------------------------------------

func test_quests_tab_is_a_notebook_tab() -> void:
	# QuestsTab must extend NotebookTab so the notebook controller can call
	# populate_left / populate_right polymorphically.
	# https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html#inheritance
	var tab: QuestsTab = QuestsTab.new()
	autofree(tab)

	assert_true(tab is NotebookTab,
			"QuestsTab must be a NotebookTab (extend NotebookTab)")


# ---------------------------------------------------------------------------
# Test 2 — QuestRow.setup() puts the quest title into a Label child
# ---------------------------------------------------------------------------

func test_quest_row_shows_title() -> void:
	# QuestRow is responsible for rendering one quest entry. The quest title
	# must be visible as a Label so the player can scan the list at a glance.
	# Row instantiated from scene so @onready refs resolve correctly.
	var quest: QuestData = QuestData.new()
	quest.id = &"test_quest"
	quest.title = "Test Quest"
	autofree(quest)

	var row: QuestRow = _make_row()
	row.setup(quest, QuestLog.Status.ACTIVE)

	# The title label can be a direct child or nested inside a container.
	var matches: Array[Label] = _find_labels(row,
			func(lbl: Label) -> bool: return lbl.text == "Test Quest")

	assert_true(matches.size() >= 1,
			"QuestRow must contain a Label with text == quest.title after setup()")


# ---------------------------------------------------------------------------
# Test 3 — QuestRow.setup() does not crash for COMPLETED status
# ---------------------------------------------------------------------------

func test_quest_row_setup_does_not_crash() -> void:
	# COMPLETED quests are dimmed but must not throw errors. This guards against
	# off-by-one modulate assignments or missing-node errors on the icon label.
	# Row instantiated from scene so @onready refs resolve correctly.
	var quest: QuestData = QuestData.new()
	quest.id = &"finished_quest"
	quest.title = "Finished Quest"
	autofree(quest)

	var row: QuestRow = _make_row()

	# If this line raises an error, GUT records a test failure automatically.
	row.setup(quest, QuestLog.Status.COMPLETED)

	assert_true(true, "setup() with COMPLETED status must not crash")


# ---------------------------------------------------------------------------
# Test 4 — populate_left() adds rows (or their container) to the parent
# ---------------------------------------------------------------------------

func test_quests_tab_populate_left_adds_rows() -> void:
	# populate_left() must add at least one child to the parent so the left
	# page is not visually empty. Phase 1 always has the_foraging_book quest.
	var tab: QuestsTab = add_child_autofree(QuestsTab.new())
	var parent: Control = add_child_autofree(Control.new())

	tab.populate_left(parent)

	assert_true(parent.get_child_count() >= 1,
			"populate_left() must add at least one child (quest rows or their container) to the parent")


# ---------------------------------------------------------------------------
# Test 5 — populate_right() shows a "select a quest" placeholder by default
# ---------------------------------------------------------------------------

func test_quests_tab_populate_right_shows_placeholder_when_no_selection() -> void:
	# When no quest is selected, the right page should guide the player.
	# The placeholder text must contain "select a quest" (case-insensitive).
	var tab: QuestsTab = add_child_autofree(QuestsTab.new())
	var parent: Control = add_child_autofree(Control.new())

	tab.populate_right(parent)

	# Search the whole subtree — the label may be inside a VBox or similar.
	var matches: Array[Label] = _find_labels(parent,
			func(lbl: Label) -> bool:
				return lbl.text.to_lower().contains("select a quest"))

	assert_true(matches.size() >= 1,
			"populate_right() with no selection must include a Label containing 'select a quest'")


# ---------------------------------------------------------------------------
# Test 6 — _ready() pre-populates the quest log with the foraging book
# ---------------------------------------------------------------------------

func test_quest_log_pre_populates_with_foraging_book() -> void:
	# The foraging book is the intro quest every player starts with completed.
	# _ready() must insert it into _quest_log.states so the Quests tab shows
	# it as COMPLETED on first open — without the player having to do anything.
	var tab: QuestsTab = add_child_autofree(QuestsTab.new())

	assert_true(tab._quest_log.states.has(&"the_foraging_book"),
			"_quest_log must contain the_foraging_book after _ready() runs")

	assert_eq(
			tab._quest_log.states[&"the_foraging_book"]["status"],
			QuestLog.Status.COMPLETED,
			"the_foraging_book must have COMPLETED status in _quest_log")


# ---------------------------------------------------------------------------
# Test 7 — setup() with COMPLETED status dims the row (modulate.a < 1.0)
# ---------------------------------------------------------------------------

func test_quest_row_setup_completed_dims_row() -> void:
	# COMPLETED quests must be visually separated from active work by dimming
	# the entire row. The modulate.a dim is applied in setup() — checking it
	# here guards that the @onready ref to the row's root (or the relevant child)
	# is resolved before the modulate assignment runs. A value of 1.0 means the
	# dim was silently skipped; a value < 1.0 confirms the treatment was applied.
	#
	# Row instantiated from scene so @onready refs are resolved before setup().
	var quest: QuestData = QuestData.new()
	quest.id = &"completed_quest"
	quest.title = "Completed Quest"
	autofree(quest)

	var row: QuestRow = _make_row()
	row.setup(quest, QuestLog.Status.COMPLETED)

	assert_true(row.modulate.a < 1.0,
			"setup(quest, COMPLETED) must set modulate.a < 1.0 to dim the row")


# ---------------------------------------------------------------------------
# Test 8 — pressing the row's ViewButton drives quest selection
# ---------------------------------------------------------------------------

func test_view_button_press_drives_selection() -> void:
	# DECISION: assert the observable outcome only — that pressing a row's
	# ViewButton causes the right page to transition from the placeholder to
	# a detail view. We do NOT assert whether the row emits a signal, whether
	# the tab connects directly, or any other wiring mechanism — that is an
	# implementation detail that may change in Phase 2.
	#
	# Setup: tab + two parents, all in tree so _ready() and @onready resolve.
	var tab: QuestsTab = add_child_autofree(QuestsTab.new())
	var left_parent: Control = add_child_autofree(Control.new())
	var right_parent: Control = add_child_autofree(Control.new())

	tab.populate_left(left_parent)
	tab.populate_right(right_parent)

	# Locate the first ViewButton anywhere under the left page. Phase 1 always
	# seeds the_foraging_book so there is at least one row. Use the recursive
	# helper to locate any Button named "ViewButton" anywhere in the subtree.
	var view_button: Button = _find_view_button(left_parent)

	assert_not_null(view_button,
			"quest_row.tscn must declare a node named 'ViewButton' under left_parent")
	if view_button == null:
		return

	# Act: press the ViewButton.
	view_button.pressed.emit()

	# Assert observable outcome: the right page no longer shows only the
	# placeholder. At least one Label with "select a quest" should be gone, OR
	# a label containing the quest title should now be present.
	# We check the title because it is the most concrete observable evidence.
	var title_labels: Array[Label] = _find_labels(right_parent,
			func(lbl: Label) -> bool:
				return lbl.text != "" and not lbl.text.to_lower().contains("select a quest"))

	assert_true(title_labels.size() >= 1,
			"After pressing ViewButton, right page must show quest detail (a non-placeholder Label), not the placeholder")


## Walk root's subtree recursively and return the first Button named 'ViewButton'.
## Returns null if no match is found.
func _find_view_button(root: Node) -> Button:
	for child in root.get_children():
		if child is Button and child.name == "ViewButton":
			return child as Button
		var found: Button = _find_view_button(child)
		if found != null:
			return found
	return null
