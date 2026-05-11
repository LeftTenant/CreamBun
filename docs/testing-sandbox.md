# Visual Testing Sandbox

A lightweight system for running the game, capturing screenshots, and injecting input — all scoped to the Godot process with no OS-level desktop access.

---

## Why This Approach

Automated game testing requires two capabilities: observing what the game looks like, and driving it with input. The naive approach — OS-level screenshot tools and input injection — can accidentally target any window on the desktop. Instead, this system routes both directions entirely through Godot:

- **Screenshots** are captured inside Godot from the active viewport texture. No screen capture tools needed.
- **Input** is injected as `InputEvent` objects directly into Godot's input queue. No keyboard/mouse emulation needed.

All of this is exposed over a local HTTP server that only runs in debug builds on `127.0.0.1`. An MCP server wraps that HTTP API and exposes it as Claude Code tools, so any agent in this project can drive the game programmatically.

---

## Components

```
┌─────────────────────────────────────────────────┐
│  Claude Code / Agent                            │
│                                                 │
│  calls MCP tools:                               │
│   screenshot, press_action, get_state, ...      │
└────────────────────┬────────────────────────────┘
                     │  MCP (stdio)
┌────────────────────▼────────────────────────────┐
│  MCP Server  (testing/mcp_server.py)            │
│                                                 │
│  Thin wrapper — translates MCP tool calls       │
│  into HTTP POST requests to localhost:9080      │
└────────────────────┬────────────────────────────┘
                     │  HTTP JSON  (localhost only)
┌────────────────────▼────────────────────────────┐
│  Godot Testing Plugin  (testing/testing_server.gd) │
│                                                 │
│  Autoload. Active only in debug builds.         │
│  Accepts commands. Injects InputEvents.         │
│  Returns viewport screenshots as base64 PNG.    │
└─────────────────────────────────────────────────┘
```

### Godot Testing Plugin (`plugins/godot-testing/godot/testing_server.gd`)

An autoload script that opens a `TCPServer` listening on `127.0.0.1:9080`. It is only active when `OS.is_debug_build()` returns `true`, so it compiles away in release exports.

The server accepts HTTP POST requests with a JSON body. Each request contains a `command` field and optional parameters. Responses are JSON.

**Available commands:**

| Command | Parameters | Returns | Purpose |
|---|---|---|---|
| `screenshot` | — | `{ image: "<base64 PNG>" }` | Capture the current viewport frame |
| `press_action` | `action: String` | `{ ok: true }` | Press a named Input Map action |
| `release_action` | `action: String` | `{ ok: true }` | Release a named Input Map action |
| `press_key` | `keycode: int`, `duration_frames: int` | `{ ok: true }` | Press a physical key for N frames |
| `mouse_button_press` | `x: int`, `y: int`, `button: int` | `{ ok: true }` | Press a mouse button at viewport coordinates without releasing |
| `mouse_button_release` | `x: int`, `y: int`, `button: int` | `{ ok: true }` | Release a mouse button at viewport coordinates |
| `mouse_move` | `x: int`, `y: int` | `{ ok: true }` | Move mouse to viewport coordinates |
| `get_game_state` | — | `{ state: "PLAYING" }` | Read the current `GameState` enum name |
| `get_node_property` | `path: String`, `property: String` | `{ value: <any> }` | Read a property from a node in the active scene tree |
| `emit_game_event` | `signal_name: String`, `args: Array` | `{ ok: true }` | Emit a `GameEvents` signal (for test setup) |
| `load_scene` | `path: String` | `{ ok: true }` | Replace the current scene with a `.tscn` path |
| `wait_frames` | `count: int` | `{ ok: true }` | Block the response until N frames have elapsed |
| `reset_state` | — | `{ ok: true }` | Reload the current scene and reset `GameState` to `PLAYING` |

Input actions (`press_action` / `release_action`) use the names defined in Project Settings → Input Map (e.g. `"move_left"`, `"interact"`, `"open_notebook"`). This keeps tests device-agnostic.

### MCP Server (`plugins/godot-testing/server/mcp_server.py`)

A Python MCP server (stdio transport) that wraps each HTTP command as a named tool. The plugin's `.mcp.json` registers it with Claude Code automatically once the plugin is installed.

Each MCP tool maps 1:1 to a plugin command. Two additional tools are provided at the process level:

| MCP Tool | What it does |
|---|---|
| `launch_game` | Starts Godot with the project path; waits until the testing server responds |
| `stop_game` | Kills the Godot process |
| `screenshot` | Captures and returns a base64 PNG |
| `press_action` | Presses a named action |
| `release_action` | Releases a named action |
| `press_key` | Presses a keycode for N frames |
| `mouse_button_press` | Presses a mouse button at (x, y) without releasing — use before `mouse_move` for drags |
| `mouse_button_release` | Releases a mouse button at (x, y) |
| `mouse_move` | Moves the cursor to (x, y) |
| `get_game_state` | Returns the current GameState name |
| `get_node_property` | Reads a property from a scene node |
| `emit_game_event` | Fires a GameEvents signal |
| `load_scene` | Loads a scene by resource path |
| `wait_frames` | Waits N game frames |
| `reset_state` | Reloads the current scene |

---

## Setup

### 1. Install the Claude Code plugin

The repo ships a local Claude Code marketplace at `.claude-plugin/marketplace.json` that exposes a single plugin named `godot-testing` (under `plugins/godot-testing/`). The project-shared `.claude/settings.json` already lists the marketplace under `extraKnownMarketplaces` and enables the plugin by default — Claude Code will prompt to install on first launch.

To install manually from the project root:

```
/plugin marketplace add ./
/plugin install godot-testing@creambun-local
```

Once installed, the plugin's MCP server (`testing-sandbox`), the `godot-test-engineer` agent, and the three test skills (`test-unit`, `test-integration`, `test-e2e`) all become available to Claude.

### 2. Autoload + Python deps

No manual setup required:

- The Godot autoload is already registered in `project.godot` as `res://plugins/godot-testing/godot/testing_server.gd`. It compiles out of release builds via `OS.is_debug_build()`.
- The Python MCP server's bash launcher (`plugins/godot-testing/server/launch.sh`) auto-creates a project-local venv and installs `mcp` from `requirements.txt` on first invocation. The venv lives at `plugins/godot-testing/server/.venv/` and is git-ignored.

### 3. Verify

With the game open in the editor, press Play (`F5`). In a terminal:

```bash
curl -s -X POST http://localhost:9080 \
  -H "Content-Type: application/json" \
  -d '{"command":"get_game_state"}'
# → {"state":"PLAYING"}
```

To verify the MCP layer, restart Claude Code so it picks up the plugin, then call `mcp__testing-sandbox__get_game_state` from any agent.

---

## End-to-End Test Scenarios

### What E2E tests are

Unit and integration tests (in `tests/unit/` and `tests/integration/`) verify code logic in isolation using GUT. E2E tests verify the *experience* — that the game looks and behaves correctly when driven the same way a player would drive it.

E2E tests are **scenario documents**: structured Markdown files in `tests/e2e/`. Each scenario describes a sequence of game actions and the expected outcomes at each step. Claude (as the executor) reads the scenario, drives the game using MCP tools, captures screenshots, and reports whether the outcome matched.

### Scenario format

Scenarios live at `tests/e2e/<feature>/<scenario_name>.md`.

Each scenario file contains:

1. **Setup** — which scene to load and what initial state to establish
2. **Steps** — numbered actions (input) and checkpoints (assertions)
3. **Expected screenshots** — saved PNG references at `tests/e2e/<feature>/screenshots/<scenario>_step_N.png`

Example structure:

```markdown
# Scenario: Pick up an item from the forest floor

## Setup
- Load scene: `res://world/forest.tscn`
- Wait: 10 frames (let the scene settle)

## Steps

### Step 1: Observe item on ground
- Screenshot → save as reference `step_01_item_visible.png`
- Assert: node `World/ForageSpot` exists

### Step 2: Walk player to item
- Press action: `move_right` for 30 frames
- Screenshot → compare to `step_02_near_item.png`

### Step 3: Interact
- Press action: `interact`
- Wait: 5 frames
- Assert: GameState == `DIALOGUE`
- Screenshot → compare to `step_03_pickup_prompt.png`

### Step 4: Confirm pickup
- Press action: `ui_accept`
- Wait: 5 frames
- Assert: node property `Player/Inventory.item_count` == 1
- Assert: GameState == `PLAYING`
- Screenshot → compare to `step_04_item_in_inventory.png`
```

### Screenshot comparison

Screenshots are compared visually by Claude — not by pixel diff. Claude inspects each screenshot and determines whether the visual result matches the description in the scenario. Reference screenshots serve as a baseline for what "correct" looks like; Claude flags regressions when the current output deviates meaningfully.

On the first run of a new scenario (no reference screenshots exist yet), Claude captures and saves the screenshots as the baseline rather than comparing.

### How the `godot-test-engineer` agent uses this system

When building E2E coverage for a feature:

1. **Read the design doc** for the feature to understand the intended player experience.
2. **Launch the game** via `launch_game`.
3. **Explore the feature** interactively using MCP tools to understand what currently exists.
4. **Write the scenario** document at `tests/e2e/<feature>/<scenario>.md` covering the happy path and any notable edge cases from the design doc.
5. **Execute the scenario** step by step, capturing reference screenshots.
6. **Report findings**: pass/fail for each step, any deviations from the design doc, and the path to each saved screenshot.

When running existing E2E tests (e.g. after a code change):

1. **Launch the game**.
2. **Execute each scenario** in the relevant feature folder.
3. **Compare screenshots** to the saved references.
4. **Report**: which steps passed, which failed, and — for failures — include the current screenshot alongside the reference so the difference is immediately visible.

---

## Iterative Coding with the Sandbox

The sandbox changes the coding loop from *"write code → open editor → test manually → repeat"* to *"write code → Claude drives the game → compare to spec → iterate"*. This section describes how that loop works in practice.

### The design → code → validate loop

```
Design doc
    │
    ▼
godot-coder writes implementation
    │
    ▼
Launch game (launch_game)
    │
    ▼
Navigate to the feature
    │
    ▼
Take screenshots at each meaningful state
    │
    ▼
Compare screenshots + state to design doc description
    │
    ├─ Matches spec? → Done
    │
    └─ Mismatch? → Identify what's wrong
                      │
                      ▼
                 Edit the code (Godot hot-reloads GDScript)
                      │
                      ▼
                 Reset state (reset_state) and re-drive
                      │
                      ▼
                 Take screenshots again → compare again
```

### When to use hot-reload vs. restart

Godot hot-reloads `.gd` script changes automatically while the game is running. For pure logic changes, you can edit the script and then use `reset_state` (which reloads the current scene) without stopping and restarting the process.

For changes to `.tscn` scenes, resources (`.tres`), or autoloads, a full restart via `stop_game` + `launch_game` is required.

### How the `godot-coder` agent uses this system

After implementing a feature:

1. **Launch the game** via `launch_game`.
2. **Navigate to the feature**: load the relevant scene, drive the player to the right position, press actions to trigger the feature.
3. **Screenshot key states**: take a screenshot at each significant moment (feature trigger, mid-animation, outcome). Annotate each screenshot with what is being observed.
4. **Compare to the design doc**: describe what each screenshot shows and whether it matches the design spec's described experience. If the spec says "the player bounces with excitement when they find a rare ingredient", confirm that the animation plays.
5. **Iterate on mismatches**: make the code change, call `reset_state` (or restart if needed), re-drive, re-screenshot.
6. **Report**: summarize what was validated visually, include the final screenshots, and flag any design doc ambiguities that came up during validation (e.g. the spec describes an animation but doesn't specify its duration).

### Driving conventions

- Always call `wait_frames` after input actions before taking a screenshot. UI transitions, animations, and signal responses need at least a few frames to settle. 5–10 frames is usually enough; 30 frames for animations.
- Use `get_game_state` and `get_node_property` for hard assertions. Screenshots catch visual regressions; property checks catch logic bugs.
- To drag an item, use `mouse_button_press` at the source, one or more `mouse_move` calls along the path, then `mouse_button_release` at the destination. Call `wait_frames` between press and the first move so Godot recognises the drag gesture before the cursor leaves the origin.
- Use `load_scene` to jump straight to the feature under test rather than playing through the full game flow from `MAIN_MENU` each time.
- Use `emit_game_event` to set up preconditions (e.g. add an item to the player's inventory before testing the inventory screen) rather than playing through the flow that normally produces those conditions.

---

## Constraints and Safety

- The HTTP server only starts when `OS.is_debug_build()` is `true`. It is never active in an exported release build.
- The server binds to `127.0.0.1` only. It is not reachable from outside the local machine.
- Input injection is scoped to Godot's own input queue (`Input.parse_input_event`). It cannot affect other applications.
- `emit_game_event` only emits signals that exist on the `GameEvents` autoload. It cannot call arbitrary code.
- `get_node_property` is read-only. There is no `set_node_property` command by design — test setup should use `load_scene` and `emit_game_event` rather than mutating scene state directly.

---

## Limitations

- **No audio verification.** The sandbox cannot listen to game audio. Audio behavior must be verified by reading the code.
- **No physics timing guarantees.** Physics runs at a fixed timestep. `wait_frames` counts rendered frames, not physics ticks. For physics-dependent tests, wait enough frames to cover multiple physics steps (≥ 10).
- **Hot-reload does not reset state.** `reset_state` reloads the current scene but does not reset autoload state (`GameState`, `SaveManager`). For tests that need a clean autoload state, use `stop_game` + `launch_game`.
- **Screenshot comparison is qualitative.** Claude compares screenshots by inspection, not pixel diff. Subtle visual regressions (a 2px offset, a color shift) may be missed. For pixel-exact verification, a future extension could add a `compare_screenshot` command using Godot's `Image` class.
