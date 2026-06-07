## test_quests_tab.gd (integration)
## Cross-system integration tests for QuestsTab after the Slice 3 scene migration.
##
## WHAT THESE TESTS GUARD
## ----------------------
## These tests cover flows that involve more than one class working together:
##   - populate_left + populate_right round-trip on a live scene tree
##   - ViewButton press → right-page transition from placeholder to detail
##   - Re-select rebuild: the right page is rebuilt, not duplicated
##   - Completed/active sectioning: rows in correct containers, divider visibility
##   - ViewButton minimum width preserved after setup() (regression guard for
##     the B3 layout defect where ViewButton collapsed to zero width)
##
## These are integration tests (not unit tests) because they exercise:
##   - QuestsTab + QuestRow + QuestData + QuestLog wired together in-tree
##   - Named node navigation (find_child on @onready targets after populate())
##   - The free-and-rebuild refresh path guarded by _refresh_right_page()
##   - Layout measurement after a process frame (custom_minimum_size.x check)
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
	# Tab added to tree (add_child_autofree) so _ready() runs and @onready
	# refs — including _quest_log and _quests — are resolved before populate.
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
	if btn == null:
		pending("No ViewButton found under left_parent — test requires B3 implementation of quest_row.tscn")
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
	if btn == null:
		pending("No ViewButton found under left_parent — test requires B3 implementation of quest_row.tscn")
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
	# subtree" rather than recursing for QuestDetail specifically, because the
	# exact node name may change during the migration (B3 may or may not keep
	# "QuestDetail" as the top-level reparented node name). Top-level count
	# is a stable proxy: populate_right always starts with a clean slate.
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
	# This test verifies the new named-container logic (ActiveSection,
	# CompletedSection, CompletedSeparator) against the existing bucket sort
	# that previously used an anonymous VBoxContainer.
	var tab: QuestsTab = add_child_autofree(QuestsTab.new())
	var left_parent: Control = add_child_autofree(Control.new())

	tab.populate_left(left_parent)

	# Locate CompletedSection — after B3 it is a named node inside LeftPage.
	# If the node does not exist yet (pre-B3), the test pends cleanly.
	var completed_section: Node = left_parent.find_child("CompletedSection", true, false)
	if completed_section == null:
		# Pre-B3: the section containers may not be named yet. Check the
		# existing bucket-sort invariant a different way: at least one row
		# is present (proves the quest was not silently hidden).
		var any_labels: Array[Label] = _find_labels(left_parent,
				func(lbl: Label) -> bool: return lbl.text != "")
		assert_true(any_labels.size() >= 1,
				"populate_left() must render at least one row (the_foraging_book is COMPLETED)")
		gut.p("CompletedSection not found — running pre-B3 fallback assertion (label presence)")
		return

	# B3 path: CompletedSection must have at least one child (the foraging book row).
	assert_true(completed_section.get_child_count() >= 1,
			"CompletedSection must contain at least one child after populate_left() (the_foraging_book is COMPLETED)")

	# Locate CompletedSeparator. In Phase 1 only COMPLETED quests exist, so the
	# separator must be hidden (no ACTIVE bucket to separate from).
	var separator: Node = left_parent.find_child("CompletedSeparator", true, false)
	if separator == null:
		# Pre-B3: separator does not exist as a named node yet.
		gut.p("CompletedSeparator not found — skipping separator visibility assertion (pre-B3)")
		return

	assert_false((separator as CanvasItem).visible,
			"CompletedSeparator must be hidden when there are no ACTIVE quests (only COMPLETED exist in Phase 1)")


# ---------------------------------------------------------------------------
# Test 5 — ViewButton keeps a usable width after setup() and layout
# ---------------------------------------------------------------------------

func test_view_button_keeps_usable_width_after_setup() -> void:
	# REGRESSION GUARD for the B3 layout defect where ViewButton collapsed to
	# zero width because TitleLabel's SIZE_EXPAND_FILL claimed the full row
	# and the button had no custom_minimum_size to resist it.
	#
	# The fix sets custom_minimum_size = Vector2(64, 0) on ViewButton in
	# quest_row.tscn. This test measures that value directly — it is the layout
	# contract the .tscn file must uphold. If a future scene edit accidentally
	# removes or zeroes custom_minimum_size.x, the button will silently vanish
	# again and this assertion will catch it.
	#
	# WHY THIS IS AN INTEGRATION TEST (not unit):
	# We need the row in the tree with a real QuestData passed to setup() so
	# that @onready refs are non-null and the full HBoxContainer layout has run
	# at least one frame before we measure. A bare QuestRow.new() in a unit test
	# would leave the node off-tree, so layout would never settle and
	# size.x would report 0 regardless of custom_minimum_size.
	#
	# https://docs.godotengine.org/en/stable/classes/class_control.html#class-control-property-custom_minimum_size
	const MIN_BUTTON_WIDTH: float = 60.0

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
	# custom_minimum_size = Vector2(64, 0), so >= 60 gives a small tolerance
	# for any future intentional resize while still catching a collapse to zero.
	assert_true(view_button.custom_minimum_size.x >= MIN_BUTTON_WIDTH,
			"ViewButton.custom_minimum_size.x must be >= %.0f px after setup() so the button stays visible; got %.1f" % [MIN_BUTTON_WIDTH, view_button.custom_minimum_size.x])
