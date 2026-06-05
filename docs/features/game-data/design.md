# PlayerData — Central Game Data Architecture

**Status:** Design (not yet implemented)
**Author:** Game design pass, 2026-06-05
**Related:** `docs/features/notebook/design.md`, `autoloads/save_manager.gd`, `autoloads/game_events.gd`

---

## 1. Overview

Right now every notebook tab owns its own runtime data. `InventoryTab` builds a fresh
`Inventory` in `_ready()`, `QuestsTab` hand-seeds a `QuestLog`, `SettingsTab` makes a fresh
`GameSettings`, and `MapTab` will eventually make a `MapState`. There is no single source of
truth, so a foraging system has nowhere to deposit berries, a brewing system has no recipe
list to read, and `SaveManager` has no defined object to serialize.

This document designs **`PlayerData`** — one Resource that holds all *mutable, per-save* game
state. It becomes the single thing `SaveManager` writes to disk and the single thing every
gameplay system and notebook tab reads from and writes to.

The guiding principle for this beginner project: **one obvious place for save data, reached one
obvious way.** Clarity beats cleverness.

---

## 2. Recommendation (read this first)

Two decisions drive everything else, so they lead the document:

1. **`PlayerData` is a Resource, held by `SaveManager` (a `current_data` property). It is NOT a
   fourth autoload.** Gameplay code reaches it through `SaveManager.current_data`.
2. **`GameSettings` stays out of `PlayerData`.** Settings are per-device (a player's preferred
   volume), not per-save (this story's berries). They live in a separate file and a separate
   `SaveManager.settings` property.

The rest of this doc justifies these choices, defines the schema, shows the access pattern, and
lays out a phased migration so nothing breaks while we wire it up.

---

## 3. Architecture choice: Resource-in-SaveManager, not a 4th autoload

CLAUDE.md says "Autoloads (3 only)." Two readings are possible — a snapshot of today, or a
constraint. We treat it as a **constraint, and a good one.** A new autoload per system is exactly
how a beginner project turns into a tangle of globals. We already have the right home: a save
file is, by definition, owned by the thing that saves files.

### The chosen shape

`SaveManager` (an existing autoload) gains two properties:

```gdscript
# autoloads/save_manager.gd
var current_data: PlayerData = null   # the live, per-save game state
var settings: GameSettings = null     # per-device, separate file (see §6)
```

Gameplay systems and UI reach the data through the autoload:

```gdscript
SaveManager.current_data.inventory.add(berry, 2)
var gold: int = SaveManager.current_data.gold
```

### Why this over a `PlayerData` autoload

| Concern | Resource in SaveManager (chosen) | `PlayerData` autoload |
| --- | --- | --- |
| Save/load | Trivial — `ResourceSaver.save(current_data, path)` writes the whole tree in one call. | The autoload is a `Node`; you must hand-copy every field into a Resource to save, then hand-copy back on load. Tedious and bug-prone. |
| "New game" / "load game" | Replace one object: `current_data = PlayerData.new()`. | You must reset every field on the persistent Node by hand. Easy to forget one. |
| Multiple save slots | Each slot is a different `.tres` file deserialized into `current_data`. Natural. | Awkward — the autoload is a singleton; slot switching means clearing and refilling it. |
| Autoload count | Stays at 3. Honors CLAUDE.md. | Becomes 4. |
| Mental model | "The save file, in memory." One concept. | "A global bag of state that *also* needs a parallel Resource to be saved." Two concepts. |

The only thing the autoload buys you is a slightly shorter access path (`PlayerData.gold` vs
`SaveManager.current_data.gold`), and that is not worth a parallel-serialization chore on a
beginner project.

> **Why a Resource at all (not a plain script object)?** Resources serialize to `.tres` for free
> via `ResourceSaver`/`ResourceLoader`, show up in the Godot inspector for debugging, and match
> the pattern already used by every data class in `resources/data/`. The existing `Inventory`,
> `QuestLog`, and `MapState` are already Resources — `PlayerData` simply holds them.

---

## 4. What goes IN PlayerData

`PlayerData` is the container for everything that is **mutable** and **belongs to one save/story
slot**. Each field is a Resource (or a primitive), so the whole graph serializes in one call.

| Field | Type | Phase | Why it lives here |
| --- | --- | --- | --- |
| `inventory` | `Inventory` | 1 | Already exists; currently orphaned in `InventoryTab`. The clearest case. |
| `quest_log` | `QuestLog` | 1 | Already exists; currently hand-seeded in `QuestsTab`. |
| `map_state` | `MapState` | 1 | Already exists; `MapTab` will need it. Tracks visited destinations + fog. |
| `gold` | `int` | 1 | Currency from the market. A single primitive — no Resource needed. Foraging/brewing/market all touch it. |
| `player_stats` | `PlayerStats` (new) | 2 | Cozy stats only — e.g. energy/stamina for a gentle day loop. **No combat stats.** See §4.1. |
| `known_recipes` | `Array[StringName]` | 2 | Brewing recipe ids the player has learned. The recipe *definitions* are static `.tres` (out of scope, see §5); this is just "which ones do I know." |
| `forage_state` | `ForageState` (new) | 2 | Per-location forage cooldowns / regrowth timers so a picked bush stays empty for a while. See §4.2. |
| `relationships` | `Dictionary` (StringName → int) | 3 | NPC affinity scores keyed by npc id. Plain Dictionary round-trips cleanly. |
| `dialogue_history` | `Dictionary` (StringName → Variant) | 3 | What's been said / one-time lines already shown, keyed by npc or dialogue id. |
| `calendar` | `CalendarState` (new) | 3 | In-game day/season/time-of-day. Drives forage regrowth and seasonal events. See §4.3. |
| `save_version` | `int` | 1 | Schema version stamp so future loads can migrate old files. Defaults to 1. |

**Phase 1 ships only the four already-real pieces** (`inventory`, `quest_log`, `map_state`,
`gold`) plus `save_version`. Everything else is declared as a clearly-commented stub or simply
added when its system arrives. We do **not** build empty systems ahead of need.

### 4.1 PlayerStats (Phase 2, new) — cozy only

A small Resource for gentle life-sim stats. CreamBun has no combat, so there is no health, attack,
or defense. Reasonable starters: `energy` (spent foraging/brewing, refilled by sleep) and maybe a
soft `mood`. Keep it tiny; add fields when a system actually reads them.

> **Naming note:** call it `PlayerStats`, not `CharacterStats`. The project already reserves
> combat-flavored `CharacterStats`/`AbilityData` as future stubs; a cozy stats Resource should
> read as cozy.

### 4.2 ForageState (Phase 2, new)

Tracks which forageable spots are currently depleted and when they regrow. Simplest form: a
`Dictionary` mapping a spot id (`StringName`) to a "ready again on day N" value, checked against
`calendar`. No regrowth system in Phase 1, so this stays a stub until foraging lands.

### 4.3 CalendarState (Phase 3, new)

Holds `day` (int), `season` (enum), and `time_of_day` (enum or float). Cozy pacing only — time
advances on player actions or sleep, never on a punishing real-time clock. Out of scope until the
day/night system is designed.

---

## 5. What stays OUT of PlayerData

| Excluded | Where it lives instead | Why |
| --- | --- | --- |
| **`GameSettings`** (volumes, window scale, text speed) | `SaveManager.settings`, its own `user://settings.tres` file. | **Per-device, not per-save.** A player who made three stories still wants one volume preference. Folding settings into each save means changing volume in story A doesn't affect story B, and a fresh save resets the player's accessibility choices. That is wrong. Settings are a property of the *player's machine*, not of *Cream Bun's adventure*. |
| **Static definitions** — `ItemData`, `QuestData`, `MapDestination`, `NpcData`, future `DrinkRecipe`, `AbilityData` | `resources/data/**/*.tres`, loaded read-only at runtime. | These are *content*, authored once and shared by every save. `PlayerData` stores **references by id** (e.g. `ItemStack.item_id`, `QuestLog.states[quest_id]`, `known_recipes`), never the definition objects. This is the existing `item_id`-survives-save-load pattern — keep it. |
| **`StorySlot`** metadata (cover color, playtime, timestamps) | Its own per-slot metadata, owned by `SaveManager`'s slot index. | It's the "cover page" the player sees *before* loading a save — see `story_slot.gd`. It must be readable without deserializing the whole `PlayerData`. |
| **UI/session ephemera** — current notebook tab, scroll positions, selected row | Stays in the notebook scene (it persists for the session because the node stays in the tree — see `notebook.gd`). | Not game progress. No reason to persist to disk. |

> **The core split, in one line:** `PlayerData` = *this story's progress*. `GameSettings` = *this
> player's preferences*. `*.tres` definitions = *the game's content*.

---

## 6. Save / load integration

### 6.1 Files on disk

```
user://settings.tres          # GameSettings — one per device, shared by all slots
user://slots/slot_<id>.tres   # PlayerData — one file per save slot
user://slots/index.tres       # (Phase 2+) list of StorySlot metadata for the Sessions tab
```

**Per-slot files, not one big file.** The Sessions tab is already designed around multiple
stories (`sessions_tab.gd`, the `StorySlot` Resource). One file per slot means switching stories
is "load a different file," deleting a story is "delete a file," and a corrupt slot can't take
down the others. Phase 1 can ship with a single `slot_default.tres` and still be forward-compatible.

### 6.2 SaveManager API

```gdscript
# autoloads/save_manager.gd
extends Node
## Owns the live PlayerData (per-save) and GameSettings (per-device),
## and reads/writes them to user:// via ResourceSaver / ResourceLoader.

const SETTINGS_PATH := "user://settings.tres"
const SLOT_DIR := "user://slots/"

var current_data: PlayerData = null
var settings: GameSettings = null


## Build a brand-new game. Called from the main menu's "New Story" flow.
func new_game() -> void:
    current_data = PlayerData.new()
    current_data.reset_to_new_game()   # seeds starter inventory, intro quest, etc.


## Load a slot from disk into current_data. Returns false if the file is missing
## or unreadable (caller can then fall back to new_game()).
## ResourceLoader: https://docs.godotengine.org/en/stable/classes/class_resourceloader.html
func load_slot(slot_id: String) -> bool:
    var path: String = _slot_path(slot_id)
    if not ResourceLoader.exists(path):
        return false
    var loaded: PlayerData = ResourceLoader.load(path) as PlayerData
    if loaded == null:
        return false
    current_data = loaded
    current_data.rehydrate()           # re-link runtime-only refs (see §6.3)
    return true


## Write current_data to its slot file.
## ResourceSaver: https://docs.godotengine.org/en/stable/classes/class_resourcesaver.html
func save_slot(slot_id: String) -> void:
    if current_data == null:
        return
    DirAccess.make_dir_recursive_absolute(SLOT_DIR)
    ResourceSaver.save(current_data, _slot_path(slot_id))


## Settings persist independently of any slot.
func load_settings() -> void:
    if ResourceLoader.exists(SETTINGS_PATH):
        settings = ResourceLoader.load(SETTINGS_PATH) as GameSettings
    if settings == null:
        settings = GameSettings.new()   # first run → defaults


func save_settings() -> void:
    if settings != null:
        ResourceSaver.save(settings, SETTINGS_PATH)


func _slot_path(slot_id: String) -> String:
    return "%sslot_%s.tres" % [SLOT_DIR, slot_id]
```

### 6.3 The save/load gotcha: runtime-only references

`ItemStack` carries a non-exported `item: ItemData` runtime ref that is **not** written to disk —
only `item_id` survives (see `item_stack.gd`). After loading, those refs are `null` until
re-linked. So `PlayerData` needs a `rehydrate()` method called once after load:

```gdscript
# In PlayerData
## Re-attach runtime-only references (e.g. ItemStack.item) after a load, using
## the static item definitions. Loading from .tres restores item_id but not the
## non-exported `item` ref — see resources/data/items/item_stack.gd.
func rehydrate() -> void:
    var registry: Dictionary = ItemDatabase.all()   # static id → ItemData (out of scope here)
    for stack: ItemStack in inventory.stacks:
        stack.item = registry.get(stack.item_id, null)
```

> **Why not just export `ItemStack.item`?** Because embedding the full `ItemData` in every save
> file means a content change (rebalancing an item's weight) wouldn't reach old saves, and the
> save file bloats. The id-only pattern is deliberate and already in place — `rehydrate()` is the
> price we pay for it, and it's a cheap, one-time pass. (A small `ItemDatabase` helper that scans
> `resources/data/items/` for the registry is its own task, out of scope for this doc.)

---

## 7. Access pattern

### 7.1 The rule

- **Read** through `SaveManager.current_data` directly. It's a plain property; reading is cheap
  and obvious.
- **Write** by calling methods on the data Resources (`inventory.add(...)`,
  `quest_log.states[id] = ...`), then **announce the change via a `GameEvents` signal** so any
  listener (the HUD, an open notebook tab) refreshes.

This matches the project's existing convention exactly: `InventoryTab._do_equip()` already calls
`_inventory.equip(item)` and then `GameEvents.inventory_changed.emit()`. We are just moving
`_inventory` from "owned by the tab" to "owned by `SaveManager.current_data`."

> **Why signals for change-announcement but direct refs for reads?** Per CLAUDE.md's signal-bus
> rule: `GameEvents` is for *cross-system* notification ("inventory changed, whoever cares should
> refresh"), where the writer shouldn't know who the readers are. A *read* has a known caller and
> a known target, so a direct property access is correct and simpler. Don't route reads through
> signals.

### 7.2 Gameplay system writes (foraging example)

```gdscript
# In a forageable bush's interact handler (foraging system, future)
func _on_harvested() -> void:
    var berry: ItemData = preload("res://resources/data/items/wild_berry.tres")
    var leftover: int = SaveManager.current_data.inventory.add(berry, randi_range(1, 3))
    GameEvents.inventory_changed.emit()   # HUD weight bar + open notebook refresh
    if leftover > 0:
        GameEvents.inventory_full.emit(berry)
```

### 7.3 Market write (gold + inventory)

```gdscript
# In the market stall (selling system, future)
func _sell(item: ItemData, count: int, unit_price: int) -> void:
    if SaveManager.current_data.inventory.remove(item, count):
        SaveManager.current_data.gold += unit_price * count
        GameEvents.inventory_changed.emit()
        GameEvents.gold_changed.emit(SaveManager.current_data.gold)   # new signal, §8
```

### 7.4 Notebook tab reads (the new InventoryTab)

Tabs **stop owning data**. They read from the central store and **listen** for change signals to
refresh while open:

```gdscript
# InventoryTab, after migration
func _ready() -> void:
    # Refresh the open tab whenever anything (forage, market, brewing) changes the bag.
    GameEvents.inventory_changed.connect(_on_inventory_changed)

func _current_inventory() -> Inventory:
    return SaveManager.current_data.inventory   # single source of truth

func _on_inventory_changed() -> void:
    if visible:
        _refresh_both_pages()
```

This is a real upgrade beyond cleanup: today, picking a berry in the world could never update an
open notebook because the tab held a *different* `Inventory`. After migration it just works,
because there is only one.

---

## 8. New GameEvents signals

`GameEvents` already carries `inventory_changed`, `item_equipped/_unequipped/_dropped/_recycled`,
`destination_visited`, and the quest signals. Add only what new state needs, following the
existing untyped-`Variant` convention noted in `game_events.gd` (autoloads load before
`class_name` indexing, so typed params would break startup):

```gdscript
# Currency
signal gold_changed(new_total: int)

# Game data lifecycle — emitted by SaveManager after new_game()/load_slot()
# so all listeners rebind to the fresh PlayerData in one place.
signal player_data_loaded()

# Phase 2+
signal recipe_learned(recipe_id: StringName)
signal relationship_changed(npc_id: StringName, new_score: int)
signal day_advanced(new_day: int)
```

`player_data_loaded` is the important one: after a load or new-game swaps `current_data`, any
long-lived listener (HUD, persistent notebook) must re-read from the new object. Emitting one
signal lets them all rebind without each polling.

---

## 9. PlayerData schema (GDScript pseudocode)

Phase 1 fields are live; later fields are shown commented to document intent without building
empty systems. Member ordering follows CLAUDE.md (class_name, extends, constants, @export, methods).

```gdscript
class_name PlayerData
extends Resource
## The complete mutable state of a single save/story slot, in memory.
## Owned by SaveManager.current_data; serialized whole to user://slots/slot_<id>.tres
## via ResourceSaver. Static content (ItemData, QuestData, recipes) is NOT stored
## here — only references by id — so content edits reach old saves. See design doc §5.

## Bump when the schema changes in a way that needs migration on load.
const CURRENT_VERSION: int = 1

## Schema stamp written into every save. Read on load to migrate older files.
@export var save_version: int = CURRENT_VERSION

# --- Phase 1: already-real data, moved out of the notebook tabs ---

## All items Cream Bun is carrying or wearing. See resources/data/items/inventory.gd.
@export var inventory: Inventory = Inventory.new()

## Quest progress, keyed by quest id. See resources/data/quests/quest_log.gd.
@export var quest_log: QuestLog = QuestLog.new()

## Discovered map destinations + fog data. See resources/data/map/map_state.gd.
@export var map_state: MapState = MapState.new()

## Market currency. A plain int — no Resource needed for a single number.
@export var gold: int = 0

# --- Phase 2: declared when their systems arrive (do NOT build empty) ---

## Cozy life-sim stats (energy, mood). NO combat stats — CreamBun has no combat.
# @export var player_stats: PlayerStats = PlayerStats.new()

## Brewing recipe ids the player has learned. Recipe definitions are static .tres.
# @export var known_recipes: Array[StringName] = []

## Per-spot forage cooldowns: spot_id -> "ready again on day N".
# @export var forage_state: ForageState = ForageState.new()

# --- Phase 3: relationships, dialogue, calendar ---

## NPC affinity: npc_id (StringName) -> score (int). Plain Dictionary round-trips cleanly.
# @export var relationships: Dictionary = {}

## What's already been said: dialogue/npc id -> arbitrary state.
# @export var dialogue_history: Dictionary = {}

## In-game day / season / time-of-day. Cozy pacing only.
# @export var calendar: CalendarState = CalendarState.new()


## Seed a brand-new game. Called by SaveManager.new_game().
## Mirrors the sample data the notebook tabs currently create in _ready(), so the
## starting experience is identical after migration.
func reset_to_new_game() -> void:
    inventory = Inventory.new()
    quest_log = QuestLog.new()
    map_state = MapState.new()
    gold = 0
    save_version = CURRENT_VERSION
    _seed_starter_content()


## Re-attach runtime-only references after a load (see design doc §6.3).
func rehydrate() -> void:
    pass   # Phase 1: re-link ItemStack.item from the item registry.


## Give the new player the intro quest and any starter items.
## (Replaces the hand-seeding currently in InventoryTab/QuestsTab._ready().)
func _seed_starter_content() -> void:
    quest_log.states[&"the_foraging_book"] = {
        "status": QuestLog.Status.COMPLETED,
        "completed_objectives": [0, 1, 2],
    }
```

> **Why initialize `@export var inventory: Inventory = Inventory.new()` inline?** So a
> default-constructed `PlayerData` is never half-null — every sub-Resource exists immediately.
> Note Godot serializes the *current* values, so a loaded file overwrites these defaults; they
> only matter for `PlayerData.new()` before `reset_to_new_game()` runs.

---

## 10. Initialization / new-game vs load flow

```
Game launch
   │
   ├─ SaveManager.load_settings()          # always; per-device, independent of slots
   │
   └─ Main menu
        ├─ "New Story"  → SaveManager.new_game()
        │                   └─ current_data = PlayerData.new(); reset_to_new_game()
        │                   └─ GameEvents.player_data_loaded.emit()
        │
        └─ "Continue"   → SaveManager.load_slot(slot_id)
                            ├─ ok    → rehydrate(); GameEvents.player_data_loaded.emit()
                            └─ fail  → SaveManager.new_game()  (graceful fallback)
```

The world scene and HUD do **not** create any data. They wait for `current_data` to exist
(guaranteed by the time `PLAYING` state begins) and listen for `player_data_loaded` to bind to it.

**Saving** is triggered explicitly (Phase 1: on notebook close or a Sessions-tab "Save" action)
via `SaveManager.save_slot(slot_id)`. No autosave-on-every-change in Phase 1 — keep it simple and
predictable; revisit autosave-on-sleep when the calendar lands.

---

## 11. Migration plan

Incremental, one tab at a time, so the game stays runnable after each step. Each step is small
enough to test in the editor before moving on.

**Step 0 — Build the foundation.**
- Add `PlayerData` (`resources/data/player_data.gd`) with the Phase 1 fields and
  `reset_to_new_game()` / `rehydrate()`.
- Add `current_data` + `new_game()` / `load_slot()` / `save_slot()` to `SaveManager`.
- Add `settings` + `load_settings()` / `save_settings()` to `SaveManager`.
- Add `player_data_loaded` and `gold_changed` to `GameEvents`.
- On launch, call `SaveManager.load_settings()` and `SaveManager.new_game()` so `current_data`
  is never null while the rest of the migration is in flight.

**Step 1 — InventoryTab.**
- Delete `_inventory`/`_item_registry` ownership and the sample-data block in `_ready()`.
- Read via `SaveManager.current_data.inventory`; build the registry from the item database helper
  (or keep a temporary local registry until that helper exists).
- Connect `GameEvents.inventory_changed` to refresh while visible.
- The existing `*.emit()` calls in `_do_equip/_do_throw/_do_recycle` already announce changes —
  leave them.

**Step 2 — QuestsTab.**
- Delete `_quest_log` ownership; read `SaveManager.current_data.quest_log`.
- Move the intro-quest seeding into `PlayerData._seed_starter_content()` (already shown in §9).

**Step 3 — MapTab.**
- When the real map lands, read/write `SaveManager.current_data.map_state`; emit
  `destination_visited` on discovery (signal already exists).

**Step 4 — SettingsTab.**
- Replace the fresh-`GameSettings`-per-session with `SaveManager.settings`.
- Persist via `SaveManager.save_settings()` when a value changes (or on notebook close).
- Note: settings do **not** go through `PlayerData` — this step proves the per-device split works.

**Step 5 — Wire real save/load to the Sessions tab.**
- Replace the hardcoded `_default_slot` with the slot index; "switch story" calls `load_slot()`;
  emit/handle `story_loaded` (signal already exists).

**Tests.** Existing tab tests (`tests/unit/ui/notebook/...`) construct tabs directly and assume
self-owned data. After each step, update that suite to set `SaveManager.current_data =
PlayerData.new()` in setup so the tab has a store to read. (Test rewrite is its own task.)

---

## 12. FAQ — "why not X?"

**Why not make `PlayerData` an autoload?**
A save file is naturally owned by the thing that saves files. As a `Node` autoload it can't be
serialized in one call, can't be swapped for slot-switching, and pushes us to 4 autoloads against
CLAUDE.md. See §3.

**Why not one giant save file with all slots inside it?**
A corrupt slot would take down every story, and slot-switching/deletion become array surgery
instead of file operations. The Sessions tab is already multi-slot by design. See §6.1.

**Why not put `GameSettings` in `PlayerData` "to keep it all together"?**
Settings are per-device, not per-story. Bundling them means volume changes don't carry across
stories and a new save resets accessibility choices. Wrong model. See §5.

**Why not store the full `ItemData` inside each `ItemStack` so loading is simpler?**
Content edits (rebalancing weight) wouldn't reach old saves, and files bloat. The id-only pattern
already exists in `item_stack.gd`; `rehydrate()` re-links runtime refs once on load. See §6.3.

**Why not let tabs keep a local copy and sync it?**
Two copies of the inventory is exactly today's bug — picking a berry in the world can't update an
open notebook because they're different objects. One source of truth, read live. See §7.4.

**Why not route every read through a `GameEvents` signal too?**
Signals are for *cross-system announcements* where the writer doesn't know the readers. A read has
a known caller and target — a direct property access is simpler and correct. See §7.1.

**Why not autosave on every change now?**
Disk writes on every berry pick are wasteful and make save timing unpredictable. Explicit saves
(notebook close / Sessions action) are simpler for Phase 1; revisit autosave-on-sleep with the
calendar. See §10.

---

## 13. Out of scope (later)

- `ItemDatabase` helper that scans `resources/data/items/` to build the id→`ItemData` registry
  used by `rehydrate()`.
- `PlayerStats`, `ForageState`, `CalendarState` Resource definitions (declared as Phase 2/3 stubs
  in §9 — build with their systems, not before).
- Save-version migration logic (the `save_version` field exists now; the migration switch comes
  when the schema first changes).
- Autosave triggers and the day/night save-on-sleep flow.
