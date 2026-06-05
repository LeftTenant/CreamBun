---
name: Game data access + signal pattern
description: How systems/UI read and write central game data, and which GameEvents signals carry state changes
type: project
---

Access pattern agreed in the PlayerData design (`docs/features/game-data/design.md` §7-8):
- **Read** game state via direct property access: `SaveManager.current_data.inventory`, `.gold`, etc. Reads have a known caller+target, so no signal indirection.
- **Write** by calling methods on the data Resources, THEN announce via a GameEvents signal so listeners (HUD, open notebook tab) refresh. Matches existing convention: InventoryTab already does `_inventory.equip(...)` then `GameEvents.inventory_changed.emit()`.
- Notebook tabs STOP owning data after migration — they read SaveManager.current_data and connect to change signals to refresh while visible.

GameEvents signals: existing ones cover inventory (inventory_changed, item_equipped/unequipped/dropped/recycled, inventory_full), quests (quest_added/updated/completed), map (destination_visited, fast_travel_requested), sessions (story_created/loaded/switch_requested). New ones the design adds: `gold_changed(new_total)`, `player_data_loaded()` (emitted by SaveManager after new_game/load so all listeners rebind to fresh PlayerData), plus Phase 2/3: recipe_learned, relationship_changed, day_advanced. All signal params stay untyped Variant (autoloads load before class_name indexing — typed params break startup).

Migration order (one tab at a time, game stays runnable): Step0 build PlayerData+SaveManager API → Step1 InventoryTab → Step2 QuestsTab (move intro-quest seeding into PlayerData._seed_starter_content) → Step3 MapTab → Step4 SettingsTab (uses SaveManager.settings, proves per-device split) → Step5 Sessions tab real load/save.

**Why:** signal-bus rule (CLAUDE.md) = GameEvents for cross-system announcements only, direct refs for known caller/target.
**How to apply:** when designing any system that mutates save data, specify the method call + the announce-signal, and reuse an existing signal before inventing one.
