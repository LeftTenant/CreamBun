class_name ItemData
extends Resource
## Data resource describing a single type of item in the game world.
## Create one .tres file per item type; never share instances between
## characters at runtime — call .duplicate() if you need a mutable copy.
##
## See: https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html#resources

# EquipSlot is defined here (not in a separate file) so that any code working
# with ItemData can access slot constants without an extra import or string look-up.
enum EquipSlot {
	NONE,
	BACKPACK,
	CLOTHING,
	BOOTS,
	GLOVES,
	GOGGLES,
	NECKLACE,
}

## Unique identifier used in save files and registries. Prefer &"snake_case" literals.
@export var id: StringName = &""
## Human-readable name shown in the UI.
@export var display_name: String = ""
## Sprite shown in the notebook inventory grid and tooltip.
@export var icon: Texture2D
## Weight in kilograms. Used by Inventory.add() to enforce backpack capacity.
@export var weight: float = 0.0
## Flavour text shown in the item tooltip.
@export var description: String = ""
## Which equipment slot this item occupies. NONE means it cannot be equipped.
@export var equip_slot: EquipSlot = EquipSlot.NONE
## Whether this item can be broken down into raw materials in the notebook.
@export var is_recyclable: bool = false
## What you get back when recycling one unit of this item.
@export var recycle_yield: Array[ItemStack] = []
## Stackable items share a single slot in the inventory grid.
## Non-stackable items (equipment, unique finds) always occupy their own slot.
@export var stackable: bool = false
## Maximum number of items allowed in a single stack.
@export var max_stack: int = 99
## Only relevant when equip_slot == BACKPACK.
## Defines how many kilograms of other items this backpack can carry.
@export var backpack_capacity: float = 0.0
