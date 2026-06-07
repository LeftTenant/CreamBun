---
name: scene-migration-pattern
description: The _ensure_pages_built() pattern used in the notebook UI scene migration (Slices 1–2), its orphan trade-off, re-entrancy guards, and conventions for subsequent slices
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

## Slice 2 additions and confirmed conventions

**Re-entrancy guards confirmed (Slice 2):** Both `populate_left` and `populate_right` now guard against being called twice on the same instance. Pattern: `if node.get_parent() != null: node.get_parent().remove_child(node)` before `parent.add_child(node)`. Signal connections guarded with `if not signal.is_connected(handler)`. OptionButton items guarded with `if get_item_count() == 0`. These guards were backported to `settings_tab.gd` as part of the same PR.

**EQUIPMENT_SLOT_SCENE constant kept for documentation only:** `inventory_tab.gd` declares `const EQUIPMENT_SLOT_SCENE` even though the script never calls `instantiate()` on it at runtime (slots live in the .tscn as instanced children). This is a deliberate documentation choice. Future reviewers should not flag it as dead code without reading the comment.

**_scroll_container stored-but-unused var:** `_scroll_container` is resolved inside `populate_right()` and stored as a private var, but as of Slice 2 nothing else reads it. It is a forward provision; acceptable for Phase 1 but worth noting in later reviews if it is still unused by Slice 5.

**"B2 edit" breadcrumbs in test_inventory_tab.gd:** Each updated test has an inline `# B2 edit:` comment explaining the change from `.new()` to scene instantiation. These are migration-history comments, not spec documents. They are appropriate in test files (where future developers may wonder why the pattern changed) but should not appear in production scripts. This convention has been applied consistently throughout Slices 1–2.

**`_refresh_both_pages()` null safety removed intentionally:** After Slice 2 the empty-slots guard (`if not _equipment_slots.is_empty()`) was removed from `_refresh_both_pages()`. The loop body is a no-op when the array is empty, so the guard was redundant. Consistent with how `_rows_container` null check in `_build_right_page()` acts as the real guard for the right page.

## PR 5 (Map tab) — confirmed conventions and new observations

**Map tab is intentionally inset-free:** `map_tab.gd` calls `set_anchors_and_offsets_preset(PRESET_FULL_RECT)` but omits the 10-px offset block that `inventory_tab.gd` and `settings_tab.gd` apply. This is a deliberate preservation of the original map_tab.gd visual behaviour. The comment in the code explains it explicitly. Reviewers should not flag the omission as a defect.

**`size_flags_horizontal = 3` (EXPAND_FILL) set on all four Label nodes in `map_tab.tscn`:** Labels that might approach the column width carry `SIZE_EXPAND_FILL` per `ui/CLAUDE.md` rule 4. The two heading labels are short fixed strings and technically do not need it, but having it is not harmful (no autowrap, so no Godot warning). The note/phase-2 labels are the ones that actually benefit.

**Color equality: `Color(r,g,b)` vs `Color(r,g,b,1)` in GDScript:** Godot 4 `Color` equality treats `Color(0.2, 0.3, 0.2)` (alpha defaults to 1.0) as equal to `Color(0.2, 0.3, 0.2, 1)`. The tscn stores the 4-component form; test constants use the 3-component form. Tests pass correctly.

**`_ensure_pages_built()` guard uses `_left_page != null`:** The guard only checks `_left_page`. If somehow `_right_page` were null while `_left_page` were set (impossible in normal flow since both are assigned in the same block), the method would be a no-op and `_right_page` would stay null. This edge case is theoretical — both are set atomically in the same `_ensure_pages_built()` block, so no real risk. Pattern is consistent with InventoryTab and SettingsTab.

**Related:** [[project_patterns]]
