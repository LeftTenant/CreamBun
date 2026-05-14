# Scenario: Inventory tab — equip and throw via keyboard

Verifies the inventory tab renders both seed items, that the keyboard verbs
`E` (equip) and `T` (throw) route through `InventoryTab._unhandled_input`,
and that the `Inventory` resource and weight header update afterward.

The inventory tab seeds two sample items in `_ready()`:
- `sample_leaf` — Forest Leaf, weight 0.5, stackable, count 3
- `sample_boots` — Old Boots, weight 0.8, equip_slot BOOTS, count 1

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
  (one for the leaf, one for the boots) — verify visually that "Forest Leaf"
  and "Old Boots" labels are visible.
- Assert: the weight header reads `Weight: 2.3 / ∞`
  (3 × 0.5 + 1 × 0.8 = 2.3)

### Step 2: Click the boots row to select it
- Mouse move to: centre of the second `InventoryRow` in the right page list
- Mouse button press: `LEFT`
- Mouse button release: `LEFT`
- Wait: 5 frames
- Screenshot → save / compare reference: `inventory_actions_step_02_boots_selected.png`
- Assert: visually the boots row has the active/focus styling (or — if the
  Phase 1 row does not yet show a highlight — the screenshot at least matches
  step 1 with no extra noise; the real check is in step 3)

### Step 3: Press E — boots move from list to BOOTS equipment slot
- Press action: `notebook_equip`
- Wait: 10 frames
- Screenshot → save / compare reference: `inventory_actions_step_03_boots_equipped.png`
- Assert: the right page now shows exactly one row ("Forest Leaf x3")
- Assert: the BOOTS slot on the left page shows the boots icon area
  (the slot's `_slot_label` is hidden and `_icon_rect` is visible)
- Assert: the weight header reads `Weight: 1.5 / ∞`
  (3 × 0.5 = 1.5; the boots have been moved into `equipped` and are no
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
- Assert: the weight header reads `Weight: 0.0 / ∞`
