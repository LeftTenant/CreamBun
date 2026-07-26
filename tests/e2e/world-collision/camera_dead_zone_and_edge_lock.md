# Scenario: Camera dead zone, edge lock, and perimeter walls (Slice 9)

Verifies Slice 9 — "Camera dead zone, edge lock, and perimeter walls" — the parts of design
doc §12.3 (camera derivation) and §12.4 (no-neighbour invisible wall) that a GUT test cannot
confirm: whether the camera's behavior actually *reads* right on screen as Cream Bun roams the
meadow and approaches each of its four edges. The numeric properties this depends on
(`Camera2D.limit_*`, `drag_*_margin`, `drag_*_enabled`, `position_smoothing_enabled`, and the
perimeter walls' collision geometry) are already covered precisely by
`tests/integration/world/test_camera_dead_zone_and_limits.gd` and
`tests/integration/world/test_perimeter_walls.gd` — this document exists to catch what those
can't: whether the camera visibly stops at the map edge without ever showing the void beyond the
painted floor, whether the player is visibly halted rather than sliding off-screen, and whether
roaming the interior actually feels like a dead zone rather than the camera locking to the
player's exact position.

Design doc reference: `docs/features/world-collision/design.md` §12.3 (camera dead-zone/edge-lock
derivation), §12.4 (the no-neighbour invisible-wall case only — open-edge triggers are slice 10,
out of scope here).
Test plan: `docs/features/world-collision/slice-9-camera-perimeter-test-plan.md`.

**Node path convention**: per slice 8's restructure, the player (and its child `Camera2D`) is
reparented at runtime from the world shell into the currently-loaded area, so its live path is
`World/ActiveArea/Meadow/Player`, not `World/Player` — see `boulder_collision_and_sort.md` and
`player_feet_anchor_baseline.md` for the same convention already established in this folder.

**Meadow bounds for reference (confirm live, don't assume):** as of this writing, meadow.tscn's
`Ground` layer is painted as a complete rectangle spanning tile x in `[0, 16]` and tile y in
`[1, 20]` (17 x 20 tiles). At `TILE_SIZE = (32, 16)`, `get_bounds_px()` should therefore return
`Rect2(position=(0, 16), size=(544, 320))`, i.e. `limit_left=0, limit_top=16, limit_right=544,
limit_bottom=336`. This is exactly the kind of value this scenario should read live (via
`Camera2D.limit_*` properties in Setup below) rather than trust from this document — the meadow's
painted extent has already changed once during this feature's authoring (it was hand-edited into
this rectangle after slice 8's tests were written against its old irregular shape), and could
change again.

## Setup

- Call `get_config` to obtain `reports_dir` (transient/comparison frames go there, never into
  `tests/e2e/`).
- Call `launch_game`.
- Wait: 20 frames (allow the world scene, tilemap, player, and camera to fully initialize).
- Get node property: `World/ActiveArea/Meadow/Player/Camera2D.limit_left`, `.limit_top`,
  `.limit_right`, `.limit_bottom`. Record these four as **limit_left/top/right/bottom** — the
  ground truth for every "does the camera stop exactly here" checkpoint below. If these read as
  Camera2D's engine defaults (`-10000000` / `10000000`) rather than the meadow's bounds, the
  camera-limit wiring doesn't exist yet — stop and report that rather than attempting the
  walk-to-edge steps, since there is nothing meaningful to observe.
- Get node property: `World/ActiveArea/Meadow/Player.position`. Record as **spawn_position**.
- Screenshot → save to `<reports_dir>/e2e/` (not the committed tree): a baseline reference showing
  the player at spawn, useful context for judging the checkpoints below.

## Steps

### Step 1: Interior roaming — the dead zone lets the player drift before the camera follows

This is the one checkpoint in this scenario that is NOT about an edge — it establishes that the
camera has a dead zone at all, before the edge-lock steps below establish what happens once the
player leaves it.

- From spawn (well inside the meadow, away from any edge), `press_action move_right`.
- `wait_frames` 10 (a short nudge — well under the two-tile/64px dead zone width, not a full
  walk to any edge).
- `release_action move_right`.
- Get node property: `World/ActiveArea/Meadow/Player.position` (call this **nudge_position**) and
  `World/ActiveArea/Meadow/Player/Camera2D.global_position` (call this **camera_position_after_nudge**).
- Screenshot → compare / save reference:
  `tests/e2e/world-collision/screenshots/camera_dead_zone_step_01_interior_nudge.png`

**Visual checkpoint:** the player should have visibly moved off-centre in the frame — Cream Bun
noticeably closer to one side of the viewport than dead-centre — while the background tiles
should NOT have scrolled by anywhere near the same amount the player moved (compare
`camera_position_after_nudge` against the Setup baseline: it should have moved little to not at
all for a nudge this small, since design doc §12.3's two-tile/64px-wide dead zone is much larger
than a 10-frame nudge at the player's normal speed). If the camera instead tracked the player
pixel-for-pixel (background scrolled by the same amount the player visibly moved), the dead zone
isn't working — report this as a bug rather than continuing.

### Step 2: Walking to the north edge

- Reset to spawn (`reset_state`, or otherwise reposition to **spawn_position**).
- `press_action move_up`.
- `wait_frames` in increments (e.g. 30 at a time) until `Player.position.y` stops changing between
  two successive reads — the same plateau-detection idea used in
  `solids_collision_response.md`'s Step 1 — or until roughly 5 seconds of simulated time has
  passed, whichever comes first.
- `release_action move_up`.
- Get node property: `World/ActiveArea/Meadow/Player.position`. Call this **stop_position_north**.
- Get node property: `World/ActiveArea/Meadow/Player/Camera2D.global_position`. Call this
  **camera_position_north**.
- Screenshot → compare / save reference:
  `tests/e2e/world-collision/screenshots/camera_edge_lock_step_02_north.png`

**Visual checkpoints:**

1. **The player is visibly halted, not sliding off-screen or continuing to press against the
   viewport's top edge.** Cream Bun's sprite should be fully on screen and stationary once
   released — this is the invisible perimeter wall from design doc §12.4 stopping `move_and_slide()`,
   not the camera merely clipping what's drawn.
2. **`stop_position_north.y` should be close to `limit_top + NORTH_WALL_HEADROOM_INSET_PX +
   5`** — noticeably *more* than `limit_top` itself, not "a few pixels of tolerance" above it.
   `NORTH_WALL_HEADROOM_INSET_PX` (32px, `world/areas/shared/world_area.gd`) is a deliberate
   inset: the north perimeter wall's player-facing surface sits one sprite-height south of the
   true painted north edge, so the camera (clamped to `limit_top` at that true edge) always keeps
   a full sprite-height of headroom above the player's feet — otherwise the player's sprite would
   stop entirely above the visible viewport. The `+ 5` is the player's own collider half-depth
   (design.md §10's (20, 10) collider, half of 10px). With the meadow's current `limit_top = 16`,
   expect a stop position around **y = 53** — a ~37px gap from `limit_top`, which is correct by
   design, not a bug: the strip of painted ground between the true edge and this stop line is a
   non-walkable decorative backdrop (design.md §12.4) — it should be visible in the screenshot
   above the player's resting position, but the player can never actually walk into it.
3. **No unpainted void is visible above the topmost row of ground tiles.** The camera's
   `limit_top` should have locked the view so the viewport's top edge sits flush with (or inside)
   the meadow's painted floor — there should be no black/empty background strip visible above the
   grass.
4. **The camera itself has stopped scrolling** — `camera_position_north` should match (or be very
   close to) whatever the camera's last few reads were as the player approached, not still
   trailing behind the player's stopped position (which would indicate `position_smoothing_enabled`
   is still catching up — if the camera visibly continues to glide for more than a few frames
   after the player has fully stopped, that's expected per the "cozy glide," but it must settle,
   not oscillate or drift indefinitely).

### Step 3: Walking to the south edge

Mirror of Step 2.

- Reset to spawn.
- `press_action move_down`, wait for plateau (or ~5s), `release_action move_down`.
- Get node property: `World/ActiveArea/Meadow/Player.position`. Call this **stop_position_south**.
- Screenshot → compare / save reference:
  `tests/e2e/world-collision/screenshots/camera_edge_lock_step_03_south.png`

**Visual checkpoints:** same shape as Step 2 — halted (not sliding off-screen), `stop_position_south.y`
close to but not greater than `limit_bottom`, no unpainted void visible below the bottommost row of
ground tiles, camera settled rather than still trailing.

### Step 4: Walking to the east edge

- Reset to spawn.
- `press_action move_right`, wait for plateau (or ~5s), `release_action move_right`.
- Get node property: `World/ActiveArea/Meadow/Player.position`. Call this **stop_position_east**.
- Screenshot → compare / save reference:
  `tests/e2e/world-collision/screenshots/camera_edge_lock_step_04_east.png`

**Visual checkpoints:** same shape again — halted, `stop_position_east.x` close to but not greater
than `limit_right`, no unpainted void visible to the right of the rightmost column of ground
tiles, camera settled.

### Step 5: Walking to the west edge

- Reset to spawn.
- `press_action move_left`, wait for plateau (or ~5s), `release_action move_left`.
- Get node property: `World/ActiveArea/Meadow/Player.position`. Call this **stop_position_west**.
- Screenshot → compare / save reference:
  `tests/e2e/world-collision/screenshots/camera_edge_lock_step_05_west.png`

**Visual checkpoints:** same shape again — halted, `stop_position_west.x` close to but not less
than `limit_left`, no unpainted void visible to the left of the leftmost column of ground tiles,
camera settled.

---

## Notes for the executor

- **Assert in every step:** no red engine error/assertion overlay visible anywhere in any frame.
- **This scenario intentionally does not assert exact pixel positions or collider geometry** —
  `tests/integration/world/test_camera_dead_zone_and_limits.gd` and
  `tests/integration/world/test_perimeter_walls.gd` already cover the numeric `Camera2D.limit_*`/
  `drag_*_margin`/`drag_*_enabled`/`position_smoothing_enabled` values and the perimeter walls'
  collision-blocking behavior precisely. This document exists to catch what those can't: whether
  the edge lock and dead zone actually *read* correctly on screen.
- **Reference screenshots**: on first run of this scenario (post-Slice-9), save the five captures
  (interior nudge + four edges) as references under `tests/e2e/world-collision/screenshots/`.
  There is no pre-Slice-9 reference to diff against — judge each against the checkpoints described
  above, not against an older screenshot.
- **Transient / comparison frames** — the Setup baseline screenshot and any exploratory shots used
  to confirm plateau detection or re-check `limit_*` values — must be saved to
  `<reports_dir>/e2e/` (gitignored), never into the committed `tests/e2e/` tree. Call `get_config`
  to retrieve `reports_dir` before saving any such shot. Only the five named screenshots in Steps
  1–5 belong in the committed `tests/e2e/world-collision/screenshots/` folder.
- **If `Camera2D.limit_*` still reads as engine defaults** (`-10000000`/`10000000`) when checked in
  Setup, or if the player is observed sliding smoothly off-screen at any edge instead of being
  halted, this scenario cannot proceed meaningfully — report the missing implementation rather
  than forcing the remaining steps.
- **Scope**: this scenario does not re-verify `Ground`/`Solids` tile collision (covered by
  `solids_collision_response.md`) or boulder/tree footprint collision (covered by
  `boulder_collision_and_sort.md`) — it is scoped to the camera's dead zone, edge lock, and the
  four perimeter walls introduced in this slice. It also does not cover open-edge transitions
  (walking through a linked neighbour) — meadow.tscn declares no `neighbour_*` scenes as of this
  slice, so every edge is a hard wall; slice 10 is where an open edge and its own scenario land.
