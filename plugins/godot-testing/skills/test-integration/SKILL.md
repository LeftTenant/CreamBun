---
name: test-integration
description: Write or run cross-system Godot integration tests using GUT. Trigger when the user asks for "integration tests" or when a behavior under test spans multiple systems — autoload signal flows, scene instantiation with multiple wired nodes, autoload interactions, or save/load round-trips. Skip for single-class logic (use test-unit) and for full-game user-visible behavior (use test-e2e).
---

# Integration testing skill (Godot 4.4 / GUT)

Integration tests verify cross-system flows in `tests/integration/`. They DO instantiate small scene fragments, DO touch autoloads (signal bus, game state, save manager), but DO NOT drive the full game loop with input — that's the e2e skill.

## When to use this skill

- A signal bus flow needs verification end-to-end (emitter → autoload → listener)
- A scene with multiple wired nodes needs to be tested as a unit
- An autoload interaction needs verification (e.g. inventory updates fire `inventory_changed`, which the HUD picks up)
- A save/load round-trip needs to preserve state correctly

If the behavior is contained to a single class with no scene or autoload dependency, **use the test-unit skill instead**. If verification requires actually rendering the screen or driving keyboard/mouse input, **use the test-e2e skill instead**.

## What to do

1. **Read the target systems** — identify the entry point (function call, signal emission, scene instantiation) and the observable side effects (signal emissions, autoload state changes, node tree mutations).
2. **Delegate or write directly**:
   - For multi-file suites or coordinated planning across unit/integration/e2e, invoke the `godot-test-engineer` agent with scope "integration tests" and the relevant file paths.
   - For a focused single-file integration test, write inline.
3. **Place the file** at `tests/integration/<feature>/test_<flow>.gd`, organized by feature rather than mirroring source paths.
4. **Setup conventions**:
   - `before_each()` resets autoload state (e.g. clear inventory, reset `GameState.current_state`)
   - `after_each()` cleans up: `queue_free` any leftover scenes, disconnect signal listeners, restore mutated `.tres` resources to their saved-on-disk version
   - Use `add_child_autofree(scene_root)` for scene fragments to ensure they exit the tree at test end
5. **Signal verification**:
   - Call `watch_signals(autoload_or_node)` BEFORE the act phase
   - Assert with `assert_signal_emitted(obj, "signal_name")` and, when args matter, `assert_signal_emitted_with_parameters(obj, "signal_name", [expected_args])`
6. **Autoload state**:
   - Read `GameState.current_state` (or equivalent) to assert state transitions
   - Mutate via the public API the system uses, not by setting fields directly — that's what's being verified
7. **Run via the `run_gut_tests` tool** on the `testing-sandbox` MCP server. Pass the test directory or specific file paths — the tool handles the Godot binary and headless command. Read the output; fix failures; re-run until green.
8. **Report**: list new files, summarize the flows covered, call out bugs.

## Tree-pause / process_mode awareness

If the system under test pauses the scene tree (`get_tree().paused = true`), GUT itself runs inside that tree. Make sure the test cleans up by un-pausing in `after_each()`, and that any `CanvasLayer` involved has `process_mode = ALWAYS` (value 3) so it can be observed while paused.

## Anti-patterns

- Re-testing what unit tests already cover (don't re-verify pure logic in an integration test)
- Skipping `before_each()` reset and relying on test order
- Asserting on private autoload fields instead of public signals/properties
- Using full e2e drive (input injection, screenshots) when an integration test would suffice
