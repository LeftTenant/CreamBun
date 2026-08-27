# Notebook — E2E Test Plan

End-to-end coverage for the in-game notebook UI (`ui/notebook/`). The notebook
is the primary out-of-world UI in CreamBun and the only pause mechanism: opening
it freezes world time and transitions `GameState` to `NOTEBOOK`.

Behaviour spec: `docs/features/notebook/design.md`. Plugin: `plugins/godot-testing`.

## Scope

Phase 1 of the notebook ships five tabs (`INVENTORY`, `MAP`, `QUESTS`, `SETTINGS`,
`SESSIONS`), three open hotkeys (I / M / Q), Esc toggle, PageUp / PageDown
cycling, and keyboard verbs `E` / `T` / `R` for the inventory tab. The map and sessions
tabs are stubbed to placeholder content in Phase 1, so the scenarios for those
tabs only assert "the page renders" rather than asserting on real content.

In scope:

- Lifecycle (open / close / toggle / Esc / `get_tree().paused` / `GameState`)
- Hotkey opens to specific tabs and switches between tabs without closing
- Tab cycling via `notebook_page_next` / `notebook_page_prev`
- Inventory tab: row selection, `E` equips, `T` discards, `R` ignored for
  non-recyclable items, weight header updates
- Quests tab: clicking "View" populates the right page with title/description
  and the objective checklist
- Settings tab: sliders show defaults, "Reset" buttons restore defaults
- Sessions tab: default Story card visible on the left page

Out of scope (deferred to dedicated future scenarios):

- Drag-and-drop equip via mouse — `_get_drag_data` / `_drop_data` integration
  is hard to drive reliably through the input-injection sandbox; covered by
  the integration test on `equipment_slot.gd` instead.
- Map fog-of-war and fast travel (Phase 2).
- Multi-Story creation, switching, deletion (Phase 2).
- Settings persistence and Audio bus side-effects (`AudioServer` state).

## Scenarios

| # | File | What it verifies |
|---|------|------------------|
| 1 | `lifecycle.md`          | Open with I, world pauses, `GameState.NOTEBOOK`; toggle closes; M opens to map; Esc reopens to last tab; Esc closes |
| 2 | `tab_navigation.md`     | PageUp cycles INVENTORY→MAP→QUESTS→SETTINGS→SESSIONS→INVENTORY; PageDown reverses; hotkey on different tab switches without closing |
| 3 | `inventory_actions.md`  | Sample leaf and scarf present; clicking a row selects it; `E` equips the scarf into the CLOTHING slot; `T` removes one leaf and updates the weight header |
| 4 | `quests_detail.md`      | "The Foraging Book" listed under "Completed"; clicking "View" renders title, description, and three `[x]` objective lines on the right page |
| 5 | `settings_controls.md`  | Three volume sliders + text-speed slider on left; window-scale option on right; "Reset" buttons restore the underlying `GameSettings` values |

Each scenario is independently runnable: each calls `reset_state` (or
`load_scene` of `res://world/world.tscn`) at the top, drives only the inputs
needed for its assertions, and saves its screenshots under
`tests/e2e/notebook/screenshots/<scenario>_step_NN_*.png`.

## Driving notes

- The notebook is instanced in `world.tscn` at path `World/Notebook`. Property
  reads use that path (e.g. `get_node_property("World/Notebook", "visible")`).
- The tab controllers attach themselves under `World/Notebook` as children
  (`_create_tab` calls `add_child(tab_node)`), so the active inventory tab is
  found by querying children of `World/Notebook`.
- `_current_tab` is an `int`; assert against the `NotebookTab` enum integer
  (0=INVENTORY, 1=MAP, 2=QUESTS, 3=SETTINGS, 4=SESSIONS).
- After any `press_action`, wait at least 5 frames before reading state or
  screenshotting — the notebook rebuilds its pages on tab switch and the new
  content does not exist on the same frame as the input.
- **2× coordinate scaling**: the project renders at 640×480 and stretches to a
  1280×960 window. All mouse coordinates passed to the testing-sandbox tools must
  be **2× the viewport-space values** reported by `get_node_property` (e.g. a
  node whose `global_position` is (120, 80) requires mouse coords (240, 160)).
  Forgetting this makes clicks land in empty space with no error.
