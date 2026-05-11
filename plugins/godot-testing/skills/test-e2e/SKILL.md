---
name: test-e2e
description: Write or execute end-to-end visual scenarios that drive the running Godot game via the testing-sandbox MCP server (input injection + viewport screenshots). Trigger when the user asks for "e2e tests", "visual tests", "scenario tests", or wants to verify a complete user-visible behavior (input → game → UI). Skip when the behavior can be verified without rendering or simulated input — use test-unit or test-integration instead.
---

# End-to-end testing skill (Godot 4.4 / testing-sandbox MCP)

E2E tests verify the *experience*: that the running game looks and behaves correctly when driven the same way a player drives it. They live in `tests/e2e/<feature>/<scenario>.md` as Markdown scenario documents. Reference screenshots live alongside in `tests/e2e/<feature>/screenshots/`.

## When to use this skill

- A user-visible flow (open notebook → click an item → see UI update) needs verification
- An animation, transition, or visual feedback needs to be observed
- A bug repro needs to be captured as a regression scenario

If the behavior can be verified by reading state or signals — **use test-integration**. If it's pure logic with no input/visual surface — **use test-unit**. E2E tests are the slowest and most brittle; reach for them sparingly.

## What you have access to (testing-sandbox MCP)

The plugin exposes these MCP tools (all prefixed `mcp__testing-sandbox__`):

| Tool | Purpose |
|---|---|
| `launch_game` | Start Godot; waits until the in-game testing server responds |
| `stop_game` | Kill the Godot process |
| `screenshot` | Capture the viewport (returns base64 PNG) |
| `press_action` / `release_action` | Inject Input Map actions (`move_left`, `interact`, etc.) |
| `press_key` | Inject a physical keycode for N frames |
| `mouse_button_press` / `mouse_button_release` / `mouse_move` | Pointer + drag |
| `wait_frames` | Block until N frames have elapsed (use after input!) |
| `get_game_state` | Read the current `GameState` enum name |
| `get_node_property` | Read a property from a node in the active scene |
| `emit_game_event` | Emit a signal on the `GameEvents` autoload (test setup) |
| `load_scene` | Replace the current scene |
| `reset_state` | Reload the current scene + reset `GameState` to PLAYING |

## Scenario file format

Each scenario is a Markdown document with three sections:

```markdown
# Scenario: <one-line description>

## Setup
- Load scene: res://path/to/scene.tscn
- Wait: 10 frames

## Steps

### Step 1: <observable description>
- Press action: <action_name>
- Wait: 5 frames
- Screenshot → save / compare reference: step_01_<descriptor>.png
- Assert: GameState == PLAYING
- Assert: node property <Path>.<property> == <expected>

### Step N: <next observable>
...
```

Each numbered step is independently auditable: an input or setup line, a settle wait, then assertions and/or a screenshot capture.

## What to do

1. **Read the design doc / feature spec** — understand the intended player experience; that's the contract you are verifying.
2. **Decide scope** — usually one happy-path scenario per feature, plus one or two scenarios for notable edge cases the design doc calls out.
3. **Delegate or write directly**:
   - For multi-feature suites or coordinated unit/integration/e2e planning, invoke the `godot-test-engineer` agent with scope "e2e scenarios".
   - For a single scenario, write the Markdown inline.
4. **Write the scenario file** at `tests/e2e/<feature>/<scenario>.md`. Each step is a small, observable unit; favor more steps over fewer.
5. **Execute the scenario**:
   - Call `launch_game` (idempotent — no-ops if already running)
   - Call `load_scene` for the setup scene (skip booting through `MAIN_MENU` from scratch)
   - Use `emit_game_event` to set up preconditions (add inventory item, etc.) instead of replaying flows
   - Walk through the steps in order. Always call `wait_frames` after input (5–10 for UI, 30 for animations) before screenshotting or asserting
   - On the first run, save screenshots as `tests/e2e/<feature>/screenshots/<scenario>_step_NN_<descriptor>.png`. On subsequent runs, compare visually
   - Use `get_game_state` and `get_node_property` for hard assertions; screenshots catch visual regressions; property checks catch logic bugs
   - Call `reset_state` between scenarios in the same run
6. **Report**: pass/fail per step, paths to saved screenshots, any deviations from the design doc, and any bugs uncovered.

## Driving conventions

- **Always wait after input.** Animations and signal cascades take frames to settle. 5–10 frames for UI, 30 for animations.
- **Drag with explicit press → wait → move → release.** Call `mouse_button_press` at the source, `wait_frames` 1–2 (so Godot recognizes the drag gesture before the cursor leaves the origin), one or more `mouse_move` calls along the path, then `mouse_button_release` at the destination.
- **Prefer Input Map actions over raw keycodes.** Tests stay device-agnostic; bindings can change without rewriting scenarios.
- **Jump straight to the feature.** Don't replay through `MAIN_MENU` every time — `load_scene` + `emit_game_event` skips the prelude.

## Screenshot review

Screenshots are compared **qualitatively** by Claude (not pixel-diffed). On first run of a new scenario, save the captures as the baseline and tell the user that the references were established. On subsequent runs, inspect each screenshot and flag differences that look meaningful — a layout shift, a missing element, the wrong sprite — not subpixel rendering noise.

When in doubt, ask the user to eyeball the failing screenshot rather than guessing.

## Anti-patterns

- Driving the game without a scenario file ("just run a few inputs and screenshot")
- Skipping `wait_frames` after input ("the screenshot will be of the previous frame")
- Asserting only on screenshots when a `get_node_property` check is available (visual regressions are noisier than logic regressions)
- Committing screenshots without reviewing them — they ARE the spec for "what right looks like"
