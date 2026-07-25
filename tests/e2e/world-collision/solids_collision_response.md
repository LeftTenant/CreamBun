# Scenario: Solids tiles block movement; Ground-only tiles do not (Slice 4)

Verifies that after Slice 4 (TileSet physics layer + Ground/Solids Y-sort
restructure, design doc §6, §6.1), walking Cream Bun toward a painted
`Solids` tile that carries a collision polygon visibly stops them at its
edge, while walking onto a tile painted only on `Ground` lets them cross it
without interruption. This is a purely behavioral/visual check: the
integration tests (`tests/integration/world/test_solids_collision.gd`)
already assert the exact `TileSet` physics-layer values and drive the player
programmatically via `move_and_slide()` to confirm the numeric stop/cross
distances; this scenario confirms the same behavior is legible when actually
playing the game with real input.

Design doc reference: `docs/features/world-collision/design.md` §6 (painted
terrain collision), §6.1 (Ground/Solids layer structure), §9 (depth
sorting — not directly exercised here, but Solids is Y-sorted per §6.1 so
watch for a painted tile visually overlapping the player correctly while you
work).
Test plan: `docs/features/world-collision/slice-4-tileset-physics-test-plan.md`.

## Setup

- Call `get_config` to obtain `reports_dir` (transient/comparison frames go
  there, never into `tests/e2e/`).
- Call `launch_game`.
- Wait: 20 frames (allow the world scene, tilemap, player, and camera to
  fully initialize before the first screenshot).
- Get node property: `Player.position` — record this as the baseline. (Check
  the actual Player node path in the live scene tree if it differs from
  `World/Player`.)

**Important — this scenario is exploratory by design.** Slice 4 only
guarantees that *at least one* tile painted on `Solids` has a collision
polygon (design doc §15 phasing item 2: "give one test tile a collision
polygon"); its exact map location is level-design data, not something this
document can hard-code ahead of implementation. The steps below use
`Player.position` sampling — not a fixed destination — to find it. Explore
patiently; the interesting result is the *contrast* between a direction that
blocks and one that doesn't, not any specific coordinate.

## Steps

### Step 1: Find a direction that blocks movement

For each of the four directions in turn (`move_up`, `move_down`,
`move_left`, `move_right`) — starting from the baseline position recorded in
Setup, and returning to a known-clear tile between attempts if a direction
turns out blocked partway through:

1. `press_action` the direction.
2. `wait_frames` 30.
3. Get node property: `Player.position`. Call this **checkpoint A**.
4. `wait_frames` 30 more (60 total held).
5. Get node property: `Player.position` again. Call this **checkpoint B**.
6. `release_action` the direction.

Compare checkpoint A and checkpoint B:

- **If they are equal (or differ by only a pixel or two of slide/settle):**
  this direction has hit a `Solids` tile with collision. This is the
  direction to use for Step 2 below. Note the position and which direction
  it was.
- **If position B has advanced roughly another 30 physics-ticks' worth of
  travel past position A** (i.e. movement continued at the same rate): this
  direction is clear (either open `Ground` or simply hasn't reached a
  `Solids` tile yet within 60 ticks). Move on and try the next direction, or
  hold longer / walk further before concluding it's clear.

Once a blocking direction is found, continue to Step 2 without releasing
the "known good" state — i.e. you may need to `reset_state` and re-approach
cleanly for the screenshot pair below, now that you know which direction and
roughly how far to hold.

### Step 2: Screenshot pair confirming the block reads as a stop, not a slowdown

Re-approach the blocking tile found in Step 1 from a clean state
(`reset_state` first if convenient):

- `press_action` the blocking direction.
- `wait_frames` 30.
- Screenshot → compare / save reference:
  `tests/e2e/world-collision/screenshots/solids_collision_step_02_mid_approach.png`
- `wait_frames` 60 more (90 total held).
- Screenshot → compare / save reference:
  `tests/e2e/world-collision/screenshots/solids_collision_step_02_still_stopped.png`
- `release_action` the blocking direction.

**Visual checkpoint:** the two screenshots should look **identical** —
same player position and pose relative to the tile grid, same camera
framing. This is the test plan's key assertion in visual form: "a screenshot
taken mid-approach and one taken after several more frames of held input
look identical, confirming the tile visually blocks further movement rather
than merely slowing it." If the player has visibly crept forward between the
two shots (even slightly), that reads as a *slowdown*, not a block — flag it,
since it suggests partial collision (e.g. a too-small or misaligned collision
polygon) rather than the full stop the design calls for.

### Step 3: Uninterrupted movement across a Ground-only tile, for contrast

Pick any direction from Step 1 that was clear (did not plateau), or simply
face away from the blocking tile found above:

- `press_action` that direction.
- `wait_frames` 30.
- Screenshot → compare / save reference:
  `tests/e2e/world-collision/screenshots/solids_collision_step_03_crossing_ground.png`
- Get node property: `Player.position`.
- `release_action` the direction.

**Visual checkpoint:** the player should have visibly moved a meaningful
distance from the Setup baseline (compare the recorded positions — the delta
should be close to `speed * elapsed_time`, not near zero), and the
screenshot should show them mid-stride over plain terrain with nothing
visibly obstructing them. This is the direct contrast to Step 2's frozen
pair.

---

## Notes for the executor

- **Assert in every step:** no red engine error/assertion overlay visible
  anywhere in any frame.
- **This scenario intentionally does not assert exact pixel positions or
  TileSet data** — the integration tests already cover the numeric collision
  polygon, `collision_layer`, and stop/cross-distance assertions exactly.
  This document exists to catch what those can't: whether the block reads,
  on screen, as a hard stop rather than a slowdown, jitter, or partial
  clip.
- **Reference screenshots**: on first run of this scenario (post-Slice-4),
  save the three captures as references under
  `tests/e2e/world-collision/screenshots/`. There is no pre-Slice-4
  reference to diff against (nothing blocked movement before this slice) —
  judge the "identical pair vs. visibly different" contrast described above,
  not against an older screenshot.
- **Transient / comparison frames** captured while exploring for the
  blocking direction (Step 1) must be saved to `<reports_dir>/e2e/`
  (gitignored), never into the committed `tests/e2e/` tree. Call
  `get_config` to retrieve `reports_dir` before saving any exploratory or
  comparison shot. Only the three named screenshots in Steps 2–3 belong in
  the committed `tests/e2e/world-collision/screenshots/` folder.
- **If Step 1 finds no blocking direction within a reasonable search** (e.g.
  60+ tiles held in every direction with no plateau), this is a genuine
  bug — Slice 4 requires at least one `Solids` tile with a collision
  polygon to be reachable from spawn (design doc §15 phasing item 2). Do not
  keep expanding the search indefinitely; report it as a finding rather than
  exploring the entire map.
- **Scope**: this scenario does not verify Y-sort draw order between the
  player and a `Solids` tile (design doc §9) — that is implicitly visible in
  the screenshots but not called out as a checkpoint here, since no props
  exist yet to make Y-sort interesting (that lands in later slices per
  design doc §15 phasing items 3–5). It checks collision *response* only.
