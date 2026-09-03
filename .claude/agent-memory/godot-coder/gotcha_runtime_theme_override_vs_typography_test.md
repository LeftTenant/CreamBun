---
name: runtime-theme-override-vs-typography-test
description: Adding a runtime font_color override in _update_display()/_ready() can flip an existing test_notebook_typography.gd assertion that reads the color via add_child_autofree()
metadata:
  type: project
---

When a notebook UI script (e.g. `equipment_slot.gd`) starts setting a per-node
`theme_override_colors/font_color` at runtime (via `add_theme_color_override()` in
`_ready()`/`_update_display()`), any existing `tests/unit/ui/notebook/test_notebook_typography.gd`
test that asserts that same Label's color via `_make_instance()` will start reading the
**runtime** value, not the `.tscn`-baked one — because `_make_instance()` uses
`add_child_autofree()`, which enters the tree and runs `_ready()`.

**Why:** properties are applied at `instantiate()`; `_ready()` (and any override logic inside it)
only runs on tree entry. `_make_instance()` intentionally enters the tree so `@onready` refs
resolve — but that means it can no longer distinguish "the .tscn bakes this color" from "the
script recomputes this color at runtime from some default (e.g. unset/empty) state."

**How to apply:** when adding a fill-state- or selection-driven color branch to a Label already
covered by a typography test, check whether that test's fixture ever calls `setup()`/equivalent
before asserting. If it doesn't (default/never-configured state), the assertion may now be
reading the "empty" branch instead of the "populated" one it was written to check — fix the test
by driving the node into the state the assertion name describes (e.g. call `setup(slot, item)`
before asserting the "populated" color), not by changing the implementation to match the stale
assertion. See `.claude/agent-memory/code-reviewer/gotcha_runtime_theme_override_vs_scene_guard.md`
for the fuller writeup (this is the same fact, recorded for implementation-time awareness rather
than review-time).

## Related

[[feedback_enum_rename_partial_test_coverage]] — same root shape: an out-of-scope existing test
can silently start failing (or, here, start asserting the wrong branch) once new code touches
state it reads.
