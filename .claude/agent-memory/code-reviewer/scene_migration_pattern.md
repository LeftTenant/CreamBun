---
name: scene-migration-pattern
description: The notebook-tab _ensure_pages_built() page-extraction pattern, its orphan trade-off, and the surrounding durable conventions
metadata:
  type: project
---

The notebook tabs keep their static layout in `.tscn` files, but `notebook.gd` only wants
the `LeftPage`/`RightPage` subtrees, not the tab scene's bare root. The pattern below is the
established way to bridge that; treat its trade-offs as intentional.

## Pattern: extract page subtrees from a TAB_SCENE instantiation

`_ensure_pages_built()` (in the tab scripts): instantiate `TAB_SCENE`, grab the
`LeftPage`/`RightPage` `VBoxContainer`s via `get_node()`, `remove_child()` each, clear
`.owner = null` on the two roots, `queue_free()` the shell, and cache the pages as
`_left_page`/`_right_page`. `populate_left`/`populate_right` later `add_child` each page into
the real page `Control` and apply `PRESET_FULL_RECT`.

Note: `notebook.gd` builds the tab *controller* with `TabClass.new()` — that is separate from
the scene shell, which `_ensure_pages_built()` instantiates internally. Both coexist by design.

## Durable trade-offs & conventions

- **Orphan warnings are expected in single-page unit tests.** `_ensure_pages_built()` extracts
  BOTH pages on the first `populate_*` call, so a test that calls only `populate_left` (or only
  `populate_right`) leaves the other page + children as GUT orphans for the test's lifetime. In
  production `notebook.gd` calls both in sequence, so no orphan occurs. Cosmetic; don't flag.
- **Owner clearing is not recursive.** Only the two page roots get `.owner = null`; descendants
  keep the old owner. This silences the top-level `add_child` inconsistency warning but deeper
  nodes may still warn — a recursive owner-clear helper is the fix if that surfaces.
- **Set initial widget values BEFORE connecting `value_changed`** so handlers don't fire during
  init — preferred over `set_value_no_signal()`.
- **Re-entrancy guards** (populate may be called twice on the same instance): reparent with
  `if node.get_parent() != null: node.get_parent().remove_child(node)` before `add_child`;
  guard signals with `if not sig.is_connected(handler)`; guard `OptionButton` items with
  `if get_item_count() == 0`.
- **Runtime-populated `OptionButton` items** (e.g. a window-scale option whose labels embed
  `ProjectSettings` values) are correct to add in `populate_*` rather than the `.tscn`.
- **`free()` (not `queue_free()`) for stale leaf widgets in rebuild paths** (rows, cards): they
  have no deferred logic and tests need them gone synchronously before inspecting the subtree.

## Related

[[project_patterns]]
