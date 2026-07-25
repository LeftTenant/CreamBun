# CLAUDE.md

## Project

CreamBun is a cozy top-down RPG built in **Godot 4.6** using the **Mobile renderer**. The player character is Cream Bun — a small round creature who forages ingredients, brews drinks, and sells them at market. No combat; no enemies. The tone is cozy life-sim. The `combat/` folder and `COMBAT` game state are stubs reserved for future design — do not implement combat mechanics.

See `README.md` in the root project folder for more details on project requirements and the intended game experience.

## Development

There is no build CLI or automated test suite — all iteration and testing happens in the Godot editor. Scripts can be edited externally; Godot hot-reloads them.

This is a beginner project, so always keep things as simple as possible. Favor easy to read and understand code over efficiency unless implementing code in critical sections of the game loop that demand performance. Document code well and explain why code is written as it is, not just what is implemented. Include links to documentation in comments whenever new APIs are used.

## Code Style

Follow the official [GDScript style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html). Additional project rules:

- Use type hints on variables, parameters, and return types
- Script member ordering: class_name, extends, signals, enums, constants, @export vars, public vars, private vars, @onready vars, built-in overrides (`_ready`, `_process`, `_physics_process`), public methods, private methods

## Architecture

### Autoloads

Autoloads are Godot's global singletons — reachable from anywhere, which makes them easy to
overuse. Every autoload must represent a **genuinely application-wide concern with no better
natural owner**. The current autoloads are:

- `autoloads/game_events.gd` — **Signal bus**. All cross-system communication goes through here. Read this first to understand inter-system wiring.
- `autoloads/game_state.gd` — Global state machine. States: `MAIN_MENU`, `PLAYING`, `DIALOGUE`, `INVENTORY`, `COMBAT`, `PAUSED`, `LOADING`.
- `autoloads/save_manager.gd` — Save/load persistence. Reads and writes `PlayerDataResource` files to disk; also owns `GameSettings` (per-device preferences). Does **not** hold live game state.
- `autoloads/player_data.gd` — **Live game state** for the current save slot (inventory, gold, quests, map progress, etc.). A thin `Node` wrapper over a serializable `PlayerDataResource`. See `docs/features/game-data/design.md`.

Resist adding more autoloads. If a new system needs persistent state, check whether it belongs in
`PlayerData` first. Only add an autoload when a system is *genuinely* application-wide with no
natural owner — and document the justification in CLAUDE.md when you do.

### Dependency injection over direct autoload access

Classes should generally **not** reach for autoloads directly. Instead, a scene orchestrator (the
world scene, a level root, or a menu controller) reads from autoloads and **injects** the specific
data a node needs right after the game is loaded. This keeps individual nodes testable in
isolation — a unit test can pass in a plain `Inventory.new()` without standing up the full autoload
graph.

**Preferred — receive dependencies via a setup method:**

```gdscript
# ForageableBush.gd — no knowledge of global state
var _inventory: Inventory = null

func setup(inventory: Inventory) -> void:
    _inventory = inventory

func _on_harvested() -> void:
    _inventory.add(berry, 2)
    GameEvents.inventory_changed.emit()
```

**Avoid in leaf nodes — couples the class to global state, breaks hermetic tests:**

```gdscript
func _on_harvested() -> void:
    PlayerData.inventory.add(berry, 2)  # hard to unit test
```

Exceptions where direct autoload access is acceptable:

- **`GameEvents` signal emissions** — signals are inherently cross-cutting; there is nothing to inject.
- **`GameState.current_state` reads** — checking the current mode in `_process` is fine.
- **Scene orchestrators** (world.gd, level root, main menu) — their explicit job is wiring the scene graph from the available autoloads, so touching autoloads directly is correct.

In tests, call `PlayerData._load_resource(PlayerDataResource.new())` in `before_each()` to give
the autoload a clean state, or skip the autoload entirely by injecting a sub-resource (e.g. a bare
`Inventory`) directly into the node under test.

### Script co-location
Scripts live alongside their scene in the same folder (e.g. `player/player.gd` next to `player/player.tscn`). Shared base classes live in a `shared/` subfolder within the relevant area.

`shared/interactable.gd` is the base class for all interactable world objects.

### Signal bus pattern
Prefer direct node references and `$Node` paths for parent/child communication within a scene. Use `GameEvents` only for cross-scene or cross-system events where a direct reference isn't practical.

### Resources for data
Game data lives in `.tres` resource files backed by `.gd` resource classes: `ItemData`, `CharacterStats`, `NpcData`, `AbilityData`. Always call `stats.duplicate()` at runtime — never share a `.tres` instance between multiple characters.

### Depth sorting
Y Sort must be enabled on `TileMapLayer` nodes **and** their parent `Node2D`. Use `TileMapLayer` — `TileMap` is deprecated in Godot 4.3+.

### UI during pause
Set `process_mode = ALWAYS` (value `3`) on all `CanvasLayer` nodes so UI remains responsive when the game is paused.

### Resources folder
Assets live in `resources/`, organized by type (`tilesets/`, `sprites/`, `sounds/`, `music/`, `fonts/`, `data/`). Add subfolders within a type when helpful, but keep the top-level grouping by type.

There is also an `art/` folder with original game assets from which resources are derived. Never reference this folder in code or configuration files directly, unless it is to automate the creation of resources from the original assets.
