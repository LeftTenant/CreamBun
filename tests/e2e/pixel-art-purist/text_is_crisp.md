# Pixel-Art-Purist — Text Is Crisp

**Design reference:** `docs/refactors/pixel-art-purist-size-and-theme.md` §2 and §7 Step 5
**Test plan:** `docs/features/pixel-art-purist/slice-4-pixel-perfect-stretch-snap-test-plan.md`

## Purpose

Verify that the switch from `stretch/mode="viewport"` to `"canvas_items"` (plus the `"integer"`
scale mode and pixel-snap rendering flags) delivers the expected visual outcome:

- Glyph edges are hard pixel-boundaries — no blur, no anti-aliasing fringe.
- The same crispness holds at both the default 4× launch window (1280×720) and a 2× integer scale
  (640×360, the minimum allowed window size).
- After a camera pan, world sprites hold their positions without shimmer or sub-pixel jitter.

These are rendering-mode differences that cannot be confirmed by any in-process GUT assertion.
Screenshots are the only verification method.

## Preconditions

- `project.godot` has been updated with all five Slice 4 keys (`canvas_items`, `keep`,
  `integer`, both snap flags).
- The game runs headlessly via the testing-sandbox MCP server.
- Reference screenshots are stored at
  `tests/e2e/pixel-art-purist/screenshots/` (committed baselines).
- Transient comparison captures go to `.godot-test-reports/e2e/` (gitignored).

---

## Scenario 1 — Hard-edged text at default 4× window (1280×720)

**Goal:** At the default launch window size, notebook text shows clean single-pixel glyph edges.

### Setup

1. Launch the game at its default window size (1280×720 — 4× the 320×180 viewport).
2. Wait for the world scene to be ready.

### Steps

| # | Action | Checkpoint |
|---|--------|-----------|
| 1 | Open the notebook (press `I` to open the inventory tab). | Notebook is visible with text labels. |
| 2 | Capture a screenshot of the full window. | Save to `tests/e2e/pixel-art-purist/screenshots/text_crisp_step_01_4x_window.png` on first run; compare against baseline on subsequent runs. |
| 3 | Inspect the screenshot at the pixel level. | Every glyph boundary is a hard single-pixel step — no gray or colored fringe pixels adjacent to character edges. Confirm by zooming the captured image to 4× in the viewer. |

### Expected result

Each character in the notebook text (tab labels, item names, gold count) has hard pixel-aligned
edges. No smoothing artifacts. If anti-aliasing fringe is present, the `canvas_items` stretch
mode was not applied correctly or the font is using linear filtering instead of Nearest.

---

## Scenario 2 — Hard-edged text at 2× integer scale (640×360)

**Goal:** Resizing down to 640×360 (the 2× minimum window — 2× the 320×180 base) preserves the
same hard edges — `integer` scale mode must not introduce any fractional scaling at the smallest
supported size.

### Setup

1. Launch the game (default window is 1280×720 at 4× scale).
2. Resize the window to 640×360 (or configure `window_width_override` / `window_height_override`
   to 640×360 for the test run if the sandbox supports it).
3. Wait for the resize to settle (at least 5 frames).

### Steps

| # | Action | Checkpoint |
|---|--------|-----------|
| 1 | Open the notebook (press `I`). | Notebook text is visible at the smaller window. |
| 2 | Capture a screenshot of the full window. | Save to `tests/e2e/pixel-art-purist/screenshots/text_crisp_step_02_2x_window.png` on first run; compare against baseline on subsequent runs. |
| 3 | Inspect the screenshot at the pixel level. | Each pixel is a clean single-pixel edge — the same sharpness as Scenario 1, just at half the screen resolution. No blurred transitions. No color fringing. |

### Expected result

The 2× window shows crisp pixel art at the minimum supported scale. If any smoothing or
non-integer scaling artifact is visible, the `integer` scale mode is not active in `project.godot`.
Note: 640×360 is enforced as the minimum window size by `world.gd:_set_minimum_window_size()`.

---

## Scenario 3 — No shimmer after camera pan

**Goal:** After the player walks several tiles and the camera follows, world sprites sit on whole
pixel coordinates — no jitter or shimmering between frames.

### Setup

1. Launch the game at 1280×720 (the default 4× window).
2. Wait for the world scene and player to be ready.

### Steps

| # | Action | Checkpoint |
|---|--------|-----------|
| 1 | Hold the `move_right` action for approximately 30 frames (about 0.5 seconds at 60 fps) to walk the player several tiles right, panning the camera. | Player moves; camera tracks. |
| 2 | Release movement. | Player idles. |
| 3 | Wait 5 frames for any in-flight camera interpolation to settle. | Camera is at rest. |
| 4 | Capture a screenshot. | Save to `tests/e2e/pixel-art-purist/screenshots/text_crisp_step_03_post_pan.png` on first run; compare against baseline on subsequent runs. |
| 5 | Inspect the screenshot. | Sprite tile edges are consistent single-pixel lines. No pixel-width variation in what should be uniform vertical or horizontal tile edges. |

### Expected result

World tile edges are clean and consistent. If shimmer is present — visible as a 1-pixel-wide
flicker at tile boundaries — either `snap_2d_transforms_to_pixel` or `snap_2d_vertices_to_pixel`
is not set to `true` in `project.godot`, or `Camera2D.position_smoothing_enabled` was
accidentally set to `true` in `player/player.tscn`. The integration test
`tests/integration/player/test_player_scene.gd` guards against the latter.

---

## Notes for the executor

- Run Scenarios 1 and 2 before Scenario 3 — if text is blurry in Scenario 1, Slice 4 keys are
  missing and there is no point continuing.
- On first run of each scenario, the captured screenshot IS the baseline. Commit it alongside this
  file so future runs have a reference.
- Compare screenshots qualitatively — zoom to 4× in an image viewer and visually confirm hard
  pixel edges. There is no pixel-diff tool requirement for these scenarios.
- If the sandbox cannot resize the window for Scenario 2, skip it and note the limitation; the
  4× default launch and post-pan checks are the higher-priority signals.
- The default launch window is now 1280×720 (4× of 320×180). The minimum allowed size is
  640×360 (2×), enforced at runtime by `world.gd:_set_minimum_window_size()`. There is no 1× option.
