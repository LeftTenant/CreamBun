# Slice 3 — Quests Tab Scene Migration — Test Plan

Refactor design: `docs/refactors/notebook-ui-scene-migration/design.md` (PR 3)
Slice: `docs/refactors/notebook-ui-scene-migration/slices.md` (Slice 3)

This is a **structure-only migration**, not a behavior change. The goal of these
tests is to (a) lock the new scene-as-data contract between `quests_tab.gd` /
`quest_row.gd` and their `.tscn` files, and (b) prove the externally-observable
behavior (rows appear, placeholder shows, selecting a quest shows detail) is
**identical** before and after the migration. We mirror the test shape already
established by the completed Inventory slice (Slice 2): `test_*_scene.gd` for the
scene contract, public-API/type-recursion tests for behavior, and a visual
baseline e2e scenario.

The existing behavioral tests in
`tests/unit/ui/notebook/quests/test_quests_tab.gd` (6 tests) are deliberately
written against the public API / signals / label-text recursion, **not** internal
node paths, so they should continue to pass after the migration with at most a
helper tweak. They are listed in the Regression section below.

---

### E2E

- **Quests tab visual regression baseline** — Open the notebook to the Quests tab from `world.tscn` (via `open_notebook_quests`), wait for layout frames, and capture-or-compare a screenshot baseline at `tests/e2e/notebook-ui-scene-migration/baselines/quests_tab.png` (capture on first run, compare within 2% pixel tolerance thereafter); confirms the migration renders identically to the pre-migration layout.
- **Quests tab active during capture** — Assert `GameEvents.notebook_tab_changed` fired at least once after opening the notebook, confirming the Quests tab is actually the active tab being screenshotted (uses the public signal, not a private `_current_tab` field).
- **Left page renders at least one quest row** — Structural belt-and-suspenders against a blank capture: the left page contains at least one `QuestRow` descendant (Phase 1 always seeds `the_foraging_book` as COMPLETED).
- **Right page shows the placeholder before any selection** — On first open with no quest selected, the right page contains a `Label` whose text contains "select a quest" (case-insensitive).
- **Selecting a quest swaps the right page to detail** — Press the row's `ViewButton`, wait for layout, and confirm the right page now shows the quest title and objective lines and the placeholder is gone; mirrors the existing `quests_detail.md` e2e flow against the migrated scene.
- **Notebook closes cleanly** — Press `ui_cancel` and assert `GameState.current_state == GameState.State.PLAYING`, confirming the migration did not leave the game stuck in the NOTEBOOK state.

### Integration

- **populate_left → populate_right round trip on a fresh tab** — Instantiate `QuestsTab`, call `populate_left(parent_a)` then `populate_right(parent_b)` with two real `Control` parents in the tree, and confirm both pages populate without error and the contract (`populate_left`/`populate_right` from `NotebookTab`) is honored.
- **ViewButton press drives the right page from placeholder to detail** — After `populate_left` and `populate_right`, locate a row's `ViewButton`, emit its `pressed` signal, and assert the right page transitions from the placeholder Label to a detail view containing the selected quest's title — proving the reparented-subtree wiring survives selection.
- **Re-selecting refreshes (does not duplicate) the right page** — Press `ViewButton` twice (same or different quest) and assert the right page is rebuilt cleanly each time (no accumulating duplicate `QuestDetail` subtrees), guarding the `_refresh_right_page()` free-and-rebuild path under the new scene structure.
- **Completed/active sectioning still places rows correctly** — With the seeded foraging-book quest COMPLETED, confirm rows land under the `CompletedSection` and the `CompletedSeparator` Label is only present when both an active and a completed bucket are non-empty (preserves the existing divider logic against the new named containers).

### Unit — `quests_tab.tscn` scene contract (`test_quests_tab_scene.gd`, new)

- **Scene loads as a valid PackedScene** — `load("res://ui/notebook/quests/quests_tab.tscn")` returns a non-null `PackedScene` (gate test so later assertions fail cleanly rather than crash).
- **Root is a QuestsTab / NotebookTab** — The instantiated root has the `quests_tab.gd` script attached and is a `NotebookTab`.
- **Declares a `LeftPage` Control subtree** — A node named `LeftPage` exists and is a `Control` (it is the subtree `populate_left` reparents).
- **LeftPage contains `ActiveSection`, `CompletedSeparator`, `CompletedSection`** — All three named nodes exist inside `LeftPage`; `ActiveSection` and `CompletedSection` are containers (`VBoxContainer`) and `CompletedSeparator` is a `Label`.
- **Declares a `RightPage` Control subtree** — A node named `RightPage` exists and is a `Control` (the subtree `populate_right` reparents).
- **RightPage contains a `QuestDetail` VBoxContainer** — A node named `QuestDetail` exists inside `RightPage` and is a `VBoxContainer`.
- **QuestDetail contains `TitleLabel`, `DescriptionLabel`, `ObjectivesContainer`** — `TitleLabel` and `DescriptionLabel` are `Label`s; `ObjectivesContainer` is a container (`VBoxContainer`) into which objective lines are added dynamically.
- **RightPage contains a `Placeholder` Label** — A node named `Placeholder` exists, is a `Label`, and its text contains "select a quest" (case-insensitive) so the no-selection prompt is editor-defined, not code-defined.
- **Placeholder is visible and QuestDetail is hidden by default** — In the saved scene the `Placeholder` is visible and `QuestDetail` is hidden, so a freshly instantiated tab shows the prompt and not a blank/half-built detail view before any selection.

### Unit — `quest_row.tscn` scene contract (`test_quest_row_scene.gd`, new)

- **Scene loads as a valid PackedScene** — `load("res://ui/notebook/quests/quest_row.tscn")` returns a non-null `PackedScene`.
- **Root is a QuestRow** — The instantiated root has the `quest_row.gd` script attached.
- **Declares a `TitleLabel` Label** — A node named `TitleLabel` exists and is a `Label` (the title is now an editor node, not built in `_ready()`).
- **Declares a `ViewButton` Button** — A node named `ViewButton` exists and is a `Button` (the per-row select affordance now lives in the row scene, not built per-row in `quests_tab.gd`).

### Unit — `QuestRow` behavior after migration (`test_quests_tab.gd`, updated helpers)

- **`setup()` writes the quest title into `TitleLabel`** — After instantiating the row **from the scene** and calling `setup(quest, ACTIVE)`, a Label in the row subtree has text equal to `quest.title` (replaces the old `QuestRow.new()` construction in the existing test).
- **`setup()` with COMPLETED status does not crash and dims the row** — Calling `setup(quest, COMPLETED)` runs without error and sets `modulate.a < 1.0`, preserving the dim-completed visual treatment under `@onready` refs.
- **`ViewButton` press emits / drives selection** — Pressing the row's `ViewButton` triggers quest selection (via the row's own signal or the wiring `quests_tab.gd` installs), confirming row clicks still select a quest after construction moved from code to scene.

### Unit — `QuestsTab` behavior after migration (`test_quests_tab.gd`, existing, expected to still pass)

- **QuestsTab is a NotebookTab** — Unchanged; `QuestsTab` still extends `NotebookTab`.
- **`populate_left()` adds at least one child to its parent** — Unchanged contract: the reparented `LeftPage` subtree appears under the passed parent.
- **`populate_right()` shows a "select a quest" placeholder when nothing is selected** — Unchanged: the `Placeholder` Label (now scene-defined) is reachable in the parent subtree by case-insensitive text match.
- **`_ready()` pre-populates `_quest_log` with `the_foraging_book` as COMPLETED** — Unchanged; data seeding is untouched by this structure-only slice.
- **Quest title is findable by recursive label search after `populate_left`** — The migrated row's title Label is reachable via the test's existing `_find_labels` recursion, confirming the type-recursion assertions survive the scene-instantiation switch.

---

## Notes for the implementer / tester

- **No quest content or data changes.** `QuestData`, `QuestLog`, `the_foraging_book.tres`, and the `_ready()` seeding logic are out of scope — tests must not assert on new quest data, only on the relocated layout.
- **Row construction switches to scene instantiation.** Tests that previously did `QuestRow.new()` must instantiate from `quest_row.tscn` (or via `add_child_autofree(preload(...).instantiate())`) so `@onready` refs resolve; this is the one expected test-helper edit, matching the Inventory slice's approach.
- **Test for "rebuild, not duplicate"** — the existing `_refresh_right_page()` frees children before rebuilding; the integration "re-select" test guards that this still holds when the right page is a reparented `QuestDetail` subtree rather than a code-built VBox.
- **Visual baseline is capture-on-first-run** — same rationale as the Inventory scenario (Mobile renderer sub-pixel variance); run the e2e baseline capture **before** B3 implementation so the comparison after B3 is meaningful.
