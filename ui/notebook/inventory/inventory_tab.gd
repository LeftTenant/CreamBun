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
## The static layout (page subtrees, named nodes) lives in inventory_tab.tscn.
## populate_left() / populate_right() instantiate that scene once, extract
## the LeftPage / RightPage subtrees, and reparent them into the Controls
## provided by notebook.gd. The same pattern is established in SettingsTab.
##
## DATA SOURCE (Slice 3): the bag rendered here IS PlayerData.inventory — the
## single source of truth for the current save. This tab no longer constructs
## or owns its own Inventory. _item_registry remains a TEMPORARY local lookup
## (StringName -> ItemData) until the real ItemDatabase helper exists (design
## §13); it is rebuilt from PlayerData.inventory.stacks each time the right
## page is built so current_weight() can resolve item weights without a
## global item database.
##
## Design doc: docs/features/game-data/design.md §7.4, §13
## Design doc: docs/features/notebook/design.md §3.1 (Inventory Tab)
## Refactor:   docs/refactors/notebook-ui-scene-migration.md


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# The scene that holds the complete static layout for this tab.
# Loaded once at class parse time; Godot caches PackedScene objects so
# multiple instantiate() calls are cheap.
# https://docs.godotengine.org/en/stable/classes/class_packedscene.html
const TAB_SCENE: PackedScene = preload("res://ui/notebook/inventory/inventory_tab.tscn")

# Row scene instantiated once per visible stack in the right page.
# Using scene instantiation (not InventoryRow.new()) so that @onready refs
# inside inventory_row.gd are fully resolved when setup() writes to them.
const INVENTORY_ROW_SCENE: PackedScene = preload("res://ui/notebook/inventory/inventory_row.tscn")

# Maps slot enum value (int) to the node name used in inventory_tab.tscn.
# The script matches scene children by name rather than by position so that
# reordering children in the editor does not break the slot→enum mapping.
const SLOT_NODE_NAMES: Dictionary = {
	ItemData.EquipSlot.BACKPACK: "Slot_BACKPACK",
	ItemData.EquipSlot.CLOTHING: "Slot_CLOTHING",
	ItemData.EquipSlot.BOOTS:    "Slot_BOOTS",
	ItemData.EquipSlot.GLOVES:   "Slot_GLOVES",
	ItemData.EquipSlot.GOGGLES:  "Slot_GOGGLES",
	ItemData.EquipSlot.NECKLACE: "Slot_NECKLACE",
}


# ---------------------------------------------------------------------------
# Private vars
# ---------------------------------------------------------------------------

# TEMPORARY local lookup: maps StringName (item id) → ItemData, rebuilt from
# PlayerData.inventory.stacks each time the right page is built. Stands in for
# the future ItemDatabase helper (design §13) so Inventory.current_weight()
# can resolve ids to weights without a global item database autoload.
var _item_registry: Dictionary = {}

# The row the player most recently clicked. Null means nothing is selected.
# Action buttons and keyboard shortcuts operate on _selected_row._stack.
var _selected_row: InventoryRow = null

# The equipment slot the player most recently clicked (Phase 2 selection).
# When set, Equip acts as Unequip. Null when a bag row is selected instead.
var _selected_slot: EquipmentSlot = null

# All six equipment slot nodes, stored so _refresh_both_pages() can iterate
# them on refresh without re-querying the tree.
var _equipment_slots: Array[EquipmentSlot] = []

# Stored ref to the weight header so _update_weight_label() can patch just
# the text without rebuilding the whole right page.
# Resolved inside populate_right() from the RightPage subtree.
var _weight_label: Label = null

# Stored ref so we can enable/disable the Recycle button based on selection.
# Resolved inside populate_right().
var _recycle_button: Button = null

# Stored so we can clear and rebuild the right page on inventory changes
# without passing the parent through multiple method calls.
var _right_page_parent: Control = null

# Stored ref to the RowsContainer VBoxContainer so _rebind_selected_row()
# can walk it directly after a _build_right_page() call.
var _rows_container: VBoxContainer = null

# Cached LeftPage and RightPage VBoxContainers extracted from a single
# TAB_SCENE instance. Populated on the first populate_left() or
# populate_right() call and reused for the second call, so we only pay
# the instantiation cost once per InventoryTab lifetime.
var _left_page: VBoxContainer = null
var _right_page: VBoxContainer = null


# ---------------------------------------------------------------------------
# Built-in overrides
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Listen for cross-system inventory changes (foraging, market, etc.) so an
	# open tab stays in sync with PlayerData.inventory (design §7.4). Guarded
	# with is_connected() because _ready() can run more than once for a node
	# re-added to the tree — without the guard a second connection would cause
	# _on_inventory_changed (and therefore _refresh_both_pages()) to run twice
	# per emitted signal.
	# https://docs.godotengine.org/en/stable/classes/class_signal.html#class-signal-method-is-connected
	if not GameEvents.inventory_changed.is_connected(_on_inventory_changed):
		GameEvents.inventory_changed.connect(_on_inventory_changed)


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
## The six EquipmentSlot nodes (res://ui/notebook/inventory/equipment_slot.tscn)
## are declared as children of LeftPage in inventory_tab.tscn, named
## Slot_BACKPACK … Slot_NECKLACE. This method extracts that subtree, reparents
## it into parent, then resolves each slot by name, calls setup(), and wires
## the slot_drop_received signal. No additional slots are instantiated at runtime.
##
## @param parent - Control that will receive the page children. Guard for null
##                 per NotebookTab contract (tests may omit parent).
func populate_left(parent: Control) -> void:
	if parent == null:
		return

	_ensure_pages_built()

	# Add the LeftPage VBox into the real page Control provided by notebook.gd.
	# _ensure_pages_built() already detached it from the temporary scene instance.
	# Guard against re-entry: if _left_page already has a parent (because
	# populate_left() was called twice on the same InventoryTab instance, as
	# happens in some tests), detach it first so add_child does not fail.
	# https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-add-child
	if _left_page.get_parent() != null:
		_left_page.get_parent().remove_child(_left_page)
	parent.add_child(_left_page)

	# Anchor the VBox to fill the parent page so children get a real width.
	# Without this, a plain Control parent won't resize its children automatically.
	# Negative right/bottom offsets apply a 10 px inset on all sides (rule 2, ui/CLAUDE.md).
	# https://docs.godotengine.org/en/stable/classes/class_control.html#class-control-method-set-anchors-and-offsets-preset
	_left_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_left_page.offset_left = 10
	_left_page.offset_top = 10
	_left_page.offset_right = -10
	_left_page.offset_bottom = -10

	# Clear previously stored slot refs so a re-populate is safe.
	_equipment_slots.clear()

	# Resolve each slot node by its stable name and call setup() on it.
	# We use a plain Array (not Array[ItemData.EquipSlot]) because GDScript 4
	# does not support typed arrays of inner enum types — see note in the
	# original build loop for the full explanation.
	var slots: Array = [
		ItemData.EquipSlot.BACKPACK,
		ItemData.EquipSlot.CLOTHING,
		ItemData.EquipSlot.BOOTS,
		ItemData.EquipSlot.GLOVES,
		ItemData.EquipSlot.GOGGLES,
		ItemData.EquipSlot.NECKLACE,
	]

	for slot_enum: int in slots:
		var node_name: String = SLOT_NODE_NAMES.get(slot_enum, "")
		if node_name.is_empty():
			continue
		var slot_node: EquipmentSlot = _left_page.get_node(node_name) as EquipmentSlot
		if slot_node == null:
			push_warning("InventoryTab: expected slot node '%s' not found in LeftPage" % node_name)
			continue

		# Pass the currently equipped item (null when empty) so the slot shows
		# either the slot-name label or the item icon straight away.
		slot_node.setup(slot_enum, PlayerData.inventory.equipped.get(slot_enum, null))

		# When a drop lands on this slot, _on_slot_drop() calls Inventory.equip()
		# and refreshes both pages. Guard against duplicate connections: if
		# populate_left() is called more than once on the same InventoryTab instance,
		# the slot nodes are reused and the signal would be connected a second time.
		if not slot_node.slot_drop_received.is_connected(_on_slot_drop):
			slot_node.slot_drop_received.connect(_on_slot_drop)
		_equipment_slots.append(slot_node)


## Build the right page: a weight header, a scrollable item list, and a
## footer with action buttons.
##
## Extracts the RightPage subtree from inventory_tab.tscn, reparents it into
## parent, resolves named-node references (_weight_label, _rows_container,
## footer buttons), wires button signals, then calls _build_right_page() to
## populate the RowsContainer with one InventoryRow per inventory stack.
##
## @param parent - Control that will receive the page children. Guard for null.
func populate_right(parent: Control) -> void:
	if parent == null:
		return

	_ensure_pages_built()

	# Add the RightPage VBox into the notebook's right page Control.
	# Same anchoring + margin scheme as populate_left() for consistent insets.
	# Guard against re-entry: if _right_page already has a parent (because
	# populate_right() was called twice on the same InventoryTab instance), detach
	# it first so add_child does not fail.
	# https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-remove-child
	if _right_page.get_parent() != null:
		_right_page.get_parent().remove_child(_right_page)
	parent.add_child(_right_page)
	_right_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_right_page.offset_left = 10
	_right_page.offset_top = 10
	_right_page.offset_right = -10
	_right_page.offset_bottom = -10

	# Resolve named-node references from the RightPage subtree.
	# Paths are relative to _right_page; using get_node() rather than @onready
	# because the tree shape is established here (inside populate_right) rather
	# than at _ready time.
	_weight_label = _right_page.get_node("WeightLabel") as Label
	_rows_container = _right_page.get_node("ScrollContainer/RowsContainer") as VBoxContainer

	# Wire footer button signals. The buttons are already in the scene;
	# this call makes the script the handler for each pressed event.
	# Guard each connection with is_connected() so calling populate_right() a
	# second time on the same InventoryTab instance does not register duplicates.
	var equip_btn: Button = _right_page.get_node("Footer/EquipButton") as Button
	if not equip_btn.pressed.is_connected(_do_equip):
		equip_btn.pressed.connect(_do_equip)

	var throw_btn: Button = _right_page.get_node("Footer/ThrowButton") as Button
	if not throw_btn.pressed.is_connected(_do_throw):
		throw_btn.pressed.connect(_do_throw)

	_recycle_button = _right_page.get_node("Footer/RecycleButton") as Button
	if not _recycle_button.pressed.is_connected(_do_recycle):
		_recycle_button.pressed.connect(_do_recycle)

	# Store the parent so _refresh_both_pages() can rebuild on inventory changes.
	_right_page_parent = parent

	# Populate the RowsContainer with initial inventory data.
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
		PlayerData.inventory.equip(item)
		GameEvents.item_equipped.emit(item, item.equip_slot)
		GameEvents.inventory_changed.emit()
		_selected_row = null
		_refresh_both_pages()

	elif _selected_slot != null:
		# Equipment slot selected → unequip whatever is in it.
		var old_item: ItemData = PlayerData.inventory.unequip(_selected_slot._slot)
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

	PlayerData.inventory.remove(item, 1)
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
	PlayerData.inventory.remove(item, 1)
	for yield_stack: ItemStack in item.recycle_yield:
		# yield_stack.item may be null if the recycle_yield array was built from
		# .tres without runtime hydration — skip those safely.
		if yield_stack.item != null:
			PlayerData.inventory.add(yield_stack.item, yield_stack.count)

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

	PlayerData.inventory.equip(item)
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


## Called whenever GameEvents.inventory_changed fires, including from systems
## that have nothing to do with this tab (foraging, market, equip/throw on
## another tab instance). Per design §7.4, only rebuild while this tab is the
## one currently shown — refreshing a hidden tab would waste work rebuilding
## node trees nobody can see, and _build_right_page() frees the existing rows,
## which could orphan a row mid-interaction on another tab.
##
## A hidden tab simply shows stale content until it is next populated; since
## populate_right() always rebuilds from PlayerData.inventory, no data is lost.
func _on_inventory_changed() -> void:
	if visible:
		_refresh_both_pages()


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Instantiate TAB_SCENE once per InventoryTab lifetime, extract both page
## VBoxContainers, and discard the scene shell. Called at the start of each
## populate_* method so either method can be called first without ordering
## constraints.
##
## We detach the pages from the scene instance rather than reparenting the
## whole instance, because the notebook only needs the page subtrees and the
## bare InventoryTab root Control from the .tscn has no purpose at runtime.
## This is the same pattern established in SettingsTab._ensure_pages_built().
func _ensure_pages_built() -> void:
	if _left_page != null:
		# Already extracted on a previous call; nothing to do.
		return

	# Instantiate the scene to get a fully-formed node tree with editor
	# properties (labels, size flags, button text) already applied.
	# https://docs.godotengine.org/en/stable/classes/class_packedscene.html#class-packedscene-method-instantiate
	var instance: Control = TAB_SCENE.instantiate() as Control

	# Grab references before detaching. Nodes are still children of instance
	# at this point, so get_node paths are relative to instance.
	_left_page = instance.get_node("LeftPage") as VBoxContainer
	_right_page = instance.get_node("RightPage") as VBoxContainer

	# Detach both pages so they survive when the shell is freed.
	# remove_child does not free the node — it simply unparents it.
	# https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-remove-child
	instance.remove_child(_left_page)
	instance.remove_child(_right_page)

	# Clear the owner on both detached pages. After remove_child the nodes still
	# retain their .owner (the TAB_SCENE root). When add_child'd into a different
	# scene tree Godot emits an owner-inconsistency warning that GUT counts as a
	# test failure. Setting owner to null severs that link.
	# https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-property-owner
	_left_page.owner = null
	_right_page.owner = null

	# The bare InventoryTab Control shell is no longer needed.
	# queue_free() defers deletion to end-of-frame; safe because we removed all
	# nodes we care about before calling it.
	# https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-queue-free
	instance.queue_free()


## TEMPORARY (design §13): rebuild _item_registry from PlayerData.inventory.stacks.
## Stands in for the future ItemDatabase helper — until that exists, the only
## ItemData references this tab can resolve are the runtime refs Inventory.add()
## already attached to each stack (ItemStack.item).
##
## A stack whose item_id is unknown to this tab and whose runtime `item` ref is
## null (e.g. a stack loaded from save before rehydrate() exists, or an id this
## tab has simply never seen) is skipped — current_weight() and the row-building
## loop in _build_right_page() already treat a missing registry entry as "skip
## this stack gracefully", so no special-casing is needed beyond not inserting it.
func _rebuild_item_registry() -> void:
	_item_registry.clear()
	for stack: ItemStack in PlayerData.inventory.stacks:
		if stack.item != null:
			_item_registry[stack.item_id] = stack.item


## Clear the RowsContainer and rebuild it with one InventoryRow per stack.
## Called by populate_right() on first open and by _refresh_both_pages() on
## any inventory change.
##
## This does NOT rebuild the static right-page chrome (WeightLabel, buttons)
## — those are set up once in populate_right() and persist across rebuilds.
func _build_right_page() -> void:
	if _rows_container == null:
		return

	# Rebuild the temporary local registry from the bag's current stacks so
	# weight calculations and lookups stay correct even when another system
	# (foraging, market, ...) added items directly to PlayerData.inventory
	# since the last build. See _rebuild_item_registry() for details.
	_rebuild_item_registry()

	# Remove all previously built row children before rebuilding.
	# free() (not queue_free()) is intentional here: the rows are leaf nodes
	# with no children to defer and we want them gone before we add new ones.
	for child: Node in _rows_container.get_children():
		child.free()

	# Add one row per stack. Stacks are ordered by insertion — the order the
	# player picked items up. Phase 2 may add sorting controls.
	for stack in PlayerData.inventory.stacks:
		# Look up the ItemData. Prefer the registry (which always has the full
		# object); fall back to the runtime ref on the stack for items added
		# directly without going through _item_registry.
		var item: ItemData = _item_registry.get(stack.item_id, stack.item)
		if item == null:
			continue  # Skip orphaned stacks gracefully.

		# Instantiate from the scene so @onready refs inside inventory_row.gd
		# are resolved before setup() writes to them.
		var row: InventoryRow = INVENTORY_ROW_SCENE.instantiate() as InventoryRow

		# Node names disallow spaces, `/`, and `:` — Godot silently replaces them
		# with `@`, breaking any test that addresses the node via a literal string.
		# Sanitize the item id so names like "Row_sample_leaf" are stable.
		var safe_id: String = str(stack.item_id).replace(" ", "_").replace("/", "_").replace(":", "_")
		row.name = "Row_%s" % safe_id
		_rows_container.add_child(row)
		row.setup(stack, item)

		# `_gui_input` on the row emits this signal on left-click; we connect to it
		# instead of the row's `gui_input` signal because the latter is swallowed by
		# the surrounding ScrollContainer.
		row.selected.connect(_on_row_selected)

	_update_weight_label()


## Refresh both pages after an inventory change so equipment slots and the
## item list stay in sync. Cheaper than a full populate_left/right because
## it reuses the stored parent references.
func _refresh_both_pages() -> void:
	# Update each slot's equipped item without rebuilding from scratch.
	for slot_node: EquipmentSlot in _equipment_slots:
		slot_node.setup(slot_node._slot, PlayerData.inventory.equipped.get(slot_node._slot, null))

	# Rebuild the row list — item list and weight header.
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
	# _rows_container is assigned in populate_right() and stays valid for the
	# lifetime of the tab. If it's null the right page was never built — bail.
	if _rows_container == null:
		return

	# Walk the rows and match by item_id — not by node name or array position,
	# since names are derived from ids and positions can shift after a depletion.
	for child: Node in _rows_container.get_children():
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

	var current: float = PlayerData.inventory.current_weight(_item_registry)
	var cap: float = PlayerData.inventory.capacity()

	# When capacity is 0.0 there is no backpack equipped — show "∞" so the
	# player knows they are currently carrying without a weight limit.
	if cap == 0.0:
		_weight_label.text = "Weight: %.1f / ∞" % current
	else:
		_weight_label.text = "Weight: %.1f / %.1f" % [current, cap]
