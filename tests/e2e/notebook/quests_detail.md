# Scenario: Quests tab — detail view populates on "View"

Verifies the quests tab seeds the intro quest as COMPLETED, that the right
page shows the placeholder before any selection, and that clicking the
quest's "View" button replaces the placeholder with the title, description,
and a checklist of objectives all rendered as `[x]`.

The Phase 1 quest log is seeded in `QuestsTab._ready()` with one quest
(`the_foraging_book`) marked COMPLETED with objectives `[0, 1, 2]`. With
only one quest and it being COMPLETED, the left page omits the
"— Completed —" separator (only shown when both buckets are non-empty).

Design doc reference: §5.4 (Quests tab).

## Setup
- Load scene: `res://world/world.tscn`
- Wait: 10 frames
- Press action: `open_notebook_quests`
- Wait: 15 frames

## Steps

### Step 1: Right page shows the placeholder before selection
- Screenshot → save / compare reference: `quests_detail_step_01_placeholder.png`
- Assert: the right page contains a `Label` with text
  "Select a quest to see details."
- Assert: the left page contains a "View" button under the quest title.

### Step 2: Click "View" — right page renders the quest detail
- Mouse move to: centre of the "View" button on the left page
- Mouse button press: `LEFT`
- Mouse button release: `LEFT`
- Wait: 10 frames
- Screenshot → save / compare reference: `quests_detail_step_02_detail_view.png`
- Assert: the right page placeholder is replaced — no Label with the
  "Select a quest to see details." text remains.
- Assert: the right page now contains a title Label and a description Label
  populated from `the_foraging_book.tres`.
- Assert: three objective Labels appear, each prefixed `[x] ` (because the
  seed entry has `completed_objectives: [0, 1, 2]`).
