# Scenario: Inventory tab — equip and throw via keyboard

Verifies the inventory tab renders both seed items, that the keyboard verbs
`E` (equip) and `T` (throw) route through `InventoryTab._unhandled_input`,
and that the `Inventory` resource and weight header update afterward.

The starter save seeds two sample items (see
`resources/data/player_data_resource.gd::_seed_starter_content()`):
- `sample_leaf` — Forest Leaf, weight 0.5, stackable, count 3
- `sample_scarf` — Cozy Scarf, weight 0.3, equip_slot CLOTHING, count 1

No backpack is equipped at start, so `capacity()` returns `0.0` and the
weight header is rendered as `Weight: <current> / ∞`.

Design doc reference: §5.2 (Inventory tab) and §7.3 (Within-tab input).

## Setup
- Load scene: `res://world/world.tscn`
- Wait: 10 frames
- Press action: `open_notebook_inventory`
- Wait: 15 frames     # extra time for the tab to populate both pages
- Assert: node property `Notebook._current_tab` == `0` (INVENTORY)

## Steps

### Step 1: Both seed items present, nothing equipped
- Screenshot → save / compare reference: `inventory_actions_step_01_initial.png`
- Assert: the right page shows two `InventoryRow` children
  (one for the leaf, one for the scarf) — verify visually that "Forest Leaf"
  and "Cozy Scarf" labels are visible.
- Assert: the left page shows four equipment slots (Backpack, Clothing,
  Goggles, Belt), all empty — each shows only its slot-name label, no icon.
- Assert: the weight header reads `Weight: 1.8 / ∞`
  (3 × 0.5 + 1 × 0.3 = 1.8)

### Step 2: Click the scarf row to select it
- Mouse move to: centre of the second `InventoryRow` in the right page list
- Mouse button press: `LEFT`
- Mouse button release: `LEFT`
- Wait: 5 frames
- Screenshot → save / compare reference: `inventory_actions_step_02_scarf_selected.png`
- Assert: visually the scarf row shows its warm-cream `SelectionRect` highlight
  (`InventoryRow.set_selected(true)`) — the row's background is tinted while
  the leaf row above it is not

### Step 3: Press E — scarf moves from list to CLOTHING equipment slot
- Press action: `notebook_equip`
- Wait: 10 frames
- Screenshot → save / compare reference: `inventory_actions_step_03_scarf_equipped.png`
- Assert: the right page now shows exactly one row ("Forest Leaf x3")
- Assert: the CLOTHING slot on the left page shows the scarf icon area
  (the slot's `_slot_label` stays visible per issue #7, but `_icon_rect`
  becomes visible and `_item_name_label` reads "Cozy Scarf")
- Assert: the weight header reads `Weight: 1.5 / ∞`
  (3 × 0.5 = 1.5; the scarf has been moved into `equipped` and is no
  longer counted via `stacks`)

### Step 4: Click the leaf row to select it
- Mouse move to: centre of the (now first/only) `InventoryRow` in the right
  page list
- Mouse button press: `LEFT`
- Mouse button release: `LEFT`
- Wait: 5 frames

### Step 5: Press T — one leaf is discarded
- Press action: `notebook_throw`
- Wait: 10 frames
- Screenshot → save / compare reference: `inventory_actions_step_05_threw_leaf.png`
- Assert: the row now shows `Forest Leaf x2` (count badge updated)
- Assert: the weight header reads `Weight: 1.0 / ∞`
  (2 × 0.5 = 1.0)

### Step 6: Press T twice more — leaf stack empties
- Press action: `notebook_throw`
- Wait: 8 frames
- Press action: `notebook_throw`
- Wait: 10 frames
- Screenshot → save / compare reference: `inventory_actions_step_06_leaf_gone.png`
- Assert: the right page item list is empty (no `InventoryRow` children
  remain)
- Assert: the CLOTHING slot still shows the equipped Cozy Scarf (throwing
  bag items does not touch equipped items)
- Assert: the weight header reads `Weight: 0.0 / ∞`
