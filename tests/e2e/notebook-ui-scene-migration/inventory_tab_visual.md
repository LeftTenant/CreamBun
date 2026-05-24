# Scenario: Inventory tab — visual regression baseline

This scenario confirms that moving the inventory tab layout from GDScript into
`inventory_tab.tscn`, `equipment_slot.tscn`, and `inventory_row.tscn` produces
an identical rendered result to the pre-migration state. It is not testing
behaviour (that is covered by the integration tests in
`tests/integration/notebook/test_inventory_tab.gd`) — it is testing *visual
fidelity* between the pre-migration and post-migration renderings.

## Baseline capture strategy

On first run (before B3), this scenario captures the current rendered state of
the Inventory tab as the **reference baseline** at:

  `tests/e2e/notebook-ui-scene-migration/baselines/inventory_tab.png`

On subsequent runs (after B3 lands), the same screenshot step compares against
that baseline. A visible difference indicates the migration changed the rendered
output — which is a regression unless the team has explicitly approved a visual
change.

Why capture-on-first-run rather than committing a fixed reference?

The project uses the Godot Mobile renderer, which can produce sub-pixel
differences across machines and GPU drivers. Capturing the baseline from the
same environment that runs the comparison avoids spurious failures caused by
renderer variation rather than actual layout bugs.

## Signal-based tab observation

This scenario does NOT assert on `Notebook._current_tab` (a private field that
may change name or type during the migration). Instead it observes the
`GameEvents.notebook_tab_changed` signal to confirm the Inventory tab is active.
This is the same cross-system event the rest of the game (HUD, save system) uses
to react to tab switches, so it is the correct public surface to test against.

## Design doc reference

`docs/refactors/notebook-ui-scene-migration/design.md` — "Verification" section.

## Side-effect note

This scenario navigates to the Inventory tab and does not interact with any
items, slots, or buttons. There are no inventory or world-state side effects.

---

## Setup

- Load scene: `res://world/world.tscn`
- Wait: 10 frames (let the world and all autoloads fully initialise)
- Press action: `open_notebook_inventory`
- Wait: 15 frames (layout frames: the notebook animates open, the tab VBox
  anchors settle, EquipmentSlot children fill their rects)
- Assert signal: `GameEvents.notebook_tab_changed` was emitted at least once
  since the action (confirms the notebook opened and fired the tab-change event)

---

## Steps

### Step 1: Capture or compare the full Inventory tab layout

- Screenshot → **capture or compare baseline**:
  - Path: `tests/e2e/notebook-ui-scene-migration/baselines/inventory_tab.png`
  - If the file **does not exist**: save the screenshot as the baseline and
    **pass** — this is the pre-migration reference capture.
  - If the file **exists**: compare the current screenshot against the stored
    baseline. Report a failure if any visible region differs by more than a 2%
    pixel tolerance (to allow for sub-pixel anti-aliasing variation across
    identical GPU/driver setups).

- Assert (structural, not visual — belt-and-suspenders against a blank capture):
  - The left page contains at least 6 `EquipmentSlot` descendants (one per
    equip slot: BACKPACK, CLOTHING, BOOTS, GLOVES, GOGGLES, NECKLACE).
  - The right page contains at least 1 `InventoryRow` descendant (the sample
    data seeded in `_ready()` always produces at least one row).
  - The right page contains a `Label` whose text begins with `"Weight:"`.
  - The right page contains at least 3 `Button` descendants (Equip, Throw,
    Recycle footer buttons).

### Step 2: Confirm tab-switch signal emitted correctly

- Get node property: `GameEvents` — check that `notebook_tab_changed` was
  emitted with the inventory tab identifier.
  (If `get_game_state` exposes the last-emitted signal args, use that;
  otherwise this assertion is satisfied by the Step 1 signal assert in Setup.)

### Step 3: Close the notebook

- Press action: `ui_cancel`     # closes the notebook via Esc → ui_cancel
- Wait: 5 frames
- Assert: `GameState.current_state` == `GameState.State.PLAYING`
  (confirms the notebook closed cleanly and did not leave the game in NOTEBOOK
  state after the migration)
