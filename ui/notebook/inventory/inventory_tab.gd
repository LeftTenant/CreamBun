class_name InventoryTab
extends NotebookTab
## The Inventory tab of the in-game notebook.
##
## Left page: equipment silhouette with six drop-target slots (BACKPACK,
## CLOTHING, BOOTS, GLOVES, GOGGLES, NECKLACE).
##
## Right page: scrollable item list showing every stack in the bag, a
## weight header, and three action buttons (Equip E, Throw T, Recycle R).
##
## Interaction model:
##   - Click a row to select it (selection drives the action buttons).
##   - Drag a row onto an equipment slot to equip it.
##   - Press E/T/R (or click the corresponding button) to act on selection.
##
## _inventory and _item_registry are populated in _ready() with sample data
## for Phase 1 so the tab is never visually empty during development.
## In a later phase the notebook controller will inject the real player
## Inventory via a setter before calling populate_left/right.
##
## Design doc: docs/features/notebook/design.md §3.1 (Inventory Tab)


# ---------------------------------------------------------------------------
# Private vars
# ---------------------------------------------------------------------------

# The bag the player is currently carrying. Created fresh in _ready() with
# sample items so the tab is useful on first open without save data.
var _inventory: Inventory = null

# Maps StringName (item id) → ItemData. Built alongside _inventory so
# Inventory.current_weight() can resolve ids to weights without a global
# item database autoload. Pattern mirrors QuestsTab's approach of owning
# its own data for Phase 1.
var _item_registry: Dictionary = {}

# The row the player most recently clicked. Null means nothing is selected.
# Action buttons and keyboard shortcuts operate on _selected_row._stack.
var _selected_row: InventoryRow = null

# The equipment slot the player most recently clicked (Phase 2 selection).
# When set, Equip acts as Unequip. Null when a bag row is selected instead.
var _selected_slot: EquipmentSlot = null

# All six equipment slot nodes, stored so populate_left can iterate them on
# refresh without re-querying the tree.
var _equipment_slots: Array[EquipmentSlot] = []

# Stored ref to the weight header so _update_weight_label() can patch just
# the text without rebuilding the whole right page.
var _weight_label: Label = null

# Stored ref so we can enable/disable the Recycle button based on selection.
var _recycle_button: Button = null

# Stored so we can clear and rebuild the right page on inventory changes
# without passing the parent through multiple method calls.
var _right_page_parent: Control = null

# Stored ref to the freshly-built ItemList VBoxContainer so _rebind_selected_row
# can walk it directly instead of navigating by node-name path each time.
# Assigned at the end of every _build_right_page() call.
var _item_list: VBoxContainer = null


# ---------------------------------------------------------------------------
# Built-in overrides
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Create a fresh inventory owned by this tab. Phase 2 will replace this
	# with the real player inventory injected by the notebook controller.
	_inventory = Inventory.new()

	# --- Sample leaf item ---
	# A stackable ingredient so the player can see a count badge and experience
	# the full weight calculation immediately.
	var leaf: ItemData = ItemData.new()
	leaf.id = &"sample_leaf"
	leaf.display_name = "Forest Leaf"
	leaf.weight = 0.5
	leaf.stackable = true
	leaf.max_stack = 99
	_inventory.add(leaf, 3)
	_item_registry[leaf.id] = leaf

	# --- Sample boots item ---
	# A non-stackable equippable so both equipment-slot drag and the Equip
	# button are testable without needing real .tres item files in Phase 1.
	var boots: ItemData = ItemData.new()
	boots.id = &"sample_boots"
	boots.display_name = "Old Boots"
	boots.weight = 0.8
	boots.equip_slot = ItemData.EquipSlot.BOOTS
	_inventory.add(boots, 1)
	_item_registry[boots.id] = boots


func _unhandled_input(event: InputEvent) -> void:
	# Only handle hotkeys when this tab is visible; otherwise the key would
	# silently consume an event while a different tab is active.
	if not visible:
		return

	# Keyboard shortcuts mirror the button labels so the player can act
	# quickly without moving their mouse to the footer.
	if event.is_action_pressed("notebook_equip"):
		_do_equip()
	elif event.is_action_pressed("notebook_throw"):
		_do_throw()
	elif event.is_action_pressed("notebook_recycle"):
		_do_recycle()


# ---------------------------------------------------------------------------
# Public methods (override NotebookTab)
# ---------------------------------------------------------------------------

## Build the left page: an "Equipment" header followed by one EquipmentSlot
## per equippable slot. Each slot is a drop target for dragging items from
## the right page.
##
## @param parent - Control that will receive the page children. Guard for null
##                 per NotebookTab contract (tests may omit parent).
func populate_left(parent: Control) -> void:
	if parent == null:
		return

	# Clear previously built slots so re-populating is safe.
	_equipment_slots.clear()

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.name = "EquipmentVBox"
	parent.add_child(vbox)
	# PRESET_FULL_RECT makes the VBoxContainer fill its parent Control completely.
	# Without this, a plain Control parent won't resize its children automatically —
	# only Container subclasses do that. See: https://docs.godotengine.org/en/stable/classes/class_control.html#class-control-method-set-anchors-and-offsets-preset
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var header: Label = Label.new()
	header.text = "Equipment"
	header.focus_mode = Control.FOCUS_NONE
	vbox.add_child(header)

	# The six equippable slots, in the order they appear in the silhouette
	# from top to bottom. NONE is not a real slot and is always skipped.
	# We use a plain Array rather than Array[ItemData.EquipSlot] because
	# GDScript 4 does not support typed arrays of inner enum types.
	var slots: Array = [
		ItemData.EquipSlot.BACKPACK,
		ItemData.EquipSlot.CLOTHING,
		ItemData.EquipSlot.BOOTS,
		ItemData.EquipSlot.GLOVES,
		ItemData.EquipSlot.GOGGLES,
		ItemData.EquipSlot.NECKLACE,
	]

	for slot_enum: int in slots:
		var slot_node: EquipmentSlot = EquipmentSlot.new()
		# Name slots by enum key (`Slot_BACKPACK`, `Slot_CLOTHING`, ...) so the
		# mapping is stable if the enum is reordered or values are renumbered.
		slot_node.name = "Slot_%s" % ItemData.EquipSlot.find_key(slot_enum)
		vbox.add_child(slot_node)
		# Pass the currently equipped item (null when empty) so the slot shows
		# either the slot-name label or the item icon straight away.
		# slot_enum is an int at runtime (GDScript enums are int aliases), so
		# the type system accepts it for the EquipSlot parameter.
		slot_node.setup(slot_enum, _inventory.equipped.get(slot_enum, null))
		# When a drop lands on this slot, _on_slot_drop() calls Inventory.equip()
		# and refreshes both pages.
		slot_node.slot_drop_received.connect(_on_slot_drop)
		_equipment_slots.append(slot_node)


## Build the right page: a weight header, a scrollable item list, and a
## footer with action buttons.
##
## @param parent - Control that will receive the page children. Guard for null.
func populate_right(parent: Control) -> void:
	if parent == null:
		return

	# Store so _refresh_right_page() can rebuild on inventory changes.
	_right_page_parent = parent
	_build_right_page()


# ---------------------------------------------------------------------------
# Action methods (called by buttons and keyboard shortcuts)
# ---------------------------------------------------------------------------

## Equip the selected bag item, or unequip if an equipment slot is selected.
## Does nothing when nothing is selected.
func _do_equip() -> void:
	if _selected_row != null and _selected_row._stack != null:
		# Bag row selected → try to equip the item.
		var stack: ItemStack = _selected_row._stack
		var item: ItemData = _item_registry.get(stack.item_id, stack.item)
		if item == null:
			return
		# Only items with a designated slot can be equipped.
		if item.equip_slot == ItemData.EquipSlot.NONE:
			return
		_inventory.equip(item)
		GameEvents.item_equipped.emit(item, item.equip_slot)
		GameEvents.inventory_changed.emit()
		_selected_row = null
		_refresh_both_pages()

	elif _selected_slot != null:
		# Equipment slot selected → unequip whatever is in it.
		var old_item: ItemData = _inventory.unequip(_selected_slot._slot)
		if old_item != null:
			GameEvents.item_unequipped.emit(old_item, _selected_slot._slot)
			GameEvents.inventory_changed.emit()
		_selected_slot = null
		_refresh_both_pages()


## Remove one unit of the selected item from the bag and emit item_dropped.
## Does nothing when nothing is selected.
##
## After the remove we rebuild the right page (via _refresh_both_pages). Because
## the rebuild destroys all row nodes, _selected_row would become a dangling
## reference. We save the item_id before the rebuild and then restore the
## selection by looking up the new row for the same id. This lets the player
## hold T to deplete a stack one unit at a time without re-clicking.
## If the last unit was just removed the item_id won't be found and
## _selected_row is left null — clearing both the pointer and the visual state.
func _do_throw() -> void:
	if _selected_row == null or _selected_row._stack == null:
		return

	var stack: ItemStack = _selected_row._stack
	var item: ItemData = _item_registry.get(stack.item_id, stack.item)
	if item == null:
		return

	# Remember which item was selected before the rebuild destroys all row nodes.
	var prev_item_id: StringName = stack.item_id

	_inventory.remove(item, 1)
	GameEvents.item_dropped.emit(item, 1)
	GameEvents.inventory_changed.emit()

	# Clear the pointer before rebuilding — _refresh_both_pages → _build_right_page
	# calls child.free() on every existing row, so keeping the old reference would
	# leave _selected_row pointing at a freed object.
	_selected_row = null
	_refresh_both_pages()

	# After the rebuild, try to re-select the same item's new row. If the stack
	# was fully depleted the lookup returns null and the selection stays cleared.
	_rebind_selected_row(prev_item_id)


## Recycle one unit of the selected item: remove it and add the yield items.
## Does nothing if the item is not recyclable or nothing is selected.
func _do_recycle() -> void:
	if _selected_row == null or _selected_row._stack == null:
		return

	var stack: ItemStack = _selected_row._stack
	var item: ItemData = _item_registry.get(stack.item_id, stack.item)
	if item == null:
		return
	if not item.is_recyclable:
		return

	# Remove the consumed item first, then add each yield stack.
	_inventory.remove(item, 1)
	for yield_stack: ItemStack in item.recycle_yield:
		# yield_stack.item may be null if the recycle_yield array was built from
		# .tres without runtime hydration — skip those safely.
		if yield_stack.item != null:
			_inventory.add(yield_stack.item, yield_stack.count)

	GameEvents.item_recycled.emit(item, item.recycle_yield)
	GameEvents.inventory_changed.emit()
	_selected_row = null
	_refresh_both_pages()


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

## Called when the player drops an item stack onto an equipment slot.
## Resolves the item from the stack, calls Inventory.equip(), and refreshes.
##
## @param stack - the ItemStack payload from InventoryRow._get_drag_data()
## @param slot  - the EquipSlot int the player dropped onto
func _on_slot_drop(stack: ItemStack, slot: int) -> void:
	# Prefer the runtime reference on the stack; fall back to registry lookup
	# in case the stack was loaded from save without re-hydration.
	var item: ItemData = stack.item
	if item == null:
		item = _item_registry.get(stack.item_id, null)
	if item == null:
		return

	_inventory.equip(item)
	GameEvents.item_equipped.emit(item, item.equip_slot)
	GameEvents.inventory_changed.emit()
	_selected_row = null
	_refresh_both_pages()


# Exactly one of _selected_row or _selected_slot is non-null at any time.
# Clearing _selected_slot here enforces that contract — verb handlers (_do_equip,
# _do_throw, _do_recycle) branch on which one is set.
# We also clear the previous row's visual highlight so only one row ever
# shows the selection indicator at a time.
func _on_row_selected(row: InventoryRow) -> void:
	if _selected_row != null:
		_selected_row.set_selected(false)
	_selected_row = row
	_selected_row.set_selected(true)
	_selected_slot = null


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Build or rebuild the entire right page from scratch.
## Called by populate_right() on first open and by _refresh_both_pages() on
## any inventory change.
func _build_right_page() -> void:
	if _right_page_parent == null:
		return

	# Remove all previously built children before rebuilding.
	for child in _right_page_parent.get_children():
		child.free()

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.name = "RightVBox"
	_right_page_parent.add_child(vbox)
	# PRESET_FULL_RECT makes the VBoxContainer fill its parent Control completely.
	# Without this, a plain Control parent won't resize its children automatically —
	# only Container subclasses do that. See: https://docs.godotengine.org/en/stable/classes/class_control.html#class-control-method-set-anchors-and-offsets-preset
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Weight header — shows current / max so the player always knows their load.
	_weight_label = Label.new()
	_weight_label.name = "WeightLabel"
	_weight_label.focus_mode = Control.FOCUS_NONE
	vbox.add_child(_weight_label)
	_update_weight_label()

	# ScrollContainer so long item lists don't overflow the page.
	# https://docs.godotengine.org/en/stable/classes/class_scrollcontainer.html
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "ItemScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var item_list: VBoxContainer = VBoxContainer.new()
	item_list.name = "ItemList"
	item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(item_list)
	# Store a direct ref so _rebind_selected_row can walk this container without
	# navigating by name (which would break if the tree shape ever changed).
	_item_list = item_list

	# Add one row per stack. Stacks are ordered by insertion — the order the
	# player picked items up. Phase 2 may add sorting controls.
	for stack in _inventory.stacks:
		# Look up the ItemData. Prefer the registry (which always has the full
		# object); fall back to the runtime ref on the stack for items added
		# directly without going through _item_registry.
		var item: ItemData = _item_registry.get(stack.item_id, stack.item)
		if item == null:
			continue  # Skip orphaned stacks gracefully.

		var row: InventoryRow = InventoryRow.new()
		# Node names disallow spaces, `/`, and `:` — Godot silently replaces them
		# with `@`, breaking any test that addresses the node via a literal string.
		# Sanitize the item id so names like "Row_sample_leaf" are stable.
		var safe_id: String = str(stack.item_id).replace(" ", "_").replace("/", "_").replace(":", "_")
		row.name = "Row_%s" % safe_id
		item_list.add_child(row)
		row.setup(stack, item)
		# `_gui_input` on the row emits this signal on left-click; we connect to it
		# instead of the row's `gui_input` signal because the latter is swallowed by
		# the surrounding ScrollContainer.
		row.selected.connect(_on_row_selected)

	# Footer buttons — three actions side by side.
	var footer: HBoxContainer = HBoxContainer.new()
	vbox.add_child(footer)

	var equip_btn: Button = Button.new()
	equip_btn.text = "Equip (E)"
	equip_btn.pressed.connect(_do_equip)
	footer.add_child(equip_btn)

	var throw_btn: Button = Button.new()
	throw_btn.text = "Throw (T)"
	throw_btn.pressed.connect(_do_throw)
	footer.add_child(throw_btn)

	_recycle_button = Button.new()
	_recycle_button.text = "Recycle (R)"
	_recycle_button.pressed.connect(_do_recycle)
	footer.add_child(_recycle_button)


## Refresh both pages after an inventory change so equipment slots and the
## item list stay in sync. Cheaper than a full populate_left/right because
## it reuses the stored parent references.
func _refresh_both_pages() -> void:
	# Rebuild the left page if it was ever built (parent still valid).
	if not _equipment_slots.is_empty():
		# Update each slot's equipped item without rebuilding from scratch.
		for slot_node in _equipment_slots:
			slot_node.setup(slot_node._slot, _inventory.equipped.get(slot_node._slot, null))

	# Rebuild the right page — item list and weight header.
	_build_right_page()


## After a _build_right_page() call, find the newly created row whose stack
## matches item_id and restore it as the visual selection.
##
## This is the "rebuild + rebind" pattern: we always rebuild the whole page on
## inventory change (simple, no partial-update bookkeeping), but we save the
## selected item_id across the rebuild so the selection survives.
##
## @param item_id - the StringName id of the item we want to keep selected.
##                  If no row with this id exists (stack fully depleted) the
##                  method is a no-op and _selected_row stays null.
func _rebind_selected_row(item_id: StringName) -> void:
	# _item_list is assigned at the end of every _build_right_page() call.
	# If it's null here, the page was never built — bail silently.
	if _item_list == null:
		return

	# Walk the rows and match by item_id — not by node name or array position,
	# since names are derived from ids and positions can shift after a depletion.
	for child: Node in _item_list.get_children():
		var row: InventoryRow = child as InventoryRow
		if row == null:
			continue
		if row._stack != null and row._stack.item_id == item_id:
			_selected_row = row
			_selected_row.set_selected(true)
			return


## Update the weight header text to reflect the current inventory state.
## Called after every action that might change total weight.
func _update_weight_label() -> void:
	if _weight_label == null:
		return

	var current: float = _inventory.current_weight(_item_registry)
	var cap: float = _inventory.capacity()

	# When capacity is 0.0 there is no backpack equipped — show "∞" so the
	# player knows they are currently carrying without a weight limit.
	if cap == 0.0:
		_weight_label.text = "Weight: %.1f / ∞" % current
	else:
		_weight_label.text = "Weight: %.1f / %.1f" % [current, cap]
