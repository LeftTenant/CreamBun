## test_quests_tab.gd
## TDD contract tests for the Phase 1 Quests Tab.
##
## Covers QuestsTab (ui/notebook/quests/quests_tab.gd) and
## QuestRow (ui/notebook/quests/quest_row.gd).
##
## These tests define the expected API. They will FAIL until the implementation
## files exist — that is by design. Run them after implementing each class to
## confirm the contract is met.
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
	var quest: QuestData = QuestData.new()
	quest.id = &"test_quest"
	quest.title = "Test Quest"
	autofree(quest)

	# add_child_autofree so _ready() runs (child nodes are built in _ready).
	var row: QuestRow = add_child_autofree(QuestRow.new())
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
	var quest: QuestData = QuestData.new()
	quest.id = &"finished_quest"
	quest.title = "Finished Quest"
	autofree(quest)

	var row: QuestRow = add_child_autofree(QuestRow.new())

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
