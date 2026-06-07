# Scenario: Quests tab — visual regression baseline

This scenario confirms that moving the Quests tab layout from GDScript into
`quests_tab.tscn` and `quest_row.tscn` produces an identical rendered result
to the pre-migration state. It is not testing behaviour (that is covered by the
integration tests in `tests/integration/notebook/test_quests_tab.gd`) — it is
testing *visual fidelity* between the pre-migration and post-migration renderings.

## Baseline capture strategy

On first run (before B3), this scenario captures the current rendered state of
the Quests tab as the **reference baseline** at:

  `tests/e2e/notebook-ui-scene-migration/baselines/quests_tab.png`

On subsequent runs (after B3 lands), the same screenshot step compares against
that baseline. A visible difference indicates the migration changed the rendered
output — which is a regression unless the team has explicitly approved a visual
change.

Why capture-on-first-run rather than committing a fixed reference?

The project uses the Godot Mobile renderer, which can produce sub-pixel
differences across machines and GPU drivers. Capturing the baseline from the
same environment that runs the comparison avoids spurious failures caused by
renderer variation rather than actual layout bugs.

## Signal-based tab observation

This scenario does NOT assert on `Notebook._current_tab` (a private field that
may change name or type during the migration). Instead it observes the
`GameEvents.notebook_tab_changed` signal to confirm the Quests tab is active.
This is the same cross-system event the rest of the game (HUD, save system) uses
to react to tab switches, so it is the correct public surface to test against.

## Design doc reference

`docs/refactors/notebook-ui-scene-migration/design.md` — "Verification" section.
`docs/features/notebook/design.md` §3.3 (Quests Tab).

## Side-effect note

This scenario opens the Quests tab and presses one ViewButton. It does not
modify any quest state (status, completed_objectives) or any inventory/world
state. The `_quest_log` in `QuestsTab._ready()` is re-seeded every time the
scene loads, so there are no persistent side effects from this scenario.

---

## Setup

- Load scene: `res://world/world.tscn`
- Wait: 10 frames (let the world and all autoloads fully initialise)
- Press action: `open_notebook_quests`
- Wait: 15 frames (layout frames: the notebook animates open, the tab VBox
  anchors settle, QuestRow children fill their rects)
- Assert signal: `GameEvents.notebook_tab_changed` was emitted at least once
  since the action (confirms the notebook opened and fired the tab-change event,
  verifying the Quests tab is actually the active tab being screenshotted)

---

## Steps

### Step 1: Capture or compare the full Quests tab layout

- Screenshot → **capture or compare baseline**:
  - Path: `tests/e2e/notebook-ui-scene-migration/baselines/quests_tab.png`
  - If the file **does not exist**: save the screenshot as the baseline and
    **pass** — this is the pre-migration reference capture.
  - If the file **exists**: compare the current screenshot against the stored
    baseline. Report a failure if any visible region differs by more than a 2%
    pixel tolerance (to allow for sub-pixel anti-aliasing variation across
    identical GPU/driver setups).

- Assert (structural, not visual — belt-and-suspenders against a blank capture):
  - The left page contains at least 1 `QuestRow` descendant (Phase 1 always
    seeds `the_foraging_book` as COMPLETED so the list is never empty).
  - The right page contains a `Label` whose text contains "select a quest"
    (case-insensitive) — the placeholder prompt is visible before any
    quest is selected.

### Step 2: Confirm tab-switch signal emitted correctly

- Get node property: `GameEvents` — check that `notebook_tab_changed` was
  emitted with the quests tab identifier.
  (If `get_game_state` exposes the last-emitted signal args, use that;
  otherwise this assertion is satisfied by the signal assert in Setup.)

### Step 3: Press ViewButton and confirm right page shows quest detail

- Locate the first `Button` named `ViewButton` in the left page subtree.
- Press the button (mouse_button_press on its screen position or via
  emit_game_event targeting the button's pressed signal).
- Wait: 5 frames (let _select_quest → _refresh_right_page run and layout settle).
- Assert:
  - The right page no longer contains a `Label` with text that contains
    "select a quest" (case-insensitive) — the placeholder is gone.
  - The right page contains a `Label` whose text matches the quest title
    (Phase 1: "The Foraging Book" or the title defined in
    `resources/data/quests/the_foraging_book.tres`).
  - The right page contains at least 1 `Label` whose text begins with either
    "[x]" or "[ ]" — at least one objective line is rendered.
- Screenshot: capture the detail view state for visual inspection
  (not compared against a baseline — this is a state-change capture for
  debugging purposes only).

### Step 4: Close the notebook

- Press action: `ui_cancel`     # closes the notebook via Esc → ui_cancel
- Wait: 5 frames
- Assert: `GameState.current_state` == `GameState.State.PLAYING`
  (confirms the notebook closed cleanly and did not leave the game in the
  NOTEBOOK state after the migration)
