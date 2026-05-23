---
name: Tree-Pause Testing Pattern
description: How to safely test Notebook.open()/close() without leaking get_tree().paused into adjacent tests
type: feedback
---

When testing any feature that calls `get_tree().paused = true` (e.g. `Notebook.open()`), GUT itself is in the same tree and is affected by the pause.

**Pattern established in test_notebook_shell.gd:**

1. Declare the node under test as a class-level `var` (e.g. `var _notebook: Notebook`) so `after_each()` can reference it even if the test method threw an error.
2. In `after_each()`, always:
   - Call `close()` on the notebook if it is still visible (catch uncleaned test state).
   - Set `get_tree().paused = false` unconditionally (in case `close()` itself failed).
   - Call `GameState.change_state(GameState.State.PLAYING)` to reset state for the next test.
3. In `before_each()`, mirror the same resets for symmetry.

**Why:** If a test asserts something after `open()` and fails before reaching `close()`, the next test starts with a paused tree, which causes confusing cascading failures that look unrelated to the original failure.

**How to apply:** Use this same pattern for any future feature that pauses the tree (cutscenes, loading screens, etc.). The key is the class-level node var + unconditional unpause in `after_each()`.

**GUT note:** GUT's own node needs `process_mode = PROCESS_MODE_ALWAYS` (which the addon sets automatically) to keep running while the tree is paused. If tests hang after `open()`, check that GUT is installed correctly and not using PROCESS_MODE_INHERIT.
