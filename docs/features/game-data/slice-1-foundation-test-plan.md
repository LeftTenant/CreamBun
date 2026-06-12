# Slice 1 — Foundation: PlayerDataResource + PlayerData autoload — Test Plan

### E2E
(none — this slice has no player-visible surface; no tab reads PlayerData yet)

### Regression
Slice 1 adds the `PlayerData` autoload, adds `player_data_loaded` and `gold_changed` signals
to `GameEvents`, and edits the autoload registration order in `project.godot`. The following
existing tests exercise that shared wiring and should be re-run to confirm nothing else broke:
- [ ] `tests/integration/foundation/test_foundation_layer.gd` — asserts `GameEvents.has_signal(...)` for the full existing signal set and checks `GameState.State` enum contents; a botched autoload registration or signal-bus edit would surface here first
- [ ] `tests/integration/notebook/test_notebook_shell.gd` — boots the notebook scene and uses `watch_signals(GameEvents)` / `assert_signal_emitted(...)` for `notebook_opened`, `notebook_closed`, and `notebook_tab_changed`; confirms the `GameEvents` autoload is still reachable and emitting correctly with the new autoload inserted ahead of it in load order
- [ ] `tests/integration/notebook/test_inventory_tab.gd` — instantiates the inventory tab and asserts `GameEvents.inventory_changed`, `item_dropped`, and `item_recycled` emissions; guards against the signal bus or autoload graph breaking scene instantiation
- [ ] `tests/integration/notebook/test_inventory_tab_handlers.gd` — same autoload-graph dependency as above via `watch_signals(GameEvents)` for `inventory_changed` and `item_recycled`
- [ ] `tests/integration/notebook/test_quests_tab.gd` — boots the quests tab scene; confirms scene instantiation still succeeds with the new `PlayerData` autoload present in `project.godot`
- [ ] `tests/integration/notebook/test_settings_tab_handlers.gd` — boots the settings tab and exercises its signal wiring; another scene-instantiation canary for the edited autoload list

### Integration
- [ ] `PlayerData` is reachable as an autoload singleton alongside `GameEvents`, `GameState`, and `SaveManager`, registered after `SaveManager`
- [ ] A freshly constructed `PlayerData._resource` is never null at startup, even before any load/new-game call
- [ ] `PlayerData._load_resource()` swaps in a new `PlayerDataResource` and subsequent forwarded reads (`inventory`, `quest_log`, `map_state`, `gold`) reflect the new resource's data
- [ ] `PlayerData._load_resource()` emits `GameEvents.player_data_loaded`
- [ ] `GameEvents.gold_changed` can be emitted with an `int` payload and received by a listener

### Unit
- [ ] A default-constructed `PlayerDataResource` has non-null `inventory`, `quest_log`, and `map_state`, `gold` is `0`, and `save_version` equals `CURRENT_VERSION` (1)
- [ ] `reset_to_new_game()` replaces `inventory`, `quest_log`, and `map_state` with fresh instances (distinct object identity from any prior ones) and resets `gold` to `0` (seeded contents are covered by the foraging-book and starter-bag items below; `map_state` stays empty)
- [ ] `reset_to_new_game()` sets `save_version` to `CURRENT_VERSION`
- [ ] `reset_to_new_game()` seeds `quest_log.states[&"the_foraging_book"]` as `{"status": QuestLog.Status.COMPLETED, "completed_objectives": [0, 1, 2]}`
- [ ] `reset_to_new_game()` seeds `inventory` with the default starter bag: a stack of 3 `&"sample_leaf"` and a stack of 1 `&"sample_boots"`, each present with the expected `item_id` and `count`
- [ ] `rehydrate()` runs without error on a freshly loaded resource and leaves `inventory`, `quest_log`, and `map_state` unchanged (documented no-op)
- [ ] `PlayerData.inventory`, `.quest_log`, and `.map_state` getters return the same object instances as `PlayerData.to_resource()`'s corresponding fields
- [ ] `PlayerData.gold` getter returns the inner resource's `gold` value
- [ ] Setting `PlayerData.gold` writes through to `PlayerData.to_resource().gold`
- [ ] `PlayerData.to_resource()` returns the exact `PlayerDataResource` instance currently held by the autoload
