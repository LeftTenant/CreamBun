# Slice 2 — SaveManager rewrite + launch wiring — Test Plan

### E2E
- [ ] On launch, the world scene loads with `PlayerData` already holding seeded starter
      content (the foraging-book quest completed, the starter bag present) — visible the
      moment the Inventory/Quests tabs are opened, with no extra setup step.

### Regression
- [ ] `tests/integration/foundation/test_player_data_foundation.gd` — still passes
      end-to-end: `PlayerData` autoload reachable, `_resource` never null, `_load_resource()`
      swap + `player_data_loaded`/`gold_changed` signals unaffected by the SaveManager
      rewrite and new launch call.
- [ ] `tests/integration/foundation/test_foundation_layer.gd` — `GameSettings` defaults
      (test 14) and the `GameEvents`/`GameState` contract checks remain green; SaveManager's
      new `settings: GameSettings` field does not change `GameSettings` itself.
- [ ] `tests/unit/autoloads/test_player_data.gd` — forwarded getters/setter and
      `to_resource()` identity contract still hold once `SaveManager.new_game()` (not a bare
      `PlayerDataResource.new()`) is what populates `PlayerData` at launch.
- [ ] `tests/unit/resources/data/test_player_data_resource.gd` — `reset_to_new_game()` /
      `_seed_starter_content()` behavior is unchanged when invoked via
      `SaveManager.new_game()` rather than directly.
- [ ] `tests/integration/notebook/test_notebook_shell.gd` — notebook open/close/state-machine
      tests still pass with `PlayerData._resource` pre-populated by launch wiring instead of
      a bare default-constructed resource (no notebook test currently calls
      `PlayerData._load_resource()`, so a populated `_resource` at suite start must not break
      `before_each()`/`after_each()` assumptions).
- [ ] `tests/unit/ui/notebook/settings/test_settings_tab.gd` — tests that construct their own
      `GameSettings.new()` directly (the master-volume default check and the "GameSettings
      defaults are correct" spot-check) remain unaffected by `SaveManager.settings` now being
      populated via `load_settings()` at launch.

### Integration
- [ ] At launch, `SaveManager.load_settings()` runs and `SaveManager.settings` is a non-null
      `GameSettings` with default values (no `user://settings.tres` present yet).
- [ ] At launch, `SaveManager.new_game()` runs and `PlayerData._resource` reflects a freshly
      seeded `PlayerDataResource` (foraging-book quest COMPLETED, starter bag with
      `sample_leaf` x3 and `sample_boots` x1, gold 0) before any notebook tab is opened.
- [ ] At launch, `GameEvents.player_data_loaded` is emitted exactly once as a result of the
      `new_game()` call (not zero, not duplicated by an additional stray `_load_resource()`
      call elsewhere).
- [ ] `SaveManager.new_game()` calls `PlayerData._load_resource()` with a resource that has
      already had `reset_to_new_game()` applied (seeded content present immediately, not
      applied after the swap).
- [ ] `SaveManager.save_slot(slot_id)` writes a `.tres` file under `user://slots/` whose
      filename matches `_slot_path(slot_id)`, and the directory is created if it does not
      already exist.
- [ ] `SaveManager.save_slot(slot_id)` followed by `SaveManager.load_slot(slot_id)` round-trips
      `PlayerData`'s state — gold, inventory stack contents, and quest log states saved before
      `save_slot()` are all present on `PlayerData` after `load_slot()`.
- [ ] `SaveManager.load_slot(slot_id)` returns `false` and leaves `PlayerData._resource`
      unchanged when no file exists at `_slot_path(slot_id)`.
- [ ] `SaveManager.load_slot(slot_id)` on a successfully-loaded file calls
      `PlayerData._load_resource()` (verified via `GameEvents.player_data_loaded` emission),
      so listeners rebind to the loaded data.
- [ ] `SaveManager.save_settings()` followed by `SaveManager.load_settings()` (a fresh
      `SaveManager.settings` instance) round-trips a changed `GameSettings` field (e.g.
      `master_volume`) from `user://settings.tres`.
- [ ] `SaveManager.load_settings()` assigns a default-valued `GameSettings` to `settings` when
      `user://settings.tres` does not exist (first run), rather than leaving `settings` null.

### Unit
- [ ] `SaveManager._slot_path(slot_id)` returns `"user://slots/slot_<slot_id>.tres"` for a
      given slot id, matching `SLOT_DIR` and the `slot_<id>.tres` naming convention.
- [ ] `SaveManager.SETTINGS_PATH` equals `"user://settings.tres"` and `SaveManager.SLOT_DIR`
      equals `"user://slots/"` (the constants design §6.2 specifies).
- [ ] The old `SAVE_PATH` constant and `save_game()`/`load_game()` stub methods no longer
      exist on `SaveManager`.
- [ ] `SaveManager.settings` is `null` before `load_settings()` has ever been called (i.e. the
      field itself does not eagerly construct a `GameSettings` — `load_settings()` is the only
      thing that populates it).
