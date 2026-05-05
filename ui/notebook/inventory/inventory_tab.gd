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
	parent.add_child(vbox)

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
func _do_throw() -> void:
	if _selected_row == null or _selected_row._stack == null:
		return

	var stack: ItemStack = _selected_row._stack
	var item: ItemData = _item_registry.get(stack.item_id, stack.item)
	if item == null:
		return

	_inventory.remove(item, 1)
	GameEvents.item_dropped.emit(item, 1)
	GameEvents.inventory_changed.emit()
	_selected_row = null
	_refresh_both_pages()


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


## Called when the player left-clicks a row to select it.
## Clears any equipment-slot selection so only one thing is selected at a time.
##
## @param event - the InputEvent forwarded from the row's gui_input signal
## @param row   - the InventoryRow that was clicked
func _on_row_gui_input(event: InputEvent, row: InventoryRow) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_selected_row = row
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
	_right_page_parent.add_child(vbox)

	# Weight header — shows current / max so the player always knows their load.
	_weight_label = Label.new()
	_weight_label.name = "WeightLabel"
	_weight_label.focus_mode = Control.FOCUS_NONE
	vbox.add_child(_weight_label)
	_update_weight_label()

	# ScrollContainer so long item lists don't overflow the page.
	# https://docs.godotengine.org/en/stable/classes/class_scrollcontainer.html
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var item_list: VBoxContainer = VBoxContainer.new()
	item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(item_list)

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
		item_list.add_child(row)
		row.setup(stack, item)
		# Connect gui_input with the row bound into the lambda so each callback
		# knows which row was clicked. GDScript lambdas capture by reference, so
		# we capture an explicit local to avoid the loop-variable aliasing bug.
		# https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html#lambdas
		var captured_row: InventoryRow = row
		row.gui_input.connect(
			func(event: InputEvent) -> void: _on_row_gui_input(event, captured_row))

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
