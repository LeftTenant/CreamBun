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

This document designs **`PlayerData`** — a fourth autoload that holds all *mutable, per-save*
game state and makes it reachable from anywhere in the game via `PlayerData.inventory`,
`PlayerData.gold`, etc. The serializable data lives in a separate `PlayerDataResource`
(a `Resource` subclass) that `SaveManager` reads and writes to disk.

The guiding principle: **one obvious place for live game state, reached one obvious way.**

---

## 2. Recommendation (read this first)

Two decisions drive everything else:

1. **`PlayerData` is a fourth autoload** — a thin `Node` wrapper over a `PlayerDataResource`.
   Gameplay code reaches live state through `PlayerData.inventory`, `PlayerData.gold`, etc.
   `SaveManager` serializes and deserializes only the inner resource.
2. **`GameSettings` stays out of `PlayerData`.** Settings are per-device (one volume preference
   across all stories), not per-save. They live in a separate file owned by `SaveManager.settings`.

The rest of this doc justifies these choices, defines the schema, shows the access pattern
(including the dependency injection rule), and lays out a phased migration.

---

## 3. Architecture: PlayerData autoload + PlayerDataResource

### The shape

```
PlayerData (autoloads/player_data.gd — extends Node, registered as autoload)
   │  exposes: .inventory, .quest_log, .map_state, .gold, ...
   └─ _resource: PlayerDataResource  (resources/data/player_data_resource.gd — extends Resource)
                  serialized whole to user://slots/slot_<id>.tres by SaveManager
```

The autoload is a thin wrapper. It holds one `PlayerDataResource` at a time and forwards
property reads/writes to it. When a new game is started or a slot is loaded, `SaveManager`
swaps the inner resource in a single call:

```gdscript
# autoloads/player_data.gd
extends Node
## Live game state for the current save slot. A thin Node wrapper over PlayerDataResource
## so the data can be serialized cleanly — Godot autoloads must extend Node, but
## ResourceSaver can only serialize Resource objects, not Node trees.
## See: https://docs.godotengine.org/en/stable/classes/class_resourcesaver.html

var _resource: PlayerDataResource = PlayerDataResource.new()

## All items Cream Bun is carrying or wearing.
var inventory: Inventory:
    get: return _resource.inventory

## Quest progress, keyed by quest id.
var quest_log: QuestLog:
    get: return _resource.quest_log

## Discovered map destinations and fog data.
var map_state: MapState:
    get: return _resource.map_state

## Market currency.
var gold: int:
    get: return _resource.gold
    set(v): _resource.gold = v

## Called by SaveManager after new_game() or load_slot() to swap in fresh data.
## Emits player_data_loaded so all listeners rebind to the new resource.
func _load_resource(resource: PlayerDataResource) -> void:
    _resource = resource
    GameEvents.player_data_loaded.emit()

## Returns the serializable resource for SaveManager to write to disk.
func to_resource() -> PlayerDataResource:
    return _resource
```

### Why a 4th autoload is the right call here

The previous design (Resource held by `SaveManager.current_data`) conflated two
responsibilities in `SaveManager` and introduced a nullable trap:

| Concern | `PlayerData` autoload + `PlayerDataResource` (chosen) | Resource in `SaveManager` |
| --- | --- | --- |
| **Access path** | `PlayerData.inventory` — short, obvious | `SaveManager.current_data.inventory` — verbose, wrong semantic owner |
| **Null safety** | `_resource` initializes in the field declaration; never null | `current_data` is null until `new_game()`/`load_slot()` runs |
| **Responsibilities** | `SaveManager` = I/O only. `PlayerData` = live state only. | `SaveManager` = I/O + live state. Two unrelated jobs in one class. |
| **Serialization** | `ResourceSaver.save(PlayerData.to_resource(), path)` — one call | Same — the resource is still the unit of serialization |
| **New game / load** | `PlayerData._load_resource(data)` — swap one object | `SaveManager.current_data = data` — same, but semantically odd |
| **Autoload count** | 4 | 3 |

The only cost is one more autoload. That cost is paid back immediately in clarity, null safety,
and clean separation of responsibilities. `PlayerData` is genuinely application-wide (every
system that touches game state needs it) with no better natural owner — it passes the bar.

### Why the thin-wrapper pattern, not `PlayerData extends Resource`

Godot autoloads must extend `Node` (or `PackedScene`). You cannot register a bare `Resource`
subclass as an autoload. The wrapper pattern is the idiomatic solution: the autoload `Node`
delegates everything to the inner `Resource`, which is the only thing that ever touches the
disk. New-game and slot-switching swap the resource in one call; the Node itself is stable.

> **No direct field duplication.** The wrapper forwards reads and writes through GDScript
> property getters/setters. There are no parallel copies to keep in sync.

---

## 4. What goes IN PlayerData

`PlayerDataResource` is the container for everything that is **mutable** and **belongs to one
save/story slot**. Each field is a Resource (or a primitive) so the whole graph serializes in
one `ResourceSaver.save()` call.

| Field | Type | Phase | Why it lives here |
| --- | --- | --- | --- |
| `inventory` | `Inventory` | 1 | Already exists; currently orphaned in `InventoryTab`. The clearest case. |
| `quest_log` | `QuestLog` | 1 | Already exists; currently hand-seeded in `QuestsTab`. |
| `map_state` | `MapState` | 1 | Already exists; `MapTab` will need it. Tracks visited destinations + fog. |
| `gold` | `int` | 1 | Currency from the market. A single primitive — no Resource needed. |
| `player_stats` | `PlayerStats` (new) | 2 | Cozy stats only — energy/stamina for a gentle day loop. **No combat stats.** See §4.1. |
| `known_recipes` | `Array[StringName]` | 2 | Brewing recipe ids the player has learned. Recipe *definitions* are static `.tres` (see §5). |
| `forage_state` | `ForageState` (new) | 2 | Per-location forage cooldowns / regrowth timers. See §4.2. |
| `relationships` | `Dictionary` (StringName → int) | 3 | NPC affinity scores keyed by npc id. |
| `dialogue_history` | `Dictionary` (StringName → Variant) | 3 | What's been said / one-time lines already shown. |
| `calendar` | `CalendarState` (new) | 3 | In-game day/season/time-of-day. See §4.3. |
| `save_version` | `int` | 1 | Schema version stamp for future migration. Defaults to 1. |

**Phase 1 ships only the four already-real pieces** (`inventory`, `quest_log`, `map_state`,
`gold`) plus `save_version`. Do **not** build empty systems ahead of need.

### 4.1 PlayerStats (Phase 2, new) — cozy only

A small Resource for gentle life-sim stats. CreamBun has no combat, so there is no health,
attack, or defense. Reasonable starters: `energy` (spent foraging/brewing, refilled by sleep)
and maybe a soft `mood`. Keep it tiny; add fields when a system actually reads them.

> **Naming note:** call it `PlayerStats`, not `CharacterStats`. The project reserves
> combat-flavored `CharacterStats`/`AbilityData` as stubs; a cozy stats Resource should read cozy.

### 4.2 ForageState (Phase 2, new)

Tracks which forageable spots are depleted and when they regrow. Simplest form: a `Dictionary`
mapping a spot id (`StringName`) to a "ready again on day N" value, checked against `calendar`.
Stub until foraging lands.

### 4.3 CalendarState (Phase 3, new)

Holds `day` (int), `season` (enum), and `time_of_day` (enum or float). Cozy pacing only — time
advances on player actions or sleep, never on a punishing real-time clock. Out of scope until
the day/night system is designed.

---

## 5. What stays OUT of PlayerData

| Excluded | Where it lives instead | Why |
| --- | --- | --- |
| **`GameSettings`** (volumes, window scale, text speed) | `SaveManager.settings`, its own `user://settings.tres`. | **Per-device, not per-save.** One volume preference for all stories. Bundling it in each save means a new story resets accessibility choices — wrong. |
| **Static definitions** — `ItemData`, `QuestData`, `MapDestination`, `NpcData`, future `DrinkRecipe` | `resources/data/**/*.tres`, loaded read-only at runtime. | These are *content*, authored once, shared by every save. `PlayerData` stores **references by id** (`ItemStack.item_id`, quest ids, `known_recipes`), never the definitions. |
| **`StorySlot`** metadata (cover color, playtime, timestamps) | Its own per-slot metadata file, read by `SaveManager`'s slot index. | It's the "cover page" the player sees *before* loading a save. Must be readable without deserializing the whole `PlayerDataResource`. |
| **UI/session ephemera** — current tab, scroll positions, selected row | Stays in the notebook scene (the node persists in the tree for the session — see `notebook.gd`). | Not game progress. No reason to persist to disk. |

> **The core split, in one line:** `PlayerData` = *this story's progress*. `GameSettings` = *this
> player's preferences*. `*.tres` definitions = *the game's content*.

---

## 6. Save / load integration

### 6.1 Files on disk

```
user://settings.tres          # GameSettings — one per device, shared by all slots
user://slots/slot_<id>.tres   # PlayerDataResource — one file per save slot
user://slots/index.tres       # (Phase 2+) list of StorySlot metadata for the Sessions tab
```

**Per-slot files, not one big file.** Switching stories is "load a different file," deleting a
story is "delete a file," and a corrupt slot can't take down the others.

### 6.2 SaveManager API

`SaveManager` is now purely I/O — it no longer owns live game state. It reads and writes
resources; `PlayerData` holds the live data.

```gdscript
# autoloads/save_manager.gd
extends Node
## Reads and writes PlayerDataResource save slots and GameSettings to disk.
## Does NOT hold live game state — that lives in the PlayerData autoload.

const SETTINGS_PATH := "user://settings.tres"
const SLOT_DIR := "user://slots/"

## Per-device preferences. Independent of any save slot.
var settings: GameSettings = null


## Build a brand-new game. Called from the main menu's "New Story" flow.
## Constructs a fresh PlayerDataResource, seeds starter content, and hands it
## to the PlayerData autoload which emits player_data_loaded.
func new_game() -> void:
    var data := PlayerDataResource.new()
    data.reset_to_new_game()
    PlayerData._load_resource(data)


## Load a slot from disk into the PlayerData autoload. Returns false if the file
## is missing or unreadable (caller should fall back to new_game()).
## ResourceLoader: https://docs.godotengine.org/en/stable/classes/class_resourceloader.html
func load_slot(slot_id: String) -> bool:
    var path: String = _slot_path(slot_id)
    if not ResourceLoader.exists(path):
        return false
    var loaded: PlayerDataResource = ResourceLoader.load(path) as PlayerDataResource
    if loaded == null:
        return false
    loaded.rehydrate()                      # re-link runtime-only refs (see §6.3)
    PlayerData._load_resource(loaded)       # swap into the live autoload
    return true


## Write the current PlayerDataResource to its slot file.
## ResourceSaver: https://docs.godotengine.org/en/stable/classes/class_resourcesaver.html
func save_slot(slot_id: String) -> void:
    DirAccess.make_dir_recursive_absolute(SLOT_DIR)
    ResourceSaver.save(PlayerData.to_resource(), _slot_path(slot_id))


## Settings persist independently of any slot.
func load_settings() -> void:
    if ResourceLoader.exists(SETTINGS_PATH):
        settings = ResourceLoader.load(SETTINGS_PATH) as GameSettings
    if settings == null:
        settings = GameSettings.new()       # first run → defaults


func save_settings() -> void:
    if settings != null:
        ResourceSaver.save(settings, SETTINGS_PATH)


func _slot_path(slot_id: String) -> String:
    return "%sslot_%s.tres" % [SLOT_DIR, slot_id]
```

### 6.3 The save/load gotcha: runtime-only references

`ItemStack` carries a non-exported `item: ItemData` runtime ref that is **not** written to disk —
only `item_id` survives (see `item_stack.gd`). After loading, those refs are `null` until
re-linked. `PlayerDataResource.rehydrate()` runs once after load:

```gdscript
# In PlayerDataResource
## Re-attach runtime-only references (e.g. ItemStack.item) after a load, using
## the static item definitions. Loading from .tres restores item_id but not the
## non-exported `item` ref — see resources/data/items/item_stack.gd.
func rehydrate() -> void:
    var registry: Dictionary = ItemDatabase.all()   # id → ItemData (out of scope here)
    for stack: ItemStack in inventory.stacks:
        stack.item = registry.get(stack.item_id, null)
```

> **Why not export `ItemStack.item`?** Content edits (rebalancing weight) wouldn't reach old
> saves, and save files bloat. The id-only pattern is deliberate and already in place.
> `rehydrate()` is the price, and it's cheap — one pass after each load.

---

## 7. Access pattern

### 7.1 The rule

- **Read** through `PlayerData` directly. It's an autoload property; reading is cheap and obvious.
- **Write** by calling methods on the sub-resources (`PlayerData.inventory.add(...)`,
  `PlayerData.quest_log.states[id] = ...`), then **announce the change via a `GameEvents` signal**
  so any listener (HUD, open notebook tab) refreshes.

> **Why signals for change-announcement but direct refs for reads?** Per CLAUDE.md's signal-bus
> rule: `GameEvents` is for *cross-system* notification where the writer shouldn't know the
> readers. A *read* has a known caller and target — a direct property is simpler and correct.

### 7.2 Gameplay system writes (foraging example)

```gdscript
# In a forageable bush's interact handler (foraging system, future)
func _on_harvested() -> void:
    var berry: ItemData = preload("res://resources/data/items/wild_berry.tres")
    var leftover: int = PlayerData.inventory.add(berry, randi_range(1, 3))
    GameEvents.inventory_changed.emit()   # HUD weight bar + open notebook refresh
    if leftover > 0:
        GameEvents.inventory_full.emit(berry)
```

### 7.3 Market write (gold + inventory)

```gdscript
# In the market stall (selling system, future)
func _sell(item: ItemData, count: int, unit_price: int) -> void:
    if PlayerData.inventory.remove(item, count):
        PlayerData.gold += unit_price * count
        GameEvents.inventory_changed.emit()
        GameEvents.gold_changed.emit(PlayerData.gold)   # new signal, §8
```

### 7.4 Notebook tab reads (the new InventoryTab)

Tabs **stop owning data**. They read from `PlayerData` and **listen** for change signals:

```gdscript
# InventoryTab, after migration
func _ready() -> void:
    GameEvents.inventory_changed.connect(_on_inventory_changed)

func _current_inventory() -> Inventory:
    return PlayerData.inventory   # single source of truth

func _on_inventory_changed() -> void:
    if visible:
        _refresh_both_pages()
```

This is a real upgrade: today, picking a berry could never update an open notebook because the
tab held a *different* `Inventory` object. After migration it just works.

### 7.5 Dependency injection for testable leaf nodes

Direct `PlayerData` access in leaf nodes (bushes, market stalls, NPCs) couples them to the
global autoload graph, making isolated unit tests impossible. **Prefer injecting the specific
sub-resource a node needs:**

```gdscript
# ForageableBush.gd — no autoload knowledge required
var _inventory: Inventory = null

## Called by the world scene after player_data_loaded.
func setup(inventory: Inventory) -> void:
    _inventory = inventory

func _on_harvested() -> void:
    _inventory.add(berry, 2)
    GameEvents.inventory_changed.emit()
```

```gdscript
# world.gd (scene orchestrator — touching autoloads here is correct)
func _ready() -> void:
    GameEvents.player_data_loaded.connect(_on_player_data_loaded)

func _on_player_data_loaded() -> void:
    for bush: ForageableBush in get_tree().get_nodes_in_group("forageables"):
        bush.setup(PlayerData.inventory)
```

A unit test for `ForageableBush` only needs a bare `Inventory.new()` — no autoloads at all:

```gdscript
# tests/unit/world/test_forageable_bush.gd
func test_harvest_adds_to_inventory() -> void:
    var inventory := Inventory.new()
    var bush := ForageableBush.new()
    bush.setup(inventory)
    bush._on_harvested()
    assert_gt(inventory.stacks.size(), 0)
```

The pattern extends to any node that reads or writes game state: market stalls receive
`(inventory, gold_ref)`, NPCs receive `(quest_log, relationships)`, brewing stations receive
`(inventory, known_recipes)`. The orchestrator (world.gd) is the only place that reads from
`PlayerData` to assemble these references.

---

## 8. New GameEvents signals

`GameEvents` already carries `inventory_changed`, `item_equipped/_unequipped/_dropped/_recycled`,
`destination_visited`, and the quest signals. Add only what new state needs, following the
existing untyped-`Variant` convention in `game_events.gd` (autoloads load before `class_name`
indexing completes, so typed non-primitive params would fail at startup):

```gdscript
# Currency
signal gold_changed(new_total: int)

# Game data lifecycle — emitted by PlayerData._load_resource() after new_game()/load_slot()
# so all listeners rebind to the fresh resource in one place.
signal player_data_loaded()

# Phase 2+
signal recipe_learned(recipe_id: StringName)
signal relationship_changed(npc_id: StringName, new_score: int)
signal day_advanced(new_day: int)
```

`player_data_loaded` is the important one: after a slot swap, any long-lived listener (HUD,
persistent notebook) must re-read from the new data. One signal, all listeners update.

---

## 9. Schemas (GDScript pseudocode)

### 9.1 PlayerData autoload (autoloads/player_data.gd)

```gdscript
class_name PlayerData   # class_name is fine on autoloads; the registered name matches
extends Node
## Thin Node wrapper over PlayerDataResource. The autoload is the stable, always-available
## access point; the Resource is the unit that gets serialized. Swap _resource on
## new-game or slot-load; callers never see the swap because they always go through
## the forwarded properties.

var _resource: PlayerDataResource = PlayerDataResource.new()

# --- Forwarded properties (Phase 1) ---

var inventory: Inventory:
    get: return _resource.inventory

var quest_log: QuestLog:
    get: return _resource.quest_log

var map_state: MapState:
    get: return _resource.map_state

var gold: int:
    get: return _resource.gold
    set(v): _resource.gold = v

var save_version: int:
    get: return _resource.save_version

# --- Phase 2 (add when their systems arrive) ---
# var player_stats: PlayerStats: get: return _resource.player_stats
# var known_recipes: Array[StringName]: get: return _resource.known_recipes
# var forage_state: ForageState: get: return _resource.forage_state


## Swap in a new resource (from SaveManager.new_game or load_slot) and notify listeners.
func _load_resource(resource: PlayerDataResource) -> void:
    _resource = resource
    GameEvents.player_data_loaded.emit()


## Return the serializable resource so SaveManager can write it to disk.
func to_resource() -> PlayerDataResource:
    return _resource
```

### 9.2 PlayerDataResource (resources/data/player_data_resource.gd)

```gdscript
class_name PlayerDataResource
extends Resource
## The complete mutable state of a single save/story slot.
## Serialized whole to user://slots/slot_<id>.tres by SaveManager via ResourceSaver.
## Static content (ItemData, QuestData, recipes) is NOT stored here — only references
## by id — so content edits reach old saves without requiring a migration. See design §5.

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

## NPC affinity: npc_id (StringName) -> score (int).
# @export var relationships: Dictionary = {}

## What's already been said: dialogue/npc id -> arbitrary state.
# @export var dialogue_history: Dictionary = {}

## In-game day / season / time-of-day. Cozy pacing only.
# @export var calendar: CalendarState = CalendarState.new()


## Seed a brand-new game. Called by SaveManager.new_game().
func reset_to_new_game() -> void:
    inventory = Inventory.new()
    quest_log = QuestLog.new()
    map_state = MapState.new()
    gold = 0
    save_version = CURRENT_VERSION
    _seed_starter_content()


## Re-attach runtime-only references after a load (see design §6.3).
func rehydrate() -> void:
    pass   # Phase 1: re-link ItemStack.item from the item registry once ItemDatabase exists.


## Give the new player the intro quest and any starter items.
## Replaces the hand-seeding currently in InventoryTab/QuestsTab._ready().
func _seed_starter_content() -> void:
    quest_log.states[&"the_foraging_book"] = {
        "status": QuestLog.Status.COMPLETED,
        "completed_objectives": [0, 1, 2],
    }
```

> **Why initialize `@export var inventory: Inventory = Inventory.new()` inline?** So a
> default-constructed `PlayerDataResource` is never half-null. Godot serializes the *current*
> values, so a loaded file overwrites these defaults; they only matter before `reset_to_new_game()`
> runs on a fresh construction.

---

## 10. Initialization / new-game vs load flow

```
Game launch
   │
   ├─ SaveManager.load_settings()          # always; per-device, independent of slots
   │
   └─ Main menu
        ├─ "New Story"  → SaveManager.new_game()
        │                   └─ PlayerDataResource.new() + reset_to_new_game()
        │                   └─ PlayerData._load_resource(data)
        │                   └─ GameEvents.player_data_loaded.emit()
        │
        └─ "Continue"   → SaveManager.load_slot(slot_id)
                            ├─ ok    → rehydrate() → PlayerData._load_resource(loaded)
                            │          → GameEvents.player_data_loaded.emit()
                            └─ fail  → SaveManager.new_game()  (graceful fallback)
```

The world scene and HUD do **not** create any data. They connect to `player_data_loaded` and
wire up their injected references when it fires. `PlayerData._resource` is initialized inline in
the field declaration, so it is never null — even before `new_game()` has been called.

**Saving** is triggered explicitly (Phase 1: on notebook close or a Sessions-tab "Save" action)
via `SaveManager.save_slot(slot_id)`. No autosave-on-every-change in Phase 1 — predictable and
easy to reason about. Revisit autosave-on-sleep when the calendar arrives.

---

## 11. Migration plan

Incremental, one tab at a time, game stays runnable after every step.

**Step 0 — Build the foundation.**
- Add `PlayerDataResource` (`resources/data/player_data_resource.gd`) with Phase 1 fields,
  `reset_to_new_game()`, and `rehydrate()`.
- Add `PlayerData` autoload (`autoloads/player_data.gd`) with forwarded properties and
  `_load_resource()` / `to_resource()`.
- Register `PlayerData` in Project Settings → Autoloads.
- Rewrite `SaveManager`: strip `current_data`; add `new_game()` / `load_slot()` /
  `save_slot()` as described in §6.2; keep `settings` / `load_settings()` / `save_settings()`.
- Add `player_data_loaded` and `gold_changed` to `GameEvents`.
- Call `SaveManager.load_settings()` and `SaveManager.new_game()` on launch so
  `PlayerData._resource` is populated before any tab opens.

**Step 1 — InventoryTab.**
- Delete `_inventory` / `_item_registry` ownership and the sample-data block in `_ready()`.
- Read via `PlayerData.inventory`; build the registry from the item database helper (or
  keep a temporary local registry until that helper exists).
- Connect `GameEvents.inventory_changed` to refresh while visible.
- Existing `*.emit()` calls in `_do_equip/_do_throw/_do_recycle` stay — they already announce
  changes correctly.

**Step 2 — QuestsTab.**
- Delete `_quest_log` ownership; read `PlayerData.quest_log`.
- Move the intro-quest seeding into `PlayerDataResource._seed_starter_content()` (§9.2).

**Step 3 — MapTab.**
- When the real map lands, read/write `PlayerData.map_state`; emit `destination_visited` on
  discovery (signal already exists in `GameEvents`).

**Step 4 — SettingsTab.**
- Replace the fresh-`GameSettings`-per-session with `SaveManager.settings`.
- Persist via `SaveManager.save_settings()` on notebook close.
- Settings do **not** go through `PlayerData` — this step proves the per-device split works.

**Step 5 — Wire real save/load to the Sessions tab.**
- Replace the hardcoded `_default_slot` with the slot index; "switch story" calls
  `SaveManager.load_slot()`; emit/handle `story_loaded` (signal already exists).

**Tests.** Existing tab tests construct tabs and assume self-owned data. After each step,
update the suite to either (a) call `PlayerData._load_resource(PlayerDataResource.new())` in
`before_each()` to populate the autoload, or (b) extract the sub-resource and inject it
directly into the node under test — the preferred approach for hermetic unit tests. (Full test
rewrite is its own task.)

---

## 12. FAQ — "why not X?"

**Why use a thin-wrapper autoload instead of keeping PlayerData as a plain Resource?**
Godot autoloads must extend `Node`. You can't register a `Resource` subclass as an autoload.
The wrapper delegates everything to the inner `PlayerDataResource`; there's no field
duplication. The Node is the stable global handle; the Resource is the serializable payload.

**Why not keep `PlayerData` as a Resource held by `SaveManager.current_data`?**
It conflates two responsibilities (`SaveManager` does I/O *and* owns live state), produces a
nullable access trap, and yields the verbose `SaveManager.current_data.inventory` path.
See §3 for the full comparison.

**Why not one giant save file with all slots inside it?**
A corrupt slot would take down every story, and slot-switching/deletion become array surgery
instead of file operations. The Sessions tab is already multi-slot by design. See §6.1.

**Why not put `GameSettings` in `PlayerData` "to keep it all together"?**
Settings are per-device, not per-story. Bundling them means volume changes don't carry across
stories and a new save resets accessibility choices. Wrong model. See §5.

**Why not store the full `ItemData` inside each `ItemStack` so loading is simpler?**
Content edits (rebalancing weight) wouldn't reach old saves, and files bloat. The id-only
pattern already exists in `item_stack.gd`; `rehydrate()` re-links runtime refs once on load.
See §6.3.

**Why not let tabs keep a local copy and sync it?**
Two copies of the inventory is exactly today's bug — a berry picked in the world can't update
an open notebook because they're different objects. One source of truth, read live. See §7.4.

**Why not route every read through a `GameEvents` signal too?**
Signals are for cross-system announcements where the writer doesn't know the readers. A read
has a known caller and target — direct property access is simpler and correct. See §7.1.

**Why not autosave on every change now?**
Disk writes on every berry pick are wasteful and make save timing unpredictable. Explicit saves
(notebook close / Sessions action) are simpler for Phase 1. See §10.

**Why not inject `PlayerData` itself rather than its sub-resources?**
You could — `bush.setup(PlayerData)` passes the whole thing. But passing only what a node
*needs* (e.g. just `Inventory`) makes the dependency explicit in the method signature, keeps
tests minimal, and prevents nodes from accidentally reading unrelated state. Narrow injection
beats wide injection.

---

## 13. Out of scope (later)

- `ItemDatabase` helper that scans `resources/data/items/` to build the id→`ItemData` registry
  used by `rehydrate()`.
- `PlayerStats`, `ForageState`, `CalendarState` Resource definitions (declared as Phase 2/3
  stubs in §9.2 — build with their systems, not before).
- Save-version migration logic (the `save_version` field exists now; the migration switch comes
  when the schema first changes).
- Autosave triggers and the day/night save-on-sleep flow.
- The world.gd orchestration layer that calls `bush.setup(PlayerData.inventory)` etc. — that
  comes when the first gameplay system (foraging) is designed.
