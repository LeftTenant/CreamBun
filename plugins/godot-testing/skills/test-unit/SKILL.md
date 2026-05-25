---
name: test-unit
description: Write or run isolated GDScript unit tests using the GUT framework. Trigger when the user asks for "unit tests", "test this function/class/resource", or after a self-contained piece of GDScript logic (a pure function, a Resource subclass, or a single-node script with no scene dependencies) has been written. Skip for tests that span multiple systems, autoloads, or full scenes — use the test-integration or test-e2e skill instead.
---

# Unit testing skill (Godot 4.4 / GUT)

Unit tests verify isolated GDScript logic in `tests/unit/`. They do **not** instantiate scenes, do **not** rely on autoload state, and do **not** drive the game — for those, see the integration and e2e skills.

## When to use this skill

- A pure function or method on a single class needs verification
- A `Resource` subclass (e.g. `ItemData`, `CharacterStats`) needs duplication, validation, or default-value tests
- A small node script with no scene dependencies needs its public API tested

If the test would need to load a scene, mount an autoload, or simulate input, **stop and use a different skill**.

## What to do

1. **Read the target** — open the script under test, list its public methods/properties, and identify what behavior the user actually cares about. Skip getters/setters that wrap a simple variable.
2. **Delegate or write directly**:
   - For more than one or two test files, or when the work overlaps with integration/e2e coverage, invoke the `godot-test-engineer` agent with the target file paths and "unit tests only" scope.
   - For a single tightly-scoped file, write the test inline.
3. **Place the file** at `tests/unit/<mirrored-source-path>/test_<subject>.gd`, mirroring the source folder structure.
4. **Follow project conventions**:
   - File starts with `class_name TestSubject` (optional) and `extends GutTest`
   - Type hints on all variables, params, and return types
   - `autofree(obj)` or `add_child_autofree(node)` to prevent leaks
   - Each test method named `test_<behavior_being_verified>()`
   - Arrange / act / assert structure
   - Use `gut.p("...")` for diagnostic output
   - Comments explain WHY non-obvious assertions matter, not WHAT they check
5. **Run the tests** via the `run_gut_tests` tool on the `testing-sandbox` MCP server. Pass the test directory or specific file paths — the tool handles locating the Godot binary and building the headless command. Read the output, fix failures, re-run until green.
6. **Report**: list new files, summarize coverage, and call out any bugs the tests uncovered in the code under test.

## Resource-duplication trap

For any test that touches a `.tres` resource, always call `.duplicate()` before mutating — sharing a `.tres` instance between tests causes state to bleed across runs. This is project convention; never share a resource between characters.

## Anti-patterns

- Mocking the system under test
- Testing private methods directly (test through the public API)
- Asserting framework behavior (e.g. that GDScript types work) instead of project behavior
- Padding coverage with one-liner tests that re-prove the same thing
