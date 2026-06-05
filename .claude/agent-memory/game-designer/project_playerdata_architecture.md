---
name: PlayerData architecture decision
description: Agreed-upon central game-data architecture — PlayerData Resource owned by SaveManager, settings split out
type: project
---

Designed the central game-data architecture for CreamBun. Doc: `docs/features/game-data/design.md`.

Core decisions:
- **PlayerData is a Resource held by SaveManager.current_data, NOT a 4th autoload.** Honors CLAUDE.md "3 autoloads only". Serializes whole via ResourceSaver in one call; new-game/load-slot = swap one object.
- **GameSettings stays OUT of PlayerData** — it's per-device (one volume pref across all stories), saved to its own `user://settings.tres` via `SaveManager.settings`. PlayerData = this story's progress; GameSettings = this player's prefs; `.tres` definitions = game content.
- **Per-slot save files**: `user://slots/slot_<id>.tres`, not one big file. Sessions tab is already multi-slot by design.
- **Static definitions never stored in PlayerData** — only references by id (item_id, quest_id, recipe id). Keeps the existing id-survives-save-load pattern. `rehydrate()` re-links runtime-only refs (e.g. ItemStack.item) after load.

PlayerData fields by phase:
- Phase 1 (real now): inventory, quest_log, map_state, gold (int), save_version (int).
- Phase 2 (build with their systems): player_stats (COZY only — energy/mood, NO combat stats; name it PlayerStats not CharacterStats), known_recipes (Array[StringName]), forage_state (per-spot cooldowns vs calendar).
- Phase 3: relationships (Dict npc_id→int), dialogue_history (Dict), calendar (CalendarState: day/season/time-of-day, cozy pacing only).

**Why:** Tabs currently each own their own data (InventoryTab makes fresh Inventory in _ready, QuestsTab seeds QuestLog, etc.) — no single source of truth, so foraging/brewing/market have nowhere to read/write, and an open notebook can't reflect a world change.
**How to apply:** When designing foraging/brewing/market/NPC/dialogue/calendar systems, have them read SaveManager.current_data directly and announce writes via GameEvents. Don't propose a new autoload per system. Don't fold settings into saves.
