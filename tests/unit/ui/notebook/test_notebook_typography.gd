## test_notebook_typography.gd
## Scene-as-data typography contract tests for the Slice 5 notebook font-size pass.
##
## WHAT THESE TESTS GUARD
## ----------------------
## Slice 5's job is purely assignment: Labels that are headings receive
## `theme_type_variation = "Heading"` (so they inherit font_size 16 from the
## theme); all other Labels carry NO per-node font_size override (so they
## inherit the base-theme default of 8). Two color-only differentiations
## are also asserted: equipment_slot SlotLabel/ItemNameLabel and quests
## CompletedSeparator.
##
## Regression guard for that shipped assignment. See the approved test plan at:
##   docs/features/pixel-art-purist/slice-5-notebook-font-size-pass-test-plan.md
##
## HOW PER-NODE THEME OVERRIDES ARE TESTED
## ----------------------------------------
## Godot 4 exposes per-node override checks via:
##   Control.has_theme_font_size_override(name: StringName) -> bool
##   Control.has_theme_color_override(name: StringName) -> bool
## These are distinct from the cascade-resolved helpers (get_theme_font_size,
## get_theme_color), which walk the theme hierarchy. We use the override-specific
## API to assert that no hardcoded font_size is baked into the node.
## Note: there is no get_theme_color_override() method in Godot 4. To read back
## a per-node color override value, use Control.get("theme_override_colors/<name>").
##
## PALETTE COLORS UNDER TEST
## -------------------------
## §4 palette values (from test_base_theme.gd / base_theme.tres):
##   ink        = Color("#3b2f2a")
##   ink_muted  = Color("#7a6a5d")
##
## Requires GUT: https://github.com/bitwes/Gut
## Install via Godot Asset Library (search "GUT - Godot Unit Testing").

class_name TestNotebookTypography
extends GutTest


# ---------------------------------------------------------------------------
# Palette color constants (§4 — matches test_base_theme.gd)
# ---------------------------------------------------------------------------

## ink — used for prominent body labels (e.g. SlotLabel slot role name).
const COLOR_INK: Color = Color("#3b2f2a")

## ink_muted — used for secondary body labels (e.g. ItemNameLabel, CompletedSeparator).
const COLOR_INK_MUTED: Color = Color("#7a6a5d")

## Heading variation name — must match theme resource definition.
const HEADING_VARIATION: String = "Heading"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Load and instantiate a PackedScene from the given res:// path.
## The instance is added to the scene tree (so @onready vars resolve) and
## autofreed after the test. Returns null if the scene cannot be loaded.
func _make_instance(scene_path: String) -> Node:
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		return null
	var instance: Node = packed.instantiate()
	add_child_autofree(instance)
	return instance


## Assert that `label` has `theme_type_variation == "Heading"`.
## Wraps a common pattern with a consistent failure message.
func _assert_is_heading(label: Label, label_path: String) -> void:
	assert_eq(label.theme_type_variation, HEADING_VARIATION,
			("'%s' must have theme_type_variation = \"Heading\" "
			+ "so it receives font_size 16 from the theme variation — got \"%s\"")
			% [label_path, label.theme_type_variation])


## Assert that `label` has NO `theme_type_variation` set (empty string).
func _assert_is_not_heading(label: Label, label_path: String) -> void:
	assert_eq(label.theme_type_variation, "",
			("'%s' must have NO theme_type_variation (body text inherits "
			+ "the default font_size 8 from the theme cascade) — got \"%s\"")
			% [label_path, label.theme_type_variation])


## Assert that `label` has NO per-node font_size override set.
## A per-node override blocks the theme cascade and would produce the wrong size.
func _assert_no_font_size_override(label: Label, label_path: String) -> void:
	# https://docs.godotengine.org/en/stable/classes/class_control.html#class-control-method-has-theme-font-size-override
	assert_false(label.has_theme_font_size_override("font_size"),
			("'%s' must have NO per-node font_size override — "
			+ "size must come only from the theme cascade or Heading variation, "
			+ "not a hardcoded node property")
			% [label_path])


## Assert that `label` has a per-node font_color override equal to `expected`.
func _assert_color_override(label: Label, expected: Color, color_name: String, label_path: String) -> void:
	# https://docs.godotengine.org/en/stable/classes/class_control.html#class-control-method-has-theme-color-override
	assert_true(label.has_theme_color_override("font_color"),
			("'%s' must have a per-node font_color override set to '%s' "
			+ "for color-only differentiation")
			% [label_path, color_name])
	if not label.has_theme_color_override("font_color"):
		return
	# Godot 4 does not expose get_theme_color_override() as a method. Per-node
	# theme overrides live in an internal dict and are readable via the property
	# path "theme_override_colors/<name>" using Control.get(). This is the
	# canonical way to read back a per-node color override value.
	# https://docs.godotengine.org/en/stable/classes/class_control.html#class-control-property-theme_override_colors
	var actual: Color = label.get("theme_override_colors/font_color") as Color
	assert_eq(actual, expected,
			("'%s' font_color override must equal %s (%s) — got %s")
			% [label_path, color_name, expected, actual])


# ---------------------------------------------------------------------------
# equipment_slot.tscn — font-size override removal + color differentiation
# ---------------------------------------------------------------------------

func test_equipment_slot_slot_label_has_no_font_size_override() -> void:
	# The hardcoded font_size = 12 override on SlotLabel must be removed so it
	# inherits the body default of 8 from the theme cascade. This was the primary
	# typography violation found in equipment_slot.tscn during Slice 5 analysis.
	var instance: Node = _make_instance("res://ui/notebook/inventory/equipment_slot.tscn")
	assert_not_null(instance, "equipment_slot.tscn must load and instantiate")
	if instance == null:
		return

	var label: Node = instance.find_child("SlotLabel", true, false)
	assert_not_null(label, "equipment_slot.tscn must contain a node named 'SlotLabel'")
	if label == null:
		return

	_assert_no_font_size_override(label as Label, "SlotLabel")


func test_equipment_slot_item_name_label_has_no_font_size_override() -> void:
	# The hardcoded font_size = 10 override on ItemNameLabel must also be removed.
	# Like SlotLabel, it must fall back to the theme cascade default of 8.
	var instance: Node = _make_instance("res://ui/notebook/inventory/equipment_slot.tscn")
	assert_not_null(instance, "equipment_slot.tscn must load and instantiate")
	if instance == null:
		return

	var label: Node = instance.find_child("ItemNameLabel", true, false)
	assert_not_null(label, "equipment_slot.tscn must contain a node named 'ItemNameLabel'")
	if label == null:
		return

	_assert_no_font_size_override(label as Label, "ItemNameLabel")


func test_equipment_slot_slot_label_has_no_heading_variation() -> void:
	# SlotLabel is body text at 8 — differentiated from ItemNameLabel by color
	# only (ink vs ink_muted), NOT by size. No Heading variation is applied.
	# This records the user decision from 2026-06-16.
	var instance: Node = _make_instance("res://ui/notebook/inventory/equipment_slot.tscn")
	assert_not_null(instance, "equipment_slot.tscn must load and instantiate")
	if instance == null:
		return

	var label: Node = instance.find_child("SlotLabel", true, false)
	assert_not_null(label, "equipment_slot.tscn must contain a node named 'SlotLabel'")
	if label == null:
		return

	_assert_is_not_heading(label as Label, "SlotLabel")


func test_equipment_slot_slot_label_color_is_ink() -> void:
	# SlotLabel shows the slot role name ("Backpack", "Clothing", etc.) — the more
	# prominent of the two text lines. It uses ink (#3b2f2a) for higher contrast.
	var instance: Node = _make_instance("res://ui/notebook/inventory/equipment_slot.tscn")
	assert_not_null(instance, "equipment_slot.tscn must load and instantiate")
	if instance == null:
		return

	var label: Node = instance.find_child("SlotLabel", true, false)
	assert_not_null(label, "equipment_slot.tscn must contain a node named 'SlotLabel'")
	if label == null:
		return

	_assert_color_override(label as Label, COLOR_INK, "ink", "SlotLabel")


func test_equipment_slot_item_name_label_has_no_heading_variation() -> void:
	# ItemNameLabel shows the equipped item name — secondary information within
	# the slot widget. It is body text at 8 with no Heading variation.
	var instance: Node = _make_instance("res://ui/notebook/inventory/equipment_slot.tscn")
	assert_not_null(instance, "equipment_slot.tscn must load and instantiate")
	if instance == null:
		return

	var label: Node = instance.find_child("ItemNameLabel", true, false)
	assert_not_null(label, "equipment_slot.tscn must contain a node named 'ItemNameLabel'")
	if label == null:
		return

	_assert_is_not_heading(label as Label, "ItemNameLabel")


func test_equipment_slot_item_name_label_color_is_ink_muted() -> void:
	# ItemNameLabel uses ink_muted (#7a6a5d) — the muted palette color signals
	# that this text is secondary within the slot widget, below the SlotLabel.
	var instance: Node = _make_instance("res://ui/notebook/inventory/equipment_slot.tscn")
	assert_not_null(instance, "equipment_slot.tscn must load and instantiate")
	if instance == null:
		return

	var label: Node = instance.find_child("ItemNameLabel", true, false)
	assert_not_null(label, "equipment_slot.tscn must contain a node named 'ItemNameLabel'")
	if label == null:
		return

	_assert_color_override(label as Label, COLOR_INK_MUTED, "ink_muted", "ItemNameLabel")


# ---------------------------------------------------------------------------
# inventory_tab.tscn — EquipmentHeader (heading) + WeightLabel (body)
# ---------------------------------------------------------------------------

func test_inventory_tab_equipment_header_has_heading_variation() -> void:
	# "Equipment" is the section heading for the left-page equipment silhouette.
	# It must receive the Heading variation so it renders at size 16.
	var instance: Node = _make_instance("res://ui/notebook/inventory/inventory_tab.tscn")
	assert_not_null(instance, "inventory_tab.tscn must load and instantiate")
	if instance == null:
		return

	var label: Node = instance.find_child("EquipmentHeader", true, false)
	assert_not_null(label, "inventory_tab.tscn must contain a node named 'EquipmentHeader'")
	if label == null:
		return

	_assert_is_heading(label as Label, "EquipmentHeader")


func test_inventory_tab_equipment_header_has_no_font_size_override() -> void:
	# Size must come only from the Heading variation in the theme, not from a
	# hardcoded per-node override — a hardcoded override would block the cascade
	# and make the variation irrelevant.
	var instance: Node = _make_instance("res://ui/notebook/inventory/inventory_tab.tscn")
	assert_not_null(instance, "inventory_tab.tscn must load and instantiate")
	if instance == null:
		return

	var label: Node = instance.find_child("EquipmentHeader", true, false)
	assert_not_null(label, "inventory_tab.tscn must contain a node named 'EquipmentHeader'")
	if label == null:
		return

	_assert_no_font_size_override(label as Label, "EquipmentHeader")


func test_inventory_tab_weight_label_has_no_heading_variation() -> void:
	# WeightLabel ("Weight: 0.0 / ∞") is a live data readout — body text at 8.
	var instance: Node = _make_instance("res://ui/notebook/inventory/inventory_tab.tscn")
	assert_not_null(instance, "inventory_tab.tscn must load and instantiate")
	if instance == null:
		return

	var label: Node = instance.find_child("WeightLabel", true, false)
	assert_not_null(label, "inventory_tab.tscn must contain a node named 'WeightLabel'")
	if label == null:
		return

	_assert_is_not_heading(label as Label, "WeightLabel")


func test_inventory_tab_weight_label_has_no_font_size_override() -> void:
	var instance: Node = _make_instance("res://ui/notebook/inventory/inventory_tab.tscn")
	assert_not_null(instance, "inventory_tab.tscn must load and instantiate")
	if instance == null:
		return

	var label: Node = instance.find_child("WeightLabel", true, false)
	assert_not_null(label, "inventory_tab.tscn must contain a node named 'WeightLabel'")
	if label == null:
		return

	_assert_no_font_size_override(label as Label, "WeightLabel")


# ---------------------------------------------------------------------------
# inventory_row.tscn — all body text (NameLabel, CountLabel, WeightLabel)
# ---------------------------------------------------------------------------

func test_inventory_row_name_label_is_body() -> void:
	# The item name in a row is body text — no variation, no size override.
	var instance: Node = _make_instance("res://ui/notebook/inventory/inventory_row.tscn")
	assert_not_null(instance, "inventory_row.tscn must load and instantiate")
	if instance == null:
		return

	var label: Node = instance.find_child("NameLabel", true, false)
	assert_not_null(label, "inventory_row.tscn must contain a node named 'NameLabel'")
	if label == null:
		return

	_assert_is_not_heading(label as Label, "NameLabel")
	_assert_no_font_size_override(label as Label, "NameLabel")


func test_inventory_row_count_label_is_body() -> void:
	var instance: Node = _make_instance("res://ui/notebook/inventory/inventory_row.tscn")
	assert_not_null(instance, "inventory_row.tscn must load and instantiate")
	if instance == null:
		return

	var label: Node = instance.find_child("CountLabel", true, false)
	assert_not_null(label, "inventory_row.tscn must contain a node named 'CountLabel'")
	if label == null:
		return

	_assert_is_not_heading(label as Label, "CountLabel")
	_assert_no_font_size_override(label as Label, "CountLabel")


func test_inventory_row_weight_label_is_body() -> void:
	var instance: Node = _make_instance("res://ui/notebook/inventory/inventory_row.tscn")
	assert_not_null(instance, "inventory_row.tscn must load and instantiate")
	if instance == null:
		return

	var label: Node = instance.find_child("WeightLabel", true, false)
	assert_not_null(label, "inventory_row.tscn must contain a node named 'WeightLabel'")
	if label == null:
		return

	_assert_is_not_heading(label as Label, "WeightLabel")
	_assert_no_font_size_override(label as Label, "WeightLabel")


# ---------------------------------------------------------------------------
# map_tab.tscn — WorldMapHeading + LocalAreaHeading (heading), notes (body)
# ---------------------------------------------------------------------------

func test_map_tab_world_map_heading_has_heading_variation() -> void:
	# "World Map" is the page heading for the left-page world overview.
	var instance: Node = _make_instance("res://ui/notebook/map/map_tab.tscn")
	assert_not_null(instance, "map_tab.tscn must load and instantiate")
	if instance == null:
		return

	var label: Node = instance.find_child("WorldMapHeading", true, false)
	assert_not_null(label, "map_tab.tscn must contain a node named 'WorldMapHeading'")
	if label == null:
		return

	_assert_is_heading(label as Label, "WorldMapHeading")


func test_map_tab_world_map_heading_has_no_font_size_override() -> void:
	var instance: Node = _make_instance("res://ui/notebook/map/map_tab.tscn")
	assert_not_null(instance, "map_tab.tscn must load and instantiate")
	if instance == null:
		return

	var label: Node = instance.find_child("WorldMapHeading", true, false)
	assert_not_null(label, "map_tab.tscn must contain a node named 'WorldMapHeading'")
	if label == null:
		return

	_assert_no_font_size_override(label as Label, "WorldMapHeading")


func test_map_tab_world_map_note_is_body() -> void:
	# Placeholder note text is body text — no variation, no size override.
	var instance: Node = _make_instance("res://ui/notebook/map/map_tab.tscn")
	assert_not_null(instance, "map_tab.tscn must load and instantiate")
	if instance == null:
		return

	var label: Node = instance.find_child("WorldMapNote", true, false)
	assert_not_null(label, "map_tab.tscn must contain a node named 'WorldMapNote'")
	if label == null:
		return

	_assert_is_not_heading(label as Label, "WorldMapNote")
	_assert_no_font_size_override(label as Label, "WorldMapNote")


func test_map_tab_local_area_heading_has_heading_variation() -> void:
	# "Local Area" is the page heading for the right-page local map.
	var instance: Node = _make_instance("res://ui/notebook/map/map_tab.tscn")
	assert_not_null(instance, "map_tab.tscn must load and instantiate")
	if instance == null:
		return

	var label: Node = instance.find_child("LocalAreaHeading", true, false)
	assert_not_null(label, "map_tab.tscn must contain a node named 'LocalAreaHeading'")
	if label == null:
		return

	_assert_is_heading(label as Label, "LocalAreaHeading")


func test_map_tab_local_area_heading_has_no_font_size_override() -> void:
	var instance: Node = _make_instance("res://ui/notebook/map/map_tab.tscn")
	assert_not_null(instance, "map_tab.tscn must load and instantiate")
	if instance == null:
		return

	var label: Node = instance.find_child("LocalAreaHeading", true, false)
	assert_not_null(label, "map_tab.tscn must contain a node named 'LocalAreaHeading'")
	if label == null:
		return

	_assert_no_font_size_override(label as Label, "LocalAreaHeading")


func test_map_tab_local_map_note_is_body() -> void:
	var instance: Node = _make_instance("res://ui/notebook/map/map_tab.tscn")
	assert_not_null(instance, "map_tab.tscn must load and instantiate")
	if instance == null:
		return

	var label: Node = instance.find_child("LocalMapNote", true, false)
	assert_not_null(label, "map_tab.tscn must contain a node named 'LocalMapNote'")
	if label == null:
		return

	_assert_is_not_heading(label as Label, "LocalMapNote")
	_assert_no_font_size_override(label as Label, "LocalMapNote")


# ---------------------------------------------------------------------------
# quests_tab.tscn — CompletedSeparator (body+ink_muted), TitleLabel (heading),
#                   DescriptionLabel + objectives + Placeholder (body)
# ---------------------------------------------------------------------------

func test_quests_tab_completed_separator_has_no_heading_variation() -> void:
	# "— Completed —" is body text at 8 differentiated by ink_muted color only.
	# User decision recorded 2026-06-16: NOT a heading.
	var instance: Node = _make_instance("res://ui/notebook/quests/quests_tab.tscn")
	assert_not_null(instance, "quests_tab.tscn must load and instantiate")
	if instance == null:
		return

	var label: Node = instance.find_child("CompletedSeparator", true, false)
	assert_not_null(label, "quests_tab.tscn must contain a node named 'CompletedSeparator'")
	if label == null:
		return

	_assert_is_not_heading(label as Label, "CompletedSeparator")


func test_quests_tab_completed_separator_has_no_font_size_override() -> void:
	var instance: Node = _make_instance("res://ui/notebook/quests/quests_tab.tscn")
	assert_not_null(instance, "quests_tab.tscn must load and instantiate")
	if instance == null:
		return

	var label: Node = instance.find_child("CompletedSeparator", true, false)
	assert_not_null(label, "quests_tab.tscn must contain a node named 'CompletedSeparator'")
	if label == null:
		return

	_assert_no_font_size_override(label as Label, "CompletedSeparator")


func test_quests_tab_completed_separator_color_is_ink_muted() -> void:
	# ink_muted visually recedes relative to ink rows, creating the section
	# divider effect without requiring a different font size.
	var instance: Node = _make_instance("res://ui/notebook/quests/quests_tab.tscn")
	assert_not_null(instance, "quests_tab.tscn must load and instantiate")
	if instance == null:
		return

	var label: Node = instance.find_child("CompletedSeparator", true, false)
	assert_not_null(label, "quests_tab.tscn must contain a node named 'CompletedSeparator'")
	if label == null:
		return

	_assert_color_override(label as Label, COLOR_INK_MUTED, "ink_muted", "CompletedSeparator")


func test_quests_tab_title_label_has_heading_variation() -> void:
	# QuestDetail/TitleLabel shows the selected quest's name in the detail pane —
	# the primary heading for that content block. It must receive the Heading variation.
	var instance: Node = _make_instance("res://ui/notebook/quests/quests_tab.tscn")
	assert_not_null(instance, "quests_tab.tscn must load and instantiate")
	if instance == null:
		return

	# Path: RightPage > QuestDetail > TitleLabel
	var detail: Node = instance.find_child("QuestDetail", true, false)
	assert_not_null(detail, "quests_tab.tscn must contain a node named 'QuestDetail'")
	if detail == null:
		return

	var label: Node = detail.find_child("TitleLabel", true, false)
	assert_not_null(label, "QuestDetail must contain a node named 'TitleLabel'")
	if label == null:
		return

	_assert_is_heading(label as Label, "QuestDetail/TitleLabel")


func test_quests_tab_title_label_has_no_font_size_override() -> void:
	var instance: Node = _make_instance("res://ui/notebook/quests/quests_tab.tscn")
	assert_not_null(instance, "quests_tab.tscn must load and instantiate")
	if instance == null:
		return

	var detail: Node = instance.find_child("QuestDetail", true, false)
	assert_not_null(detail, "quests_tab.tscn must contain a node named 'QuestDetail'")
	if detail == null:
		return

	var label: Node = detail.find_child("TitleLabel", true, false)
	assert_not_null(label, "QuestDetail must contain a node named 'TitleLabel'")
	if label == null:
		return

	_assert_no_font_size_override(label as Label, "QuestDetail/TitleLabel")


func test_quests_tab_description_label_is_body() -> void:
	# Quest description prose is body text — longer text that needs to wrap,
	# and should not overpower the heading.
	var instance: Node = _make_instance("res://ui/notebook/quests/quests_tab.tscn")
	assert_not_null(instance, "quests_tab.tscn must load and instantiate")
	if instance == null:
		return

	var label: Node = instance.find_child("DescriptionLabel", true, false)
	assert_not_null(label, "quests_tab.tscn must contain a node named 'DescriptionLabel'")
	if label == null:
		return

	_assert_is_not_heading(label as Label, "DescriptionLabel")
	_assert_no_font_size_override(label as Label, "DescriptionLabel")


func test_quests_tab_sample_objective_1_is_body() -> void:
	# Objective bullet lines are body text — small data items in a list.
	var instance: Node = _make_instance("res://ui/notebook/quests/quests_tab.tscn")
	assert_not_null(instance, "quests_tab.tscn must load and instantiate")
	if instance == null:
		return

	var label: Node = instance.find_child("SampleObjective1", true, false)
	assert_not_null(label, "quests_tab.tscn must contain a node named 'SampleObjective1'")
	if label == null:
		return

	_assert_is_not_heading(label as Label, "SampleObjective1")
	_assert_no_font_size_override(label as Label, "SampleObjective1")


func test_quests_tab_sample_objective_2_is_body() -> void:
	var instance: Node = _make_instance("res://ui/notebook/quests/quests_tab.tscn")
	assert_not_null(instance, "quests_tab.tscn must load and instantiate")
	if instance == null:
		return

	var label: Node = instance.find_child("SampleObjective2", true, false)
	assert_not_null(label, "quests_tab.tscn must contain a node named 'SampleObjective2'")
	if label == null:
		return

	_assert_is_not_heading(label as Label, "SampleObjective2")
	_assert_no_font_size_override(label as Label, "SampleObjective2")


func test_quests_tab_right_page_placeholder_is_body() -> void:
	# "Select a quest to see details." is a placeholder — body text at 8.
	# Note: there is a Placeholder in RightPage (direct child), distinct from
	# nodes inside QuestDetail. find_child with false recursive=false won't work
	# here since it's nested; we search the full tree and take the RightPage one.
	var instance: Node = _make_instance("res://ui/notebook/quests/quests_tab.tscn")
	assert_not_null(instance, "quests_tab.tscn must load and instantiate")
	if instance == null:
		return

	var right_page: Node = instance.find_child("RightPage", true, false)
	assert_not_null(right_page, "quests_tab.tscn must contain a node named 'RightPage'")
	if right_page == null:
		return

	# The Placeholder is a direct child of RightPage (not inside QuestDetail).
	var label: Node = right_page.find_child("Placeholder", false, false)
	assert_not_null(label,
			"RightPage must contain a direct child named 'Placeholder' (the 'Select a quest' label)")
	if label == null:
		return

	_assert_is_not_heading(label as Label, "RightPage/Placeholder")
	_assert_no_font_size_override(label as Label, "RightPage/Placeholder")


# ---------------------------------------------------------------------------
# quest_row.tscn — TitleLabel (body — list row, not the detail pane heading)
# ---------------------------------------------------------------------------

func test_quest_row_title_label_is_body() -> void:
	# The quest list row title is body text at 8. The Heading treatment is
	# reserved for QuestDetail/TitleLabel in the detail pane, not the list row.
	# If the list row were also a heading, both would render at 16 and the
	# detail pane heading would lose its visual distinction.
	var instance: Node = _make_instance("res://ui/notebook/quests/quest_row.tscn")
	assert_not_null(instance, "quest_row.tscn must load and instantiate")
	if instance == null:
		return

	var label: Node = instance.find_child("TitleLabel", true, false)
	assert_not_null(label, "quest_row.tscn must contain a node named 'TitleLabel'")
	if label == null:
		return

	_assert_is_not_heading(label as Label, "TitleLabel")
	_assert_no_font_size_override(label as Label, "TitleLabel")


# ---------------------------------------------------------------------------
# settings_tab.tscn — section headings (heading), slider captions (body)
# ---------------------------------------------------------------------------

func test_settings_tab_audio_label_has_heading_variation() -> void:
	# "Audio" is a section heading for the volume sliders block.
	var instance: Node = _make_instance("res://ui/notebook/settings/settings_tab.tscn")
	assert_not_null(instance, "settings_tab.tscn must load and instantiate")
	if instance == null:
		return

	var label: Node = instance.find_child("AudioLabel", true, false)
	assert_not_null(label, "settings_tab.tscn must contain a node named 'AudioLabel'")
	if label == null:
		return

	_assert_is_heading(label as Label, "AudioLabel")


func test_settings_tab_gameplay_label_has_heading_variation() -> void:
	# "Gameplay" is a section heading on the right page.
	var instance: Node = _make_instance("res://ui/notebook/settings/settings_tab.tscn")
	assert_not_null(instance, "settings_tab.tscn must load and instantiate")
	if instance == null:
		return

	var label: Node = instance.find_child("GameplayLabel", true, false)
	assert_not_null(label, "settings_tab.tscn must contain a node named 'GameplayLabel'")
	if label == null:
		return

	_assert_is_heading(label as Label, "GameplayLabel")


func test_settings_tab_display_label_has_heading_variation() -> void:
	# "Display" is a section heading on the right page below "Gameplay".
	var instance: Node = _make_instance("res://ui/notebook/settings/settings_tab.tscn")
	assert_not_null(instance, "settings_tab.tscn must load and instantiate")
	if instance == null:
		return

	var label: Node = instance.find_child("DisplayLabel", true, false)
	assert_not_null(label, "settings_tab.tscn must contain a node named 'DisplayLabel'")
	if label == null:
		return

	_assert_is_heading(label as Label, "DisplayLabel")


func test_settings_tab_master_volume_label_is_body() -> void:
	# "Master Volume" is a slider caption — body text at 8.
	var instance: Node = _make_instance("res://ui/notebook/settings/settings_tab.tscn")
	assert_not_null(instance, "settings_tab.tscn must load and instantiate")
	if instance == null:
		return

	var label: Node = instance.find_child("MasterVolumeLabel", true, false)
	assert_not_null(label, "settings_tab.tscn must contain a node named 'MasterVolumeLabel'")
	if label == null:
		return

	_assert_is_not_heading(label as Label, "MasterVolumeLabel")
	_assert_no_font_size_override(label as Label, "MasterVolumeLabel")


func test_settings_tab_music_volume_label_is_body() -> void:
	var instance: Node = _make_instance("res://ui/notebook/settings/settings_tab.tscn")
	assert_not_null(instance, "settings_tab.tscn must load and instantiate")
	if instance == null:
		return

	var label: Node = instance.find_child("MusicVolumeLabel", true, false)
	assert_not_null(label, "settings_tab.tscn must contain a node named 'MusicVolumeLabel'")
	if label == null:
		return

	_assert_is_not_heading(label as Label, "MusicVolumeLabel")
	_assert_no_font_size_override(label as Label, "MusicVolumeLabel")


func test_settings_tab_sfx_volume_label_is_body() -> void:
	var instance: Node = _make_instance("res://ui/notebook/settings/settings_tab.tscn")
	assert_not_null(instance, "settings_tab.tscn must load and instantiate")
	if instance == null:
		return

	var label: Node = instance.find_child("SfxVolumeLabel", true, false)
	assert_not_null(label, "settings_tab.tscn must contain a node named 'SfxVolumeLabel'")
	if label == null:
		return

	_assert_is_not_heading(label as Label, "SfxVolumeLabel")
	_assert_no_font_size_override(label as Label, "SfxVolumeLabel")


func test_settings_tab_text_speed_label_is_body() -> void:
	# "Text Speed" is a slider caption — body text at 8.
	var instance: Node = _make_instance("res://ui/notebook/settings/settings_tab.tscn")
	assert_not_null(instance, "settings_tab.tscn must load and instantiate")
	if instance == null:
		return

	var label: Node = instance.find_child("TextSpeedLabel", true, false)
	assert_not_null(label, "settings_tab.tscn must contain a node named 'TextSpeedLabel'")
	if label == null:
		return

	_assert_is_not_heading(label as Label, "TextSpeedLabel")
	_assert_no_font_size_override(label as Label, "TextSpeedLabel")


# ---------------------------------------------------------------------------
# sessions_tab.tscn — Placeholder (body)
# ---------------------------------------------------------------------------

func test_sessions_tab_placeholder_is_body() -> void:
	# "Select a Story to see details." is a placeholder — body text at 8.
	var instance: Node = _make_instance("res://ui/notebook/sessions/sessions_tab.tscn")
	assert_not_null(instance, "sessions_tab.tscn must load and instantiate")
	if instance == null:
		return

	var label: Node = instance.find_child("Placeholder", true, false)
	assert_not_null(label, "sessions_tab.tscn must contain a node named 'Placeholder'")
	if label == null:
		return

	_assert_is_not_heading(label as Label, "Placeholder")
	_assert_no_font_size_override(label as Label, "Placeholder")


# ---------------------------------------------------------------------------
# story_card.tscn — NameLabel (heading), LastPlayedLabel (body)
# ---------------------------------------------------------------------------

func test_story_card_name_label_has_heading_variation() -> void:
	# NameLabel shows the Story name — the primary heading of the card.
	# It must receive the Heading variation so it renders at size 16.
	var instance: Node = _make_instance("res://ui/notebook/sessions/story_card.tscn")
	assert_not_null(instance, "story_card.tscn must load and instantiate")
	if instance == null:
		return

	var label: Node = instance.find_child("NameLabel", true, false)
	assert_not_null(label, "story_card.tscn must contain a node named 'NameLabel'")
	if label == null:
		return

	_assert_is_heading(label as Label, "NameLabel")


func test_story_card_last_played_label_is_body() -> void:
	# LastPlayedLabel is secondary metadata — body text at 8, no variation.
	var instance: Node = _make_instance("res://ui/notebook/sessions/story_card.tscn")
	assert_not_null(instance, "story_card.tscn must load and instantiate")
	if instance == null:
		return

	var label: Node = instance.find_child("LastPlayedLabel", true, false)
	assert_not_null(label, "story_card.tscn must contain a node named 'LastPlayedLabel'")
	if label == null:
		return

	_assert_is_not_heading(label as Label, "LastPlayedLabel")
	_assert_no_font_size_override(label as Label, "LastPlayedLabel")
