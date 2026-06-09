---
description: Run the project's end-to-end visual scenarios via the testing sandbox
argument-hint: "[optional feature folder or scenario name]"
---

Run the project's **e2e** scenarios using the `testing-sandbox` MCP tools (these are driven by you reading scenario docs and driving the game — not by GUT).

Scope (optional): `$ARGUMENTS`
- If given, limit to the matching feature folder or scenario under `tests/e2e/`.
- If empty, run the core scenario for each feature folder under `tests/e2e/`.

For each scenario:
1. `launch_game` (and `load_scene` / `emit_game_event` to set up preconditions).
2. Drive the numbered steps with the input + observation tools, using `wait_frames` to let things settle.
3. Compare the result against the committed reference baselines under `tests/e2e/<feature>/screenshots/` (or `baselines/`). Save any transient/comparison frames to the gitignored `.godot-test-reports/e2e/` — never into the committed `tests/e2e/` tree.
4. `reset_state` / `stop_game` between scenarios.

Then report per-scenario pass/fail and surface any mismatching screenshots side by side.

Note: e2e is slow and brittle relative to GUT. For quick logic checks prefer `/godot-testing:run-unit` or `/godot-testing:run-integration`.
