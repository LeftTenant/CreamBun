# Notebook UI: Move Static Layout from Code into Scenes

**Status: Complete.** Shipped one tab per PR — Settings (`460d322`), Inventory
(`44aa800`), Quests (`1dd41f7`), Sessions (`96d737b`); Map landed alongside. This file
is the durable record of *why* the refactor happened and *what shape the code now has*,
so future work doesn't reintroduce the problem it fixed.

## Why this was done

Every notebook tab `.tscn` (`settings_tab.tscn`, `inventory_tab.tscn`, `quests_tab.tscn`,
`sessions_tab.tscn`, `map_tab.tscn`) used to be an empty `Control` + script, with ~1,000
lines of GDScript across `ui/notebook/**/*.gd` building the entire layout at runtime in
`populate_left()` / `populate_right()`. The row/card scenes (`quest_row.tscn`,
`inventory_row.tscn`, `equipment_slot.tscn`, `story_card.tscn`) were empty too — row
scripts built their own labels and buttons in code, and tabs instantiated rows via
`RowClass.new()` instead of loading the `.tscn`.

CreamBun is a beginner-friendly project, and this was actively hostile to that goal: a
beginner opening any tab in the editor saw a blank node and learned nothing. They could
not drag a slider, retype a label, or change a font without reading GDScript, and the
hard-won layout rules in `ui/CLAUDE.md` (PRESET_FULL_RECT, autowrap, EXPAND_FILL on
`HSlider`) lived as scattered imperative calls instead of editor checkboxes.

**Takeaway for future design:** notebook tab/row layout that is the same every time the
tab is shown belongs in the `.tscn`, authored in the editor — not constructed in
`populate_*`. Keep new tabs/rows on this side of the line.

## What changed — the architecture now in place

- **Static structure lives in scenes.** Each `<tab>_tab.tscn` (and its row/card scenes)
  is built in the editor with real `VBoxContainer`s, section `Label`s, `HSlider`s,
  `OptionButton`s, `Button`s, `ScrollContainer`s, etc., with stable node names
  (`MasterSlider`, `EquipmentSlots`, `RowsContainer`, `TitleLabel`, …) the scripts resolve.
- **Two-page tabs** grow named `LeftPage` / `RightPage` child subtrees in the tab scene;
  single-page tabs (Settings, Map) need only one.
- **`populate_left(parent)` / `populate_right(parent)` shrank to data binding + wiring.**
  They instantiate the tab scene (`const TAB_SCENE = preload(...)`), reparent the relevant
  page subtree into `parent`, and call `set_anchors_and_offsets_preset(PRESET_FULL_RECT)`
  (+ ~10 px insets). Named-node refs are resolved inside `populate_*` (not `@onready`,
  because the tree shape is per-call), signals are wired once per build, and rows are
  created with `ROW_SCENE.instantiate()` instead of `RowClass.new()`.
- **`notebook.gd` still builds tabs via `TabClass.new()`**, not scene instantiation — so a
  tab scene's *root* node and its authored root-level layout are editor-preview only and
  are never mounted in-game. Only the `LeftPage`/`RightPage` subtrees the tab extracts are
  used at runtime. (See the editor-preview policy in agent memory before authoring tab
  scenes.)
- **Notebook root** (`notebook.tscn` / `notebook.gd`) and the shared
  `shared/notebook_tab.gd` / `shared/page_panel.gd` contracts were intentionally left
  unchanged; the `populate_left/right(parent)` contract is preserved by every tab.

## What "done" looks like

- A new engineer can open `settings_tab.tscn` in Godot and see the sliders without running
  the game.
- Adding a setting is "drag a Label + HSlider into the scene, name them, add a few lines to
  the script" — not "read hundreds of lines of build code to find the pattern."
- Coverage lives in `tests/unit/ui/notebook/**` (scene-contract + behavior),
  `tests/integration/notebook/**` (open → tab-switch flows), and `tests/e2e/notebook/**`
  (behavioral scenarios).
