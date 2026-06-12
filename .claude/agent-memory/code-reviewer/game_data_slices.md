---
name: game-data-slices
description: PlayerData (game-data) feature slice reviews — conventions and findings per slice, for Slices 2-6 reference
metadata:
  type: project
---

## Slice 1 — Foundation (PlayerDataResource + PlayerData autoload) — PASS, clean

Reviewed 2026-06-11. Files: `resources/data/player_data_resource.gd`, `autoloads/player_data.gd`,
`autoloads/game_events.gd` (+gold_changed, +player_data_loaded), `project.godot` (PlayerData
autoload after SaveManager), tests under `tests/unit/resources/data/`, `tests/unit/autoloads/`,
`tests/integration/foundation/test_player_data_foundation.gd`.

No blocking or should-fix issues. Notable confirmed conventions:

**Autoload omits `class_name` despite design doc pseudocode showing `class_name PlayerData`.**
Correct — matches the established "autoloads have no class_name" convention (game_state.gd,
game_events.gd, save_manager.gd all omit it too). Design docs are aspirational; codebase
convention wins. Don't flag this divergence in future slices.

**`_seed_starter_content()` is the single source of truth for starter inventory + quest seed,**
duplicating (not importing) the shapes previously hand-seeded in `inventory_tab.gd` (`sample_leaf`
3x, `sample_boots` 1x via fresh `ItemData.new()` instances) and `quests_tab.gd`
(`the_foraging_book` COMPLETED, `completed_objectives: [0,1,2]`). This is per explicit user
sign-off in slices.md (2026-06-11 note) — Slice 3/4 will delete the tabs' copies. Verified the
field values match exactly (id, display_name, weight, stackable, max_stack, equip_slot).

**`reset_to_new_game()` replaces sub-resources with fresh instances** (not in-place clear) —
explicitly documented rationale (stale-reference safety) and test-covered via identity
inequality (`assert_ne`).

**Test layout:** new dirs `tests/unit/resources/data/` and `tests/unit/autoloads/` are
auto-included by `.gutconfig.json` (`include_subdirs: true`, dirs: `res://tests/`) — no config
change needed for new test subdirectories.

**`gold_changed(new_total: int)` and `player_data_loaded()`** — both signal additions are safe
under the autoload-load-order constraint (int is primitive; player_data_loaded has no params).

## Wave 2 (Slices 2, 3, 4 in parallel) — PASS, clean

Reviewed 2026-06-11. Files: `autoloads/save_manager.gd` (full rewrite to design §6.2),
`ui/notebook/inventory/inventory_tab.gd`, `ui/notebook/quests/quests_tab.gd`, plus their test
files under `tests/integration/notebook/`, `tests/unit/ui/notebook/{inventory,quests}/`, and the
new `tests/unit/autoloads/test_save_manager.gd` + `tests/integration/foundation/test_save_manager_integration.gd`.
No blocking or should-fix issues. Notable confirmed details:

**Autoload init-order is safe for `SaveManager._ready()` → `PlayerData._load_resource()`.**
`SaveManager` is declared before `PlayerData` in project.godot, so `SaveManager._ready()` runs
before `PlayerData._ready()` (which doesn't exist anyway). This is safe because `PlayerData._resource`
is initialized via an inline field default (`var _resource: PlayerDataResource = PlayerDataResource.new()`),
which runs at object construction, not at `_ready()`. The `PlayerData` autoload object already
exists by the time `SaveManager._ready()` calls `PlayerData._load_resource()`. Don't flag autoload
order here as a bug in future slices — it's the documented "never null" guarantee at work.

**`SaveManager._ready()` as the temporary launch hook is well-documented and approved.** The
comment explicitly says this lives in `_ready()` "for now" and will move to a main-menu New
Story/Continue flow later (design §10). Don't flag this as a layering violation — it's a
documented, approved interim decision (slices.md "Approved scope & execution").

**`_slot_path()` / `SLOT_DIR` / `SETTINGS_PATH` match design §6.2 exactly**, including the
`"%sslot_%s.tres" % [SLOT_DIR, slot_id]` format producing `"user://slots/slot_default.tres"`.
Old `SAVE_PATH`/`save_game()`/`load_game()` fully removed — confirmed via
`get_script_constant_map()` + `has_method()` checks in `tests/unit/autoloads/test_save_manager.gd`.

**`ResourceSaver.save()` mutates `resource.resource_path` as a side effect — not yet an issue,
but will matter for Slice 6 multi-save.** `save_slot()` calls `ResourceSaver.save(PlayerData.to_resource(), _slot_path(slot_id))`
on the LIVE shared `_resource` instance (not a copy). `ResourceSaver.save()` stamps
`resource.resource_path = path`, so saving the same live resource to two different slot ids in
sequence would leave `resource_path` pointing at whichever slot was saved last. Phase 1 only ever
saves to one slot in tests/launch, so this is cosmetic now — but flag it if Slice 6 (multi-slot
save/switch) starts exhibiting cache/identity weirdness with `ResourceLoader.load()`.

**InventoryTab/QuestsTab migrations are clean removals — no leftover `_inventory`/`_quest_log`
references anywhere** (grep-verified). `_item_registry` is now explicitly TEMPORARY and rebuilt
every `_build_right_page()` call via `_rebuild_item_registry()`, documented as a stand-in for
the future ItemDatabase (design §13).

**`_on_inventory_changed()` visibility guard is correct and safe even before first populate.**
If `inventory_changed` fires before `populate_right()` ever ran (`_rows_container == null` and
`_equipment_slots` empty), `_refresh_both_pages()` → `_build_right_page()` early-returns and the
equipment-slot loop is a no-op. No crash path.

**Test seeding convention for Wave 2+: `PlayerDataResource.new()` + `reset_to_new_game()` +
`PlayerData._load_resource(data)` in `before_each()`.** Two flavors seen: (1) tabs that need the
starter bag/seeded quest (inventory/quests integration + handler tests) call
`reset_to_new_game()`; (2) tabs that test pure scene structure independent of content
(`test_inventory_tab_scene.gd`'s structure tests) seed a bare `PlayerDataResource.new()` (empty
inventory). Both are documented inline with "PLAYERDATA SEEDING NOTE" / "SLICE 3 DATA SOURCE
NOTE" comment blocks. Expect this same pattern in Slices 5/6.

## Cross-slice setup note

The `run_gut_tests` MCP tool (testing-sandbox) was NOT reachable via ToolSearch in a code-reviewer
sub-agent session even though `claude mcp list` showed the server connected. Static review only
was performed for Slice 1 and Wave 2; if this persists for later slices, note it but don't block
the review on it — static analysis covered all checkable criteria.

## Wave 3 (Slices 5, 6 in parallel) — PASS, clean

Reviewed 2026-06-12. Files: `autoloads/save_manager.gd` (added `_ready()` settings-load +
`new_game()`/`load_slot()`/`save_slot()`/`load_settings()`/`save_settings()`/`_slot_path()`),
`ui/notebook/settings/settings_tab.gd`, `ui/notebook/notebook.gd` (`close()` close-hook),
`ui/notebook/sessions/sessions_tab.gd` + `.tscn`, `ui/notebook/sessions/story_card.gd`, plus
test files: `tests/integration/notebook/test_notebook_shell.gd`,
`test_settings_tab_handlers.gd`, `test_settings_tab_layout.gd`,
`tests/integration/notebook/test_sessions_tab.gd` (new),
`tests/unit/ui/notebook/{settings,sessions}/*`. No blocking or should-fix issues.

**`CACHE_MODE_REPLACE` carry-forward fix is correct.** `PlayerData.to_resource()` returns the
live `_resource` by reference (not a copy); `save_slot()` calls
`ResourceSaver.save(PlayerData.to_resource(), path)`, which stamps `resource_path = path` on
that live instance as a side effect, registering it in Godot's resource cache under `path`. A
plain `ResourceLoader.load(path)` would then return that SAME cached live instance (not a fresh
disk read), so any in-memory mutation made after `save_slot()` would "win" on the next
`load_slot()` — backwards from what "switch story" should do.
`ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)` discards the cache entry and
forces a genuine fresh deserialization. Confirmed both the 3-arg `ResourceLoader.load()` overload
and `CACHE_MODE_REPLACE` enum value are valid Godot 4 API. Test file
`tests/integration/notebook/test_sessions_tab.gd` tests 6 and 7 directly exercise this
save→mutate→switch round trip and assert object-identity (`assert_ne`) on
`PlayerData.to_resource()` before/after. This is the authoritative test for this fix — if it's
ever removed/weakened in a future slice, flag it.

**Shared-by-reference `SaveManager.settings` ↔ `SettingsTab._settings` is correct and
test-proven.** `SettingsTab._ready()` does `_settings = SaveManager.settings` (no
`.duplicate()`). `test_settings_tab.gd` test 7 (`test_settings_tab_settings_is_save_manager_settings_instance`)
asserts `assert_same()` (reference identity) — this is the right test for "by reference, not
copy" and the right exception to the general "always `.duplicate()` `.tres` data" rule, because
`GameSettings` is explicitly per-device/shared-singleton data (design §5), not per-character
stats. Don't flag missing `.duplicate()` here in future slices — it's intentional and
test-locked.

**`notebook.gd close()` is the single shared close-persistence hook (approved option (a)).**
`SaveManager.save_settings()` runs unconditionally on every `close()`, regardless of which tab
was last active — confirmed via `test_notebook_close_persists_settings_regardless_of_active_tab`
in `test_notebook_shell.gd`. Settings persistence is fully decoupled from `PlayerData` — verified
by `test_settings_edit_and_close_does_not_change_player_data` (checks `assert_same` on
`PlayerData.to_resource()` plus gold/inventory/quest-state equality). Future slices that need
close-time persistence should extend this same `close()` method, per the in-code comment.

**Sessions tab "Save" button is a real `.tscn` node (`SaveButton` under `LeftPage`), not
runtime-constructed** — consistent with `ui/CLAUDE.md` "static layout lives in scenes" rule.
Wired in `populate_left()` via `get_node()` + `is_connected()` guard, same pattern as
`ResetLeftButton`/`ResetRightButton` in SettingsTab.

**Test hermetic file-I/O pattern for `user://slots/slot_default.tres` and
`user://settings.tres`:** every integration test that triggers a save/load or `close()` backs up
pre-existing bytes in `before_each()` and restores (or deletes) them in `after_each()`. This
pattern is now used in `test_sessions_tab.gd`, `test_notebook_shell.gd`, and
`test_settings_tab_layout.gd`. Expect this pattern in any future slice that touches real
`user://` paths.

**Minor theoretical gap (not blocking, same class as prior "theoretical, not exercised" notes):**
`StoryCard._on_switch_pressed()` does `GameEvents.story_switch_requested.emit(_slot.slot_id)`
with no null guard on `_slot`. `_slot` is only ever null if `setup()` was never called, which
cannot happen on the production path (`populate_left()` always calls `card.setup(_default_slot)`
immediately after `add_child`) or in the test suite (every test that presses SwitchButton calls
`setup()` first). Don't flag unless a future slice adds a path that presses the button before
`setup()`.

**`SessionsTab._on_story_switch_requested(slot_id)` ignores its `slot_id` parameter and always
emits `story_loaded` with `_default_slot`** (hardcoded). Correct for Phase 1 single-slot scope
(Scope B — `_default_slot.slot_id == slot_id == "default"` always), but will need to look up the
right `StorySlot` by `slot_id` once the multi-slot index (Phase 2, design §6.1) exists. Not a
Wave 3 issue — note for whoever picks up Phase 2 multi-slot work.

**Related:** [[project_patterns]], [[scene_migration_pattern]]
