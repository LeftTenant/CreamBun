## test_equipment_slot.gd
## Behavior tests for EquipmentSlot (ui/notebook/inventory/equipment_slot.gd).
##
## WHAT THESE TESTS GUARD (Issue #7)
## ----------------------------------
## Before the fix, equipping an item hid the slot-name heading entirely
## (SlotLabel.visible = false), replacing it with the item icon. Per issue #7
## the desired behavior is:
##   - SlotLabel (the slot-name heading) stays visible ALWAYS, filled or empty.
##   - IconFrame/IconRect show the equipped item's icon in a persistent framed
##     area beside the heading when filled.
##   - ItemNameLabel appears UNDER the heading only while the slot is selected.
##   - A filled slot is selectable (click emits `selected`); an EMPTY slot is
##     NOT selectable (click does nothing, no `selected` emission).
##   - set_selected(true) reveals ItemNameLabel + SelectionRect; set_selected(false)
##     hides them again.
##
## These tests currently FAIL against the pre-fix equipment_slot.gd, which:
##   - hides SlotLabel when an item is set (_update_display branch),
##   - has no `selected` signal, set_selected(), or _gui_input override,
##   - has no ItemNameLabel / SelectionRect nodes to toggle.
##
## --- SUBJECT CONSTRUCTION NOTE ---
## EquipmentSlot is instantiated from equipment_slot.tscn (not .new()) because
## the script resolves @onready children (_slot_label, _icon_rect, etc.) that
## only exist when the node comes from the scene.
##
## Requires GUT: https://github.com/bitwes/Gut
## Install via Godot Asset Library (search "GUT - Godot Unit Testing").
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd -gselect=test_equipment_slot.gd -gexit

class_name TestEquipmentSlot
extends GutTest


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const SCENE_PATH: String = "res://ui/notebook/inventory/equipment_slot.tscn"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Instantiate equipment_slot.tscn and add it to the scene tree so @onready
## refs resolve before setup() is called.
##
## @return the instantiated EquipmentSlot root node
func _make_slot() -> EquipmentSlot:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	var instance: EquipmentSlot = packed.instantiate() as EquipmentSlot
	add_child_autofree(instance)
	return instance


## Build a minimal equippable ItemData with an icon texture set, so
## _update_display() has something non-null to assign to IconRect.texture.
func _make_item(id: StringName, slot: ItemData.EquipSlot) -> ItemData:
	var item: ItemData = ItemData.new()
	item.id = id
	item.display_name = "Test " + String(id)
	item.weight = 0.5
	item.equip_slot = slot
	# A 1x1 ImageTexture is enough to give IconRect.texture a non-null value
	# without depending on any art asset.
	# https://docs.godotengine.org/en/stable/classes/class_imagetexture.html
	var image: Image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
	item.icon = ImageTexture.create_from_image(image)
	autofree(item)
	return item


## Simulate a left-click press by calling _gui_input directly with a synthetic
## InputEventMouseButton. We call _gui_input directly (rather than driving a
## real Viewport click) for the same reason inventory_row tests do — no OS
## window or real input focus is required.
func _click(slot: EquipmentSlot) -> void:
	var mb: InputEventMouseButton = InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	slot._gui_input(mb)


# ---------------------------------------------------------------------------
# Test 1 — heading stays visible when the slot is empty
# ---------------------------------------------------------------------------

func test_heading_visible_when_empty() -> void:
	var slot: EquipmentSlot = _make_slot()
	slot.setup(ItemData.EquipSlot.BOOTS, null)

	var heading: Label = slot.find_child("SlotLabel", true, false) as Label
	assert_not_null(heading, "equipment_slot.tscn must declare 'SlotLabel'")
	if heading == null:
		return
	assert_true(heading.visible,
			"SlotLabel must be visible when the slot is empty")
	assert_eq(heading.text, "Boots",
			"SlotLabel must show the slot name ('Boots') when empty")


# ---------------------------------------------------------------------------
# Test 2 — heading stays visible when an item is equipped (the core bug)
# ---------------------------------------------------------------------------

func test_heading_stays_visible_when_item_equipped() -> void:
	# This is the central regression from issue #7: equipping an item used to
	# set SlotLabel.visible = false. The heading must remain visible so the
	# player always knows which body region a filled slot represents.
	var slot: EquipmentSlot = _make_slot()
	var boots: ItemData = _make_item(&"heading_test_boots", ItemData.EquipSlot.BOOTS)

	slot.setup(ItemData.EquipSlot.BOOTS, boots)

	var heading: Label = slot.find_child("SlotLabel", true, false) as Label
	assert_not_null(heading, "equipment_slot.tscn must declare 'SlotLabel'")
	if heading == null:
		return
	assert_true(heading.visible,
			"SlotLabel ('Boots' heading) must remain visible after an item is equipped")


# ---------------------------------------------------------------------------
# Test 3 — framed icon area is populated when the slot is filled
# ---------------------------------------------------------------------------

func test_icon_rect_populated_when_filled() -> void:
	var slot: EquipmentSlot = _make_slot()
	var boots: ItemData = _make_item(&"icon_test_boots", ItemData.EquipSlot.BOOTS)

	slot.setup(ItemData.EquipSlot.BOOTS, boots)

	var icon_rect: TextureRect = slot.find_child("IconRect", true, false) as TextureRect
	assert_not_null(icon_rect, "equipment_slot.tscn must declare 'IconRect'")
	if icon_rect == null:
		return
	assert_true(icon_rect.visible,
			"IconRect must be visible once an item is equipped")
	assert_eq(icon_rect.texture, boots.icon,
			"IconRect.texture must be set to the equipped item's icon")


# ---------------------------------------------------------------------------
# Test 4 — empty slot hides the framed icon and clears its texture
# ---------------------------------------------------------------------------

func test_icon_rect_hidden_when_empty() -> void:
	var slot: EquipmentSlot = _make_slot()
	slot.setup(ItemData.EquipSlot.BOOTS, null)

	var icon_rect: TextureRect = slot.find_child("IconRect", true, false) as TextureRect
	assert_not_null(icon_rect, "equipment_slot.tscn must declare 'IconRect'")
	if icon_rect == null:
		return
	assert_false(icon_rect.visible,
			"IconRect must be hidden when the slot is empty")


# ---------------------------------------------------------------------------
# Test 5 — set_selected(true) on a filled slot reveals ItemNameLabel + highlight
# ---------------------------------------------------------------------------

func test_set_selected_true_reveals_item_name_and_highlight() -> void:
	var slot: EquipmentSlot = _make_slot()
	var boots: ItemData = _make_item(&"select_test_boots", ItemData.EquipSlot.BOOTS)
	slot.setup(ItemData.EquipSlot.BOOTS, boots)

	slot.set_selected(true)

	var name_label: Label = slot.find_child("ItemNameLabel", true, false) as Label
	assert_not_null(name_label, "equipment_slot.tscn must declare 'ItemNameLabel'")
	if name_label != null:
		assert_true(name_label.visible,
				"ItemNameLabel must become visible when set_selected(true) is called on a filled slot")
		assert_eq(name_label.text, boots.display_name,
				"ItemNameLabel must show the equipped item's display_name while selected")

	var highlight: ColorRect = slot.find_child("SelectionRect", true, false) as ColorRect
	assert_not_null(highlight, "equipment_slot.tscn must declare 'SelectionRect'")
	if highlight != null:
		assert_true(highlight.visible,
				"SelectionRect must become visible when set_selected(true) is called")


# ---------------------------------------------------------------------------
# Test 6 — set_selected(false) hides ItemNameLabel + highlight again
# ---------------------------------------------------------------------------

func test_set_selected_false_hides_item_name_and_highlight() -> void:
	var slot: EquipmentSlot = _make_slot()
	var boots: ItemData = _make_item(&"deselect_test_boots", ItemData.EquipSlot.BOOTS)
	slot.setup(ItemData.EquipSlot.BOOTS, boots)

	slot.set_selected(true)
	slot.set_selected(false)

	var name_label: Label = slot.find_child("ItemNameLabel", true, false) as Label
	if name_label != null:
		assert_false(name_label.visible,
				"ItemNameLabel must be hidden again after set_selected(false)")

	var highlight: ColorRect = slot.find_child("SelectionRect", true, false) as ColorRect
	if highlight != null:
		assert_false(highlight.visible,
				"SelectionRect must be hidden again after set_selected(false)")


# ---------------------------------------------------------------------------
# Test 7 — clicking a FILLED slot emits `selected`
# ---------------------------------------------------------------------------

func test_click_on_filled_slot_emits_selected() -> void:
	var slot: EquipmentSlot = _make_slot()
	var boots: ItemData = _make_item(&"click_test_boots", ItemData.EquipSlot.BOOTS)
	slot.setup(ItemData.EquipSlot.BOOTS, boots)

	watch_signals(slot)
	_click(slot)

	assert_signal_emitted(slot, "selected",
			"clicking a FILLED equipment slot must emit 'selected'")


# ---------------------------------------------------------------------------
# Test 8 — clicking an EMPTY slot does NOT emit `selected`
# ---------------------------------------------------------------------------

func test_click_on_empty_slot_does_not_emit_selected() -> void:
	var slot: EquipmentSlot = _make_slot()
	slot.setup(ItemData.EquipSlot.BOOTS, null)

	watch_signals(slot)
	_click(slot)

	assert_signal_not_emitted(slot, "selected",
			"clicking an EMPTY equipment slot must NOT emit 'selected'")


# ---------------------------------------------------------------------------
# Test 9 — clicking an EMPTY slot leaves it unselected (no highlight)
# ---------------------------------------------------------------------------

func test_click_on_empty_slot_leaves_it_unselected() -> void:
	var slot: EquipmentSlot = _make_slot()
	slot.setup(ItemData.EquipSlot.BOOTS, null)

	_click(slot)

	var highlight: ColorRect = slot.find_child("SelectionRect", true, false) as ColorRect
	if highlight != null:
		assert_false(highlight.visible,
				"clicking an EMPTY slot must not reveal the selection highlight")

	var name_label: Label = slot.find_child("ItemNameLabel", true, false) as Label
	if name_label != null:
		assert_false(name_label.visible,
				"clicking an EMPTY slot must not reveal ItemNameLabel")
