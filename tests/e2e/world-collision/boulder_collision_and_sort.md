# Scenario: Boulder blocks by footprint (not silhouette) and Y-sorts correctly (Slice 6)

Verifies Slice 6 — "Boulder: first real prop, proven end-to-end" — the slice design doc §15
calls out as where the whole `WorldProp` design (§7–§9) gets proven or falls over. A single
`Boulder` instance (`world/props/boulder.tscn`) is placed near the player's spawn point. This
scenario walks Cream Bun into it from all four compass directions and confirms two things a GUT
test cannot: that the *visual* stop point reads correctly on screen (not just that some numeric
collider blocks `move_and_slide()` — the integration tests in
`tests/integration/world/props/test_boulder.gd` already cover that), and that draw order (Y-sort)
puts the player in front of or behind the boulder correctly depending on which side they're
standing on.

Design doc reference: `docs/features/world-collision/design.md` §7 (discrete props), §7.1
(placeholder art honesty rules), §8 (footprint and ground anchor), §9 (depth sorting).
Test plan: `docs/features/world-collision/slice-6-boulder-test-plan.md`.

**Expected boulder placement:** this slice places one `Boulder` instance as a direct child of
`world.tscn`'s root, close enough to the player's spawn (`Vector2(288, 176)`) to be reachable from
all four sides — the recommended spot is `Vector2(288, 240)` (64px / 4 tiles due south of spawn,
in open `Ground` with no `Solids` tiles nearby). Confirm the actual authored position via
`get_node_property` in Setup below rather than assuming this exact value — if it differs, use
whatever was actually placed; the checkpoints below only depend on there being open ground on all
four sides of it, not on this specific coordinate.

## Setup

- Call `get_config` to obtain `reports_dir` (transient/comparison frames go there, never into
  `tests/e2e/`).
- Call `launch_game`.
- Wait: 20 frames (allow the world scene, tilemap, boulder, player, and camera to fully initialize
  before the first screenshot).
- Get node property: `World/ActiveArea/Meadow/Boulder.position` (check the actual node path/name
  in the live scene tree if it differs — design doc §6.1 names it `Boulder`; post-Slice-8 it is a
  child of the `Meadow` WorldArea instanced under `World/ActiveArea`, not the world root directly).
  Record this as **boulder_origin**.
- Get node property: `World/ActiveArea/Meadow/Player.position`. Record this as
  **spawn_position**. (The player is a permanent child of the world shell but gets reparented into
  the active area on load — see `world.gd`'s `_load_starting_area()` — so its live path is under
  `Meadow`, not directly under `World`.)
- Screenshot → save to `<reports_dir>/e2e/` (not the committed tree): a baseline reference showing
  the boulder as a grey ellipse near the player, useful context for judging the checkpoints below.

## Steps

Each of the four sub-scenarios below follows the same shape: reset to spawn, walk toward the
boulder from one side, and check where the player actually stops relative to (a) the boulder's
32×16 one-tile footprint and (b) the wider grey ellipse drawn above it. Call `reset_state` between
sub-scenarios if the game doesn't cleanly return the player to spawn on its own.

### Step 1: Approach from the north (walking south into the boulder)

- From spawn, `press_action move_down` (or reposition close to the boulder's north side first if
  spawn isn't directly north of it — use `load_scene`/manual positioning only if needed; otherwise
  just walk there).
- `wait_frames` 60, or until `Player.position` stops changing between two successive reads roughly
  30 frames apart (same plateau-detection idea as `solids_collision_response.md`'s Step 1).
- `release_action move_down`.
- Get node property: `Player.position`. Call this **stop_position_north**.
- Screenshot → compare / save reference:
  `tests/e2e/world-collision/screenshots/boulder_collision_step_01_north_approach.png`

**Visual checkpoints:**

1. **The player stops before entering the boulder's 1×1 footprint, not at the ellipse's visible
   edge.** The footprint is exactly one tile (32×16) centred horizontally on `boulder_origin` and
   extending 16px north of it (its near edge). Because the placeholder ellipse is drawn *taller*
   than the footprint (design doc §7.1 — anchored upward, never centred), the grey ellipse's own
   drawn top edge sits visibly further north than where the player actually stops. **This is the
   single most important screenshot in this scenario**: the grey ellipse should extend further
   north than where collision stops the player, and — being drawn in front (see checkpoint 3) —
   its top edge should visually overlap the player's lower body by a few pixels rather than sitting
   flush against a clean gap. This overlap is itself the proof: the player's feet stopped short of
   the ellipse's northernmost extent (the footprint, not the silhouette, decided where movement
   halted), while the ellipse's own greater height and front draw order make its top edge cover the
   player's lower sprite in the screenshot. If the player instead appears to stop flush against (or
   is blocked by) the ellipse's outer edge with no overlap at all, that's a bug: the collider is
   tracking the sprite, not `footprint` (the exact mistake design doc §8.3 explicitly rejects).
2. **`stop_position_north.y` is measurably less than `boulder_origin.y`** (the player stopped
   north of, i.e. above, the anchor) but the gap should be small — on the order of the footprint's
   16px near-edge offset plus the player's own half-depth, not several tiles' worth.
3. **Draw order: the player renders BEHIND the boulder.** Standing north of the anchor
   (`stop_position_north.y < boulder_origin.y`), Y-sort (design doc §9) should draw the boulder's
   sprite in front of the player — if any part of the player's sprite visually overlaps the
   boulder's silhouette in the screenshot, the boulder should appear on top, not the player. This
   is the "player draws behind the boulder when standing above (north of) its ground anchor"
   checkpoint from the test plan.

### Step 2: Approach from the south (walking north into the boulder)

Reset to spawn (or otherwise reposition south of the boulder).

- `press_action move_up`, `wait_frames` 60 (or until plateau), `release_action move_up`.
- Get node property: `Player.position`. Call this **stop_position_south**.
- Screenshot → compare / save reference:
  `tests/e2e/world-collision/screenshots/boulder_collision_step_02_south_approach.png`

**Visual checkpoints:**

1. **The player stops at the footprint's south (near) edge**, which sits right at
   `boulder_origin.y` (the ground anchor is the footprint's *front* edge, per design doc §8.1) —
   there is little to no vertical gap expected here between the visual base of the ellipse and the
   collision stop point, since the placeholder's ground contact and the footprint's front edge are
   meant to coincide. Contrast this explicitly with Step 1's north approach, where a gap is
   expected — the *absence* of a gap here is itself confirmation that the offset is one-directional
   (upward only), not a placeholder that's merely oversized in every direction.
2. **Draw order: the player renders IN FRONT of the boulder.** Standing south of the anchor
   (`stop_position_south.y > boulder_origin.y`), the player's sprite should visually overlap and
   cover part of the boulder's silhouette where they intersect. This is the "player draws in front
   of the boulder when standing below (south of) its ground anchor" checkpoint from the test plan.

### Step 3: Approach from the east (walking west into the boulder)

Reset to spawn (or otherwise reposition east of the boulder).

- `press_action move_left`, `wait_frames` 60 (or until plateau), `release_action move_left`.
- Get node property: `Player.position`. Call this **stop_position_east**.
- Screenshot → compare / save reference:
  `tests/e2e/world-collision/screenshots/boulder_collision_step_03_east_approach.png`

**Visual checkpoint:** the player stops at the footprint's east edge (16px east of
`boulder_origin.x`, i.e. `stop_position_east.x` should be measurably greater than
`boulder_origin.x` by roughly that margin, not several tiles further out). Note for the executor:
design doc §7.1 only calls out *vertical* placeholder anchoring explicitly (offset upward from the
anchor) — nothing mandates the ellipse be visually wider than the one-tile footprint
horizontally, unlike a tree's canopy (Slice 7). If the ellipse's left/right edges line up closely
with the footprint's east/west edges in the screenshot, that is expected and fine; the test
plan's "not the visual ellipse's edge" concern is primarily about the vertical offset proven
conclusively in Step 1. Still confirm no unexpected horizontal overhang blocks the player earlier
than the 32px-wide footprint would predict.

### Step 4: Approach from the west (walking east into the boulder)

Reset to spawn (or otherwise reposition west of the boulder).

- `press_action move_right`, `wait_frames` 60 (or until plateau), `release_action move_right`.
- Get node property: `Player.position`. Call this **stop_position_west**.
- Screenshot → compare / save reference:
  `tests/e2e/world-collision/screenshots/boulder_collision_step_04_west_approach.png`

**Visual checkpoint:** mirror of Step 3 — the player stops at the footprint's west edge (16px
west of `boulder_origin.x`). Same note as Step 3 applies re: horizontal ellipse width.

---

## Notes for the executor

- **Assert in every step:** no red engine error/assertion overlay visible anywhere in any frame.
- **The north approach (Step 1) is the load-bearing checkpoint** in this scenario — it's the one
  direction design doc §7.1's anchoring rule guarantees a visible footprint-vs-silhouette gap.
  East/west/south are included per the test plan for completeness (confirming the collider is
  exactly the 32×16 footprint on every side, no accidental overhang), but don't expect them to
  show as dramatic a visual gap as Step 1.
- **This scenario intentionally does not assert exact pixel positions or collider geometry** —
  `tests/integration/world/props/test_boulder.gd` already covers the numeric
  `RectangleShape2D`/bounding-rect math precisely (including deriving the exact "silhouette but
  not footprint" zone from the actual placeholder geometry at runtime). This document exists to
  catch what those can't: whether the gap and the draw order actually *read* correctly on screen.
- **Reference screenshots**: on first run of this scenario (post-Slice-6), save the four captures
  as references under `tests/e2e/world-collision/screenshots/`. There is no pre-Slice-6 reference
  to diff against (no props existed before this slice) — judge each against the checkpoints
  described above, not against an older screenshot. Slice 7 (the tree, where footprint ≠
  silhouette is even more pronounced) should be checked against this baseline for the Y-sort
  behavior specifically.
- **Transient / comparison frames** — the Setup baseline screenshot and any exploratory shots used
  to locate the boulder or confirm plateau detection — must be saved to `<reports_dir>/e2e/`
  (gitignored), never into the committed `tests/e2e/` tree. Call `get_config` to retrieve
  `reports_dir` before saving any such shot. Only the four named screenshots in Steps 1–4 belong in
  the committed `tests/e2e/world-collision/screenshots/` folder.
- **If the boulder cannot be reached from one or more directions** (e.g. it turns out to be placed
  against a map edge or another `Solids` tile blocks one approach), this is a genuine placement
  bug worth reporting — design doc/slices.md Slice 6 requires it be reachable from all four sides
  — rather than something to work around by relocating the player through non-standard means.
- **Scope**: this scenario does not re-verify the `Ground`/`Solids` collision response covered by
  `solids_collision_response.md`, nor the player's feet-anchor baseline covered by
  `player_feet_anchor_baseline.md` — it is scoped to the boulder's footprint-vs-silhouette
  collision behavior and its Y-sort draw order against the player specifically.
