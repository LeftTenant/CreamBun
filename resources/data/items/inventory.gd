class_name Inventory
extends Resource
## Holds all items currently carried by or belonging to the player.
##
## Inventory is a Resource (not a Node) so it can be saved to disk with
## SaveManager, passed between systems without scene coupling, and duplicated
## for cases where multiple inventories are needed.
##
## Design decisions:
## - stacks: Array[ItemStack] holds stackable and non-stackable items.
## - equipped: Dictionary maps EquipSlot (int) → ItemData for worn items.
##   Equipped items are NOT in stacks; they live only in this dictionary.
## - capacity() returns 0.0 when no backpack is equipped, which signals
##   "unlimited". This avoids a magic number and matches the design doc.

## All item stacks currently in the bag portion of the inventory.
## Equipped items are stored in `equipped` instead.
@export var stacks: Array[ItemStack] = []

## Maps ItemData.EquipSlot (int) → ItemData for each worn item slot.
## Example: { ItemData.EquipSlot.BOOTS: boots_item_data }
## We use a plain Dictionary (not a typed one) because GDScript does not
## support Dictionary[int, ItemData] type hints yet.
## See: https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html#dictionary
@export var equipped: Dictionary = {}


# ---------------------------------------------------------------------------
# Public methods
# ---------------------------------------------------------------------------

## Try to add `count` units of `item` to the inventory.
## Returns the number of items that could NOT be added (leftover).
## Leftover is > 0 only when a backpack is equipped and its weight limit
## is reached before all requested items fit.
## When no backpack is equipped, capacity() returns 0.0 and we treat that
## as unlimited — everything is accepted.
func add(item: ItemData, count: int = 1) -> int:
	var to_add: int = count

	# Enforce backpack weight limit only when a backpack is actually equipped.
	# capacity() == 0.0 means "no backpack → unlimited carry".
	if capacity() > 0.0:
		var used_weight: float = _inline_weight()
		var available_capacity: float = capacity() - used_weight
		if available_capacity <= 0.0:
			# Already full; nothing can be added.
			return count
		# How many of this item fit in the remaining space?
		# Use floor() so we never over-fill by a fractional item.
		var fits: int = int(floor(available_capacity / item.weight)) if item.weight > 0.0 else count
		to_add = mini(to_add, fits)

	if to_add <= 0:
		return count

	# Remember how many we are allowed to add (after capacity check) so we
	# can compute the correct leftover at the end.
	# Leftover = original request − items we were permitted to add.
	# Items we could not fit due to weight stay as leftover for the caller to handle.
	var allowed_to_add: int = to_add

	if item.stackable:
		# Find an existing stack for this item and grow it.
		for stack in stacks:
			if stack.item_id == item.id:
				# Respect per-stack max; carry over if the stack is already full.
				var space_in_stack: int = item.max_stack - stack.count
				var adding: int = mini(to_add, space_in_stack)
				stack.count += adding
				stack.item = item  # keep runtime reference fresh
				to_add -= adding
				if to_add <= 0:
					break
		# If there is still demand, create additional stacks.
		while to_add > 0:
			var new_stack: ItemStack = ItemStack.new()
			new_stack.item_id = item.id
			new_stack.item = item
			var adding: int = mini(to_add, item.max_stack)
			new_stack.count = adding
			stacks.append(new_stack)
			to_add -= adding
	else:
		# Non-stackable: every unit gets its own stack entry (count == 1).
		for i: int in range(to_add):
			var new_stack: ItemStack = ItemStack.new()
			new_stack.item_id = item.id
			new_stack.item = item
			new_stack.count = 1
			stacks.append(new_stack)
		to_add = 0

	# Leftover = items originally requested minus how many we were allowed to add.
	# allowed_to_add already accounts for the capacity limit; to_add at this point
	# should be 0 unless a max_stack limit within the stackable branch left some
	# unplaced (handled by the while loop above, so to_add is always 0 here).
	return count - allowed_to_add


## Remove `count` units of `item` from stacks.
## Returns true if the removal succeeded, false if the item isn't present
## or there aren't enough across all stacks of that item.
## A failed remove() NEVER partially consumes any stack.
func remove(item: ItemData, count: int = 1) -> bool:
	# First pass: total up everything available across all matching stacks.
	# This matters when the same item occupies multiple stacks (e.g. hit max_stack).
	var total_available: int = 0
	for stack in stacks:
		if stack.item_id == item.id:
			total_available += stack.count
	if total_available < count:
		return false

	# Second pass: consume from stacks in order, now that we know enough exists.
	var remaining_to_remove: int = count
	var to_erase: Array[ItemStack] = []
	for stack in stacks:
		if stack.item_id != item.id or remaining_to_remove <= 0:
			continue
		var taking: int = mini(stack.count, remaining_to_remove)
		stack.count -= taking
		remaining_to_remove -= taking
		if stack.count == 0:
			to_erase.append(stack)
	for stack in to_erase:
		stacks.erase(stack)
	return true


## Place `item` into its equipment slot.
## If the slot was already occupied the old item is bumped back into stacks.
## Returns the displaced item (or null if the slot was empty).
## The item does NOT need to be in stacks first — you can equip directly
## (e.g. when loading a save or setting up a starter kit).
## Returns null without equipping if equip_slot is NONE (item is not equippable).
func equip(item: ItemData) -> ItemData:
	# Guard: items with no designated slot cannot be equipped.
	# Storing them at equipped[NONE] would corrupt the equipment panel rendering.
	if item.equip_slot == ItemData.EquipSlot.NONE:
		push_warning("Attempted to equip item '%s' which has equip_slot NONE." % item.id)
		return null

	# Remove one instance from stacks if it happens to be there.
	# It may not be (equipping straight from a starting config is valid).
	_remove_one_from_stacks(item.id)

	# Store whatever was previously in this slot so we can return it.
	var old_item: ItemData = equipped.get(item.equip_slot, null)

	equipped[item.equip_slot] = item

	# The displaced item goes back into the bag.
	if old_item != null:
		add(old_item, 1)

	return old_item


## Remove the item from `slot` and return it to stacks.
## Returns the removed item, or null if the slot was already empty.
func unequip(slot: ItemData.EquipSlot) -> ItemData:
	if not equipped.has(slot):
		return null

	var item: ItemData = equipped[slot]
	equipped.erase(slot)
	add(item, 1)
	return item


## Returns the maximum weight the current backpack can carry.
## Returns 0.0 when no backpack is equipped — callers treat 0.0 as unlimited.
func capacity() -> float:
	if equipped.has(ItemData.EquipSlot.BACKPACK):
		return equipped[ItemData.EquipSlot.BACKPACK].backpack_capacity
	return 0.0


## Returns the total weight of all items currently in stacks.
## `registry` maps StringName (item id) → ItemData and is provided by the
## caller so this method stays free of a global item database dependency.
## Items whose id is not in the registry are silently skipped (weight 0).
##
## Used by notebook UI and save-load validation. For the weight check inside
## add() we use _inline_weight() which relies on the ItemStack.item reference
## instead, because the registry isn't available at that call site.
func current_weight(registry: Dictionary) -> float:
	var total: float = 0.0
	for stack in stacks:
		var data: ItemData = registry.get(stack.item_id, null)
		if data != null:
			total += data.weight * stack.count
	return total


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Weight calculation used inside add() where no external registry is available.
## Relies on ItemStack.item being set whenever a stack is created by add().
## If item is null (e.g. a stack deserialized from save without re-hydrating),
## that stack contributes 0 weight — safe but slightly optimistic. The UI
## should call current_weight(registry) instead for display purposes.
func _inline_weight() -> float:
	var total: float = 0.0
	for stack in stacks:
		if stack.item != null:
			total += stack.item.weight * stack.count
	return total


## Remove exactly one unit of the item with `item_id` from stacks.
## Does nothing if the item isn't in stacks (equipping from a starting
## config is valid and should not error).
func _remove_one_from_stacks(item_id: StringName) -> void:
	for stack in stacks:
		if stack.item_id == item_id:
			stack.count -= 1
			if stack.count <= 0:
				stacks.erase(stack)
			return
