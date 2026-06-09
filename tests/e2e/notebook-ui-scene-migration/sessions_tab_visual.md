# Scenario: Sessions tab — visual regression baseline

This scenario confirms that moving the Sessions tab layout from GDScript into
`sessions_tab.tscn` and `story_card.tscn` produces an identical rendered result
to the pre-migration state. It is not testing behaviour (that is covered by the
unit tests in `tests/unit/ui/notebook/sessions/`) — it is testing *visual fidelity*
between the pre-migration and post-migration renderings.

## Baseline capture strategy

On first run (before Slice 4 implementation), this scenario captures the current
rendered state of the Sessions tab as the **reference baseline** at:

  `tests/e2e/notebook-ui-scene-migration/baselines/sessions_tab.png`

On subsequent runs (after the Slice 4 implementation lands), the same screenshot
step compares against that baseline. A visible difference indicates the migration
changed the rendered output — which is a regression unless the team has explicitly
approved a visual change.

Why capture-on-first-run rather than committing a fixed reference?

The project uses the Godot Mobile renderer, which can produce sub-pixel differences
across machines and GPU drivers. Capturing the baseline from the same environment
that runs the comparison avoids spurious failures caused by renderer variation
rather than actual layout bugs. This is the same rationale used for the Quests
tab baseline in `quests_tab_visual.md`.

## Tab navigation strategy

There is no dedicated `open_notebook_sessions` action in `project.godot`. The
Sessions tab is reached by opening the notebook with any of the three notebook
actions (`open_notebook_inventory`, `open_notebook_map`, `open_notebook_quests`)
and then cycling forward with `ui_focus_next` until
`GameEvents.notebook_tab_changed` fires with the `NotebookTab.SESSIONS` value
(`4`). We use `open_notebook_quests` as the entry point for consistency with the
Quests tab scenario.

## Signal-based tab observation

This scenario does NOT assert on `Notebook._current_tab` (a private field that
may change name or type during the migration). Instead it observes the
`GameEvents.notebook_tab_changed` signal to confirm the Sessions tab is active.
`NotebookTab.SESSIONS` has the integer value `4`.

## Transient screenshot storage

Screenshots taken during execution (intermediate frames, debugging captures) are
written to the gitignored reports directory retrieved via
`get_config` → `reports_dir`. **Only the reference baseline at
`tests/e2e/notebook-ui-scene-migration/baselines/sessions_tab.png` is committed.**
Never write transient frames into the `tests/e2e/` tree — that pollutes the repo.

## Design doc references

`docs/refactors/notebook-ui-scene-migration/design.md` — "Verification" section.
`docs/features/notebook/design.md` §5 (Sessions Tab).
`docs/refactors/notebook-ui-scene-migration/slice-4-sessions-test-plan.md` — E2E
items (authoritative test plan for this scenario).

## Side-effect note

This scenario opens the notebook and reads the Sessions tab. It does not modify
any story slot data, save files, or world state. The `_default_slot` in
`SessionsTab._ready()` is re-created every time the scene initialises, so there
are no persistent side effects from this scenario.

---

## Setup

- Load scene: `res://world/world.tscn`
- Wait: 10 frames (let the world and all autoloads fully initialise)
- Press action: `open_notebook_quests`
- Wait: 10 frames (notebook animates open; Quests tab becomes active)
- Assert signal: `GameEvents.notebook_tab_changed` was emitted (confirms the
  notebook opened and tab-change fired; the quests tab is now active)

---

## Steps

### Step 1: Cycle to the Sessions tab

The Sessions tab is tab index 4 (SESSIONS). From the Quests tab, cycle forward
with `ui_focus_next` until `GameEvents.notebook_tab_changed` emits the value `4`.
Cycle at most 5 times (there are 5 tabs total) to avoid an infinite loop if the
signal never fires.

- Press action: `ui_focus_next`
- Wait: 5 frames
- Check: has `GameEvents.notebook_tab_changed` been emitted with value `4`?
  - If yes: proceed to Step 2.
  - If no: repeat Step 1 up to 4 more times.
- Assert: `GameEvents.notebook_tab_changed` was emitted with value `4`
  (`NotebookTab.SESSIONS`) — confirms the Sessions tab is the active tab being
  screenshotted. This is the authoritative confirmation from the test plan.

---

### Step 2: Capture or compare the full Sessions tab layout

- Wait: 15 frames (layout frames: the tab VBox anchors settle, StoryCard children
  fill their rects — the same budget used for the Quests tab scenario)

- Screenshot → **capture or compare baseline**:
  - Path: `tests/e2e/notebook-ui-scene-migration/baselines/sessions_tab.png`
  - Transient intermediate frame (if needed for debugging): write to
    `<reports_dir>/sessions_tab_debug.png` (never into the `tests/e2e/` tree).
  - If the file **does not exist**: save the screenshot as the baseline and
    **pass** — this is the pre-migration reference capture.
  - If the file **exists**: compare the current screenshot against the stored
    baseline. Report a failure if any visible region differs by more than a **2%
    pixel tolerance** (to allow for sub-pixel anti-aliasing variation on identical
    GPU/driver setups; same tolerance as the Quests tab baseline).

- Assert (structural, belt-and-suspenders against a blank capture):
  - The left page contains at least 1 `StoryCard` descendant. Phase 1 always
    seeds the Default Story card so the list is never empty. A blank capture
    would pass the pixel comparison against a blank baseline — this structural
    check catches that case.
  - The right page contains a `Label` whose text contains "select a story"
    (case-insensitive) — the static `Placeholder` Label from the scene is
    visible without any user interaction (D2: right page is purely static).

---

### Step 3: Confirm tab-switch signal emitted correctly

- Assert structural: `GameEvents.notebook_tab_changed` was emitted with the
  integer value `4` (`NotebookTab.SESSIONS`) during the tab-cycle actions in
  Step 1. This assertion is satisfied by the Step 1 signal check; record it
  here as an explicit pass/fail line in the scenario report for traceability
  back to the test plan item "Sessions tab active during capture".

---

### Step 4: Close the notebook

- Press action: `ui_cancel`     # closes the notebook via Esc → ui_cancel
- Wait: 5 frames
- Assert: `GameState.current_state` == `GameState.State.PLAYING`
  (confirms the notebook closed cleanly and did not leave the game in the
  NOTEBOOK state after the Slice 4 migration — matches the test plan item
  "Notebook closes cleanly")
