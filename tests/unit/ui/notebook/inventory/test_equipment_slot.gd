## test_equipment_slot.gd
## Behavior tests for EquipmentSlot (ui/notebook/inventory/equipment_slot.gd).
##
## SLOT VOCABULARY NOTE (Issue #30)
## ---------------------------------
## Issue #30 ("more blob, less limbs") removes BOOTS and GLOVES from
## ItemData.EquipSlot entirely (CreamBun has no legs/paws) and renames
## NECKLACE to BELT. Most of the tests below are about generic EquipmentSlot
## behavior (issue #7) and simply needed their fixture slot swapped from a
## removed value (BOOTS/GLOVES) to a retained one (CLOTHING/GOGGLES) so this
## file keeps compiling once the enum changes — see the bottom of the file
## for tests specifically about the new slot labels.
##
## WHAT THESE TESTS GUARD (Issue #7)
## ----------------------------------
## Before the fix, equipping an item hid the slot-name heading entirely
## (SlotLabel.visible = false), replacing it with the item icon. Per issue #7
## the desired behavior is:
##   - SlotLabel (the slot-name heading) stays visible ALWAYS, filled or empty.
##   - IconFrame/IconRect show the equipped item's icon in a persistent framed
##     area beside the heading when filled.
##   - ItemNameLabel appears UNDER the heading whenever the slot is filled
##     (_item != null), regardless of selection — and is hidden when empty.
##   - A filled slot is selectable (click emits `selected`); an EMPTY slot is
##     NOT selectable (click does nothing, no `selected` emission).
##   - set_selected(true) reveals SelectionRect only; set_selected(false)
##     hides it again. ItemNameLabel is unaffected by selection.
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
	slot.setup(ItemData.EquipSlot.CLOTHING, null)

	var heading: Label = slot.find_child("SlotLabel", true, false) as Label
	assert_not_null(heading, "equipment_slot.tscn must declare 'SlotLabel'")
	if heading == null:
		return
	assert_true(heading.visible,
			"SlotLabel must be visible when the slot is empty")
	assert_eq(heading.text, "Clothing",
			"SlotLabel must show the slot name ('Clothing') when empty")


# ---------------------------------------------------------------------------
# Test 2 — heading stays visible when an item is equipped (the core bug)
# ---------------------------------------------------------------------------

func test_heading_stays_visible_when_item_equipped() -> void:
	# This is the central regression from issue #7: equipping an item used to
	# set SlotLabel.visible = false. The heading must remain visible so the
	# player always knows which body region a filled slot represents.
	var slot: EquipmentSlot = _make_slot()
	var clothing: ItemData = _make_item(&"heading_test_clothing", ItemData.EquipSlot.CLOTHING)

	slot.setup(ItemData.EquipSlot.CLOTHING, clothing)

	var heading: Label = slot.find_child("SlotLabel", true, false) as Label
	assert_not_null(heading, "equipment_slot.tscn must declare 'SlotLabel'")
	if heading == null:
		return
	assert_true(heading.visible,
			"SlotLabel ('Clothing' heading) must remain visible after an item is equipped")


# ---------------------------------------------------------------------------
# Test 3 — framed icon area is populated when the slot is filled
# ---------------------------------------------------------------------------

func test_icon_rect_populated_when_filled() -> void:
	var slot: EquipmentSlot = _make_slot()
	var clothing: ItemData = _make_item(&"icon_test_clothing", ItemData.EquipSlot.CLOTHING)

	slot.setup(ItemData.EquipSlot.CLOTHING, clothing)

	var icon_rect: TextureRect = slot.find_child("IconRect", true, false) as TextureRect
	assert_not_null(icon_rect, "equipment_slot.tscn must declare 'IconRect'")
	if icon_rect == null:
		return
	assert_true(icon_rect.visible,
			"IconRect must be visible once an item is equipped")
	assert_eq(icon_rect.texture, clothing.icon,
			"IconRect.texture must be set to the equipped item's icon")


# ---------------------------------------------------------------------------
# Test 4 — empty slot hides the framed icon and clears its texture
# ---------------------------------------------------------------------------

func test_icon_rect_hidden_when_empty() -> void:
	var slot: EquipmentSlot = _make_slot()
	slot.setup(ItemData.EquipSlot.CLOTHING, null)

	var icon_rect: TextureRect = slot.find_child("IconRect", true, false) as TextureRect
	assert_not_null(icon_rect, "equipment_slot.tscn must declare 'IconRect'")
	if icon_rect == null:
		return
	assert_false(icon_rect.visible,
			"IconRect must be hidden when the slot is empty")


# ---------------------------------------------------------------------------
# Test 5 — set_selected(true) on a filled slot reveals the SelectionRect
#          highlight only (ItemNameLabel is unaffected by selection)
# ---------------------------------------------------------------------------

func test_set_selected_true_reveals_highlight_only() -> void:
	var slot: EquipmentSlot = _make_slot()
	var clothing: ItemData = _make_item(&"select_test_clothing", ItemData.EquipSlot.CLOTHING)
	slot.setup(ItemData.EquipSlot.CLOTHING, clothing)

	slot.set_selected(true)

	var highlight: ColorRect = slot.find_child("SelectionRect", true, false) as ColorRect
	assert_not_null(highlight, "equipment_slot.tscn must declare 'SelectionRect'")
	if highlight != null:
		assert_true(highlight.visible,
				"SelectionRect must become visible when set_selected(true) is called")

	# ItemNameLabel was already visible because the slot is filled — selection
	# must not change that.
	var name_label: Label = slot.find_child("ItemNameLabel", true, false) as Label
	assert_not_null(name_label, "equipment_slot.tscn must declare 'ItemNameLabel'")
	if name_label != null:
		assert_true(name_label.visible,
				"ItemNameLabel must remain visible (driven by fill state, not selection)")


# ---------------------------------------------------------------------------
# Test 6 — set_selected(false) hides the highlight again; ItemNameLabel stays
#          visible because the slot is still filled
# ---------------------------------------------------------------------------

func test_set_selected_false_hides_highlight_but_not_item_name() -> void:
	var slot: EquipmentSlot = _make_slot()
	var clothing: ItemData = _make_item(&"deselect_test_clothing", ItemData.EquipSlot.CLOTHING)
	slot.setup(ItemData.EquipSlot.CLOTHING, clothing)

	slot.set_selected(true)
	slot.set_selected(false)

	var highlight: ColorRect = slot.find_child("SelectionRect", true, false) as ColorRect
	if highlight != null:
		assert_false(highlight.visible,
				"SelectionRect must be hidden again after set_selected(false)")

	var name_label: Label = slot.find_child("ItemNameLabel", true, false) as Label
	if name_label != null:
		assert_true(name_label.visible,
				"ItemNameLabel must remain visible after set_selected(false) because the slot is still filled")
		assert_eq(name_label.text, clothing.display_name,
				"ItemNameLabel must show the equipped item's display_name")


# ---------------------------------------------------------------------------
# Test 5b — setup() with a filled item shows ItemNameLabel even when NOT
#           selected (the core change requested after manual testing)
# ---------------------------------------------------------------------------

func test_setup_with_item_shows_item_name_label_when_not_selected() -> void:
	var slot: EquipmentSlot = _make_slot()
	var clothing: ItemData = _make_item(&"unselected_fill_test_clothing", ItemData.EquipSlot.CLOTHING)

	slot.setup(ItemData.EquipSlot.CLOTHING, clothing)

	var name_label: Label = slot.find_child("ItemNameLabel", true, false) as Label
	assert_not_null(name_label, "equipment_slot.tscn must declare 'ItemNameLabel'")
	if name_label == null:
		return
	assert_true(name_label.visible,
			"ItemNameLabel must be visible whenever the slot is filled, even when not selected")
	assert_eq(name_label.text, clothing.display_name,
			"ItemNameLabel must show the equipped item's display_name")


# ---------------------------------------------------------------------------
# Test 5c — setup() with no item (empty slot) hides ItemNameLabel
# ---------------------------------------------------------------------------

func test_setup_without_item_hides_item_name_label() -> void:
	var slot: EquipmentSlot = _make_slot()

	slot.setup(ItemData.EquipSlot.CLOTHING, null)

	var name_label: Label = slot.find_child("ItemNameLabel", true, false) as Label
	assert_not_null(name_label, "equipment_slot.tscn must declare 'ItemNameLabel'")
	if name_label == null:
		return
	assert_false(name_label.visible,
			"ItemNameLabel must be hidden when the slot is empty")


# ---------------------------------------------------------------------------
# Test 7 — clicking a FILLED slot emits `selected`
# ---------------------------------------------------------------------------

func test_click_on_filled_slot_emits_selected() -> void:
	var slot: EquipmentSlot = _make_slot()
	var clothing: ItemData = _make_item(&"click_test_clothing", ItemData.EquipSlot.CLOTHING)
	slot.setup(ItemData.EquipSlot.CLOTHING, clothing)

	watch_signals(slot)
	_click(slot)

	assert_signal_emitted(slot, "selected",
			"clicking a FILLED equipment slot must emit 'selected'")


# ---------------------------------------------------------------------------
# Test 8 — clicking an EMPTY slot does NOT emit `selected`
# ---------------------------------------------------------------------------

func test_click_on_empty_slot_does_not_emit_selected() -> void:
	var slot: EquipmentSlot = _make_slot()
	slot.setup(ItemData.EquipSlot.CLOTHING, null)

	watch_signals(slot)
	_click(slot)

	assert_signal_not_emitted(slot, "selected",
			"clicking an EMPTY equipment slot must NOT emit 'selected'")


# ---------------------------------------------------------------------------
# Test 9 — clicking an EMPTY slot leaves it unselected (no highlight)
# ---------------------------------------------------------------------------

func test_click_on_empty_slot_leaves_it_unselected() -> void:
	var slot: EquipmentSlot = _make_slot()
	slot.setup(ItemData.EquipSlot.CLOTHING, null)

	_click(slot)

	var highlight: ColorRect = slot.find_child("SelectionRect", true, false) as ColorRect
	if highlight != null:
		assert_false(highlight.visible,
				"clicking an EMPTY slot must not reveal the selection highlight")

	var name_label: Label = slot.find_child("ItemNameLabel", true, false) as Label
	if name_label != null:
		assert_false(name_label.visible,
				"clicking an EMPTY slot must not reveal ItemNameLabel")


# ---------------------------------------------------------------------------
# Test 10 — setup() with a null item (empty slot) does not crash
# ---------------------------------------------------------------------------
# RELOCATED from tests/integration/notebook/test_inventory_tab.gd (Test 2):
# this only exercises EquipmentSlot in isolation — no PlayerData, no tab
# wiring — so it belongs at the unit level alongside the rest of this file.

func test_setup_with_null_item_does_not_crash() -> void:
	# setup() with a null item (empty slot) must be safe — it is the initial
	# state before the player has equipped anything.
	var slot: EquipmentSlot = _make_slot()

	# If this raises an error GUT records a failure automatically.
	slot.setup(ItemData.EquipSlot.CLOTHING, null)

	assert_true(true, "setup() with null item must not crash")


# ---------------------------------------------------------------------------
# Test 11 — setup() stores the slot type passed to it
# ---------------------------------------------------------------------------
# RELOCATED from tests/integration/notebook/test_inventory_tab.gd (Test 3).

func test_setup_stores_slot_type() -> void:
	# _slot is the internal record that _can_drop_data() compares against
	# incoming drag data. It must match the value passed to setup().
	# Uses GOGGLES (a retained slot, not GLOVES) per issue #30.
	var slot: EquipmentSlot = _make_slot()
	slot.setup(ItemData.EquipSlot.GOGGLES, null)

	assert_eq(slot._slot, ItemData.EquipSlot.GOGGLES,
			"EquipmentSlot._slot must equal the value passed to setup()")


# ---------------------------------------------------------------------------
# Test 12 — _can_drop_data() rejects items whose equip_slot does not match
# ---------------------------------------------------------------------------
# RELOCATED from tests/integration/notebook/test_inventory_tab.gd (Test 4).

func test_can_drop_data_returns_false_for_wrong_slot() -> void:
	# A CLOTHING slot must refuse a GOGGLES item so the player cannot put the
	# wrong item type in the wrong slot. (Was BOOTS/GLOVES before issue #30
	# removed those slots.)
	var goggles: ItemData = ItemData.new()
	goggles.id = &"test_goggles"
	goggles.equip_slot = ItemData.EquipSlot.GOGGLES
	autofree(goggles)

	var stack: ItemStack = ItemStack.new()
	stack.item_id = goggles.id
	stack.item = goggles  # set runtime reference so _can_drop_data can read equip_slot
	autofree(stack)

	var slot: EquipmentSlot = _make_slot()
	slot.setup(ItemData.EquipSlot.CLOTHING, null)

	var data: Dictionary = {"kind": "item", "stack": stack}
	assert_false(slot._can_drop_data(Vector2.ZERO, data),
			"_can_drop_data must return false when item.equip_slot != this slot")


# ---------------------------------------------------------------------------
# Test 13 — _can_drop_data() accepts items whose equip_slot matches
# ---------------------------------------------------------------------------
# RELOCATED from tests/integration/notebook/test_inventory_tab.gd (Test 5).

func test_can_drop_data_returns_true_for_matching_slot() -> void:
	# A CLOTHING slot must accept a CLOTHING item so drag-to-equip works.
	var cloak: ItemData = _make_item(&"drop_test_cloak", ItemData.EquipSlot.CLOTHING)

	var stack: ItemStack = ItemStack.new()
	stack.item_id = cloak.id
	stack.item = cloak
	autofree(stack)

	var slot: EquipmentSlot = _make_slot()
	slot.setup(ItemData.EquipSlot.CLOTHING, null)

	var data: Dictionary = {"kind": "item", "stack": stack}
	assert_true(slot._can_drop_data(Vector2.ZERO, data),
			"_can_drop_data must return true when item.equip_slot == this slot")


# ---------------------------------------------------------------------------
# Test 14 — _slot_name() labels the four retained slots correctly (issue #30)
# ---------------------------------------------------------------------------
# These tests are specifically about the issue #30 slot redesign, unlike the
# tests above (which merely needed a non-removed fixture slot). BACKPACK,
# CLOTHING, and GOGGLES already existed pre-fix, so referencing them directly
# is safe; BELT is the issue #30 rename of NECKLACE, and is resolved by name
# via .get() with a sentinel default rather than a direct
# ItemData.EquipSlot.BELT reference, so a future removal of the member fails
# that one assertion cleanly instead of causing a parse error that would take
# down this whole file.

func test_slot_name_label_for_backpack() -> void:
	var slot: EquipmentSlot = _make_slot()
	slot.setup(ItemData.EquipSlot.BACKPACK, null)

	var heading: Label = slot.find_child("SlotLabel", true, false) as Label
	assert_not_null(heading, "equipment_slot.tscn must declare 'SlotLabel'")
	if heading != null:
		assert_eq(heading.text, "Backpack", "SlotLabel must read 'Backpack' for the BACKPACK slot")


func test_slot_name_label_for_clothing() -> void:
	var slot: EquipmentSlot = _make_slot()
	slot.setup(ItemData.EquipSlot.CLOTHING, null)

	var heading: Label = slot.find_child("SlotLabel", true, false) as Label
	assert_not_null(heading, "equipment_slot.tscn must declare 'SlotLabel'")
	if heading != null:
		assert_eq(heading.text, "Clothing", "SlotLabel must read 'Clothing' for the CLOTHING slot")


func test_slot_name_label_for_goggles() -> void:
	var slot: EquipmentSlot = _make_slot()
	slot.setup(ItemData.EquipSlot.GOGGLES, null)

	var heading: Label = slot.find_child("SlotLabel", true, false) as Label
	assert_not_null(heading, "equipment_slot.tscn must declare 'SlotLabel'")
	if heading != null:
		assert_eq(heading.text, "Goggles", "SlotLabel must read 'Goggles' for the GOGGLES slot")


func test_slot_name_label_for_belt() -> void:
	# BELT is the issue #30 rename of NECKLACE. See the file-level note above
	# for why .get() is used instead of a direct enum member reference.
	var belt_slot: int = ItemData.EquipSlot.get("BELT", -1)

	var slot: EquipmentSlot = _make_slot()
	slot.setup(belt_slot, null)

	var heading: Label = slot.find_child("SlotLabel", true, false) as Label
	assert_not_null(heading, "equipment_slot.tscn must declare 'SlotLabel'")
	if heading != null:
		assert_eq(heading.text, "Belt",
				"SlotLabel must read 'Belt' for the BELT slot (renamed from NECKLACE, issue #30)")
