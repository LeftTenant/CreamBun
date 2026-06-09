# Slice 4 — Sessions Tab Scene Migration — Test Plan

Refactor design: `docs/refactors/notebook-ui-scene-migration/design.md` (PR 4)
Slice: `docs/refactors/notebook-ui-scene-migration/slices.md` (Slice 4)

This is a **structure-only migration**, not a behaviour change. The goal of these
tests is to (a) lock the new scene-as-data contract between `sessions_tab.gd` /
`story_card.gd` and their `.tscn` files, and (b) prove the externally-observable
behaviour (cards appear, static right-page placeholder shows) is **identical**
before and after the migration. We mirror the test shape established by the
completed Quests slice (Slice 3): `test_*_scene.gd` for the scene contract,
public-API / type-recursion tests for behaviour, and a visual baseline e2e
scenario.

Two user decisions are baked into this plan:

- **D1 — Fix the re-populate duplicate-card bug.** `populate_left` is known to
  accumulate duplicate `StoryCard` nodes on repeated calls because the current
  implementation never clears `_left_cards` or removes stale children. The Slice 4
  implementation must fix this. A test asserting "populate_left called twice yields
  exactly one card" is a first-class test target here, not merely a documented
  limitation.
- **D2 — Right page is purely static.** The right page contains one fixed
  `Placeholder` Label. No selection logic, no dynamic refresh, no card-click
  handlers. Do not plan any dynamic right-page tests; assert only that the static
  label is present.

There is **no dedicated hotkey** to reach the Sessions tab directly. It is reached
by opening the notebook with any of the three notebook-open actions
(`open_notebook_inventory`, `open_notebook_map`, or `open_notebook_quests`, all
defined in `project.godot`) and then cycling forward with `ui_focus_next` or
backward with `ui_focus_prev` until the Sessions tab is active.
`GameEvents.notebook_tab_changed` (emitting the `NotebookTab.SESSIONS` integer
value `4`) is the public signal to observe tab arrival — never assert on the
private `Notebook._current_tab` field.

---

### E2E

- **Sessions tab visual regression baseline** — Open the notebook via
  `open_notebook_quests`, cycle forward with `ui_focus_next` until
  `GameEvents.notebook_tab_changed` fires with `NotebookTab.SESSIONS` (`4`), wait
  for layout frames, and capture-or-compare a screenshot baseline at
  `tests/e2e/notebook-ui-scene-migration/baselines/sessions_tab.png` (capture on
  first run, compare within 2% pixel tolerance thereafter, same Mobile-renderer
  rationale as the Quests slice); confirms the migration renders identically to the
  pre-migration layout.
- **Sessions tab active during capture** — Assert `GameEvents.notebook_tab_changed`
  was emitted with the value `4` (`NotebookTab.SESSIONS`) after the tab-cycle
  actions, confirming the Sessions tab is actually the active tab being
  screenshotted.
- **Left page renders at least one StoryCard** — Structural belt-and-suspenders
  against a blank capture: after opening the Sessions tab the left page contains at
  least one `StoryCard` descendant (Phase 1 always seeds the Default Story card).
- **Right page shows the static placeholder** — The right page contains a `Label`
  whose text contains "select a story" (case-insensitive), confirming the static
  `Placeholder` Label from the scene is visible without any user interaction.
- **Notebook closes cleanly** — Press `ui_cancel` and assert
  `GameState.current_state == GameState.State.PLAYING`, confirming the migration
  did not leave the game stuck in the `NOTEBOOK` state.

---

### Integration

*(No integration tests are planned for Slice 4. The Sessions tab has no dynamic
right-page selection flow — D2 makes the right page purely static — so there is no
cross-system wiring to verify beyond what the unit and e2e tests already cover.
If Phase 2 adds card-selection, integration tests should be planned at that point.)*

---

### Unit — `story_card.tscn` scene contract (`test_story_card_scene.gd`, new)

- **Scene loads as a valid PackedScene** — `load("res://ui/notebook/sessions/story_card.tscn")` returns a non-null `PackedScene` (gate test so later assertions fail cleanly rather than crash).
- **Root is a StoryCard / VBoxContainer** — The instantiated root has `story_card.gd` attached and is both a `StoryCard` and a `VBoxContainer`.
- **Declares a `NameLabel` Label** — A node named `NameLabel` exists inside the scene root and is a `Label` (the story's display name, previously built in `_ready()`; now an editor node).
- **Declares a `CoverRect` ColorRect** — A node named `CoverRect` exists and is a `ColorRect` (the colour swatch that `setup()` sets to `slot.cover_color`).
- **Declares a `LastPlayedLabel` Label** — A node named `LastPlayedLabel` exists and is a `Label` (the Phase-1 hardcoded "last played" field).
- **Declares a `SwitchButton` Button** — A node named `SwitchButton` exists and is a `Button` (the no-op Phase-1 switch affordance; Phase 2 will wire it to `GameEvents.story_switch_requested`).
- **CoverRect preserves the 16×16 minimum size** — `CoverRect.custom_minimum_size == Vector2(16, 16)`, matching the low-res aesthetic established in the pre-migration code and ensuring visual parity after the migration.
- **LastPlayedLabel text contains "N/A"** — `LastPlayedLabel.text` contains the string "N/A", confirming the Phase-1 hardcoded copy is preserved as an editor property rather than dropped during the migration.

---

### Unit — `sessions_tab.tscn` scene contract (`test_sessions_tab_scene.gd`, new)

- **Scene loads as a valid PackedScene** — `load("res://ui/notebook/sessions/sessions_tab.tscn")` returns a non-null `PackedScene` (gate test).
- **Root is a SessionsTab / NotebookTab** — The instantiated root has `sessions_tab.gd` attached and is both a `SessionsTab` and a `NotebookTab`.
- **Declares a `LeftPage` Control containing a `CardsContainer` VBoxContainer** — A node named `LeftPage` exists and is a `Control`; within it a node named `CardsContainer` exists and is a `VBoxContainer` (the container into which `populate_left` adds `StoryCard` instances, now editor-declared rather than code-built).
- **Declares a `RightPage` Control containing a `Placeholder` Label** — A node named `RightPage` exists and is a `Control`; within it a node named `Placeholder` exists and is a `Label` whose text contains "select a story" (case-insensitive; current copy is "Select a Story to see details."), confirming D2: the static placeholder is editor-defined.
- **`populate_left(null)` does not crash** — Calling `populate_left(null)` on the instantiated scene root completes without error, confirming the null-guard required by the `NotebookTab` contract is present.
- **`populate_right(null)` does not crash** — Calling `populate_right(null)` on the instantiated scene root completes without error, for the same reason.

---

### Unit — `StoryCard` and `SessionsTab` behaviour (`test_sessions_tab.gd`, modified)

*(The SLICE 4 EDIT NOTE below mirrors the SLICE 3 EDIT NOTE in `test_quests_tab.gd`
and must appear in the file header. Tests 8 and 9 must be updated; tests 1–7 stay
in intent.)*

**SLICE 4 EDIT NOTE to add to `test_sessions_tab.gd`:**
Tests 8 and 9 previously used `StoryCard.new()` to construct cards. They now
instantiate from `story_card.tscn`. After the Slice 4 migration `story_card.gd`
will use `@onready` references to `NameLabel`, `CoverRect`, `LastPlayedLabel`, and
`SwitchButton` — named children that only exist when the node is instantiated from
the scene. Bare `StoryCard.new()` would leave those refs null and `setup()` would
null-crash. Test 7 (`is VBoxContainer`) stays as `.new()` because it never touches
children. Tests 5 and 6 keep `SessionsTab.new()` because `populate_left` /
`populate_right` load the scene internally — bare construction still works.

**Existing tests (1–7) — keep in intent:**
- **SessionsTab is a NotebookTab** — `SessionsTab.new()` is a `NotebookTab` (unchanged).
- **SessionsTab is a Control** — `SessionsTab.new()` is a `Control` (unchanged).
- **`_default_slot` is non-null after `_ready()`** — `SessionsTab` added to the tree has a non-null `_default_slot` (unchanged).
- **`_default_slot.display_name` is not empty** — Guards against a blank card title on first launch (unchanged).
- **`populate_left()` adds at least one child to the parent** — The reparented subtree appears under the passed parent (unchanged; keep `SessionsTab.new()`).
- **`populate_right()` adds at least one child to the parent** — The static `Placeholder` Label is reachable under the passed parent (unchanged; keep `SessionsTab.new()`).
- **StoryCard is a VBoxContainer** — `StoryCard.new()` is a `VBoxContainer`; safe to keep as `.new()` because this test never calls `setup()` or accesses children (unchanged).

**Updated tests (8–9) — switch to scene instantiation:**
- **`StoryCard.setup()` does not crash with a valid `StorySlot`** — Instantiate the card **from `story_card.tscn`** (not `.new()`), add to the tree, then call `setup(slot)`; assert no crash.
- **`StoryCard.setup()` stores the slot reference** — Same scene-instantiation approach; assert `card._slot == slot` after `setup()`.

**New tests (D1 + rendered-text assertions):**
- **`populate_left` called twice yields exactly one `StoryCard` in `CardsContainer`** — Call `populate_left(parent)` twice on the same `SessionsTab` instance; assert the `CardsContainer` VBoxContainer under `parent` contains exactly one `StoryCard` child, not two; confirms D1: stale cards are cleared before rebuilding.
- **`setup()` writes `slot.display_name` into `NameLabel`** — Instantiate the card from the scene, call `setup(slot)`, and use a `_find_labels`-style recursive search (mirror of `test_quests_tab.gd`) to find a `Label` in the subtree whose text equals `slot.display_name`; guards that the `NameLabel` binding survives the `@onready` migration.
- **`setup()` sets `CoverRect.color` to `slot.cover_color`** — Instantiate the card from the scene, call `setup(slot)`, and assert that the `CoverRect` node's `color` property equals `slot.cover_color`; guards the colour-swatch binding under `@onready` refs.

---

## Notes for the implementer / tester

- **No session content or data changes.** `StorySlot`, `SaveManager`, and the
  `_ready()` default-slot seeding are out of scope — tests must not assert on new
  slot data, only on the relocated layout.
- **D1 is a real bug fix, not optional.** The implementer must clear `_left_cards`
  and remove stale children from `parent` (or `CardsContainer`) before rebuilding
  in `populate_left`. The "called twice, one card" unit test and the e2e capture
  both rely on this being correct.
- **D2: no right-page dynamic tests.** Do not add selection/refresh tests. The
  `Placeholder` Label is the entire right-page story for Phase 1. If a reviewer
  sees a test asserting on card-click → right-page update, it should be rejected.
- **Card construction switches to scene instantiation.** Tests that previously did
  `StoryCard.new()` and then called `setup()` must instantiate from
  `story_card.tscn` so `@onready` refs resolve. Test 7 (`is VBoxContainer`) is the
  one exception because it never touches children.
- **Tab navigation in e2e.** There is no `open_notebook_sessions` action. The e2e
  scenario reaches the Sessions tab by cycling with `ui_focus_next` from a known
  starting tab. The `GameEvents.notebook_tab_changed` signal value `4` is the
  authoritative confirmation that Sessions is active.
- **Visual baseline timing.** Capture the baseline screenshot **before** the Slice 4
  implementation so the post-migration comparison is meaningful, matching the
  Quests slice's approach.
- **Transient screenshots** during e2e execution must be written to
  `.godot-test-reports/e2e/` (retrieved via `get_config` → `reports_dir`), not
  into the committed `tests/e2e/` tree. Only the reference baseline at
  `tests/e2e/notebook-ui-scene-migration/baselines/sessions_tab.png` is committed.
