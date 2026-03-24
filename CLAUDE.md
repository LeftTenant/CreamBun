# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

CreamBun is a cozy isometric RPG built in **Godot 4.4** using the **Mobile renderer**. The player character is Cream Bun — a small round creature who forages ingredients, brews drinks, and sells them at market. No combat; no enemies. The tone is cozy life-sim.

## Development

Open the project in Godot 4: `/Applications/Godot.app` or edit files directly in VSCode where coding convenience is desired (configured in `.vscode/settings.json`).

There is no build CLI — all iteration happens in the Godot editor. Scripts can be edited externally; Godot hot-reloads them. The `.godot/` cache directory is gitignored.

This is a beginner project, so always keep things as simple as possible. Favor easy to read and understand code over efficiency unless implementing code in critical sections of the game loop that demand performance. Document code well and explain why code is written as it is, not just what is implemented.

## Architecture

### Autoloads (3 only)
- `autoloads/game_events.gd` — **Signal bus**. All cross-system communication goes through here. Read this first to understand inter-system wiring.
- `autoloads/game_state.gd` — Global state machine. States: `MAIN_MENU`, `PLAYING`, `DIALOGUE`, `INVENTORY`, `COMBAT`, `PAUSED`, `LOADING`.
- `autoloads/save_manager.gd` — Save/load persistence.

### Script co-location
Scripts live alongside their scene in the same folder (e.g. `player/player.gd` next to `player/player.tscn`). Shared base classes live in a `shared/` subfolder within the relevant area.

`shared/interactable.gd` is the base class for all interactable world objects.

### Signal bus pattern
Prefer direct node references and `$Node` paths for parent/child communication within a scene. Use `GameEvents` only for cross-scene or cross-system events where a direct reference isn't practical.

### Resources for data
Game data lives in `.tres` resource files backed by `.gd` resource classes: `ItemData`, `CharacterStats`, `NpcData`, `AbilityData`. Always call `stats.duplicate()` at runtime — never share a `.tres` instance between multiple characters.

### Isometric depth sorting
Y Sort must be enabled on `TileMapLayer` nodes **and** their parent `Node2D`. Use `TileMapLayer` — `TileMap` is deprecated in Godot 4.3+.

### UI during pause
Set `process_mode = ALWAYS` (value `3`) on all `CanvasLayer` nodes so UI remains responsive when the game is paused.

## Folder Structure

Scenes, scripts, and resources are co-located by area:

- `player/` — player scene, script, and related resources
- `world/` — world scene, map logic; `art/tilesets/` for tile assets
- `npc/` — NPC scenes, scripts; `resources/character/` for `NpcData`/`CharacterStats`
- `ui/` — all UI scenes and scripts
- `combat/` — combat logic and `resources/combat/`
- `autoloads/` — the 3 autoload scripts

## Code Style

GDScript files use **tabs** for indentation (size 4). All files use LF line endings and UTF-8. See `.editorconfig` for the full ruleset.

## Input Actions

Defined in `project.godot`:
- Movement: `move_up`, `move_down`, `move_left`, `move_right` (WASD + arrows)
- `interact` — E / Space
- `open_inventory` — I / Tab
- `pause` — Escape
