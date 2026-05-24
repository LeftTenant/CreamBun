---
name: scene-migration-pattern
description: The _ensure_pages_built() pattern used in the notebook UI scene migration (Slice 1), its orphan trade-off, and conventions established for subsequent slices
metadata:
  type: project
---

## Pattern: extract page subtrees from a TAB_SCENE instantiation

`settings_tab.gd` introduces `_ensure_pages_built()`: instantiate `TAB_SCENE`, grab `LeftPage`/`RightPage` VBoxContainers via `get_node()`, call `remove_child()` on each, clear `.owner = null` on the two roots only (NOT recursive — children still carry old owner), `queue_free()` the shell instance, then cache the pages as `_left_page`/`_right_page`.

The two pages are later `add_child`'d into real page Controls inside `populate_left`/`populate_right`.

**Why:** notebook.gd only wants the page subtrees, not the bare root Control the .tscn carries. Extracting the subtrees lets the static layout live in the editor while the shell is discarded.

**Known trade-off — orphan warnings:** `_ensure_pages_built()` is called at the start of the FIRST `populate_*` call, which extracts BOTH pages simultaneously. The second page has no parent until the second `populate_*` call. In unit tests that call only one of `populate_left`/`populate_right`, the other page (and all its children) are GUT orphans for the test's lifetime. In production, `notebook.gd` calls both immediately in sequence so no orphan occurs. Accepted as cosmetic (~17 nodes per affected test).

**Owner clearing is NOT recursive:** Only `_left_page.owner = null` and `_right_page.owner = null` are set. Child nodes of those VBoxContainers still carry the old owner. This suppresses the top-level inconsistency warning Godot emits on add_child, but descendants may still warn. If Slices 2–5 show owner warnings deeper in the tree, consider a recursive owner-clear helper.

**Signal ordering in populate_left:** slider initial values are set BEFORE `value_changed` is connected. This prevents handlers from firing during init without needing `set_value_no_signal()`. The simpler approach is preferred here.

**OptionButton items at runtime:** `WindowScaleOption` is in the .tscn but its 4 items are added at runtime in `populate_right` because labels embed `ProjectSettings` viewport values. This is correct and documented.

**Constant naming quirk:** `TAB_SCENE` has no underscore (public-style constant, used only internally). `_WINDOW_SCALE_OPTIONS` has underscore prefix (project's private-member convention). GDScript style guide does not prefix private constants — apply consistently in Slices 2–5 (prefer no underscore on constants, or be consistent within each file).

**notebook.gd still uses `SettingsTab.new()`** (not `TAB_SCENE.instantiate()`). This is correct — the tab controller node is separate from the scene shell; `_ensure_pages_built()` instantiates the scene internally.

**Related:** [[project_patterns]]
