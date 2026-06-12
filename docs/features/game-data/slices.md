# PlayerData (Central Game Data) — Slice Breakdown

**Design doc:** `docs/features/game-data/design.md`
**Feature folder:** `docs/features/game-data/`
**Decomposition date:** 2026-06-10

This breaks the PlayerData architecture into vertical slices that follow the design doc's
own migration plan (§11, Steps 0–5). Each slice keeps the game runnable and is independently
testable. The slices are strictly ordered: each depends only on those before it.

## Approved scope & execution (user sign-off 2026-06-11)

- **Breakdown approved** as written below (6 slices).
- **Scope A — MapTab migration deferred.** The map data migration (design §11 Step 3) is OUT
  of Phase 1; it lands when the real map system is built. MapTab stays a placeholder.
- **Scope B — single/default slot only.** Phase 1 keeps a single default slot id. Do NOT build
  the `user://slots/index.tres` multi-slot index or multi-slot listing (Phase 2, design §6.1).
  Keep Slice 6 to what is already implemented for Phase 1.
- **Execution: parallel waves with disjoint files.** The dependency graph is
  `1 → {2, 3, 4} → {5, 6}`:
  - **Wave 1:** Slice 1 (foundation) — everything blocks on it.
  - **Wave 2:** Slices 2, 3, 4 in parallel (all depend only on Slice 1; touch disjoint files
    `save_manager.gd` / `inventory_tab.gd` / `quests_tab.gd`).
  - **Wave 3:** Slices 5, 6 in parallel (both depend on Slice 2; touch disjoint files
    `settings_tab.gd` / `sessions_tab.gd`; coordinate the shared `notebook.gd` close hook —
    whichever lands first adds it, the other reuses it).
  - Per wave: parallel test-engineer agents author all the wave's test plans, then ONE
    consolidated checkpoint to evaluate them together before generating tests + implementing.

Phase 1 (the only phase the design doc authorizes building now) covers the foundation plus
the four already-real data pieces: `inventory`, `quest_log`, `map_state`, `gold`. Phase 2/3
fields (`player_stats`, `forage_state`, `calendar`, relationships, etc.) are explicitly OUT
of every slice below — they ship with the systems that read them (design §4, §13).

---

## Slice 1 — Foundation: PlayerDataResource + PlayerData autoload

**Goal:** Stand up the central data container and its access point without touching any tab
yet. Create `PlayerDataResource` (`resources/data/player_data_resource.gd`) with the four
Phase 1 fields (`inventory`, `quest_log`, `map_state`, `gold`) plus `save_version`,
`CURRENT_VERSION`, `reset_to_new_game()`, `_seed_starter_content()` (seeds the foraging-book
quest as COMPLETED **and seeds the default starter inventory — the items currently hardcoded
in `inventory_tab.gd`, e.g. boots & leaves, matched by id and quantity**), and a no-op
`rehydrate()`. NOTE (user review 2026-06-11): the starter inventory now lives here so Slice 3
can delete its sample-data block; the seeding is the single source of truth. Create the `PlayerData` autoload
(`autoloads/player_data.gd`) as a thin Node wrapper exposing forwarded getters for each field
(and a getter/setter for `gold`), plus `_load_resource()` and `to_resource()`. Register
`PlayerData` in `project.godot` autoloads (after `SaveManager`). Add `player_data_loaded` and
`gold_changed` signals to `GameEvents`. After this slice, `PlayerData.inventory` etc. are
reachable from anywhere and never null, but no tab uses them yet.

**Files likely created/modified:**
- create `resources/data/player_data_resource.gd`
- create `autoloads/player_data.gd`
- modify `project.godot` (autoload registration)
- modify `autoloads/game_events.gd` (add `player_data_loaded`, `gold_changed` signals)

**Out of scope:**
- Any change to SaveManager (Slice 2).
- Any change to notebook tabs (Slices 3–6).
- Phase 2/3 fields — do NOT declare them as live fields (commented stubs from §9.2 are fine).
- `ItemDatabase` / real `rehydrate()` body — `rehydrate()` stays a documented no-op.
- Calling `new_game()` on launch (that wiring lands in Slice 2 with SaveManager).

---

## Slice 2 — SaveManager rewrite + launch wiring

**Goal:** Make `SaveManager` a pure I/O layer that drives `PlayerData`, and ensure
`PlayerData._resource` is populated before any tab opens. Rewrite `autoloads/save_manager.gd`
per design §6.2: add `SETTINGS_PATH`/`SLOT_DIR` constants, a `settings: GameSettings` field,
and the methods `new_game()`, `load_slot(slot_id)`, `save_slot(slot_id)`, `load_settings()`,
`save_settings()`, `_slot_path()`. Remove the old `save_game()`/`load_game()`/`SAVE_PATH`
stubs. Wire launch so `SaveManager.load_settings()` and `SaveManager.new_game()` run at startup
(emitting `player_data_loaded`), so `PlayerData` holds seeded data before the notebook opens.
After this slice the game can start a new game, write a slot file to disk, and read it back —
verified directly against `SaveManager`/`PlayerData`, not through any tab.

**Files likely created/modified:**
- modify `autoloads/save_manager.gd` (full rewrite to the §6.2 API)
- modify launch entry point to call `load_settings()` + `new_game()` (likely an autoload
  `_ready` or the main/world scene root — the coder confirms the right hook during the slice)

**Out of scope:**
- `rehydrate()` doing real work — still a no-op until `ItemDatabase` exists (design §13).
- The slot index file (`user://slots/index.tres`) — Phase 2 (design §6.1).
- Autosave triggers — saving stays explicit; no per-change autosave (design §10).
- Any tab change (Slices 3–6) and the Sessions-tab save/load wiring (Slice 6).

---

## Slice 3 — InventoryTab reads from PlayerData

**Goal:** Migrate `InventoryTab` off its self-owned `_inventory` so picking up / equipping /
throwing items mutates the single source of truth and an open tab refreshes live. Delete the
`_ready()` sample-data block and `_inventory` ownership; read the bag via `PlayerData.inventory`.
Keep a temporary local item registry for `current_weight()`/lookups (the real `ItemDatabase`
helper is out of scope — design §13), or seed the registry from the stacks present. Connect
`GameEvents.inventory_changed` to refresh the tab while visible (design §7.4). The existing
`*.emit()` calls in `_do_equip/_do_throw/_do_recycle/_on_slot_drop` stay — they already
announce changes correctly. After this slice, the inventory tab shows `PlayerData.inventory`
and reacts to `inventory_changed`.

**Files likely created/modified:**
- modify `ui/notebook/inventory/inventory_tab.gd`
- modify `tests/integration/notebook/test_inventory_tab*.gd` and
  `tests/unit/ui/notebook/inventory/test_inventory_tab_scene.gd` (point at injected/PlayerData
  inventory instead of self-owned sample data)

**Out of scope:**
- A permanent `ItemDatabase` registry helper (design §13) — temporary local registry is fine.
- QuestsTab / MapTab / SettingsTab / SessionsTab (later slices).
- world.gd `bush.setup(PlayerData.inventory)` orchestration (design §13 — comes with foraging).
- Changing inventory mutation logic in `Inventory` itself (unchanged).

---

## Slice 4 — QuestsTab reads from PlayerData; seeding moves to PlayerDataResource

**Goal:** Migrate `QuestsTab` off its hand-seeded `_quest_log`. Delete `_quest_log` ownership
and the intro-quest seeding block in `_ready()`; read `PlayerData.quest_log`. The foraging-book
seeding now lives in `PlayerDataResource._seed_starter_content()` (added in Slice 1), so a fresh
game already has the completed intro quest — the tab simply renders it. Quest *definitions*
still load from `.tres` as today. After this slice, the quests tab renders progress from
`PlayerData.quest_log` and there is exactly one seeding location.

**Files likely created/modified:**
- modify `ui/notebook/quests/quests_tab.gd`
- modify `tests/integration/notebook/test_quests_tab.gd`,
  `tests/unit/ui/notebook/quests/test_quests_tab.gd`,
  `tests/unit/ui/notebook/quests/test_quests_tab_scene.gd`
- possibly verify `PlayerDataResource._seed_starter_content()` shape matches the tab's reader

**Out of scope:**
- Quest *write* paths (adding/completing quests at runtime) — no gameplay system writes yet.
- MapTab / SettingsTab / SessionsTab.
- Directory-scan loading of all quest `.tres` (still Phase 2 per quests_tab.gd comments).

---

## Slice 5 — SettingsTab uses SaveManager.settings (per-device split)

**Goal:** Prove the per-device settings split. Replace `SettingsTab`'s fresh-`GameSettings`-
per-session with `SaveManager.settings` (loaded in Slice 2). Settings do NOT go through
`PlayerData`. Persist via `SaveManager.save_settings()` on notebook close (design §11 Step 4;
`notebook.gd` already emits `notebook_closed` — the coder wires the save there or in a settings
listener). After this slice, a volume/scale change survives a notebook close+reopen via the
shared settings file rather than resetting to defaults.

**Files likely created/modified:**
- modify `ui/notebook/settings/settings_tab.gd`
- possibly modify `ui/notebook/notebook.gd` (trigger `save_settings()` on close) — confirm hook
- modify `tests/integration/notebook/test_settings_tab_handlers.gd`,
  `tests/unit/ui/notebook/settings/test_settings_tab.gd`

**Out of scope:**
- MapTab and SessionsTab.
- Adding new settings fields — only re-source the existing four/five.
- Settings UI/layout changes — data sourcing only.

---

## Slice 6 — Sessions tab wires real save/load (slot switching)

**Goal:** Replace the hardcoded `_default_slot` placeholder with real save/load. The Sessions
tab "switch story" action calls `SaveManager.load_slot()`; a save action calls
`SaveManager.save_slot()`. Emit/handle the existing `story_loaded` / `story_switch_requested`
signals so the rest of the UI rebinds via `player_data_loaded`. Saving stays explicit (on a
Sessions-tab "Save" action and/or notebook close — design §10). This is the smallest end-to-end
loop that exercises new-game → save → load through the player-facing UI.

**Files likely created/modified:**
- modify `ui/notebook/sessions/sessions_tab.gd`
- possibly modify `ui/notebook/sessions/story_card.gd`
- modify `tests/unit/ui/notebook/sessions/test_sessions_tab.gd`,
  `tests/unit/ui/notebook/sessions/test_sessions_tab_scene.gd`

**Out of scope:**
- The `user://slots/index.tres` slot index and multi-slot listing (design §6.1, Phase 2) —
  if a slot index is needed to list more than one slot, flag it as a scope question rather than
  silently building it. Phase 1 may keep a single/default slot id.
- MapTab migration (Step 3 in design §11) — deferred: the real map UI does not exist yet
  (MapTab is a placeholder). See note below.

---

## Note on MapTab (design §11 Step 3)

The design lists a MapTab migration step, but MapTab is still a placeholder — there is no real
map UI reading/writing `map_state` yet. `map_state` already lives in `PlayerDataResource`
(Slice 1), so the data is ready. The actual `PlayerData.map_state` read/write wiring should
land when the real map system is built, not as a Phase 1 migration of a placeholder. It is
therefore intentionally NOT a slice here. Confirm with the user if they want a thin
placeholder-level migration anyway.
