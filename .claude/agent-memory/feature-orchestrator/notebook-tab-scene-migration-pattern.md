---
name: notebook-tab-scene-migration-pattern
description: Reusable per-slice test/impl shape for the notebook-ui-scene-migration refactor (one slice per tab); what the migrated Slice 2 Inventory pattern looks like
metadata:
  type: project
---

The `notebook-ui-scene-migration` refactor ships as 5 vertical slices, one per notebook tab (Settings, Inventory, Quests, Sessions, Map). Slices 1/2/5 shipped; Slice 3 (Quests) and 4 (Sessions) follow.

**Why:** beginner devs cannot understand a notebook tab whose layout is built entirely in GDScript `populate_left/right`. Each slice moves static layout into the `<tab>_tab.tscn` (and row `.tscn`) so the editor shows the layout.

**How to apply (the established Slice 2 / Inventory pattern — copy it exactly for later slices):**
- Tab scene root keeps the tab script + `class_name`, type stays `Control`, grows named `LeftPage` / `RightPage` child subtrees (VBoxContainer) built in the editor.
- `populate_left/right` REPARENT the LeftPage/RightPage subtree into the passed parent and call `set_anchors_and_offsets_preset(PRESET_FULL_RECT)`; they resolve named-node refs per call (not `@onready`, because tree shape is per-call). Null-guard preserved per `NotebookTab` contract.
- Row scenes get static children in the `.tscn`; row scripts convert to `@onready var _x := $Path` and drop `_ready()` build code.
- Row construction in the tab switches from `RowClass.new()` to `preload("res://.../row.tscn").instantiate()`.
- Tests mirror Slice 2: `test_<tab>_scene.gd` + `test_<row>_scene.gd` (scene-as-data contract, load PackedScene + `find_child(name, true, false)` + type asserts), behavior tests stay public-API/signal/label-text-recursion based (NOT node paths), plus a capture-on-first-run visual e2e baseline under `tests/e2e/notebook-ui-scene-migration/baselines/`.
- e2e observes `GameEvents.notebook_tab_changed` signal, never `Notebook._current_tab`. Visual baseline captured on first run (Mobile renderer sub-pixel variance), 2% pixel tolerance.
- Existing behavior tests that did `RowClass.new()` must switch to scene instantiation (the one expected test-helper edit per slice).

Reference files: `ui/notebook/inventory/inventory_tab.tscn|.gd`, `inventory_row.tscn|.gd`, `tests/unit/ui/notebook/inventory/test_inventory_tab_scene.gd`, `test_inventory_row_scene.gd`, `tests/e2e/notebook-ui-scene-migration/inventory_tab_visual.md`.

**Cross-slice consistency standard (the canonical shape is Inventory's `populate_left/right`):** every tab's populate methods do `set_anchors_and_offsets_preset(PRESET_FULL_RECT)` then a uniform 10px inset (`offset_left/top = 10`, `offset_right/bottom = -10`). Map (Slice 5) shipped WITHOUT the insets ("preserve original map_tab.gd behaviour") — this is the one known divergence; a tidy-up pass should bring it in line. No notebook test asserts an editor-baked anchor preset on the page-root container, so adding `anchors_preset = 15` (PRESET_FULL_RECT) to LeftPage/RightPage in the `.tscn` for editor legibility is test-safe; keep the runtime `set_anchors_and_offsets_preset` call too (belt-and-suspenders, and it re-applies insets). `test_settings_tab_layout.gd` DOES assert sliders are `SIZE_EXPAND_FILL`. Narrow-column descriptive Labels (e.g. Map's "...coming in Phase 2." notes, inventory_row NameLabel) get `autowrap_mode = AUTOWRAP_WORD_SMART (3)`; short headers/captions ("Audio", "World Map", "Master Volume") must NOT autowrap (triggers Godot's "needs custom minimum size" warning — ui/CLAUDE.md rule 4).
