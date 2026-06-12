# Slice 6 — Sessions tab wires real save/load (slot switching) — Test Plan

### E2E
- [ ] From a running game, opening the notebook to the Sessions tab, pressing "Save",
      changing live state (e.g. picking up an item so `PlayerData.inventory` differs),
      then pressing "Switch to this Story" reloads the saved state — the inventory/quest
      view reflects the saved values, not the in-between mutation.

### Regression
- [ ] `tests/unit/ui/notebook/sessions/test_sessions_tab.gd` — `_default_slot` existence/
      display-name checks and the `populate_left()` single-card guard (D1) still hold once
      `_default_slot` is sourced from real save data instead of a hardcoded placeholder.
- [ ] `tests/unit/ui/notebook/sessions/test_sessions_tab_scene.gd` — `LeftPage`/`CardsContainer`/
      `RightPage`/`Placeholder` scene contract is unaffected by wiring the switch/save actions.
- [ ] `tests/unit/ui/notebook/sessions/test_story_card_scene.gd` — `SwitchButton`,
      `NameLabel`, `CoverRect`, `LastPlayedLabel` node contract still holds once
      `_on_switch_pressed()` emits a real signal instead of `push_warning()`.
- [ ] `tests/integration/notebook/test_notebook_shell.gd` — open/close/state-machine and
      `notebook_closed` emission tests still pass once a save-on-close hook is added to
      `notebook.gd` (shared touchpoint with Slice 5).
- [ ] `tests/integration/foundation/test_player_data_foundation.gd` — `_load_resource()` /
      `player_data_loaded` emission contract is unaffected by `SessionsTab` now triggering
      `SaveManager.load_slot()` / `new_game()` fallback.

### Integration
- [ ] Pressing the Sessions tab "Save" action calls `SaveManager.save_slot()` with the
      default slot id and writes a `.tres` file at `SaveManager._slot_path("default")`.
- [ ] Pressing "Switch to this Story" on the default story card calls
      `SaveManager.load_slot("default")` and, on success, `PlayerData._resource` reflects
      the loaded data (verified via `GameEvents.player_data_loaded`).
- [ ] `GameEvents.story_switch_requested` is emitted with the default slot id when the
      switch action is pressed, and a connected handler (the Sessions tab or notebook)
      reacts by calling `SaveManager.load_slot()`.
- [ ] `GameEvents.story_loaded` is emitted after a successful `load_slot()` so the rest of
      the UI (e.g. an open Inventory/Quests tab) can rebind alongside `player_data_loaded`.
- [ ] If `SaveManager.load_slot("default")` returns `false` (no save file yet — first run),
      the Sessions tab falls back to `SaveManager.new_game()` rather than leaving
      `PlayerData` untouched or crashing.
- [ ] Save-then-mutate-then-load round trip via the Sessions tab: after
      `save_slot("default")`, mutate `PlayerData` in memory (e.g. `PlayerData.gold += 50`),
      then trigger "Switch to this Story" — `PlayerData.gold` and `PlayerData.inventory`
      reflect the **saved** values, not the in-memory mutation, with no stale
      `resource_path` / `ResourceLoader` cache surprise on the reloaded
      `PlayerDataResource` (carry-forward from Wave 2 review: `save_slot()` mutates the
      live shared resource's `resource_path` as a side effect of `ResourceSaver.save()`).
- [ ] After the round trip above, `PlayerData.to_resource()` is the freshly-loaded
      resource instance (not the pre-save instance whose `resource_path` was mutated by
      `ResourceSaver.save()`).
- [ ] If a shared "notebook close" hook is added to `notebook.gd` for this slice (saving on
      close, per design §10), it coexists with any save-on-close hook Slice 5 adds for
      settings — both behaviors fire from the same `close()` call without one suppressing
      the other. (Coordination note: whichever of Slice 5/6 lands first adds the shared
      hook; the other slice's plan/tests should assume it already exists.)

### Unit
- [ ] `SessionsTab._default_slot.slot_id` is `"default"`, matching the id
      `SaveManager._slot_path()` and `load_slot()`/`save_slot()` expect (Phase 1 single
      default slot — see scope note below).
- [ ] `StoryCard._on_switch_pressed()` emits `GameEvents.story_switch_requested` with the
      card's `_slot.slot_id` instead of calling `push_warning()`.
- [ ] A Sessions-tab "Save" control invokes the save path (direct `SaveManager.save_slot()`
      call or an emitted signal a handler maps to `save_slot()`) with the default slot id.

---

## Summary

This slice closes the new-game -> save -> load loop through the Sessions tab using the
single default slot already implemented in `SaveManager`/`PlayerData`. Coverage focuses on
the integration round trip (save, mutate in memory, reload, confirm saved values win) and
on the existing signal contracts (`story_switch_requested`, `story_loaded`,
`player_data_loaded`) connecting the tab to the rest of the UI. Regression items target the
three existing Sessions-tab/StoryCard test files plus the notebook shell and foundation
suites most likely to be touched by a shared close-hook and new load/save calls.

## Scope question for the user

The plan above stays within the approved single/default-slot scope — no `index.tres`,
slot listing, or multiple `StoryCard`s are planned. However, two related questions are
worth flagging before implementation:

1. **Is "Save" a visible Sessions-tab control, or does saving happen only on notebook
   close?** Design §10 says "Phase 1: on notebook close or a Sessions-tab 'Save' action."
   The plan above covers both, but if only the close-hook path is built, the unit item for
   a Sessions-tab "Save" control should be dropped.
2. **Shared `notebook.gd` close hook with Slice 5** — if both slices land in the same wave
   and both want to hook `close()`, confirm which slice adds the hook first so the other's
   tests aren't written against a hook that doesn't exist yet. (Flagged per the
   coordination note in slices.md, not a multi-slot concern.)

Neither question implies building the `user://slots/index.tres` multi-slot index — both are
resolvable within the single default slot already in place.
