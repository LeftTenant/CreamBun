# Scenario: World grid renders at 32×16 tile density (Slice 2)

Verifies that after Slice 2 (TILE_SIZE rescale from 64×32 to 32×16, design doc
§4), the world scene visibly shows roughly double the tile density it did
before — approximately a 10×11 tile grid across the 320×180 viewport, instead
of the old ~5 tiles across. This is a purely visual check: the integration
tests (`tests/integration/world/test_tile_geometry.gd`) already assert the
exact `TileSet.tile_size` and atlas `texture_region_size` values; this
scenario confirms the rescale is actually *visible* on screen, not just
correct in data.

Design doc reference: `docs/features/world-collision/design.md` §4.
Test plan: `docs/features/world-collision/slice-2-tile-geometry-test-plan.md`.

## Setup

- Call `get_config` to obtain `reports_dir` (transient/comparison frames go
  there, never into `tests/e2e/`).
- Call `launch_game`.
- Wait: 20 frames (allow the world scene, tilemap, and camera to fully
  initialize before the first screenshot).

## Steps

### Step 1: World renders a visibly denser tile grid than the old 64×32 tiles

- Screenshot → compare / save reference:
  `tests/e2e/world-collision/screenshots/tile_rescale_step_01_launch.png`
- Assert: no red engine error/assertion overlay visible anywhere in the frame.

**Visual checkpoints for this screenshot:**

1. **Roughly 10 tile-widths span the 320px-wide viewport.** Each terrain tile
   (grass / flower grass) should now be about 32 logical pixels wide — at the
   default 1280×720 launch window (4× scale) that is ~128 physical pixels per
   tile column. Count visible tile-edge seams across the width of the visible
   ground; there should be noticeably more, and noticeably smaller, tiles than
   in any pre-Slice-2 reference capture (which showed only ~5 tiles across the
   full width at the old 64×32 size).
2. **Roughly 11 tile-heights span the 180px-tall viewport.** Same reasoning
   vertically, using the tile's 16px foreshortened depth.
3. **Tiles are still visually 2:1 (twice as wide as they are tall).** The
   rescale halves both dimensions proportionally (64×32 → 32×16), so the
   foreshortened-ground look should be unchanged — only the on-screen tile
   *count* should differ, not the ground's apparent perspective.
4. **No stretching, tearing, or seam artifacts.** If a texture's on-disk size
   doesn't match the TileSet's `texture_region_size`, tiles will appear
   stretched, repeated oddly, or offset from their neighbours. The grass
   texture should tile cleanly with no visible seams or warping.

---

## Notes for the executor

- **This scenario intentionally does not check specific game-state
  properties** (no `get_node_property` calls) — Slice 2 is a pure visual
  rescale of existing art and TileSet data, and the integration tests already
  cover the exact numeric assertions. This document exists to catch anything
  those numeric checks can't — e.g. a texture that reports the right
  dimensions but doesn't visually tile correctly.
- **Reference screenshot**: on first run of this scenario (post-Slice-2),
  save the capture as the reference under
  `tests/e2e/world-collision/screenshots/`. There is no pre-Slice-2 reference
  committed for direct pixel-diff comparison — judge tile density and
  proportions qualitatively against the checkpoints above, not against an
  older screenshot.
- **Transient / comparison frames** captured while iterating must be saved to
  `<reports_dir>/e2e/` (gitignored), never into the committed `tests/e2e/`
  tree. Call `get_config` to retrieve `reports_dir` before saving any
  comparison shot.
- **Scope**: this scenario does not verify TileSet physics/collision (no
  physics layer exists yet at Slice 2 — that is a later slice per design doc
  §6 and §15 phasing item 2), prop rendering, or the player's collider
  changes (design doc §10, also a later slice). It checks tile *geometry*
  only.
