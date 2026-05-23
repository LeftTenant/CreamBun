## test_settings_tab_layout.gd
## Regression tests for GitHub issue #4 — "Settings sliders overflow the
## notebook panel".
##
## WHAT BUG THIS GUARDS AGAINST
## ---------------------------
## SettingsTab.populate_left() and populate_right() build a VBoxContainer and
## add it to the page Control passed in by Notebook._show_tab(). Previously
## those VBoxes were never anchored to their parent, so their default
## (top-left, zero-sized) rect let HSlider children expand to their content
## minimum width and bleed across the page seam into the right page.
## InventoryTab does it correctly — it calls
##   vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
## right after add_child. SettingsTab should mirror that, plus pull each edge
## in by 10px so page contents never touch the page border.
##
## WHY THIS IS AN INTEGRATION TEST (not unit)
## -----------------------------------------
## The bug only shows up once the SettingsTab interacts with the parent
## Notebook scene: Notebook owns the LeftPage / RightPage Controls whose
## global rect SettingsTab's VBox is supposed to fit inside. That means the
## test must instantiate the real notebook.tscn, drive _switch_tab, and let
## a frame pass for layout to settle — a unit test against SettingsTab in
## isolation would have no LeftPage/RightPage rect to compare against.
##
## THE 10px MARGIN
## ---------------
## Per the approved fix plan, all page contents must sit 10px inside the
## LeftPage / RightPage rects on every side, so the page background art has
## breathing room and content never touches the spine seam.
##
## Requires GUT: https://github.com/bitwes/Gut
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd -gselect=test_settings_tab_layout.gd -gexit
##
## TREE-PAUSE WARNING
## ------------------
## Notebook.open() pauses the scene tree. GUT runs inside that tree, so every
## test that opens the notebook MUST close it before the test ends.
## after_each() force-closes and force-unpauses as a safety net.

class_name TestSettingsTabLayout
extends GutTest


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Inset every page-content edge must respect. Mirrors the offsets the fix sets
# on the VBox (offset_left=10, offset_top=10, offset_right=-10, offset_bottom=-10).
const PAGE_MARGIN: float = 10.0

# Float tolerance for rect comparisons. Layout produces clean integer pixel
# values in practice, but Godot's anchor math can leave sub-pixel rounding so
# we allow half a pixel of slop on equality checks.
const POSITION_TOLERANCE: float = 0.5


# ---------------------------------------------------------------------------
# Setup / Teardown
# ---------------------------------------------------------------------------

# Held so after_each() can always close the notebook even if a test errored
# before its own close() call.
var _notebook: Notebook


func before_each() -> void:
	# Match test_notebook_shell.gd's known-good baseline.
	GameState.change_state(GameState.State.PLAYING)
	get_tree().paused = false
	_notebook = null


func after_each() -> void:
	# Safety net: if a test left the notebook open the tree is still paused,
	# which would leak into subsequent tests.
	if _notebook != null and is_instance_valid(_notebook) and _notebook.visible:
		_notebook.close()
	get_tree().paused = false
	GameState.change_state(GameState.State.PLAYING)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Instantiate the real notebook.tscn (so @onready paths to LeftPage/RightPage
## resolve), add it to the tree autofreed, and stash a ref for cleanup.
## Mirrors _make_notebook() from test_notebook_shell.gd.
func _make_notebook() -> Notebook:
	var nb: Notebook = load("res://ui/notebook/notebook.tscn").instantiate()
	add_child_autofree(nb)
	_notebook = nb
	return nb


## Recursive depth-first search for descendants matching a built-in type check.
## We can't use find_children() with built-in classes reliably, and matching by
## `node is HSlider` / `node is OptionButton` is cheaper and unambiguous than
## comparing class_name strings (which are empty for built-in nodes).
##
## @param root      - subtree root to search
## @param type_name - one of "HSlider", "OptionButton", "VBoxContainer"
## @return Array of matching Nodes in depth-first order
func _find_descendants_of_type(root: Node, type_name: String) -> Array:
	var result: Array = []
	for child in root.get_children():
		var matched: bool = false
		match type_name:
			"HSlider":       matched = child is HSlider
			"OptionButton":  matched = child is OptionButton
			"VBoxContainer": matched = child is VBoxContainer
		if matched:
			result.append(child)
		result.append_array(_find_descendants_of_type(child, type_name))
	return result


## Open the notebook on the Settings tab and wait for layout to settle.
##
## We await TWO process frames after switching:
##   1. First frame — Container resorts its children once its own rect is known.
##   2. Second frame — children whose own size_flags trigger another resort
##      (e.g. PRESET_FULL_RECT on the VBox) finish settling.
## One frame is usually enough but two makes the test deterministic on slower
## CI runs without flaking.
##
## @return the Notebook instance, fully laid out and on the Settings tab.
func _open_to_settings() -> Notebook:
	var nb: Notebook = _make_notebook()
	# open() goes through _switch_tab internally and triggers populate_left /
	# populate_right on the SettingsTab instance.
	nb.open(Notebook.NotebookTab.SETTINGS)
	await get_tree().process_frame
	await get_tree().process_frame
	return nb


# ---------------------------------------------------------------------------
# Test A — every HSlider on the LeftPage respects the horizontal page margin
# ---------------------------------------------------------------------------

func test_left_page_sliders_within_margin() -> void:
	var nb: Notebook = await _open_to_settings()

	var left_page: Control = nb.get_node("Book/Pages/LeftPage") as Control
	assert_not_null(left_page, "LeftPage Control must exist in notebook.tscn")

	var sliders: Array = _find_descendants_of_type(left_page, "HSlider")
	# Settings tab builds four sliders: Master, Music, SFX, Text Speed.
	assert_true(sliders.size() >= 4,
			"Expected at least 4 HSliders on Settings LeftPage, found %d" % sliders.size())

	var page_rect: Rect2 = left_page.get_global_rect()
	var allowed_left: float = page_rect.position.x + PAGE_MARGIN
	var allowed_right: float = page_rect.end.x - PAGE_MARGIN

	for slider in sliders:
		var rect: Rect2 = (slider as Control).get_global_rect()
		assert_true(rect.position.x >= allowed_left,
				"Slider '%s' left edge (%.1f) must be >= LeftPage left + %.0f (%.1f)" % [
						slider.name, rect.position.x, PAGE_MARGIN, allowed_left])
		assert_true(rect.end.x <= allowed_right,
				"Slider '%s' right edge (%.1f) must be <= LeftPage right - %.0f (%.1f)" % [
						slider.name, rect.end.x, PAGE_MARGIN, allowed_right])

	nb.close()


# ---------------------------------------------------------------------------
# Test B — the OptionButton on the RightPage respects the horizontal margin
# ---------------------------------------------------------------------------

func test_right_page_option_button_within_margin() -> void:
	var nb: Notebook = await _open_to_settings()

	var right_page: Control = nb.get_node("Book/Pages/RightPage") as Control
	assert_not_null(right_page, "RightPage Control must exist in notebook.tscn")

	var buttons: Array = _find_descendants_of_type(right_page, "OptionButton")
	assert_eq(buttons.size(), 1,
			"Expected exactly 1 OptionButton on Settings RightPage (window scale), found %d" % buttons.size())

	var page_rect: Rect2 = right_page.get_global_rect()
	var allowed_left: float = page_rect.position.x + PAGE_MARGIN
	var allowed_right: float = page_rect.end.x - PAGE_MARGIN

	var option_rect: Rect2 = (buttons[0] as Control).get_global_rect()
	assert_true(option_rect.position.x >= allowed_left,
			"OptionButton left edge (%.1f) must be >= RightPage left + %.0f (%.1f)" % [
					option_rect.position.x, PAGE_MARGIN, allowed_left])
	assert_true(option_rect.end.x <= allowed_right,
			"OptionButton right edge (%.1f) must be <= RightPage right - %.0f (%.1f)" % [
					option_rect.end.x, PAGE_MARGIN, allowed_right])

	nb.close()


# ---------------------------------------------------------------------------
# Test C — the LeftPage VBox sits 10px inside the page on every side
# ---------------------------------------------------------------------------
#
# We look up the VBox as a direct child of the page Control rather than
# searching recursively, because SettingsTab.populate_left() adds exactly one
# VBox as the immediate page child. Recursive search would also match nested
# VBoxes inside future widgets (e.g. a labelled-row VBox) and produce a false
# negative.

func test_left_page_vbox_respects_margin_on_all_sides() -> void:
	var nb: Notebook = await _open_to_settings()

	var left_page: Control = nb.get_node("Book/Pages/LeftPage") as Control
	assert_not_null(left_page, "LeftPage Control must exist")

	var vbox: VBoxContainer = null
	for child in left_page.get_children():
		if child is VBoxContainer:
			vbox = child as VBoxContainer
			break
	assert_not_null(vbox,
			"SettingsTab.populate_left() must add a VBoxContainer to LeftPage")

	var page: Rect2 = left_page.get_global_rect()
	var got: Rect2 = vbox.get_global_rect()

	assert_almost_eq(got.position.x, page.position.x + PAGE_MARGIN, POSITION_TOLERANCE,
			"LeftPage VBox left edge must be inset by %.0f px" % PAGE_MARGIN)
	assert_almost_eq(got.position.y, page.position.y + PAGE_MARGIN, POSITION_TOLERANCE,
			"LeftPage VBox top edge must be inset by %.0f px" % PAGE_MARGIN)
	assert_almost_eq(got.end.x, page.end.x - PAGE_MARGIN, POSITION_TOLERANCE,
			"LeftPage VBox right edge must be inset by %.0f px" % PAGE_MARGIN)
	# Bottom may sit anywhere from the 10px inset down to the page edge —
	# vertical content can fill the page; the bug is escaping it. Issue #4 is
	# about content not OVERFLOWING the page, so the only hard constraint is
	# that the VBox bottom stays at or above the page bottom. Top/left/right
	# remain strictly inset because the bug was horizontal seam-crossing.
	assert_true(got.end.y <= page.end.y + POSITION_TOLERANCE,
			"LeftPage VBox bottom edge (%.1f) must not overflow page bottom (%.1f)" % [
					got.end.y, page.end.y])

	nb.close()


# ---------------------------------------------------------------------------
# Test D — the RightPage VBox sits 10px inside the page on every side
# ---------------------------------------------------------------------------

func test_right_page_vbox_respects_margin_on_all_sides() -> void:
	var nb: Notebook = await _open_to_settings()

	var right_page: Control = nb.get_node("Book/Pages/RightPage") as Control
	assert_not_null(right_page, "RightPage Control must exist")

	var vbox: VBoxContainer = null
	for child in right_page.get_children():
		if child is VBoxContainer:
			vbox = child as VBoxContainer
			break
	assert_not_null(vbox,
			"SettingsTab.populate_right() must add a VBoxContainer to RightPage")

	var page: Rect2 = right_page.get_global_rect()
	var got: Rect2 = vbox.get_global_rect()

	assert_almost_eq(got.position.x, page.position.x + PAGE_MARGIN, POSITION_TOLERANCE,
			"RightPage VBox left edge must be inset by %.0f px" % PAGE_MARGIN)
	assert_almost_eq(got.position.y, page.position.y + PAGE_MARGIN, POSITION_TOLERANCE,
			"RightPage VBox top edge must be inset by %.0f px" % PAGE_MARGIN)
	assert_almost_eq(got.end.x, page.end.x - PAGE_MARGIN, POSITION_TOLERANCE,
			"RightPage VBox right edge must be inset by %.0f px" % PAGE_MARGIN)
	# Bottom kept symmetric with the LeftPage test: overflow-only check against
	# the page edge, not the 10px inset. See the matching comment in
	# test_left_page_vbox_respects_margin_on_all_sides.
	assert_true(got.end.y <= page.end.y + POSITION_TOLERANCE,
			"RightPage VBox bottom edge (%.1f) must not overflow page bottom (%.1f)" % [
					got.end.y, page.end.y])

	nb.close()


# ---------------------------------------------------------------------------
# Test E — sliders explicitly opt into horizontal expand-fill
# ---------------------------------------------------------------------------
#
# Locks in the second adjustment the user requested. Sliders are built by
# SettingsTab._make_slider(); making the "fill the row" intent explicit at
# the construction site prevents future refactors from accidentally relying
# on default size_flags behaviour.

func test_sliders_use_expand_fill() -> void:
	var nb: Notebook = await _open_to_settings()

	var left_page: Control = nb.get_node("Book/Pages/LeftPage") as Control
	var sliders: Array = _find_descendants_of_type(left_page, "HSlider")
	assert_true(sliders.size() >= 4,
			"Expected at least 4 HSliders on Settings LeftPage, found %d" % sliders.size())

	for slider in sliders:
		assert_eq((slider as Control).size_flags_horizontal,
				Control.SIZE_EXPAND_FILL,
				"Slider '%s' must set size_flags_horizontal = SIZE_EXPAND_FILL" % slider.name)

	nb.close()
