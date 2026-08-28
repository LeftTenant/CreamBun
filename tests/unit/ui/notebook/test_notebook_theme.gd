## test_notebook_theme.gd
## Scene-as-data and cascade tests for the notebook's base theme assignment.
##
## WHAT THESE TESTS GUARD
## ----------------------
## Slice 2 of the pixel-art-purist feature wires resources/theme/base_theme.tres
## onto the notebook's runtime ancestor Control so the theme cascades to every
## Control descendant — including the LeftPage/RightPage subtrees that tab scripts
## reparent in at runtime. These tests assert:
##   1. notebook.tscn loads as a valid PackedScene and instantiates without error.
##   2. The runtime ancestor of LeftPage/RightPage carries theme = base_theme.tres.
##   3. After _switch_tab() reparents a tab's subtree into LeftPage, a Control
##      inside that subtree resolves the monogram font and default size 8 from
##      the ancestor's theme — proving live cascade, not an editor-only property.
##   4. A tab scene's own root node is NOT required to carry the theme itself —
##      the cascade comes from the notebook ancestor after reparenting.
##
## WHY THE CASCADE TEST MATTERS
## ----------------------------
## Setting the theme on the wrong node (e.g. a tab's editor-preview root, which
## is never mounted in-game per ui/CLAUDE.md rule 4) would pass an editor-only
## check but silently fail at runtime. Test 3 drives _switch_tab() the same way
## the real game flow does, so the assertion is live, not hypothetical.
##
## WHAT "RUNTIME ANCESTOR OF LEFTPAGE/RIGHTPAGE" MEANS
## ----------------------------------------------------
## Notebook (CanvasLayer) has no theme property — theme cascading only happens
## through the Control tree. Book (Panel, child of Notebook) is the first
## Control ancestor of Pages/LeftPage and Pages/RightPage in the scene. The test
## locates this ancestor generically (walk up from LeftPage until a Control with
## a non-null theme is found) so it holds even if the coder introduces a
## different wrapper node above Book.
##
## Control.theme cascade reference:
##   https://docs.godotengine.org/en/stable/tutorials/ui/gui_using_theme_editor.html
##
## Requires GUT: https://github.com/bitwes/Gut
## Install via Godot Asset Library (search "GUT - Godot Unit Testing").
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd -gselect=test_notebook_theme.gd -gexit

class_name TestNotebookTheme
extends GutTest


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Canonical path for the scene under test.
const SCENE_PATH: String = "res://ui/notebook/notebook.tscn"

## The theme that Slice 2 wires onto the notebook's runtime ancestor Control.
## This constant is the single source of truth for the expected path — if the
## theme file ever moves, one update here covers all four tests.
const EXPECTED_THEME_PATH: String = "res://resources/theme/base_theme.tres"

## The font file the theme's default_font must resolve to (matches test_base_theme.gd).
const EXPECTED_FONT_PATH: String = "res://resources/theme/fonts/monogram-extended.ttf"

## Expected default font size from §3 of the design doc (body/default = 8px).
const EXPECTED_FONT_SIZE: int = 8

## Issue #47 — exact float values from base_theme.tres's "" type color list
## (see test_base_theme.gd), used to check live theme cascade resolves the
## same per-control-type entries the resource-level tests check directly.
const EXPECTED_PAPER_BG: Color = Color(0.95686275, 0.9137255, 0.84705883, 1)
const EXPECTED_PAPER_BG_SHADOW: Color = Color(0.8901961, 0.83137256, 0.7411765, 1)
const EXPECTED_INK: Color = Color(0.23137255, 0.18431373, 0.16470589, 1)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Instantiate the notebook scene, add it to the scene tree so _ready() runs
## and @onready refs resolve, then return it. The instance is autofreed.
func _make_notebook() -> Notebook:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	var instance: Notebook = packed.instantiate() as Notebook
	add_child_autofree(instance)
	return instance


## Walk upward from `start` through the scene tree and return the first Control
## ancestor whose `theme` property is not null — that is the cascade point.
## Returns null if no such ancestor is found within the scene.
##
## We walk up rather than hardcoding "Book" so the test is robust to the coder
## adding a new wrapper Control above Book without breaking this suite.
##
## @param start  the node to begin walking from (exclusive — we check .get_parent())
## @return the first Control ancestor with a non-null theme, or null
func _find_theme_ancestor(start: Node) -> Control:
	var current: Node = start.get_parent()
	while current != null:
		if current is Control:
			var ctrl: Control = current as Control
			# `theme` holds the explicitly assigned Theme resource. A null theme
			# means the node participates in cascade but does not own it.
			# https://docs.godotengine.org/en/stable/classes/class_control.html#class-control-property-theme
			if ctrl.theme != null:
				return ctrl
		current = current.get_parent()
	return null


## Find the first Label inside root's subtree that has NO theme_type_variation
## set (i.e. a body label, not a Heading). Used to locate a body Control inside
## a reparented tab page and verify it resolves the default font size 8.
##
## Slice 5 (font-size pass) gives some labels `theme_type_variation = "Heading"`,
## which causes them to resolve font_size 16 rather than the body default of 8.
## Using the first label regardless of variation would pick a Heading and make
## the cascade-size assertion fail. We skip variations to stay on body text.
##
## @param root  the node to search under
## @return the first body Label (no variation) found, or null if none exists
func _find_first_label(root: Node) -> Label:
	for child: Node in root.get_children():
		if child is Label:
			var lbl: Label = child as Label
			# Skip labels that carry a theme type variation — they resolve a
			# variation-specific font size, not the theme default.
			if lbl.theme_type_variation == "":
				return lbl
		var found: Label = _find_first_label(child)
		if found != null:
			return found
	return null


# ---------------------------------------------------------------------------
# Test 1 — notebook.tscn loads as a valid PackedScene and instantiates
# ---------------------------------------------------------------------------

func test_scene_loads_without_error() -> void:
	# If the .tscn file is corrupt, mis-formatted, or references a missing
	# resource, load() returns null. This is the cheapest possible check and
	# gates every subsequent test — if load fails there is no point going further.
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	assert_not_null(packed,
			"notebook.tscn must load as a non-null PackedScene")
	if packed == null:
		return

	# Instantiation failing (e.g. a missing @export dependency) would raise an
	# error recorded by GUT. The autofree here mirrors the pattern in
	# test_inventory_tab_scene.gd so the instance is cleaned up after the test.
	var instance: Notebook = packed.instantiate() as Notebook
	assert_not_null(instance,
			"notebook.tscn must instantiate as a non-null Notebook node")
	autofree(instance)


# ---------------------------------------------------------------------------
# Test 2 — The runtime ancestor Control of LeftPage/RightPage carries the theme
# ---------------------------------------------------------------------------

func test_runtime_ancestor_of_left_and_right_page_has_base_theme() -> void:
	# CanvasLayer (Notebook) has no theme property, so the theme must be set on
	# the first Control in the tree that is a true runtime ancestor of both
	# LeftPage and RightPage. This test finds that ancestor generically by
	# walking up from LeftPage, rather than hardcoding "Book", so it holds if
	# the coder introduces a new wrapper Control between Notebook and Book.
	#
	# theme cascade reference:
	#   https://docs.godotengine.org/en/stable/tutorials/ui/gui_using_theme_editor.html
	var notebook: Notebook = _make_notebook()

	# Resolve LeftPage — this @onready path matches notebook.gd's declaration.
	var left_page: Control = notebook.get_node_or_null("Book/Pages/LeftPage") as Control
	assert_not_null(left_page,
			"notebook.tscn must contain a node at path Book/Pages/LeftPage")
	if left_page == null:
		return

	# Walk upward to find the cascade owner.
	var cascade_ancestor: Control = _find_theme_ancestor(left_page)
	assert_not_null(cascade_ancestor,
			"A Control ancestor of LeftPage must have 'theme' set (the cascade point)")
	if cascade_ancestor == null:
		return

	# Confirm the ancestor is genuinely above RightPage as well — otherwise the
	# theme would cascade to LeftPage content but not RightPage content.
	var right_page: Control = notebook.get_node_or_null("Book/Pages/RightPage") as Control
	assert_not_null(right_page,
			"notebook.tscn must contain a node at path Book/Pages/RightPage")
	if right_page == null:
		return

	assert_true(cascade_ancestor.is_ancestor_of(right_page),
			"The theme-carrying ancestor must also be an ancestor of RightPage")

	# Assert the theme is the expected base_theme.tres — not a stale reference
	# to the old resources/data/notebook_theme.tres path.
	var actual_path: String = cascade_ancestor.theme.resource_path
	assert_eq(actual_path, EXPECTED_THEME_PATH,
			("The runtime ancestor Control's theme must be %s — got '%s'. "
			+ "Ensure notebook.tscn's Book node (or equivalent) has its theme "
			+ "property set to resources/theme/base_theme.tres, not the old "
			+ "notebook_theme.tres or the default empty theme.") % [EXPECTED_THEME_PATH, actual_path])


# ---------------------------------------------------------------------------
# Test 3 — After _switch_tab(), a reparented node resolves the cascade font
# ---------------------------------------------------------------------------

func test_reparented_tab_content_resolves_base_theme_font_and_size() -> void:
	# This test exercises the scenario that would silently fail if the theme were
	# set on the wrong node (e.g. a tab's editor-preview root): calling _switch_tab()
	# the same way the real game flow does causes InventoryTab.populate_left() to
	# reparent its LeftPage subtree into notebook's Book/Pages/LeftPage. A Label
	# inside that reparented content must then resolve the monogram font and
	# default size 8 via theme inheritance — proving the cascade is live and
	# reaches tab content at runtime, not just nodes that were always in the scene.
	#
	# Note: _switch_tab() is a private method by convention (underscore prefix)
	# but GDScript does not enforce access control. Driving the real method is
	# intentional here — it is the only way to trigger populate_left/right.
	#
	# PlayerData is seeded with an empty resource so populate_right() has an
	# inventory to read from (even though this test only inspects the font cascade).
	# This mirrors the pattern in test_inventory_tab_scene.gd before_each().
	PlayerData._load_resource(PlayerDataResource.new())

	var notebook: Notebook = _make_notebook()

	# Drive the tab switch. NotebookTab.INVENTORY is the zero value and the
	# safest default because InventoryTab is the most exercised tab in existing
	# tests, reducing the chance that a new InventoryTab-specific bug masks a
	# cascade failure.
	notebook._switch_tab(Notebook.NotebookTab.INVENTORY)

	# LeftPage is now populated by InventoryTab.populate_left(). Find any Label
	# inside it — the exact Label doesn't matter, only that it is a reparented
	# Control that should now inherit the notebook's theme cascade.
	var left_page: Control = notebook.get_node_or_null("Book/Pages/LeftPage") as Control
	assert_not_null(left_page,
			"Book/Pages/LeftPage must exist after _switch_tab()")
	if left_page == null:
		return

	var label: Label = _find_first_label(left_page)
	assert_not_null(label,
			("LeftPage must contain at least one Label after _switch_tab(INVENTORY) "
			+ "— InventoryTab.populate_left() renders an equipment silhouette with Labels"))
	if label == null:
		return

	# get_theme_font("font", "") resolves the 'font' property for the "" (default)
	# control type, walking up through parent themes until a match is found. If
	# base_theme.tres is correctly set on a Book ancestor, it will return the
	# monogram FontFile. If the cascade is broken it returns the engine default.
	# https://docs.godotengine.org/en/stable/classes/class_control.html#class-control-method-get-theme-font
	var resolved_font: Font = label.get_theme_font("font", "")
	assert_not_null(resolved_font,
			"get_theme_font('font', '') on a reparented Label must return a non-null Font")
	if resolved_font == null:
		return

	assert_true(resolved_font is FontFile,
			"The resolved default font must be a FontFile (the imported monogram TTF), not a fallback Font object")
	assert_eq(resolved_font.resource_path, EXPECTED_FONT_PATH,
			("A Label reparented into LeftPage by _switch_tab() must resolve the monogram font "
			+ "('%s') via theme cascade — got '%s'. "
			+ "This means the theme is not set on a Control that is a runtime ancestor of LeftPage. "
			+ "Setting the theme only on a tab's editor-preview root does not cascade to reparented content."
			) % [EXPECTED_FONT_PATH, resolved_font.resource_path])

	# get_theme_font_size("font_size", "") resolves the default font size the
	# same way — walking up through the theme hierarchy until the cascade owner's
	# default_font_size is found.
	# https://docs.godotengine.org/en/stable/classes/class_control.html#class-control-method-get-theme-font-size
	var resolved_size: int = label.get_theme_font_size("font_size", "")
	assert_eq(resolved_size, EXPECTED_FONT_SIZE,
			("A Label reparented into LeftPage must resolve font_size %d (§3 body size) "
			+ "via theme cascade — got %d. "
			+ "Check that base_theme.tres has default_font_size = 8 and that the cascade "
			+ "ancestor is a genuine runtime ancestor of LeftPage/RightPage."
			) % [EXPECTED_FONT_SIZE, resolved_size])


# ---------------------------------------------------------------------------
# Test 4 — A tab scene's root node is NOT required to carry the theme itself
# ---------------------------------------------------------------------------

func test_tab_scene_root_is_not_required_to_carry_theme() -> void:
	# Per ui/CLAUDE.md rule 4, a tab scene's root node is the editor-preview
	# root — it is never mounted in-game. The theme therefore must NOT be
	# asserted on any tab scene root: the cascade comes from the notebook
	# ancestor. This test confirms that requirement by asserting the negative:
	# InventoryTab's scene root does not need (and should not be expected to
	# have) a theme property set. The real cascade proof is in test 3 above.
	#
	# This test exists to document the design intent explicitly and prevent a
	# future contributor from adding a redundant/incorrect theme assignment to
	# individual tab scenes.
	var packed: PackedScene = load("res://ui/notebook/inventory/inventory_tab.tscn") as PackedScene
	assert_not_null(packed, "inventory_tab.tscn must load for this sanity check")
	if packed == null:
		return

	var tab_root: Control = packed.instantiate() as Control
	assert_not_null(tab_root, "inventory_tab.tscn must instantiate")
	autofree(tab_root)
	if tab_root == null:
		return

	# The tab root may or may not have a theme set (the test does not care).
	# What matters is: the CASCADE test (test 3) proved the theme reaches
	# reparented content from a notebook-level ancestor. Asserting that the
	# tab root's theme is null is explicitly NOT a contract — this test just
	# confirms no assertion is made about it (it passes unconditionally).
	#
	# If this feels tautological: it is. Its value is as a readable signal
	# to the next developer that "tab root theme = not your concern."
	assert_true(true,
			"No assertion about the tab scene root's theme is required — "
			+ "the cascade comes from the notebook ancestor after reparenting "
			+ "(proved by test_reparented_tab_content_resolves_base_theme_font_and_size).")


# ---------------------------------------------------------------------------
# Test 5 — Issue #47: Book resolves the paper_bg Panel stylebox via cascade
# ---------------------------------------------------------------------------
# base_theme.tres was originally wired onto Book as a Theme *resource* only
# (test 2 above proves that assignment) without a matching Panel/styles/panel
# entry for Book to resolve — Book fell through to the engine's built-in dark
# default Panel style instead of the documented paper background. This test
# drives the real runtime lookup Godot uses to paint the Panel, and is the
# regression guard for the fix that added that stylebox.

func test_book_panel_resolves_paper_bg_stylebox_via_cascade() -> void:
	var notebook: Notebook = _make_notebook()

	var left_page: Control = notebook.get_node_or_null("Book/Pages/LeftPage") as Control
	assert_not_null(left_page, "notebook.tscn must contain a node at path Book/Pages/LeftPage")
	if left_page == null:
		return

	var cascade_ancestor: Control = _find_theme_ancestor(left_page)
	assert_not_null(cascade_ancestor,
			"A Control ancestor of LeftPage must have 'theme' set (the cascade point)")
	if cascade_ancestor == null:
		return

	# get_theme_stylebox("panel", "") resolves against the node's own class
	# (Panel) when the type argument is the default empty string — the same
	# resolution Godot performs when actually painting this Panel on screen.
	# https://docs.godotengine.org/en/stable/classes/class_control.html#class-control-method-get-theme-stylebox
	var resolved: StyleBox = cascade_ancestor.get_theme_stylebox("panel", "")
	assert_not_null(resolved,
			"Book (a Panel) must resolve a 'panel' stylebox via theme cascade")
	if resolved == null:
		return

	assert_true(resolved is StyleBoxFlat,
			"Book's resolved 'panel' stylebox should be a StyleBoxFlat, not the engine's built-in default Panel style")
	if not (resolved is StyleBoxFlat):
		return

	var flat: StyleBoxFlat = resolved as StyleBoxFlat
	assert_eq(flat.bg_color, EXPECTED_PAPER_BG,
			("Book's resolved 'panel' stylebox bg_color should equal paper_bg (%s) — got %s. "
			+ "This is the documented cream page background; a mismatch here means Book is "
			+ "still rendering the engine's default dark Panel style."
			) % [EXPECTED_PAPER_BG, flat.bg_color])


# ---------------------------------------------------------------------------
# Test 6 — Issue #47: reparented, un-overridden Label text resolves ink
# ---------------------------------------------------------------------------
# WeightLabel (RightPage) is a plain Label node in inventory_tab.tscn with NO
# per-node font_color override — unlike SlotLabel/ItemNameLabel in
# equipment_slot.tscn, which already hardcode ink/ink_muted and would pass
# this assertion even with the bug present. WeightLabel is the honest proof
# that the *default* cascade (not a per-node override) delivers ink, matching
# base_theme.tres's Label/colors/font_color addition.
#
# Button theming (an equivalent EquipButton test) is deliberately out of
# scope here — deferred to issue #48 along with Button styleboxes; see
# test_base_theme.gd's issue #47 section header for the rationale.

func test_reparented_label_with_no_override_resolves_default_font_color_ink() -> void:
	PlayerData._load_resource(PlayerDataResource.new())

	var notebook: Notebook = _make_notebook()
	notebook._switch_tab(Notebook.NotebookTab.INVENTORY)

	# populate_right() nests InventoryTab's own "RightPage" VBoxContainer
	# inside notebook's "RightPage" Control (Book/Pages/RightPage/RightPage/...),
	# so a recursive find_child() is used rather than a hardcoded depth — same
	# robustness reasoning as _find_theme_ancestor()/_find_first_label() above:
	# this test should not break if that nesting depth ever changes.
	var right_page: Control = notebook.get_node_or_null("Book/Pages/RightPage") as Control
	assert_not_null(right_page, "notebook.tscn must contain a node at path Book/Pages/RightPage")
	if right_page == null:
		return

	var weight_label: Label = right_page.find_child("WeightLabel", true, false) as Label
	assert_not_null(weight_label,
			"RightPage must contain a WeightLabel after _switch_tab(INVENTORY) — "
			+ "InventoryTab.populate_right() reparents RightPage's static chrome, including WeightLabel")
	if weight_label == null:
		return

	# get_theme_color("font_color", "") resolves against the node's own class
	# (Label) when theme_type is the default empty string — the same
	# resolution Godot performs when actually drawing this Label's text.
	# https://docs.godotengine.org/en/stable/classes/class_control.html#class-control-method-get-theme-color
	var resolved: Color = weight_label.get_theme_color("font_color", "")
	assert_eq(resolved, EXPECTED_INK,
			("WeightLabel has no per-node font_color override, so it must resolve the theme's default "
			+ "Label font_color (ink, %s) via cascade — got %s. A mismatch (commonly engine-default "
			+ "white, Color(1,1,1,1)) means base_theme.tres has no Label/colors/font_color entry."
			) % [EXPECTED_INK, resolved])


# ---------------------------------------------------------------------------
# Test 7 — Issue #47 review follow-up: reparented PanelContainer resolves
# the paper_bg_shadow stylebox via cascade, not a per-node override
# ---------------------------------------------------------------------------
# PanelContainer does not inherit Panel's stylebox through Godot's theme type
# chain (PanelContainer -> Container -> Control, never through Panel), so it
# needed its own base_theme.tres entry — added alongside this test during
# code review. IconFrame (a PanelContainer, child of each EquipmentSlot in
# equipment_slot.tscn) has no per-node stylebox override, so it is the honest
# proof that the cascade — not a per-node override — delivers the themed box.
# Reached the same way test 6 reaches WeightLabel: drive _switch_tab(INVENTORY)
# so InventoryTab.populate_left() reparents the real EquipmentSlot nodes into
# Book/Pages/LeftPage, then locate IconFrame recursively underneath.

func test_reparented_panel_container_with_no_override_resolves_default_stylebox() -> void:
	PlayerData._load_resource(PlayerDataResource.new())

	var notebook: Notebook = _make_notebook()
	notebook._switch_tab(Notebook.NotebookTab.INVENTORY)

	var left_page: Control = notebook.get_node_or_null("Book/Pages/LeftPage") as Control
	assert_not_null(left_page, "notebook.tscn must contain a node at path Book/Pages/LeftPage")
	if left_page == null:
		return

	# find_child(..., true, false) searches recursively; owned=false is
	# required — populate_left() reparents EquipmentSlot nodes that LeftPage
	# does not own, and the default owned=true would prune them. IconFrame
	# lives at EquipmentSlot/HBox/IconFrame inside each of the four equipment
	# slots populate_left() reparents into LeftPage.
	var icon_frame: PanelContainer = left_page.find_child("IconFrame", true, false) as PanelContainer
	assert_not_null(icon_frame,
			"LeftPage must contain an EquipmentSlot IconFrame after _switch_tab(INVENTORY) — "
			+ "InventoryTab.populate_left() reparents the four EquipmentSlot nodes, each with an IconFrame PanelContainer child")
	if icon_frame == null:
		return

	# get_theme_stylebox("panel", "") resolves against the node's own class
	# (PanelContainer) when the type argument is the default empty string —
	# the same resolution Godot performs when actually painting this box.
	# https://docs.godotengine.org/en/stable/classes/class_control.html#class-control-method-get-theme-stylebox
	var resolved: StyleBox = icon_frame.get_theme_stylebox("panel", "")
	assert_not_null(resolved,
			"IconFrame (a PanelContainer) must resolve a 'panel' stylebox via theme cascade")
	if resolved == null:
		return

	assert_true(resolved is StyleBoxFlat,
			"IconFrame's resolved 'panel' stylebox should be a StyleBoxFlat, not the engine's built-in default PanelContainer style")
	if not (resolved is StyleBoxFlat):
		return

	var flat: StyleBoxFlat = resolved as StyleBoxFlat
	assert_eq(flat.bg_color, EXPECTED_PAPER_BG_SHADOW,
			("IconFrame's resolved 'panel' stylebox bg_color should equal paper_bg_shadow (%s) — got %s. "
			+ "IconFrame has no per-node stylebox override, so a mismatch means base_theme.tres has no "
			+ "PanelContainer/styles/panel entry (or it does not cascade)."
			) % [EXPECTED_PAPER_BG_SHADOW, flat.bg_color])
