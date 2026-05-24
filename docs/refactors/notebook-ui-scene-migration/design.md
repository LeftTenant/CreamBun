# Notebook UI: Move Static Layout from Code into Scenes

## Context

CreamBun is a beginner-friendly project, but the notebook UI today is opaque in the Godot editor. Every tab `.tscn` (`settings_tab.tscn`, `inventory_tab.tscn`, `quests_tab.tscn`, `sessions_tab.tscn`, `map_tab.tscn`) is an empty `Control` + script, and ~1,000 lines of GDScript across `ui/notebook/**/*.gd` build the entire layout at runtime in `populate_left()` / `populate_right()`. The row scenes (`quest_row.tscn`, `inventory_row.tscn`, `equipment_slot.tscn`, `story_card.tscn`) are similarly empty — the row scripts build their own labels and buttons in code, and tabs instantiate rows via `RowClass.new()` rather than loading the `.tscn`.

The result: a beginner opening any of these scenes in the editor sees a blank node and learns nothing about the UI. They cannot drag a slider, retype a label, or change a font without reading GDScript. The hard-won layout rules captured in `ui/CLAUDE.md` (PRESET_FULL_RECT, autowrap, EXPAND_FILL on `HSlider`) are scattered through code as imperative calls instead of being editor checkboxes a reader can find by clicking nodes.

**Intended outcome:** every notebook tab and row is a scene a beginner can open in the editor and visually understand. Static structure lives in `.tscn` files; GDScript is reduced to data binding, signal wiring, and instantiation of repeated rows from their own scenes.

**Decisions confirmed with the user:**
- **Rollout:** one PR per tab. Settings first as proof of concept; tweak the pattern, then apply to inventory → quests → sessions → map.
- **Row scope:** flesh out row/card scenes alongside their tab. Inventory PR also migrates `inventory_row.tscn` + `equipment_slot.tscn`; quests PR migrates `quest_row.tscn`; sessions PR migrates `story_card.tscn`.
- **Notebook root (`notebook.tscn` and `notebook.gd`) is out of scope.** The two-page container (`Book/Pages/LeftPage`/`RightPage`) already lives in the scene and the `populate_left(parent)` / `populate_right(parent)` contract is preserved.

## The Pattern (applied once per tab)

Each tab today follows the same shape: the controller script subclasses `NotebookTab` (in `ui/notebook/shared/notebook_tab.gd`), and `populate_left(parent)` / `populate_right(parent)` build a `VBoxContainer` full of labels/sliders/buttons inside `parent`. We replace that with a loaded scene.

**Per tab, the migration is:**

1. **Build the layout in the editor.** Open `<tab>_tab.tscn`. Currently the root is an empty `Control`. Add the static structure as visible children: `VBoxContainer`s, section header `Label`s, `HSlider`s, `OptionButton`s, `Button`s, `ScrollContainer`s — everything the code currently constructs that is the same every time the tab is shown. Set anchors, offsets, `autowrap_mode`, `size_flags_horizontal/vertical`, `step`, `min_value`, `max_value` as editor properties. Give nodes stable names (`MasterSlider`, `EquipmentSlots`, `RowsContainer`, etc.) so the script can find them.
2. **If the tab populates both pages**, the tab scene root grows two named child Controls (`LeftPage`, `RightPage`). For single-page tabs (Settings, Map), one root child is enough.
3. **Rewrite the controller script.** Replace `populate_left(parent)` / `populate_right(parent)` with:
   - On first call, instantiate the tab scene's `LeftPage` / `RightPage` subtree (via `PackedScene.instantiate()` from a `const TAB_SCENE = preload("res://ui/notebook/<tab>/<tab>_tab.tscn")`), reparent into `parent`, and call `set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)` on the inserted root.
   - Resolve `@onready`-style references to named nodes (`get_node("MasterSlider")` etc.), but assigned inside `populate_*` rather than as `@onready` because the tree shape is now per-call.
   - Wire signals (`slider.value_changed.connect(...)`) once per build.
   - For rows, replace `RowClass.new()` with `ROW_SCENE.instantiate()`, where `ROW_SCENE` is `preload("res://ui/notebook/<area>/<row>.tscn")`.
4. **Flesh out the row scene** (for tabs that have rows). Open `<row>.tscn`, add the static children the row script currently builds in `_ready`. Convert the row script to `@onready var _label: Label = $Label` etc., and remove the `Label.new(); add_child(label)` lines.
5. **Update the layout-incantation comments in `ui/CLAUDE.md`.** The four rules still apply, but now they're settings on editor properties as well as runtime calls. Add a brief note: "When building in the editor, set `Anchor preset → Full Rect`, `Autowrap → Word, Smart` on Labels in narrow columns, and `Size Flags → Expand + Fill` on `HSlider`."
6. **Run the affected tests.** All existing tests use type-recursion or public-API/signal assertions — none rely on internal node paths — so the test changes should be small. The one risk: tests that instantiate a row with `RowClass.new()` directly will need to instantiate from the scene instead, because `@onready` references assume the scene has set up children. Update test helpers in `tests/unit/ui/notebook/<area>/test_*.gd` accordingly.

## Per-tab Notes

Listed in the recommended PR order. Each item is one PR.

### PR 1 — `ui/notebook/settings/`  (proof of concept; smallest)
- File: `settings_tab.tscn`, `settings_tab.gd`
- Static-only tab. Build two section header Labels (`Audio`, `Display`), 5 label-slider pairs (`MasterSlider`, `MusicSlider`, `SfxSlider`, `TextSpeedSlider`, plus the `WindowScaleOption` `OptionButton`), and two reset buttons inside a `VBoxContainer` with `PRESET_FULL_RECT` + 10 px insets.
- Script keeps the `_apply_settings()` / `_on_*_changed()` handlers — only the build code shrinks.
- Test: `tests/unit/ui/notebook/settings/test_settings_tab.gd` and `tests/integration/notebook/test_settings_tab_layout.gd`. Both should pass unchanged; if not, fix is local.

### PR 2 — `ui/notebook/inventory/` (largest; pattern stress-test)
- Files: `inventory_tab.tscn`, `inventory_tab.gd`, `inventory_row.tscn`, `inventory_row.gd`, `equipment_slot.tscn`, `equipment_slot.gd`
- Two-page tab. Left page: header + 6 equipment slot placeholders (named `Slot_BACKPACK` … `Slot_OFFHAND`) instantiated from `equipment_slot.tscn`. Right page: weight Label, `ScrollContainer`, `RowsContainer: VBoxContainer`, three footer buttons.
- Flesh out `equipment_slot.tscn` with whatever the script currently builds (icon Rect, label, drop target). Same for `inventory_row.tscn`.
- Change tab from `EquipmentSlot.new()` / `InventoryRow.new()` to `preload(...).instantiate()`.
- Tests in `tests/unit/ui/notebook/inventory/` may need helper updates if they `.new()` rows directly.

### PR 3 — `ui/notebook/quests/`
- Files: `quests_tab.tscn`, `quests_tab.gd`, `quest_row.tscn`, `quest_row.gd`
- Two-page tab. Left page: `VBoxContainer` with `ActiveSection`, `CompletedSeparator` Label, `CompletedSection`. Right page: a `QuestDetail` `VBoxContainer` with `TitleLabel`, `DescriptionLabel`, `ObjectivesContainer` (children populated dynamically), and a `Placeholder` Label visible when no quest is selected.
- Flesh out `quest_row.tscn` with `TitleLabel` + `ViewButton`.

### PR 4 — `ui/notebook/sessions/`
- Files: `sessions_tab.tscn`, `sessions_tab.gd`, `story_card.tscn`, `story_card.gd`
- Mostly dynamic, but the right page's `Placeholder` Label and the left page's `CardsContainer: VBoxContainer` are static. Flesh out `story_card.tscn`.

### PR 5 — `ui/notebook/map/`
- Files: `map_tab.tscn`, `map_tab.gd`
- Pure placeholders today. Build the two page Controls with their heading Labels, `ColorRect` placeholders (`custom_minimum_size = Vector2(120, 80)`), and the "Phase 2" note Labels. No row scenes. `global_map.gd` / `local_map.gd` stay stubs.

## Files Touched (summary)

- Scene files: `ui/notebook/<tab>/<tab>_tab.tscn` (×5), plus row scenes `quest_row.tscn`, `inventory_row.tscn`, `equipment_slot.tscn`, `story_card.tscn`.
- Scripts: each tab's `<tab>_tab.gd`, plus the four row scripts. `populate_left/right` shrinks; `_ready` in row scripts switches from `Label.new()` to `@onready` references.
- Tests: `tests/unit/ui/notebook/**/test_*.gd` only if they `.new()` rows directly. `tests/integration/notebook/test_*.gd` should not need changes.
- Docs: append a short editor-properties note to `ui/CLAUDE.md`.

## Out of Scope (call out, do not change)
- `notebook.tscn` / `notebook.gd` — already editor-visible; `populate_left/right` contract is preserved.
- The unusual `unique_id=NNN` attributes in `notebook.tscn` are noted but not modified here. If they're plugin-generated and harmless, leave them; otherwise raise separately.
- `shared/notebook_tab.gd` and `shared/page_panel.gd` keep their current shape.

## Verification

Per PR:
1. **Open the affected `.tscn` files in the Godot editor.** Confirm the layout is visible without running the game — the central success criterion of this work.
2. **Run the project**, open the notebook with `I` (or `M`/`Q`), switch to the migrated tab, and confirm it renders identically to before.
3. **Run GUT unit tests** for the affected tab via the godot mcp server.
4. **Run integration tests** under `tests/integration/notebook/` to confirm the full open → tab-switch flow still works.
5. **Visual regression check via the testing-sandbox MCP**: launch the game, open the notebook, screenshot each tab. Compare against a pre-refactor screenshot. (Optional but cheap.)

## What "done" looks like
- A new engineer can open `settings_tab.tscn` in Godot and see five sliders without running the game.
- Adding a new setting is "drag a Label + HSlider into the scene, give them names, add three lines to the script" — not "read 343 lines of build code to find the pattern."
- Tab scripts shrink from hundreds of lines of `parent.add_child(...)` to dozens of lines of `@onready` references + signal wires + data binding.
