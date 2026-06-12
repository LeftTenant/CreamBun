# Slice 3 — InventoryTab reads from PlayerData — Test Plan

**Design doc:** `docs/features/game-data/design.md` (§7.4, §13)
**Slice breakdown:** `docs/features/game-data/slices.md` (Slice 3)

### E2E
- [ ] Opening the notebook's Inventory tab shows the starter bag (3x Forest Leaf, 1x Old Boots) sourced from PlayerData, with no flash of different/empty sample data
- [ ] Equipping the boots from the bag updates the equipment slot and the bag list while the tab remains open, with the weight header reflecting the new total

### Regression
- [ ] `tests/integration/notebook/test_inventory_tab.gd` — every test relies on `_ready()`'s sample-data block seeding `sample_leaf`/`sample_boots` directly into `_inventory`/`_item_registry`; once that block is deleted, tests 8-12 (populate_left slot count, populate_right weight header, `_do_equip`/`_do_throw`/`_do_recycle` against `sample_boots`/`sample_leaf` rows) need the tab wired to a PlayerData (or injected) inventory that's been seeded the same way before `populate_*` runs
- [ ] `tests/integration/notebook/test_inventory_tab_handlers.gd` — `before_each()` calls `populate_left`/`populate_right` immediately after instantiation and assumes a populated `_inventory`/`_item_registry`; test 1 directly mutates `_tab._inventory`/`_tab._item_registry` (lines 177-178) and tests 3-4 depend on the `sample_leaf`/`sample_boots` rows existing — all need the new data source seeded before `before_each()`'s populate calls
- [ ] `tests/unit/ui/notebook/inventory/test_inventory_tab_scene.gd` — scene-as-data tests instantiate the tab without seeding any inventory; confirm `populate_left`/`populate_right`/null-parent tests still pass against an empty or PlayerData-backed inventory now that the `_ready()` seeding is gone

### Integration
- [ ] InventoryTab no longer constructs its own `Inventory`/sample items in `_ready()` — the bag rendered by `populate_right()` is `PlayerData.inventory` (verified by mutating `PlayerData.inventory` directly and confirming the tab's rendered rows reflect it)
- [ ] A fresh PlayerDataResource seeded via `reset_to_new_game()` (3x `sample_leaf` + 1x `sample_boots`) renders as the starter bag and equipment silhouette when the tab populates both pages
- [ ] `GameEvents.inventory_changed` emitted while the tab is visible triggers `_refresh_both_pages()` (equipment slots + item rows + weight label all reflect the latest `PlayerData.inventory` state)
- [ ] `GameEvents.inventory_changed` emitted while the tab is NOT visible does not rebuild the page (no crash, no orphaned nodes, and the page reflects current data on next show)
- [ ] `_do_equip()` on a `PlayerData.inventory` item updates `PlayerData.inventory.equipped` (not a tab-local copy) and still emits `item_equipped` + `inventory_changed`
- [ ] `_do_throw()` removes the item from `PlayerData.inventory.stacks` (not a tab-local copy) and still emits `item_dropped` + `inventory_changed`
- [ ] `_do_recycle()` on a recyclable item mutates `PlayerData.inventory.stacks` (consumed item removed, yield items added) and still emits `item_recycled` + `inventory_changed`
- [ ] `_on_slot_drop()` equips into `PlayerData.inventory.equipped` and still emits `item_equipped` + `inventory_changed`
- [ ] Two InventoryTab instances (or a tab + a direct `PlayerData.inventory` mutation) observe the same bag contents — proving the tab is no longer self-owned data

### Unit
- [ ] InventoryTab has no `_inventory` field after migration (removed/renamed) and no sample-item construction remains in `_ready()`
- [ ] `current_weight()`/lookup helper resolves item data for stacks present in `PlayerData.inventory` via the temporary local registry, returning a non-zero weight for the seeded starter bag
- [ ] The temporary local registry gracefully handles a stack whose `item_id` is not yet known (skipped, no crash) — covers items added to `PlayerData.inventory` by another system before the registry has an entry for them
- [ ] `_ready()` connects `_on_inventory_changed` (or equivalent) to `GameEvents.inventory_changed` exactly once, even if `_ready()` could run more than once (no duplicate-connection error)
