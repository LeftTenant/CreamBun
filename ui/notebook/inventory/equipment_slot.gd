class_name EquipmentSlot
extends Control
## Represents a single wearable equipment slot in the inventory left page.
##
## Displays the slot name when empty and the item icon when an item is equipped.
## Accepts drag-and-drop from InventoryRow so the player can equip items by
## dragging them onto the matching slot. The parent InventoryTab handles the
## actual Inventory.equip() call after receiving slot_drop_received.
##
## Static layout (SlotLabel, IconRect, size/anchor properties) lives in
## equipment_slot.tscn — this script only handles data binding and drop logic.
##
## Drag-and-drop overview:
##   https://docs.godotengine.org/en/stable/tutorials/ui/gui_drag_and_drop.html

# Emitted when the player drops a valid item stack onto this slot.
# The parent InventoryTab connects to this and calls Inventory.equip().
# We keep it local rather than on GameEvents because it is a within-scene
# parent/child communication — not cross-system.
signal slot_drop_received(stack: ItemStack, slot: int)


# ---------------------------------------------------------------------------
# Private vars
# ---------------------------------------------------------------------------

# Which equipment slot this node represents (e.g. BOOTS, GLOVES).
# Set by setup() and never changed afterwards.
var _slot: ItemData.EquipSlot = ItemData.EquipSlot.NONE

# The item currently equipped in this slot, or null when empty.
# Updated by setup() so the slot can show the correct state.
var _item: ItemData = null


# ---------------------------------------------------------------------------
# @onready vars
# ---------------------------------------------------------------------------

# Shows the slot name ("Boots", "Gloves", etc.) when the slot is empty.
# Replaced visually by _icon_rect when an item is present.
# Declared in equipment_slot.tscn with PRESET_FULL_RECT anchors and centered
# alignment — this script only toggles visibility and sets text.
@onready var _slot_label: Label = $SlotLabel

# Shows the item icon when an item is equipped. Hidden when slot is empty.
# We use a TextureRect because it scales the Texture2D to fill the node bounds.
# https://docs.godotengine.org/en/stable/classes/class_texturerect.html
# Declared in equipment_slot.tscn with STRETCH_KEEP_ASPECT_CENTERED and
# PRESET_FULL_RECT — starts hidden (visible = false in the scene).
@onready var _icon_rect: TextureRect = $IconRect


# ---------------------------------------------------------------------------
# Built-in overrides
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Child nodes (SlotLabel, IconRect) are declared in equipment_slot.tscn.
	# _ready() just initialises the display to match the "empty" state so the
	# slot shows the slot-name label immediately after instantiation.
	_update_display()


# ---------------------------------------------------------------------------
# Public methods
# ---------------------------------------------------------------------------

## Configure this slot for a specific equipment slot type and optionally a
## currently equipped item. Call this after adding the node to the scene tree
## so _ready() has already run and child nodes exist.
##
## @param slot - the EquipSlot enum value this node represents
## @param item - the ItemData currently in this slot (null = empty)
func setup(slot: ItemData.EquipSlot, item: ItemData = null) -> void:
	_slot = slot
	_item = item
	_update_display()


# ---------------------------------------------------------------------------
# Drag-and-drop overrides
# ---------------------------------------------------------------------------

## Godot calls this every frame while a drag is hovering over this control.
## Return true to show the drop cursor; false to show the "no drop" cursor.
##
## We only accept dictionary data with kind == "item" where the item's
## equip_slot matches this slot. This prevents the player from dropping
## boots onto the gloves slot.
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

## Refresh the child nodes to reflect the current _item state.
## Label is shown when empty; icon_rect is shown when filled.
##
## @onready guarantees _slot_label and _icon_rect are non-null by the time
## _ready() runs, and setup() is always called after _ready(), so the null
## guard that was needed when children were built with .new() is no longer
## required here.
func _update_display() -> void:
	if _item == null:
		# Empty slot — show the slot name so the player knows what goes here.
		_slot_label.text = _slot_name()
		_slot_label.visible = true
		_icon_rect.texture = null
		_icon_rect.visible = false
	else:
		# Filled slot — show the item icon (or blank if none is set).
		_slot_label.visible = false
		_icon_rect.texture = _item.icon
		_icon_rect.visible = true


## Returns a human-readable label for this slot type.
## Shown when the slot is empty so the player knows what to drag here.
func _slot_name() -> String:
	match _slot:
		ItemData.EquipSlot.BACKPACK:  return "Backpack"
		ItemData.EquipSlot.CLOTHING:  return "Clothing"
		ItemData.EquipSlot.BOOTS:     return "Boots"
		ItemData.EquipSlot.GLOVES:    return "Gloves"
		ItemData.EquipSlot.GOGGLES:   return "Goggles"
		ItemData.EquipSlot.NECKLACE:  return "Necklace"
		_:                            return "—"
