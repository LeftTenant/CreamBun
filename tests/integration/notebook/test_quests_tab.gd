## test_quests_tab.gd (integration)
## Cross-system integration tests for QuestsTab and its scene-backed layout.
##
## WHAT THESE TESTS GUARD
## ----------------------
## These tests cover flows that involve more than one class working together:
##   - populate_left + populate_right round-trip on a live scene tree
##   - ViewButton press → right-page transition from placeholder to detail
##   - Re-select rebuild: the right page is rebuilt, not duplicated
##   - Completed/active sectioning: rows in correct containers, divider visibility
##   - ViewButton minimum width preserved after setup() (regression guard for
##     the layout defect where ViewButton collapsed to zero width)
##   - QuestsTab reads quest progress from PlayerData.quest_log (Slice 4) —
##     two independently-instantiated tabs reading the same PlayerData.quest_log
##     render identical progress, and detail view objectives match the seeded
##     completed_objectives indices
##
## These are integration tests (not unit tests) because they exercise:
##   - QuestsTab + QuestRow + QuestData + QuestLog wired together in-tree
##   - Named node navigation (find_child on @onready targets after populate())
##   - The free-and-rebuild refresh path guarded by _refresh_right_page()
##   - Layout measurement after a process frame (custom_minimum_size.x check)
##   - The PlayerData autoload as the single shared source of truth for
##     quest progress across multiple QuestsTab instances
##
## --- PLAYERDATA SEEDING NOTE (Slice 4) ---
## before_each() seeds PlayerData with a PlayerDataResource that has had
## reset_to_new_game() applied (NOT a bare PlayerDataResource.new()), because
## only reset_to_new_game() runs _seed_starter_content() — the single source
## of truth for the foraging-book quest's COMPLETED seed data. This mirrors a
## fresh "New Story" launch, matching what QuestsTab sees in-game.
## See docs/features/game-data/design.md §9.2, §11 Step 2.
##
## Requires GUT: https://github.com/bitwes/Gut
## Install via Godot Asset Library (search "GUT - Godot Unit Testing").
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd -gselect=test_quests_tab.gd -gexit

class_name TestQuestsTabIntegration
extends GutTest


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const QUEST_ROW_SCENE: String = "res://ui/notebook/quests/quest_row.tscn"


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func before_each() -> void:
	# Seed PlayerData the way a fresh "New Story" does: reset_to_new_game()
	# runs _seed_starter_content(), which seeds the_foraging_book quest as
	# COMPLETED with completed_objectives [0, 1, 2]. QuestsTab._ready() no
	# longer seeds anything itself — it reads PlayerData.quest_log directly.
	var data: PlayerDataResource = PlayerDataResource.new()
	data.reset_to_new_game()
	PlayerData._load_resource(data)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Walk root's full subtree and return every Label satisfying predicate.
## Labels may be deeply nested inside VBox/HBox containers so a shallow
## get_child() call would silently miss them.
##
## @param root      - node whose subtree to search
## @param predicate - Callable(Label) -> bool; true means include this label
## @return Array of matching Labels in depth-first order
func _find_labels(root: Node, predicate: Callable) -> Array[Label]:
	var result: Array[Label] = []
	for child in root.get_children():
		if child is Label and predicate.call(child as Label):
			result.append(child as Label)
		result.append_array(_find_labels(child, predicate))
	return result


## Walk root's subtree and return the first Button named 'ViewButton'.
## Returns null if none found. Used by multiple tests to locate the row's
## select affordance without assuming it is at a fixed depth.
##
## @param root - node whose subtree to search
## @return first matching Button or null
func _find_view_button(root: Node) -> Button:
	for child in root.get_children():
		if child is Button and child.name == "ViewButton":
			return child as Button
		var found: Button = _find_view_button(child)
		if found != null:
			return found
	return null


## Walk root's subtree and return every node whose script global name matches
## type_name. Used to count QuestDetail subtrees without hardcoding a depth.
##
## @param root      - node whose subtree to search
## @param node_name - the node name string to match against node.name
## @return Array of matching Node objects
func _find_by_name(root: Node, node_name: String) -> Array[Node]:
	var result: Array[Node] = []
	for child in root.get_children():
		if child.name == node_name:
			result.append(child)
		result.append_array(_find_by_name(child, node_name))
	return result


# ---------------------------------------------------------------------------
# Test 1 — populate_left + populate_right round-trip
# ---------------------------------------------------------------------------

func test_populate_left_and_right_round_trip() -> void:
	# Confirm that calling both populate methods on a fresh in-tree tab
	# does not crash and each produces at least one child in its parent.
	# This is the baseline integration check before testing interaction.
	#
	# Tab added to tree (add_child_autofree) so _ready() runs and _quests
	# (loaded from the_foraging_book.tres) is resolved before populate. Quest
	# progress now comes from PlayerData.quest_log (seeded in before_each()),
	# not a self-owned _quest_log.
	var tab: QuestsTab = add_child_autofree(QuestsTab.new())
	var left_parent: Control = add_child_autofree(Control.new())
	var right_parent: Control = add_child_autofree(Control.new())

	tab.populate_left(left_parent)
	tab.populate_right(right_parent)

	assert_true(left_parent.get_child_count() >= 1,
			"populate_left() must add at least one child (container or rows) to its parent")
	assert_true(right_parent.get_child_count() >= 1,
			"populate_right() must add at least one child (placeholder or detail) to its parent")


# ---------------------------------------------------------------------------
# Test 2 — ViewButton press transitions right page from placeholder to detail
# ---------------------------------------------------------------------------

func test_view_button_press_transitions_right_page_to_detail() -> void:
	# After populate_left() and populate_right(), pressing a row's ViewButton
	# must replace the placeholder prompt with a detail view that includes the
	# selected quest's title.
	#
	# We assert the OBSERVABLE OUTCOME only (placeholder gone, title present)
	# and intentionally avoid asserting the wiring mechanism (signal vs direct
	# call). This keeps the test valid regardless of whether the row or the tab
	# owns the connection — a Phase 2 detail we do not want to lock in now.
	#
	# DECISION: assert observable outcome, not wiring mechanism.
	var tab: QuestsTab = add_child_autofree(QuestsTab.new())
	var left_parent: Control = add_child_autofree(Control.new())
	var right_parent: Control = add_child_autofree(Control.new())

	tab.populate_left(left_parent)
	tab.populate_right(right_parent)

	# Confirm placeholder is present before any button press.
	var placeholder_before: Array[Label] = _find_labels(right_parent,
			func(lbl: Label) -> bool:
				return lbl.text.to_lower().contains("select a quest"))
	assert_true(placeholder_before.size() >= 1,
			"Right page must show placeholder before any ViewButton press")

	# Locate the ViewButton for the first (and only, in Phase 1) quest row.
	var btn: Button = _find_view_button(left_parent)
	assert_not_null(btn, "quest_row.tscn must provide a ViewButton under left_parent")
	if btn == null:
		return

	# Act: press the button.
	btn.pressed.emit()

	# Assert: placeholder is gone and at least one non-placeholder label is present.
	# We check for absence of the placeholder text (not just presence of detail)
	# because a bug could leave both visible at once.
	var placeholder_after: Array[Label] = _find_labels(right_parent,
			func(lbl: Label) -> bool:
				return lbl.text.to_lower().contains("select a quest"))
	assert_true(placeholder_after.size() == 0,
			"Right page placeholder must be gone after ViewButton press")

	var detail_labels: Array[Label] = _find_labels(right_parent,
			func(lbl: Label) -> bool: return lbl.text != "")
	assert_true(detail_labels.size() >= 1,
			"Right page must contain at least one non-empty Label after ViewButton press (quest detail)")


# ---------------------------------------------------------------------------
# Test 3 — Re-selecting rebuilds the right page without duplicate subtrees
# ---------------------------------------------------------------------------

func test_reselect_does_not_duplicate_quest_detail_subtree() -> void:
	# _refresh_right_page() frees all children and rebuilds from scratch.
	# This test guards that pattern when the right page is a reparented scene
	# subtree (QuestDetail) rather than anonymous code-built nodes: pressing
	# ViewButton a second time must produce exactly ONE QuestDetail subtree,
	# not accumulate two. A failing test here reveals a free-before-rebuild bug.
	var tab: QuestsTab = add_child_autofree(QuestsTab.new())
	var left_parent: Control = add_child_autofree(Control.new())
	var right_parent: Control = add_child_autofree(Control.new())

	tab.populate_left(left_parent)
	tab.populate_right(right_parent)

	var btn: Button = _find_view_button(left_parent)
	assert_not_null(btn, "quest_row.tscn must provide a ViewButton under left_parent")
	if btn == null:
		return

	# Press once — establishes the initial detail view.
	btn.pressed.emit()

	# Press again — must refresh (free + rebuild), not append a second copy.
	btn.pressed.emit()

	# Count top-level children on right_parent. After a correct rebuild there
	# should be exactly 1 (the detail VBox or QuestDetail node). Multiple
	# children mean the refresh path appended rather than replaced.
	#
	# We count top-level children of right_parent as the proxy for "one detail
	# subtree" rather than recursing for the QuestDetail node specifically:
	# populate_right always starts with a clean slate, so a top-level count of 1
	# is a stable proxy regardless of the reparented node's name.
	var top_level_count: int = right_parent.get_child_count()
	assert_eq(top_level_count, 1,
			"After pressing ViewButton twice, right_parent must have exactly 1 top-level child (no duplicate detail subtrees); got %d" % top_level_count)


# ---------------------------------------------------------------------------
# Test 4 — COMPLETED rows land under CompletedSection; divider visibility
# ---------------------------------------------------------------------------

func test_completed_rows_in_completed_section_and_separator_visibility() -> void:
	# Phase 1 seeds the_foraging_book as COMPLETED. With no ACTIVE quests:
	#   - the quest row must end up under CompletedSection
	#   - CompletedSeparator must be hidden (divider only shown when BOTH
	#     active and completed buckets are non-empty — a half-empty divider
	#     orphaned above the list is a known UX bug this test guards against)
	#
	# This test verifies the named-container logic (ActiveSection,
	# CompletedSection, CompletedSeparator) routes a COMPLETED quest correctly.
	var tab: QuestsTab = add_child_autofree(QuestsTab.new())
	var left_parent: Control = add_child_autofree(Control.new())

	tab.populate_left(left_parent)

	# CompletedSection is a named container inside LeftPage.
	var completed_section: Node = left_parent.find_child("CompletedSection", true, false)
	assert_not_null(completed_section,
			"populate_left() must produce a named CompletedSection container")
	if completed_section == null:
		return

	# CompletedSection must have at least one child (the foraging book row).
	assert_true(completed_section.get_child_count() >= 1,
			"CompletedSection must contain at least one child after populate_left() (the_foraging_book is COMPLETED)")

	# Locate CompletedSeparator. In Phase 1 only COMPLETED quests exist, so the
	# separator must be hidden (no ACTIVE bucket to separate from).
	var separator: Node = left_parent.find_child("CompletedSeparator", true, false)
	assert_not_null(separator,
			"populate_left() must produce a named CompletedSeparator node")
	if separator == null:
		return

	assert_false((separator as CanvasItem).visible,
			"CompletedSeparator must be hidden when there are no ACTIVE quests (only COMPLETED exist in Phase 1)")


# ---------------------------------------------------------------------------
# Test 5 — ViewButton keeps a usable width after setup() and layout
# ---------------------------------------------------------------------------

func test_view_button_keeps_usable_width_after_setup() -> void:
	# REGRESSION GUARD for the layout defect where ViewButton collapsed to
	# zero width because TitleLabel's SIZE_EXPAND_FILL claimed the full row
	# and the button had no custom_minimum_size to resist it.
	#
	# The fix sets custom_minimum_size = Vector2(32, 0) on ViewButton in
	# quest_row.tscn. This test measures that value directly — it is the layout
	# contract the .tscn file must uphold. If a future scene edit accidentally
	# removes or zeroes custom_minimum_size.x, the button will silently vanish
	# again and this assertion will catch it.
	#
	# WHY 32px (not 60px):
	# The button was reduced from 64 → 32 to give TitleLabel enough room so
	# long titles like "The Foraging Book" no longer break mid-word. The button
	# sits inside a ~110px page column; 32px is the confirmed usable floor at
	# that column width.
	#
	# WHY THIS IS AN INTEGRATION TEST (not unit):
	# We need the row in the tree with a real QuestData passed to setup() so
	# that @onready refs are non-null and the full HBoxContainer layout has run
	# at least one frame before we measure. A bare QuestRow.new() in a unit test
	# would leave the node off-tree, so layout would never settle and
	# size.x would report 0 regardless of custom_minimum_size.
	#
	# https://docs.godotengine.org/en/stable/classes/class_control.html#class-control-property-custom_minimum_size
	const MIN_BUTTON_WIDTH: float = 32.0

	# Instantiate the row from its scene so @onready refs (TitleLabel, ViewButton)
	# are resolved before setup() writes to them.
	var packed: PackedScene = load("res://ui/notebook/quests/quest_row.tscn") as PackedScene
	var row: QuestRow = add_child_autofree(packed.instantiate()) as QuestRow

	var quest: QuestData = QuestData.new()
	quest.id = &"layout_test_quest"
	quest.title = "Layout Test Quest"
	autofree(quest)

	row.setup(quest, QuestLog.Status.ACTIVE)

	# Allow one process frame so HBoxContainer layout settles and
	# custom_minimum_size propagates through the container chain.
	# https://docs.godotengine.org/en/stable/classes/class_scenetree.html#class-scenetree-signal-process_frame
	await get_tree().process_frame

	var view_button: Button = row.find_child("ViewButton", true, false) as Button

	assert_not_null(view_button,
			"ViewButton must exist as a named child of QuestRow (check quest_row.tscn)")

	if view_button == null:
		return  # avoid null-ref crash on the width assertion below

	# Assert the scene-declared minimum size is present. The .tscn sets
	# custom_minimum_size = Vector2(32, 0); asserting >= 32 catches any future
	# accidental collapse to zero while matching the current intentional size.
	assert_true(view_button.custom_minimum_size.x >= MIN_BUTTON_WIDTH,
			"ViewButton.custom_minimum_size.x must be >= %.0f px after setup() so the button stays visible; got %.1f" % [MIN_BUTTON_WIDTH, view_button.custom_minimum_size.x])


# ---------------------------------------------------------------------------
# Test 6 — Detail view shows all three foraging-book objectives as [x]
# ---------------------------------------------------------------------------

func test_view_button_press_shows_all_objectives_completed() -> void:
	# PlayerData.quest_log.states[&"the_foraging_book"]["completed_objectives"]
	# is seeded as [0, 1, 2] by _seed_starter_content() — all three of
	# the_foraging_book.tres's objectives are done. Pressing the row's
	# ViewButton must render the title, description, and all three objective
	# lines prefixed with "[x] " (none left as "[ ] ").
	var tab: QuestsTab = add_child_autofree(QuestsTab.new())
	var left_parent: Control = add_child_autofree(Control.new())
	var right_parent: Control = add_child_autofree(Control.new())

	tab.populate_left(left_parent)
	tab.populate_right(right_parent)

	var btn: Button = _find_view_button(left_parent)
	assert_not_null(btn, "quest_row.tscn must provide a ViewButton under left_parent")
	if btn == null:
		return

	# Act: select the_foraging_book by pressing its row's ViewButton.
	btn.pressed.emit()

	# Title — confirms the right page rendered detail for the_foraging_book.
	var title_labels: Array[Label] = _find_labels(right_parent,
			func(lbl: Label) -> bool: return lbl.text == "The Foraging Book")
	assert_true(title_labels.size() >= 1,
			"Detail view must show a Label with the_foraging_book's title 'The Foraging Book'")

	# Description — confirms QuestData.description is rendered too.
	var desc_labels: Array[Label] = _find_labels(right_parent,
			func(lbl: Label) -> bool: return lbl.text == "Doug the bookshop keeper gave you a guide to foraging ingredients for brewing. This was the beginning of your adventure in Brewhamton.")
	assert_true(desc_labels.size() >= 1,
			"Detail view must show a Label with the_foraging_book's description")

	# Objectives — all three of the_foraging_book.tres's objectives, each
	# prefixed "[x] " because completed_objectives == [0, 1, 2] in the seed.
	var expected_objectives: Array[String] = [
		"Meet Doug at the bookshop",
		"Receive the foraging guide",
		"Read the introduction",
	]
	for objective_text: String in expected_objectives:
		var checked_labels: Array[Label] = _find_labels(right_parent,
				func(lbl: Label) -> bool: return lbl.text == "[x] " + objective_text)
		assert_true(checked_labels.size() >= 1,
				"Detail view must show '[x] %s' (completed_objectives seeds all three objectives as done)" % objective_text)

	# Negative check: no "[ ] " (incomplete) objective lines should be present —
	# all three are seeded as completed.
	var unchecked_labels: Array[Label] = _find_labels(right_parent,
			func(lbl: Label) -> bool: return lbl.text.begins_with("[ ] "))
	assert_eq(unchecked_labels.size(), 0,
			"Detail view must not show any '[ ] ' (incomplete) objective lines for the_foraging_book")


# ---------------------------------------------------------------------------
# Test 7 — Two QuestsTabs reading the same PlayerData.quest_log agree
# ---------------------------------------------------------------------------

func test_two_quests_tabs_reading_same_player_data_render_identical_progress() -> void:
	# This is the scenario the PlayerData migration is meant to enable: two
	# independently-instantiated QuestsTabs both read PlayerData.quest_log as
	# their single shared source of truth, so they must render identical
	# quest progress — both place the_foraging_book under CompletedSection
	# with the separator hidden.
	var tab_a: QuestsTab = add_child_autofree(QuestsTab.new())
	var tab_b: QuestsTab = add_child_autofree(QuestsTab.new())

	var left_parent_a: Control = add_child_autofree(Control.new())
	var left_parent_b: Control = add_child_autofree(Control.new())

	tab_a.populate_left(left_parent_a)
	tab_b.populate_left(left_parent_b)

	# Both tabs must place the_foraging_book row under CompletedSection.
	var completed_a: Node = left_parent_a.find_child("CompletedSection", true, false)
	var completed_b: Node = left_parent_b.find_child("CompletedSection", true, false)
	assert_not_null(completed_a, "tab_a must produce a named CompletedSection container")
	assert_not_null(completed_b, "tab_b must produce a named CompletedSection container")
	if completed_a == null or completed_b == null:
		return

	assert_eq(completed_a.get_child_count(), completed_b.get_child_count(),
			"Both tabs must place the same number of rows in CompletedSection (single shared PlayerData.quest_log)")
	assert_true(completed_a.get_child_count() >= 1,
			"CompletedSection must contain the_foraging_book row (seeded COMPLETED)")

	# Both tabs must agree on _get_status() for the_foraging_book directly —
	# this is the read path both populate_left() calls go through.
	assert_eq(tab_a._get_status(&"the_foraging_book"), tab_b._get_status(&"the_foraging_book"),
			"Both QuestsTab instances must report the same status for the_foraging_book")
	assert_eq(tab_a._get_status(&"the_foraging_book"), QuestLog.Status.COMPLETED,
			"the_foraging_book should be COMPLETED via the shared PlayerData.quest_log")

	# CompletedSeparator must be hidden on both — no ACTIVE bucket exists in
	# either tab's view of the (shared) quest log.
	var separator_a: Node = left_parent_a.find_child("CompletedSeparator", true, false)
	var separator_b: Node = left_parent_b.find_child("CompletedSeparator", true, false)
	assert_not_null(separator_a, "tab_a must produce a named CompletedSeparator node")
	assert_not_null(separator_b, "tab_b must produce a named CompletedSeparator node")
	if separator_a == null or separator_b == null:
		return

	assert_false((separator_a as CanvasItem).visible,
			"tab_a's CompletedSeparator must be hidden (no ACTIVE quests in shared quest_log)")
	assert_false((separator_b as CanvasItem).visible,
			"tab_b's CompletedSeparator must be hidden (no ACTIVE quests in shared quest_log)")
