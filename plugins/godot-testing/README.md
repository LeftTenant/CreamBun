# godot-testing

A Claude Code plugin that enables visual end-to-end testing for Godot 4 projects, plus an agent and skills for writing GUT-based unit and integration tests.

## What it does

- **MCP server (`testing-sandbox`)** — exposes the running Godot game to Claude Code as a set of tools: capture viewport screenshots, inject input events, read scene-tree state, drive scenes from a clean slate. All routed through an in-process HTTP server bound to `127.0.0.1` in debug builds only — never touches the host desktop.
- **`godot-test-engineer` agent** — writes test plans, GUT unit/integration tests, and Markdown e2e scenarios; runs them remotely.
- **Three skills** — `test-unit`, `test-integration`, `test-e2e` — auto-trigger when the user asks for that flavor of test.

## Architecture

```
Claude Code  →  MCP stdio  →  server/launch.sh
                                    │
                                    ▼  spawns
                              server/mcp_server.py  ←─ Python MCP server
                                    │
                                    ▼  HTTP POST localhost:9080
                              godot/testing_server.gd  ←─ GDScript autoload
                                    │
                                    ▼  Input.parse_input_event / get_viewport()
                              The running Godot game
```

The autoload lives at `godot/testing_server.gd` inside the plugin and is registered in the host project's `project.godot` as `res://plugins/godot-testing/godot/testing_server.gd`.

## Installation

This plugin ships from a local marketplace declared at the repo root (`.claude-plugin/marketplace.json`). The repo's `.claude/settings.json` enables it by default, so contributors who clone the project will be prompted to install it on first launch.

To install manually:

```
/plugin marketplace add ./
/plugin install godot-testing@creambun-local
```

## First-run setup

The MCP server's bash launcher (`server/launch.sh`) auto-creates a project-local Python venv and installs `mcp` from `server/requirements.txt` on first invocation. No manual `pip install` step. The venv is gitignored and lives at `server/.venv/`.

The launcher also reinstalls when `requirements.txt` changes (tracked by sha256), so updating dependencies is a one-line `requirements.txt` edit.

## MCP tools

15 tools live under `mcp__testing-sandbox__*`:

| Group | Tools |
|---|---|
| Lifecycle | `launch_game`, `stop_game`, `reset_state` |
| Observation | `screenshot`, `get_game_state`, `get_node_property` |
| Input | `press_action`, `release_action`, `press_key`, `mouse_button_press`, `mouse_button_release`, `mouse_move` |
| Setup | `emit_game_event`, `load_scene`, `wait_frames` |

See `docs/testing-sandbox.md` (in the host project) for the full protocol and scenario format.

## Configuration

Defaults are auto-detected:

- **Project path** — derived by walking up from `server/mcp_server.py` looking for `project.godot`. Override with `GODOT_PROJECT_PATH`.
- **Godot binary** — probed at common macOS / Linux locations, then `which godot4` / `which godot`. Override with `GODOT_BIN`.
- **Server port** — `9080`. Override with `TESTING_SERVER_PORT` (must match the port the in-Godot autoload binds, currently hardcoded in `godot/testing_server.gd`).

Set overrides in the plugin's `.mcp.json` `env` block.

## Safety

- The HTTP server only starts when `OS.is_debug_build()` is true. Compiled out of release builds.
- Bound to `127.0.0.1` only.
- Input is injected via `Input.parse_input_event()` — confined to Godot's input queue. Cannot affect any other application.
- `emit_game_event` only emits signals already declared on the `GameEvents` autoload. No arbitrary code execution.
- `get_node_property` is read-only by design.
