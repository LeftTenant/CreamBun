# Scenario: World frames correctly at 320×180 viewport / 640×360 window (Slice 3)

Verifies that after Slice 3 (resize viewport to 320×180 with a 640×360 launch
window at 2× pixel scale), the game opens cleanly, world content is fully
visible, the notebook fits the smaller canvas, and the camera keeps the player
on-screen at the new render size.

Design doc reference: `docs/refactors/pixel-art-purist-size-and-theme.md` §1
and §7 Step 4.
Slice spec: `docs/features/pixel-art-purist/slices.md` Slice 3.
Test plan: `docs/features/pixel-art-purist/slice-3-resize-viewport-test-plan.md`

**This scenario was written for Slice 3 (640×360 window at 2× scale). The project
now launches at 1280×720 (4× scale) by default. The viewport is still 320×180.
The reference screenshots below were captured at 640×360. If re-running, launch
at 640×360 (2× scale) by setting the OptionButton to index 0 in the settings tab,
or update the references to reflect the current 1280×720 default launch window.**

## Setup

- Call `get_config` to obtain `reports_dir` (transient frames go there, not
  into `tests/e2e/`).
- Launch game via `launch_game`.
- Wait: 20 frames (allow the world scene, player, and camera to fully
  initialise before any screenshot or property check).

## Steps

### Step 1: Window opens at correct size with no engine error overlay

- Screenshot → compare / save reference:
  `tests/e2e/pixel-art-purist/screenshots/world_frames_step_01_launch.png`
- Assert: no red engine error/assertion overlay visible anywhere in the frame
  (a solid overlay with pink or red text is the Godot "script error" panel
  that appears when an uncaught engine-level error occurs).

**Visual checkpoints for this screenshot:**

1. **Window physical dimensions match the configured override.** The current
   `window_width_override` is 1280 and `window_height_override` is 720 (the 4×
   default). If running this scenario at 2× (640×360), launch with an override
   or via the settings tab first. The engine error overlay (if present) would
   occupy the top portion of the screen in bright red/pink; its absence confirms
   the viewport/window pair is accepted without error.
2. **World scene is visible.** Tilemap tiles or a placeholder background should
   fill most of the frame, confirming the main scene loaded successfully.

---

### Step 2: Tilemap and player sprite are fully visible inside the viewport

- (No additional input — still in the initial world state from Step 1.)
- Wait: 5 frames
- Get node property: `World/ActiveArea/Meadow/Ground.visible` (or the actual TileMapLayer node
  path — check the scene tree if the path differs; post-Slice-8 the tile layers live on the
  `Meadow` WorldArea instanced under `World/ActiveArea`, not directly under `World`)
- Assert: `visible` == `true`
- Screenshot → compare / save reference:
  `tests/e2e/pixel-art-purist/screenshots/world_frames_step_02_world_visible.png`

**Visual checkpoints for this screenshot:**

1. **Tilemap tiles fill the canvas.** At least one full row of tiles should be
   visible along the top and bottom edges of the 320×180 render area (scaled to
   640×360 on screen). If the tilemap is clipped — meaning the bottom row or
   right column of tiles is cut off — the camera or starting scroll position
   needs adjustment.
2. **Player sprite is fully on-screen.** The player (Cream Bun) should appear
   somewhere in the viewport with no portion of the sprite clipped by the
   canvas boundary. Partial clipping (e.g. only the player's feet visible at
   the very bottom) counts as a failure; the player must be fully inside the
   frame.
3. **No black bars or blank regions.** The entire 640×360 window area should be
   filled with world content — no unused black margin strips that would indicate
   the tilemap does not cover the full viewport.

---

### Step 3: Notebook Book panel fits the 320×180 canvas with no overflow

- Press action: `open_notebook_inventory`
- Wait: 15 frames (allow the notebook to finish opening and rendering)
- Assert: node property `Notebook.visible` == `true`
- Assert: `GameState.current_state` == `NOTEBOOK`
- Screenshot → compare / save reference:
  `tests/e2e/pixel-art-purist/screenshots/world_frames_step_03_notebook_open.png`

**Visual checkpoints for this screenshot:**

1. **Book panel is fully within the 640×360 window.** No edge of the Book
   container should be clipped or extend beyond the window boundary. The panel
   may not fill the full width (it is expected to occupy most but not all of
   the canvas), but every visible edge must be inside the frame.
2. **No horizontal or vertical overflow scrollbar on the Book container
   itself.** A ScrollContainer scrollbar appearing on the outer Book panel
   (as opposed to an inner list) means the panel content overflows the canvas
   and must be resized or reflowed for the 320×180 canvas.
3. **Tab content is legible.** At least one line of tab-area text (inventory
   slot label or heading) is readable, confirming the smaller canvas did not
   collapse the layout to zero height.

---

### Step 4: Dimmer ColorRect covers the full viewport

- (Notebook is still open from Step 3.)
- Get node property: `Notebook/Dimmer.color` (or the actual ColorRect node path
  — typically `CanvasLayer/Dimmer` or similar; check world.tscn / notebook.tscn
  if the path differs)
- Get node property: `Notebook/Dimmer.visible`
- Assert: `visible` == `true`
- Screenshot → compare / save reference:
  `tests/e2e/pixel-art-purist/screenshots/world_frames_step_04_dimmer.png`
  (may reuse step 3 capture if the notebook was already fully rendered)

**Visual checkpoints for this screenshot:**

1. **No uncovered corners.** The dimmer layer should be a semi-transparent
   dark overlay that reaches all four corners of the 640×360 window. If any
   corner shows raw world tiles without the dimmer tint, the ColorRect anchors
   are not set to FULL_RECT (anchors_preset=15) or the parent CanvasLayer's
   size is stale at the new canvas size.
2. **Dimmer does not block notebook content.** The Book panel and tabs must be
   visible above the dimmer — the dimmer sits behind the notebook panel in
   z-order. If only a black screen appears with no notebook UI, the z-order is
   inverted.

---

### Step 5: Player is on-screen after camera framing

- Press action: `ui_cancel`
- Wait: 10 frames (allow notebook to close and camera to settle)
- Assert: node property `Notebook.visible` == `false`
- Assert: `GameState.current_state` == `PLAYING`
- Screenshot → compare / save reference:
  `tests/e2e/pixel-art-purist/screenshots/world_frames_step_05_player_framed.png`

**Visual checkpoints for this screenshot:**

1. **Player is fully on-screen.** After the notebook closes, the camera should
   frame the player within the 320×180 viewport (displayed at 640×360). The
   player sprite must be fully visible with no clipping. This is the key
   regression check for the spawn-position concern noted in the test plan:
   if the camera does not follow the player from spawn, the player will start
   at world-space (640, 360) — four viewport-widths to the right of a 320×180
   canvas — and appear off-screen.
2. **World content surrounds the player.** Tiles should be visible around the
   player, not just a black void, confirming the camera has scrolled to the
   player's location rather than remaining at the world origin.
3. **No partial off-screen clipping.** The test plan notes that the coder may
   fix the spawn point to (160, 90) — the centre of the 320×180 viewport — or
   rely on the camera tracking. Either fix is acceptable; this step verifies
   only the visual outcome (player visible and framed), not the implementation.

---

## Notes for the executor

- **Reference screenshots** committed under
  `tests/e2e/pixel-art-purist/screenshots/` for this scenario were taken at
  640×360 physical pixels (the 2× window for the 320×180 viewport). The current
  default launch is 1280×720 (4×). If running this scenario against the live
  defaults, capture at 1280×720 and update the reference screenshots accordingly.
- **Transient / comparison frames** captured while iterating must be saved to
  `<reports_dir>/e2e/` (gitignored), never into the committed `tests/e2e/`
  tree. Call `get_config` to retrieve `reports_dir` before saving any
  comparison shot.
- **Node paths**: the exact paths to `TileMapLayer`, `Dimmer`, and `Notebook`
  depend on the world.tscn scene tree. Use `get_game_state` to inspect the
  live tree if a `get_node_property` call fails with "node not found", and
  adjust the path accordingly. Document any path corrections in these notes
  after the first run.
- **Step 2 tilemap path note**: If `World/ActiveArea/Meadow/Ground` does not resolve, try
  `World/ActiveArea/Meadow/Solids` — post-Slice-8's WorldArea restructure moved the tile layers
  into the swappable `Meadow` area instanced under `ActiveArea`; the actual node name/path in the
  live scene tree takes precedence over this document.
- **Player spawn concern (test plan §Judgment calls)**: If Step 5 fails
  because the player is off-screen, the fix is either moving the Player node's
  `position` in world.tscn from `Vector2(640, 360)` to `Vector2(160, 90)`, or
  confirming that the camera's `position_smoothing_enabled` and
  `drag_*` settings cause it to track from the very first frame. This document
  tests the observable outcome only — consult the coder for the chosen fix.
- **Scope**: this scenario does not verify font rendering (Slice 2),
  stretch/scale_mode integer snapping (Slice 4), or per-widget font sizes
  (Slice 5). Keep screenshot checks focused on layout and visibility.
