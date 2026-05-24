# Inventory Tab — Scene Migration Test Plan

Regression-prevention plan for **Slice 2** of the Notebook UI Scene Migration refactor.
The goal is not to test new behaviour but to confirm that moving the inventory layout
from GDScript into `inventory_tab.tscn`, `equipment_slot.tscn`, and `inventory_row.tscn`
does not silently break anything that works today, and that the new named-node contracts
the scripts will depend on are encoded in the scene files.

---

### E2E

- [ ] **[new]** Opening the notebook on the Inventory tab renders both pages with the visible
      layout (equipment silhouette on the left, scrollable item list on the right) identical
      to the pre-migration reference screenshot — verified by observing the
      `GameEvents.notebook_tab_changed` signal rather than inspecting `Notebook._current_tab`.

---

### Integration

The tests below are a mix of **existing tests that must keep passing** (marked **[existing]**) and
**new tests** that guard migration-specific risks.

- [ ] **[existing]** `test_inventory_tab.gd :: test_inventory_tab_populate_left_adds_six_slots` —
      `populate_left()` on a bare parent `Control` still produces exactly 6 `EquipmentSlot`
      descendants after the tab switches from `EquipmentSlot.new()` to
      `preload(...).instantiate()`.

- [ ] **[existing]** `test_inventory_tab.gd :: test_inventory_tab_populate_right_adds_weight_header` —
      `populate_right()` still adds a `Label` whose text starts with `"Weight:"` after the
      right-page build code moves to scene-resolved named-node references.

- [ ] **[existing]** `test_inventory_tab.gd :: test_inventory_tab_do_equip_emits_inventory_changed` —
      selecting a boots row and calling `_do_equip()` still emits `GameEvents.inventory_changed`
      after the migration; the signal-wiring path from scene-instantiated rows to tab handlers
      is intact.

- [ ] **[existing]** `test_inventory_tab.gd :: test_inventory_tab_do_throw_emits_item_dropped` —
      `_do_throw()` on a selected leaf row still emits `GameEvents.item_dropped`; the row
      `selected` signal still reaches `_on_row_selected` after rows are created via
      `InventoryRow` scene instantiation.

- [ ] **[existing]** `test_inventory_tab.gd :: test_inventory_tab_do_recycle_does_nothing_when_not_recyclable` —
      `_do_recycle()` on a non-recyclable item still does NOT emit `GameEvents.item_recycled`
      after the migration.

- [ ] **[new]** Dropping a valid `ItemStack` payload onto an `EquipmentSlot` via `_drop_data()`
      emits `slot_drop_received`; the tab's `_on_slot_drop` handler receives it and emits
      `GameEvents.inventory_changed` — verifies the signal wire that `populate_left` connects
      survives the switch to scene-instantiated slots.

- [ ] **[new]** Clicking an `InventoryRow` (via `selected.emit`) marks it as the active
      selection (`_selected_row` is set) and calls `set_selected(true)` on that row — verifies
      that the `row.selected.connect(_on_row_selected)` wire is established when rows are
      created from the scene rather than with `.new()`.

- [ ] **[new]** The `WeightLabel` text updates after `_do_throw()` removes an item — confirms
      `_update_weight_label()` still resolves the `WeightLabel` named node correctly after the
      right-page build switches to scene-resolved references.

- [ ] **[new]** `_do_recycle()` on a recyclable item emits `GameEvents.item_recycled` and
      `GameEvents.inventory_changed` — a positive-path complement to the existing non-recyclable
      test, verifying the handler survives the migration when the item IS recyclable.

---

### Unit

The tests below are a mix of **existing tests that must keep passing** (marked **[existing]**) and
**new tests**.

#### Existing contract tests (file: `tests/integration/notebook/test_inventory_tab.gd`)

- [ ] **[existing]** `test_inventory_tab_is_a_notebook_tab` — `InventoryTab` still extends
      `NotebookTab` after the script rewrite.

- [ ] **[existing]** `test_equipment_slot_setup_does_not_crash` — `setup()` with a null item
      does not crash after `EquipmentSlot` is converted from `.new()` + `_ready()` child
      construction to `@onready`-style named-node references.

- [ ] **[existing]** `test_equipment_slot_stores_slot_type` — `setup(GLOVES, null)` still sets
      `_slot` to `GLOVES` after the script conversion.

- [ ] **[existing]** `test_equipment_slot_can_drop_returns_false_for_wrong_slot` — `_can_drop_data`
      still rejects a GLOVES item on a BOOTS slot after the script conversion.

- [ ] **[existing]** `test_equipment_slot_can_drop_returns_true_for_matching_slot` — `_can_drop_data`
      still accepts a BOOTS item on a BOOTS slot after the script conversion.

- [ ] **[existing]** `test_inventory_row_setup_sets_name_label` — `setup()` still places the
      item `display_name` into a `Label` descendant of the row after the script switches from
      `Label.new()` + `add_child` to `@onready var _name_label: Label = $HBox/NameLabel`.

- [ ] **[existing]** `test_inventory_row_get_drag_data_returns_correct_structure` — `_get_drag_data()`
      still returns a `Dictionary` with `kind == "item"` and a `"stack"` key after the row
      script is converted.

#### New scene-as-data tests: `inventory_tab.tscn`
(file: `tests/unit/ui/notebook/inventory/test_inventory_tab_scene.gd`)

- [ ] **[new]** `inventory_tab.tscn` can be loaded as a `PackedScene` without errors.

- [ ] **[new]** `inventory_tab.tscn` declares a node named `LeftPage` of type `Control` (or
      `VBoxContainer`) — the left-page subtree root that `populate_left` reparents into the
      book's page.

- [ ] **[new]** `inventory_tab.tscn` declares a node named `RightPage` of type `Control` (or
      `VBoxContainer`) — the right-page subtree root that `populate_right` reparents.

- [ ] **[new]** `inventory_tab.tscn` declares exactly 6 placeholder nodes named `Slot_BACKPACK`,
      `Slot_CLOTHING`, `Slot_BOOTS`, `Slot_GLOVES`, `Slot_GOGGLES`, and `Slot_NECKLACE` somewhere
      in its subtree — the stable named-node contract `populate_left` depends on when building
      the equipment silhouette.

- [ ] **[new]** `inventory_tab.tscn` declares a node named `RowsContainer` of type `VBoxContainer`
      — the container into which `populate_right` appends `InventoryRow` instances.

- [ ] **[new]** `inventory_tab.tscn` declares a node named `ScrollContainer` of type
      `ScrollContainer` wrapping `RowsContainer`.

- [ ] **[new]** `inventory_tab.tscn` declares a node named `EquipButton` of type `Button` — the
      footer Equip action button whose `pressed` signal `populate_right` connects to `_do_equip`.

- [ ] **[new]** `inventory_tab.tscn` declares a node named `ThrowButton` of type `Button` — the
      footer Throw action button.

- [ ] **[new]** `inventory_tab.tscn` declares a node named `RecycleButton` of type `Button` — the
      footer Recycle action button.

- [ ] **[new]** `inventory_tab.tscn` declares a `Label` node named `WeightLabel` somewhere in its
      subtree — the weight display that `_update_weight_label()` patches at runtime.

- [ ] **[new]** `populate_left(null)` returns without error or crash after the migration (the null
      guard in the script is preserved).

- [ ] **[new]** `populate_right(null)` returns without error or crash after the migration.

#### New scene-as-data tests: `equipment_slot.tscn`
(file: `tests/unit/ui/notebook/inventory/test_equipment_slot_scene.gd`)

- [ ] **[new]** `equipment_slot.tscn` can be loaded as a `PackedScene` without errors.

- [ ] **[new]** `equipment_slot.tscn` declares a node named `SlotLabel` of type `Label` — the
      child that shows the slot name when empty; `_update_display()` toggles its visibility.

- [ ] **[new]** `equipment_slot.tscn` declares a node named `IconRect` of type `TextureRect` — the
      child that shows the item icon when a slot is filled; `_update_display()` sets its texture.

#### New scene-as-data tests: `inventory_row.tscn`
(file: `tests/unit/ui/notebook/inventory/test_inventory_row_scene.gd`)

- [ ] **[new]** `inventory_row.tscn` can be loaded as a `PackedScene` without errors.

- [ ] **[new]** `inventory_row.tscn` declares a node named `SelectionRect` of type `ColorRect` — the
      background highlight that `set_selected()` shows and hides.

- [ ] **[new]** `inventory_row.tscn` declares a node named `HBox` of type `HBoxContainer` — the
      horizontal layout container holding the three data labels.

- [ ] **[new]** `inventory_row.tscn` declares a node named `NameLabel` of type `Label` inside `HBox`
      — the item name display that `setup()` writes to.

- [ ] **[new]** `inventory_row.tscn` declares a node named `CountLabel` of type `Label` inside `HBox`
      — the stack count badge that `setup()` shows only when `count > 1`.

- [ ] **[new]** `inventory_row.tscn` declares a node named `WeightLabel` of type `Label` inside `HBox`
      — the per-stack weight display that `setup()` writes to.
