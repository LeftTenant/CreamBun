# Scenario: Settings tab — visual regression baseline

This scenario exists to confirm that moving the settings tab layout from GDScript
into `settings_tab.tscn` produces an identical rendered result. It is not testing
behaviour (that is covered by `tests/e2e/notebook/settings_controls.md`) — it is
testing *pixel fidelity* between the pre-migration and post-migration renderings.

## Baseline capture strategy

On first run (before B3), this scenario captures the current rendered state of the
Settings tab as the **reference baseline** at:

  `tests/e2e/notebook-ui-scene-migration/baselines/settings_tab.png`

On subsequent runs (after B3 lands), the same screenshot step compares against that
baseline. A pixel-level difference indicates the migration changed the visual output
— which is a regression unless the team has explicitly approved a visual change.

Why capture-on-first-run rather than committing a fixed reference?

The project uses the Godot Mobile renderer, which can produce sub-pixel differences
across machines and GPU drivers. Capturing the baseline from the same environment
that runs the comparison avoids spurious failures caused by renderer variation
rather than actual layout bugs. The baseline is committed to the repo once captured
so future runs on the same renderer version can compare deterministically.

## Design doc reference

`docs/refactors/notebook-ui-scene-migration/design.md` — "Verification" section.

## Side-effect note

This scenario navigates to the Settings tab, which exists in a running game session.
It does not interact with sliders or buttons, so there are no audio or window-size
side effects.

---

## Setup

- Load scene: `res://world/world.tscn`
- Wait: 10 frames (let the world and autoloads fully initialise)
- Press action: `open_notebook_inventory`
- Wait: 5 frames
- Press action: `ui_focus_next`     # INVENTORY → MAP
- Wait: 5 frames
- Press action: `ui_focus_next`     # MAP → QUESTS
- Wait: 5 frames
- Press action: `ui_focus_next`     # QUESTS → SETTINGS
- Wait: 15 frames (layout frames: VBox anchors settle, sliders fill their rects)
- Assert: node property `Notebook._current_tab` == `3` (SETTINGS enum value)

## Steps

### Step 1: Capture or compare the full Settings tab layout

- Screenshot → **capture or compare baseline**:
  - Path: `tests/e2e/notebook-ui-scene-migration/baselines/settings_tab.png`
  - If the file **does not exist**: save the screenshot as the baseline and
    **pass** — this is the pre-migration reference capture.
  - If the file **exists**: compare the current screenshot against the stored
    baseline. Report a failure if any visible region differs by more than a 2%
    pixel tolerance (to allow for sub-pixel anti-aliasing variation).

- Assert (structural, not visual — belt-and-suspenders against a blank capture):
  - The left page contains at least 4 `HSlider` descendants.
  - The right page contains exactly 1 `OptionButton` descendant.
  - The left page contains a `Label` whose text is `"Audio"`.
  - The right page contains a `Label` whose text is `"Display"`.

### Step 2: Close the notebook

- Press action: `ui_cancel`     # closes the notebook via Esc → ui_cancel
- Wait: 5 frames
- Assert: `GameState.current_state` == `GameState.State.PLAYING`
  (confirms the notebook closed cleanly and did not leave the game paused)
