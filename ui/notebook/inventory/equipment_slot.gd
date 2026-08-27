class_name EquipmentSlot
extends Control
## Represents a single wearable equipment slot in the inventory left page.
##
## The slot-name heading (SlotLabel) is ALWAYS visible, whether the slot is
## empty or filled — per issue #7, equipping an item must not hide it. When
## filled, the equipped item's icon appears in a persistent framed area
## (IconFrame/IconRect) beside the heading, and the item's display name
## appears under the heading (ItemNameLabel) whenever the slot is filled —
## regardless of selection.
##
## A filled slot is selectable: clicking it emits `selected` so the parent
## InventoryTab can treat it as "Unequip" target. An empty slot is NOT
## selectable — there is nothing to unequip.
##
## Accepts drag-and-drop from InventoryRow so the player can equip items by
## dragging them onto the matching slot. The parent InventoryTab handles the
## actual Inventory.equip() call after receiving slot_drop_received.
##
## Static layout (SlotLabel, IconFrame/IconRect, ItemNameLabel, SelectionRect,
## size/anchor properties) lives in equipment_slot.tscn — this script only
## handles data binding, selection state, and drop logic.
##
## Exception: ItemNameLabel's font_color is owned at runtime by
## _update_display() (issue #45) — the .tscn's baked color is only the
## pre-_ready() initial baseline, so editing it in the editor has no visible
## effect once the game runs.
##
## Drag-and-drop overview:
##   https://docs.godotengine.org/en/stable/tutorials/ui/gui_drag_and_drop.html

# Emitted when the player drops a valid item stack onto this slot.
# The parent InventoryTab connects to this and calls Inventory.equip().
# We keep it local rather than on GameEvents because it is a within-scene
# parent/child communication — not cross-system.
signal slot_drop_received(stack: ItemStack, slot: int)

# Emitted when the player left-clicks a FILLED slot. The parent InventoryTab
# connects to this (mirroring InventoryRow.selected) and treats the slot as
# the active selection — relabeling the Equip button to "Unequip (E)".
# Empty slots never emit this signal; see _gui_input().
signal selected(slot: EquipmentSlot)


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Theme palette values from base_theme.tres, mirrored here since no runtime
# Theme-lookup helper exists in this codebase yet; see _update_display() for
# why the selected state swaps between them (issue #45).
const COLOR_INK: Color = Color("#3b2f2a")
const COLOR_INK_MUTED: Color = Color("#7a6a5d")


# ---------------------------------------------------------------------------
# Private vars
# ---------------------------------------------------------------------------

# Which equipment slot this node represents (e.g. CLOTHING, GOGGLES).
# Set by setup() and never changed afterwards.
var _slot: ItemData.EquipSlot = ItemData.EquipSlot.NONE

# The item currently equipped in this slot, or null when empty.
# Updated by setup() so the slot can show the correct state.
var _item: ItemData = null

# Whether this slot is the player's active selection. Mirrors
# InventoryRow's selection flag — true reveals SelectionRect and switches
# ItemNameLabel's font color to the selected-text theme color (issue #45).
# Set via set_selected(); read by _update_display() and _gui_input().
var _selected: bool = false


# ---------------------------------------------------------------------------
# @onready vars
# ---------------------------------------------------------------------------

# Always-visible heading showing the slot name ("Clothing", "Goggles", etc.),
# whether the slot is empty or filled (issue #7).
# Declared in equipment_slot.tscn — this script only sets its text.
@onready var _slot_label: Label = $HBox/TextVBox/SlotLabel

# Shows the item icon when an item is equipped. Hidden when slot is empty.
# We use a TextureRect because it scales the Texture2D to fill the node bounds.
# https://docs.godotengine.org/en/stable/classes/class_texturerect.html
# Declared in equipment_slot.tscn inside IconFrame with
# STRETCH_KEEP_ASPECT_CENTERED — starts hidden (visible = false in the scene).
@onready var _icon_rect: TextureRect = $HBox/IconFrame/IconRect

# Shows the equipped item's display name under the heading whenever this
# slot is filled, regardless of selection. Hidden by default in the scene
# (the scene's default state represents an empty slot); toggled by
# _update_display() based on _item.
@onready var _item_name_label: Label = $HBox/TextVBox/ItemNameLabel

# Selection highlight, mirroring InventoryRow's SelectionRect convention.
# Hidden by default in the scene; toggled by set_selected().
@onready var _selection_rect: ColorRect = $SelectionRect


# ---------------------------------------------------------------------------
# Built-in overrides
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Child nodes (SlotLabel, IconRect) are declared in equipment_slot.tscn.
	# _ready() just initialises the display to match the "empty" state so the
	# slot shows the slot-name label immediately after instantiation.
	_update_display()


## Godot calls this during the engine's built-in control-event dispatch.
## Mirrors InventoryRow._gui_input(): a left-click emits `selected` so the
## parent InventoryTab can update its selection state.
##
## Per issue #7, an EMPTY slot has nothing to unequip, so empty slots do not
## emit `selected` at all — clicking one is a no-op.
## https://docs.godotengine.org/en/stable/classes/class_control.html#class-control-private-method-gui-input
func _gui_input(event: InputEvent) -> void:
	if _item == null:
		return

	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			selected.emit(self)
			accept_event()


# ---------------------------------------------------------------------------
# Public methods
# ---------------------------------------------------------------------------

## Configure this slot for a specific equipment slot type and optionally a
## currently equipped item. Call this after adding the node to the scene tree
## so _ready() has already run and child nodes exist.
##
## An empty slot can never be selected (see _gui_input), so if `item` is null
## we also clear `_selected`. This matters on refresh: when InventoryTab
## unequips the item shown in this slot, _refresh_both_pages() calls setup()
## with item == null without an explicit set_selected(false) — without this
## guard the now-empty slot would still show its SelectionRect highlight.
## ItemNameLabel always follows fill state independently, so it is hidden for
## the empty slot regardless of `_selected`.
##
## @param slot - the EquipSlot enum value this node represents
## @param item - the ItemData currently in this slot (null = empty)
func setup(slot: ItemData.EquipSlot, item: ItemData = null) -> void:
	_slot = slot
	_item = item
	if _item == null:
		_selected = false
	_update_display()


## Set or clear the visual selection indicator on this slot.
##
## Call set_selected(true) when the player clicks this (filled) slot, and
## set_selected(false) when a different slot or bag row is selected, or when
## the equipped item is removed (the slot becomes empty and unselectable).
##
## set_selected(true) reveals SelectionRect; set_selected(false) hides it
## again. ItemNameLabel is NOT affected — its visibility follows the slot's
## fill state (_item), not selection.
##
## @param value - true to show the selection highlight; false to hide it
func set_selected(value: bool) -> void:
	_selected = value
	_update_display()


# ---------------------------------------------------------------------------
# Drag-and-drop overrides
# ---------------------------------------------------------------------------

## Godot calls this every frame while a drag is hovering over this control.
## Return true to show the drop cursor; false to show the "no drop" cursor.
##
## We only accept dictionary data with kind == "item" where the item's
## equip_slot matches this slot. This prevents the player from dropping
## goggles onto the clothing slot.
##
## The runtime `item` reference on the stack must be set (it is set by
## Inventory.add()) so we can read equip_slot without a registry lookup.
##
## https://docs.godotengine.org/en/stable/classes/class_control.html#class-control-method-_can-drop-data
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	# Guard: data must be a Dictionary with the expected shape.
	if not (data is Dictionary):
		return false
	if not data.has("kind") or data["kind"] != "item":
		return false
	if not data.has("stack"):
		return false

	var stack: ItemStack = data["stack"] as ItemStack
	# The runtime item reference must be set — without it we cannot check the slot.
	if stack == null or stack.item == null:
		return false

	# Only accept items whose equip_slot matches this slot exactly.
	return stack.item.equip_slot == _slot


## Called when the player releases a valid drag over this control.
## We emit slot_drop_received so the parent InventoryTab can call
## Inventory.equip() and then refresh both pages.
##
## https://docs.godotengine.org/en/stable/classes/class_control.html#class-control-method-_drop-data
func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var stack: ItemStack = data["stack"] as ItemStack
	slot_drop_received.emit(stack, _slot)


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Refresh the child nodes to reflect the current _item and _selected state.
##
## SlotLabel (the heading) is ALWAYS visible, filled or empty (issue #7).
## IconRect and ItemNameLabel both follow fill state (_item != null) — they
## show the equipped item's icon and display name whenever the slot is
## filled, regardless of selection. _selected drives SelectionRect's
## visibility and ItemNameLabel's font color (issue #45).
##
## @onready guarantees all child refs are non-null by the time _ready() runs,
## and setup() is always called after _ready(), so no null guards are needed.
func _update_display() -> void:
	# The heading always shows the slot name, regardless of fill state.
	_slot_label.text = _slot_name()
	_slot_label.visible = true

	if _item == null:
		# Empty slot — clear the framed icon area and hide the item name.
		_icon_rect.texture = null
		_icon_rect.visible = false
		_item_name_label.text = ""
		_item_name_label.visible = false
	else:
		# Filled slot — show the item icon and name, regardless of selection.
		_icon_rect.texture = _item.icon
		_icon_rect.visible = true
		_item_name_label.text = _item.display_name
		_item_name_label.visible = true

	# ItemNameLabel's font color (issue #45): a filled + selected slot renders
	# full-contrast ink instead of the .tscn-baked ink_muted, because
	# SelectionRect's translucent highlight lightens the effective background
	# enough to drop ink_muted below WCAG AA contrast. Every other state
	# (empty, or filled-but-unselected) actively re-applies ink_muted rather
	# than calling remove_theme_color_override() — base_theme.tres sets no
	# Label/font_color default, so removing the override would fall through
	# to the engine-default white instead of reverting to ink_muted. This
	# lives in _update_display() (not bolted onto setup()/set_selected()
	# individually) so the color never goes stale when only one of _item or
	# _selected changes.
	if _item != null and _selected:
		_item_name_label.add_theme_color_override("font_color", COLOR_INK)
	else:
		_item_name_label.add_theme_color_override("font_color", COLOR_INK_MUTED)

	# SelectionRect's visibility is the other half of the selection state
	# (see the font-color block above).
	_selection_rect.visible = _selected


## Returns a human-readable label for this slot type.
## Shown when the slot is empty so the player knows what to drag here.
func _slot_name() -> String:
	match _slot:
		ItemData.EquipSlot.BACKPACK:  return "Backpack"
		ItemData.EquipSlot.CLOTHING:  return "Clothing"
		ItemData.EquipSlot.GOGGLES:   return "Goggles"
		ItemData.EquipSlot.BELT:      return "Belt"
		_:                            return "—"
