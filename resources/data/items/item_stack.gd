class_name ItemStack
extends Resource
## A lightweight record pairing an item type with a quantity.
## Stored inside Inventory.stacks; serialised in save files.
##
## item_id is the canonical key — it survives save/load even if the
## ItemData resource is replaced. The non-exported `item` reference is
## populated by Inventory.add() at runtime so that weight calculations
## inside add() don't need an external registry.

## Matches ItemData.id — the stable key used in save files.
@export var item_id: StringName = &""
## How many of this item are in the stack. 0 means the stack is empty.
@export var count: int = 0

## Runtime-only reference set by Inventory.add(). Not exported because
## ItemData references should be resolved from a registry on load, not
## embedded directly into save data via .tres serialisation.
## Keeping it non-exported means it won't appear in the Godot inspector
## and won't be written to .tres files.
var item: ItemData = null
