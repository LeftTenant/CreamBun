# Pixel-Art-Purist — Notebook Legible at 1×

**Design reference:** `docs/refactors/pixel-art-purist-size-and-theme.md` §3, §4, §6.3
**Test plan:** `docs/features/pixel-art-purist/slice-5-notebook-font-size-pass-test-plan.md`

## Purpose

Verify that after Slice 5's font-size pass the notebook is visually correct at the worst-case
viewport size (1× — 320×180 effective pixels, rendered at 2× in the default 640×360 window):

- Heading Labels (size 16) render visibly larger than body Labels (size 8) — the hierarchy
  is perceptible at a glance, not just measurable with a ruler.
- Body-8 text is legible — individual characters are distinguishable and not crushed to solid
  blocks or indistinguishable noise.
- The color-only differentiation for SlotLabel (ink) / ItemNameLabel (ink_muted) and
  CompletedSeparator (ink_muted) is visible without any size difference.

These are rendering outcomes that cannot be confirmed by GUT assertions; screenshots are the
only verification method.

## Preconditions

- Slice 1–4 changes are in place: base_theme.tres has Default Font Size = 8, the Heading
  variation exists at 16, and the game runs at 320×180 base resolution (640×360 window).
- Slice 5 changes are implemented: Heading variations assigned, equipment_slot font_size
  overrides removed, colors applied.
- The game runs via the testing-sandbox MCP server.
- Reference screenshots (baselines) are stored at
  `tests/e2e/pixel-art-purist/screenshots/` (committed).
- Transient comparison captures go to `.godot-test-reports/e2e/` (gitignored). Call
  `get_config` on the testing-sandbox server to get the `reports_dir` path.

---

## Scenario 1 — Inventory tab: heading vs body hierarchy and body-8 legibility gate

**Goal:** The Inventory tab makes the heading/body size contrast visible at 1×, and body-8
text can be read character-by-character. This is the primary legibility gate for the entire
body-8 design decision — if body-8 fails here, the correct escalation is to change the
base_theme.tres Default Font Size to 16, not to add per-node overrides.

### Setup

1. Launch the game at the default 640×360 window (2× the 320×180 base).
2. Wait for the world scene to be ready (allow at least 10 frames after launch).
3. Open the notebook to the Inventory tab by pressing `I`.
4. Wait 5 frames for the notebook open animation to settle.

### Steps

| # | Action | Checkpoint |
|---|--------|-----------|
| 1 | Capture a screenshot of the full window with the Inventory tab open. | Save as `tests/e2e/pixel-art-purist/screenshots/notebook_legible_1x_step_01_inventory.png` on first run; compare to baseline on subsequent runs. |
| 2 | Inspect the screenshot. | The "Equipment" header (Heading, size 16) renders noticeably taller than the equipment slot labels and weight readout (body, size 8). At least a 2:1 height ratio is visible at the pixel level. |
| 3 | Inspect the body-8 text in the equipment slots (slot role labels: "Backpack", "Clothing", etc.). | Individual characters are distinguishable — the letter shapes (e.g. "B" vs "C" vs "G") are visually different even at 8px. No characters are crushed to identical solid-block rectangles. |
| 4 | Inspect the SlotLabel ("Backpack", "Clothing") and ItemNameLabel ("[empty]" or item name) text colors in any filled slot. | SlotLabel text is darker (ink, #3b2f2a) than ItemNameLabel text (ink_muted, #7a6a5d). The color difference is visible without any size difference between the two lines. |

### Expected result

"Equipment" reads clearly larger than the text below it. The word "Backpack" in a slot label
is spelled out legibly — not a smear. SlotLabel and ItemNameLabel lines within the same slot
differ in color, not size.

**If body-8 fails the legibility check:** report to the user that size-8 is below the
legibility threshold at 320×180 and ask whether to change Default Font Size in base_theme.tres
to 16. Do not add any per-node font_size overrides.

---

## Scenario 2 — Quests tab: heading vs body in the detail pane

**Goal:** The quest detail pane makes the title heading and body description/objective text
visually distinct, and the "— Completed —" separator is body-sized with muted color.

### Setup

1. Launch the game and open the notebook to the Inventory tab (press `I`).
2. Navigate to the Quests tab (press `Q` or use the notebook_next_page action until the
   Quests tab is visible).
3. Wait 5 frames.

### Steps

| # | Action | Checkpoint |
|---|--------|-----------|
| 1 | Capture a screenshot of the Quests tab. | Save as `tests/e2e/pixel-art-purist/screenshots/notebook_legible_1x_step_02_quests.png` on first run. |
| 2 | Inspect the quest detail pane (right page). | "The Foraging Book" title (QuestDetail/TitleLabel, Heading) is visibly taller than the description and objective text below it. |
| 3 | Inspect the "— Completed —" separator on the left page. | The separator is the same height as quest row titles — it is not larger — and its text color is visibly lighter/more muted than active quest row text. |

### Expected result

Quest title heading reads larger than the description prose. "— Completed —" does not stand
out by size, only by color — it is the same height as the quest row labels above and below it.

---

## Scenario 3 — Map tab: page headings vs placeholder notes

**Goal:** "World Map" and "Local Area" headings are visibly heading-sized, and the placeholder
notes below them are body-sized.

### Setup

1. Launch the game and open the notebook. Navigate to the Map tab (press `M`).
2. Wait 5 frames.

### Steps

| # | Action | Checkpoint |
|---|--------|-----------|
| 1 | Capture a screenshot of the Map tab. | Save as `tests/e2e/pixel-art-purist/screenshots/notebook_legible_1x_step_03_map.png` on first run. |
| 2 | Inspect the left page. | "World Map" (WorldMapHeading, Heading) is visibly taller than the "World map coming in Phase 2." note below it. |
| 3 | Inspect the right page. | "Local Area" (LocalAreaHeading, Heading) is visibly taller than the "Local map coming in Phase 2." note below it. |

### Expected result

Both page headings read at heading size. Both placeholder notes read at the smaller body size.

---

## Scenario 4 — Settings tab: section headings vs slider captions

**Goal:** "Audio", "Gameplay", "Display" section labels are heading-sized; slider captions
("Master Volume", "Music Volume", etc.) are body-sized.

### Setup

1. Launch the game and open the notebook. Navigate to the Settings tab (press `S` or cycle
   with PageDown until the Settings tab is active).
2. Wait 5 frames.

### Steps

| # | Action | Checkpoint |
|---|--------|-----------|
| 1 | Capture a screenshot of the Settings tab. | Save as `tests/e2e/pixel-art-purist/screenshots/notebook_legible_1x_step_04_settings.png` on first run. |
| 2 | Inspect the left page. | "Audio" (AudioLabel, Heading) is visibly taller than "Master Volume", "Music Volume", "SFX Volume" below it. |
| 3 | Inspect the right page. | "Gameplay" and "Display" are visibly taller than "Text Speed" and the dropdown below them. |

### Expected result

Section names render at 2× the height of the slider captions beneath them.

---

## Scenario 5 — Sessions tab: story name heading vs last-played body text

**Goal:** The story card NameLabel is heading-sized; LastPlayedLabel is body-sized.

### Setup

1. Launch the game and open the notebook. Navigate to the Sessions tab (press PageDown until
   Sessions is active).
2. Wait 5 frames.

### Steps

| # | Action | Checkpoint |
|---|--------|-----------|
| 1 | Capture a screenshot of the Sessions tab. | Save as `tests/e2e/pixel-art-purist/screenshots/notebook_legible_1x_step_05_sessions.png` on first run. |
| 2 | Inspect the story card in the left page (if a save slot exists). | The story name (NameLabel, Heading) is visibly taller than "Last played: N/A" (LastPlayedLabel, body). |
| 3 | If no story card is visible (no save slot). | Note this and skip the size comparison. The test is satisfied if no visual typography regression is present. |

### Expected result

Story name heading renders at 2× the height of the last-played metadata below it.

---

## Notes for the executor

- Run Scenario 1 first — if body-8 fails the legibility gate there, escalate immediately
  before running the remaining scenarios.
- On first run, each captured screenshot IS the baseline. Commit it alongside this file
  (under `tests/e2e/pixel-art-purist/screenshots/`) so future runs have a reference.
- Compare screenshots qualitatively — zoom to 4× in an image viewer and confirm size ratios
  visually. There is no pixel-diff tool requirement.
- Tab-navigation key names above are approximate; check the actual input map in project.godot
  if a key does not open the expected tab. The notebook action is `open_notebook_inventory`
  for I and `notebook_page_next` / `notebook_page_prev` for PageDown/PageUp.
- Tab title Labels and the close hint Label are intentionally absent — they are deferred to
  a separate task and are not part of this scenario's scope.
