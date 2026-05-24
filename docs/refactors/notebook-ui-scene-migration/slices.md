# Notebook UI Scene Migration — Slice Breakdown

Source design: `docs/refactors/notebook-ui-scene-migration/design.md`

This refactor is delivered as **5 vertical slices, one per notebook tab**, in the order the design doc recommends. Each slice is a self-contained PR that migrates one tab's static layout out of GDScript and into a `.tscn`, fleshes out any row/card scenes belonging to that tab, updates the controller script, and adjusts only the tests that need it. The `populate_left(parent)` / `populate_right(parent)` contract from `shared/notebook_tab.gd` is preserved by every slice. The notebook root (`notebook.tscn` / `notebook.gd`) is out of scope throughout.

Slices are ordered so the smallest, simplest tab (Settings) lands first as the proof-of-concept; the largest, most pattern-stressing tab (Inventory) lands second so we shake out the pattern before applying it to the more dynamic tabs; the remaining three are ordered by decreasing complexity.

The `ui/CLAUDE.md` editor-properties note (`Anchor preset → Full Rect`, `Autowrap → Word, Smart` on narrow-column Labels, `Size Flags → Expand + Fill` on `HSlider`) is appended once, as part of Slice 1, and the other four slices simply respect it.

---

## Slice 1 — Settings tab (proof of concept)

**Goal:** Migrate `settings_tab.tscn` from an empty Control to a fully-built scene containing two section headers (`Audio`, `Display`), four label-slider pairs (`MasterSlider`, `MusicSlider`, `SfxSlider`, `TextSpeedSlider`), one `WindowScaleOption` `OptionButton`, and two reset buttons, all inside a `VBoxContainer` with `PRESET_FULL_RECT` + 10 px insets. Rewrite `settings_tab.gd` so `populate_left(parent)` instantiates the scene and reparents the built subtree into `parent`; the `_apply_settings()` / `_on_*_changed()` handlers stay. This is the smallest tab and has no rows, so it is the cleanest place to validate the pattern. Append the editor-properties note to `ui/CLAUDE.md`.

**Files likely created/modified:**
- `ui/notebook/settings/settings_tab.tscn` (build out static layout)
- `ui/notebook/settings/settings_tab.gd` (shrink build code; keep handlers)
- `ui/CLAUDE.md` (append editor-properties note)
- `tests/unit/ui/notebook/settings/test_*.gd` (only if existing tests need helper updates)
- `tests/integration/notebook/test_settings_tab_layout.gd` (only if it asserts on internal node paths that change)

**Out of scope for this slice:**
- Any other tab.
- `notebook.tscn` / `notebook.gd`.
- `shared/notebook_tab.gd` / `shared/page_panel.gd`.
- Visual/art changes to the settings tab (this is a structure-only migration).

---

## Slice 2 — Inventory tab (pattern stress-test; largest)

**Goal:** Migrate the two-page Inventory tab plus its two row scenes. Build `inventory_tab.tscn` with a `LeftPage` subtree containing the header + 6 equipment slot placeholders (`Slot_BACKPACK` … `Slot_OFFHAND`) and a `RightPage` subtree containing the weight Label, `ScrollContainer`, `RowsContainer: VBoxContainer`, and three footer buttons. Flesh out `equipment_slot.tscn` and `inventory_row.tscn` with whatever their scripts build in `_ready` today (icon Rect, label, drop target / row labels + buttons). Rewrite `inventory_tab.gd` so `populate_left` / `populate_right` reparent the right subtree and resolve named-node references; switch row construction from `EquipmentSlot.new()` / `InventoryRow.new()` to `preload(...).instantiate()`. Convert the row scripts from `Label.new()` / `add_child(...)` to `@onready var _label: Label = $Label` references.

**Files likely created/modified:**
- `ui/notebook/inventory/inventory_tab.tscn` (build out left + right pages)
- `ui/notebook/inventory/inventory_tab.gd` (shrink build code; instantiate rows from scenes)
- `ui/notebook/inventory/equipment_slot.tscn` (flesh out static children)
- `ui/notebook/inventory/equipment_slot.gd` (convert to `@onready` refs)
- `ui/notebook/inventory/inventory_row.tscn` (flesh out static children)
- `ui/notebook/inventory/inventory_row.gd` (convert to `@onready` refs)
- `tests/unit/ui/notebook/inventory/test_*.gd` (likely needs creation or helper update — no folder exists yet; any tests that `.new()` rows directly must instantiate from the scene instead)
- `tests/integration/notebook/test_inventory_tab.gd` (only if assertions break)

**Out of scope for this slice:**
- Settings / Quests / Sessions / Map tabs.
- `notebook.tscn` / `notebook.gd`.
- Adding new inventory features (drag-drop polish, new equipment slots, etc.).
- Re-numbering or restructuring the existing `unique_id=NNN` attributes in scene files.

---

## Slice 3 — Quests tab

**Goal:** Migrate the two-page Quests tab plus `quest_row.tscn`. Build `quests_tab.tscn` with a `LeftPage` subtree containing a `VBoxContainer` with `ActiveSection`, `CompletedSeparator` Label, `CompletedSection`, and a `RightPage` subtree with a `QuestDetail` `VBoxContainer` containing `TitleLabel`, `DescriptionLabel`, `ObjectivesContainer` (children populated dynamically), and a `Placeholder` Label visible when no quest is selected. Flesh out `quest_row.tscn` with `TitleLabel` + `ViewButton`. Rewrite `quests_tab.gd` so populate functions reparent the subtrees and resolve named-node refs; switch row construction to scene instantiation. Convert `quest_row.gd` to `@onready` refs.

**Files likely created/modified:**
- `ui/notebook/quests/quests_tab.tscn`
- `ui/notebook/quests/quests_tab.gd`
- `ui/notebook/quests/quest_row.tscn`
- `ui/notebook/quests/quest_row.gd`
- `tests/unit/ui/notebook/quests/test_*.gd` (only if tests `.new()` rows directly)

**Out of scope for this slice:**
- Other tabs.
- `notebook.tscn` / `notebook.gd`.
- Quest content/data changes.

---

## Slice 4 — Sessions tab

**Goal:** Migrate the Sessions tab and `story_card.tscn`. Most of the Sessions tab is dynamic, but the right page's `Placeholder` Label and the left page's `CardsContainer: VBoxContainer` are static — build those in `sessions_tab.tscn`. Flesh out `story_card.tscn` with whatever the script currently builds. Rewrite `sessions_tab.gd` so populate functions reparent the static subtrees and instantiate story cards from `story_card.tscn`. Convert `story_card.gd` to `@onready` refs.

**Files likely created/modified:**
- `ui/notebook/sessions/sessions_tab.tscn`
- `ui/notebook/sessions/sessions_tab.gd`
- `ui/notebook/sessions/story_card.tscn`
- `ui/notebook/sessions/story_card.gd`
- `tests/unit/ui/notebook/sessions/test_*.gd` (only if tests `.new()` cards directly)

**Out of scope for this slice:**
- Other tabs.
- `notebook.tscn` / `notebook.gd`.
- Story/session content changes.

---

## Slice 5 — Map tab

**Goal:** Migrate the Map tab. The map tab is pure placeholders today — build two page Controls with their heading Labels, `ColorRect` placeholders (`custom_minimum_size = Vector2(120, 80)`), and the "Phase 2" note Labels. No row scenes. `global_map.gd` and `local_map.gd` stay as stubs. Rewrite `map_tab.gd` populate functions to reparent the static subtrees.

**Files likely created/modified:**
- `ui/notebook/map/map_tab.tscn`
- `ui/notebook/map/map_tab.gd`
- `tests/unit/ui/notebook/map/test_*.gd` (only if any existing test breaks)

**Out of scope for this slice:**
- Other tabs.
- `notebook.tscn` / `notebook.gd`.
- `global_map.gd` / `local_map.gd` stubs (deliberately untouched per design doc).
- Implementing real map rendering (Phase 2).
