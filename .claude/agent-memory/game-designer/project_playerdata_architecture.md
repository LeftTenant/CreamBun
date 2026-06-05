---
name: PlayerData architecture decision
description: Agreed-upon central game-data architecture — PlayerData 4th autoload (thin Node wrapper over PlayerDataResource); SaveManager is I/O only
type: project
---

Designed the central game-data architecture for CreamBun. Doc: `docs/features/game-data/design.md`.

Core decisions:
- **PlayerData IS a 4th autoload** (`autoloads/player_data.gd`, extends Node) — a thin wrapper over a `PlayerDataResource` (extends Resource). The autoload is the stable global handle; the Resource is the serializable payload. Access is `PlayerData.inventory`, `PlayerData.gold`, etc.
- **SaveManager is purely I/O** — it reads/writes `PlayerDataResource` files to disk and owns `GameSettings`. It does NOT hold live game state. `SaveManager.new_game()` and `load_slot()` call `PlayerData._load_resource(data)` to swap in the resource.
- **GameSettings stays OUT of PlayerData** — it's per-device (one volume pref across all stories), saved to its own `user://settings.tres` via `SaveManager.settings`. PlayerData = this story's progress; GameSettings = this player's prefs; `.tres` definitions = game content.
- **Per-slot save files**: `user://slots/slot_<id>.tres`, not one big file. Sessions tab is already multi-slot by design.
- **Static definitions never stored in PlayerData** — only references by id (item_id, quest_id, recipe id). Keeps the existing id-survives-save-load pattern. `rehydrate()` re-links runtime-only refs (e.g. ItemStack.item) after load.
- **Dependency injection for leaf nodes** — gameplay nodes (bushes, market stalls, NPCs) receive the sub-resource they need (e.g. `Inventory`) via a `setup()` method from the world orchestrator. They do NOT reach for `PlayerData` directly. This keeps them unit-testable without any autoloads.

PlayerData fields by phase:
- Phase 1 (real now): inventory, quest_log, map_state, gold (int), save_version (int).
- Phase 2 (build with their systems): player_stats (COZY only — energy/mood, NO combat stats; name it PlayerStats not CharacterStats), known_recipes (Array[StringName]), forage_state (per-spot cooldowns vs calendar).
- Phase 3: relationships (Dict npc_id→int), dialogue_history (Dict), calendar (CalendarState: day/season/time-of-day, cozy pacing only).

**Why:** Tabs currently each own their own data (InventoryTab makes fresh Inventory in _ready, QuestsTab seeds QuestLog, etc.) — no single source of truth, so foraging/brewing/market have nowhere to read/write, and an open notebook can't reflect a world change.
**How to apply:** When designing foraging/brewing/market/NPC/dialogue/calendar systems, have them read PlayerData.X directly (in orchestrators) or receive the relevant sub-resource via setup() (in leaf nodes). Announce writes via GameEvents. Don't propose a new autoload per system. Don't fold settings into saves.
