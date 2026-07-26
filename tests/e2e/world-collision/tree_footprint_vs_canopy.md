# Scenario: Tree blocks by trunk footprint, not canopy silhouette (Slice 7)

Verifies Slice 7 — "Tree: footprint ≠ silhouette" — design doc §15's own description of this
slice: "The first prop where footprint ≠ silhouette. Placeholder canopy over a one-tile trunk
(§7.1); verify walking behind the canopy." A single `TreeOak` instance (`world/props/tree_oak.tscn`)
is placed near the player's spawn point: a wide canopy `Polygon2D` drawn well above a one-tile
trunk `Polygon2D`. This scenario walks Cream Bun at the tree from multiple angles and confirms two
things a GUT test cannot: that the *visual* stop point and pass-through read correctly on screen
(the numeric collider-vs-silhouette math is already covered by
`tests/integration/world/props/test_tree_oak.gd`), and that draw order (Y-sort) puts the player in
front of or behind the tree correctly depending on which side they're standing on.

Design doc reference: `docs/features/world-collision/design.md` §7 (discrete props), §7.1
(placeholder art honesty rules), §8 (footprint and ground anchor), §8.2 (the oak's concrete
footprint), §8.3 (why the collider is never derived from sprite alpha), §9 (depth sorting).
Test plan: `docs/features/world-collision/slice-7-tree-test-plan.md`.

**Expected tree placement:** this slice places one `TreeOak` instance as a direct child of
`world.tscn`'s Y-sorted root. The recommended spot — verified against the actual tile data painted
in `world.tscn`, per `tests/integration/world/test_tree_placement.gd`'s doc comment — is
`Vector2(208, 176)`: 80px (2.5 tiles) west of the player spawn (`Vector2(288, 176)`), sitting on
tile (6, 10)'s front edge so the trunk's 1×1 footprint occupies exactly that tile, with the entire
column clear of both Slice 4's Solids test cells (tile (11, 11)/(12, 11), well east) and Slice 6's
Boulder (`Vector2(288, 240)`, well south). Confirm the actual authored position via
`get_node_property` in Setup below rather than assuming this exact value — if it differs, use
whatever was actually placed; the checkpoints below only depend on there being open ground on all
four sides of the tree AND at least ~2 tiles of clear runway to its north (for the canopy-overhang
steps), not on this specific coordinate.

## Setup

- Call `get_config` to obtain `reports_dir` (transient/comparison frames go there, never into
  `tests/e2e/`).
- Call `launch_game`.
- Wait: 20 frames (allow the world scene, tilemap, tree, player, and camera to fully initialize
  before the first screenshot).
- Get node property: the tree instance's `position` (find its node path in the live scene tree —
  design doc §6.1 places it as a direct child of the world root, likely named `TreeOak`). Record
  this as **tree_origin**.
- Get node property: `World/Player.position`. Record this as **spawn_position**.
- Screenshot → save to `<reports_dir>/e2e/` (not the committed tree): a baseline reference showing
  the tree — wide green canopy over a narrow brown trunk — near the player, useful context for
  judging the checkpoints below.

## Steps

### Step 1: Approach from the north (walking south, through the canopy and into the trunk)

This is the load-bearing step: it walks the player through BOTH the canopy's visual overhang (no
collision expected) and into the trunk's footprint (collision expected), in one continuous
approach — exactly the "walk behind the canopy, then get stopped by the trunk" experience design
doc §8's gap describes.

- Reposition well north of the tree (north of the canopy's visual top, not just the footprint) —
  use `load_scene`/manual positioning only if spawn isn't already north of the tree; otherwise walk
  there first.
- `press_action move_down`.
- Watch `Player.position.y` as it crosses into the canopy's visual vertical band (well above
  `tree_origin.y`) — it should keep decreasing at a steady rate here, i.e. **not slow down or stop
  while the player's sprite visually overlaps the canopy**. Take a mid-approach screenshot the
  moment the player's sprite is visibly behind/under the canopy but has not yet reached the trunk:
  save to `tests/e2e/world-collision/screenshots/tree_step_01a_canopy_passthrough.png`.
- Continue holding `move_down`. `wait_frames` 60, or until `Player.position` stops changing between
  two successive reads roughly 30 frames apart (same plateau-detection idea as
  `boulder_collision_and_sort.md`'s Step 1).
- `release_action move_down`.
- Get node property: `Player.position`. Call this **stop_position_north**.
- Screenshot → save reference:
  `tests/e2e/world-collision/screenshots/tree_step_01b_north_final_stop.png`

**Visual checkpoints:**

1. **No slowdown or stop while crossing the canopy's visual silhouette.** This is the single most
   important checkpoint in this scenario — design doc §8.3's whole point is that a collider
   mistakenly generated from the canopy's sprite/silhouette (instead of the trunk's footprint)
   would block the player here, well north of where the trunk actually is. If the player pauses,
   slows, or stops anywhere north of the trunk's footprint edge while the canopy visually overlaps
   their sprite, that is exactly the bug §8.3 rejects.
2. **The player eventually stops at the trunk's footprint edge, not at the canopy's visible edge.**
   The footprint is exactly one tile (32×16) centred horizontally on `tree_origin` and extending
   16px north of it (its near edge). Because the canopy is drawn far taller than the footprint
   (design doc §7.1 — anchored upward, never centred), the canopy's own drawn top sits visibly
   further north than where the player actually stops — the final screenshot should show the
   canopy's silhouette visually overlapping the player's upper body/head by a noticeable amount
   (proof the footprint, not the silhouette, decided where movement halted), not a clean stop right
   at the canopy's outer edge.
3. **`stop_position_north.y` is measurably less than `tree_origin.y`** (the player stopped north of
   the anchor) but the gap should be small — on the order of the footprint's 16px near-edge offset
   plus the player's own half-depth, not several tiles' worth.
4. **Draw order: the player renders BEHIND the tree.** Standing north of the anchor
   (`stop_position_north.y < tree_origin.y`), Y-sort (design doc §9) should draw the tree's sprite
   (both trunk and canopy) in front of the player wherever they visually overlap. This is the
   "player draws behind the tree when standing above (north of) its ground anchor" checkpoint from
   the test plan.

### Step 2: Approach from the south (walking north into the trunk)

Reset to spawn (or otherwise reposition south of the tree).

- `press_action move_up`, `wait_frames` 60 (or until plateau), `release_action move_up`.
- Get node property: `Player.position`. Call this **stop_position_south**.
- Screenshot → save reference:
  `tests/e2e/world-collision/screenshots/tree_step_02_south_approach.png`

**Visual checkpoints:**

1. **The player stops at the trunk footprint's south (near) edge**, which sits right at
   `tree_origin.y` (the ground anchor is the footprint's *front* edge, per design doc §8.1) — there
   should be little to no vertical gap between the trunk's visible base and the collision stop
   point. Contrast this explicitly with Step 1's north approach, where a visible gap (the canopy
   overlap) is expected — the absence of a gap here confirms the canopy's overhang is
   one-directional (upward only), not an oversized collider in every direction.
2. **Draw order: the player renders IN FRONT of the tree.** Standing south of the anchor
   (`stop_position_south.y > tree_origin.y`), the player's sprite should visually overlap and cover
   part of the trunk's (and, if close enough, the low edge of the canopy's) silhouette where they
   intersect. This is the "player draws in front of the tree when standing below (south of) its
   ground anchor" checkpoint from the test plan.

### Step 3: Approach from the east (walking west into the trunk)

Note: `TreeOak.position.y` (176) exactly matches the player spawn's `y` (`Vector2(288, 176)`), so
during this side approach (and Step 4's mirror) the player and tree sit on the same Y-sort row for
most of the crossing. This is a deliberate tie, not a placement bug — Y-sort falls back to
scene-tree order for equal `y`, and `world.tscn` lists `Player` before `TreeOak`, so the resolved
draw order is stable and consistent across runs.

Reset to spawn (or otherwise reposition east of the tree).

- `press_action move_left`, `wait_frames` 60 (or until plateau), `release_action move_left`.
- Get node property: `Player.position`. Call this **stop_position_east**.
- Screenshot → save reference:
  `tests/e2e/world-collision/screenshots/tree_step_03_east_approach.png`

**Visual checkpoint:** the player stops at the trunk footprint's east edge (16px east of
`tree_origin.x`, i.e. `stop_position_east.x` should be measurably greater than `tree_origin.x` by
roughly that margin, not several tiles further out). Note: if the canopy is drawn noticeably wider
than the footprint horizontally (likely, since design doc §8.2 draws the canopy "far wider" — more
so than boulder's ellipse, which only had to prove a vertical gap), expect the player's sprite to
visually pass *under* the canopy's horizontal overhang before being stopped by the trunk collider —
same footprint-vs-silhouette gap as Step 1, just on the horizontal axis. Confirm no unexpected
overhang blocks the player earlier than the 32px-wide footprint would predict.

### Step 4: Approach from the west (walking east into the trunk)

Reset to spawn (or otherwise reposition west of the tree).

- `press_action move_right`, `wait_frames` 60 (or until plateau), `release_action move_right`.
- Get node property: `Player.position`. Call this **stop_position_west**.
- Screenshot → save reference:
  `tests/e2e/world-collision/screenshots/tree_step_04_west_approach.png`

**Visual checkpoint:** mirror of Step 3 — the player stops at the trunk footprint's west edge (16px
west of `tree_origin.x`). Same canopy-overhang note as Step 3 applies.

### Step 5: Dedicated canopy corridor crossing (walking fully through, never touching the trunk)

This step isolates the canopy-only claim from Step 1's combined approach: instead of walking into
the trunk, the player crosses horizontally at a y **strictly between the canopy's topmost visual
extent and the trunk footprint's near edge** — passing all the way through the canopy's silhouette
and out the other side, never once entering the 1×1 footprint band. This is the scenario-level
counterpart to `tests/integration/world/props/test_tree_oak.gd`'s
`test_move_and_slide_over_canopy_silhouette_is_not_blocked_at_all` — proving visually what that test
proves numerically.

- Reposition the player well west of the tree, at a y roughly halfway between the canopy's visible
  top and the trunk's top edge (i.e. clearly "under the canopy, above the trunk" — eyeball this
  from the Setup baseline screenshot, or read the canopy's approximate height off the live scene via
  `get_node_property` if the executor has access to the Canopy node's polygon bounds).
- `press_action move_right`, `wait_frames` 90 (long enough to cross well past the tree's east side —
  more than Steps 1-4's 60, since this is a full crossing, not a stop-and-check).
- `release_action move_right`.
- Get node property: `Player.position`. Call this **stop_position_canopy_crossing**.
- Screenshot → save reference:
  `tests/e2e/world-collision/screenshots/tree_step_05_canopy_crossing.png`

**Visual checkpoints:**

1. **The player's final x position is well past the tree's east side** — comparable to how far the
   player would travel over open ground in the same number of frames (there is no Solids tile or
   other prop in this corridor per the Setup placement notes). If the player stopped anywhere near
   `tree_origin.x`, the canopy is wrongly blocking movement.
2. **The screenshot shows the player's sprite passing visually behind/under the canopy at the
   midpoint of the crossing** (captured mid-crossing if the executor can time it, or inferred from
   the final screenshot showing the player clearly past the tree with the canopy visually intact
   above/behind them) — this is the "walking behind the tree's canopy ... does not block movement"
   checkpoint from the test plan, demonstrated as a full pass-through rather than a stop-then-check.

---

## Notes for the executor

- **Assert in every step:** no red engine error/assertion overlay visible anywhere in any frame.
- **Step 1 is the load-bearing checkpoint** in this scenario — it's the one approach that
  demonstrates both halves of the design claim (canopy doesn't block, trunk does) in a single
  continuous motion, which is how a player will actually experience it. Step 5 exists to prove the
  canopy claim in isolation, without the trunk stop muddying the interpretation.
- **This scenario intentionally does not assert exact pixel positions or collider geometry** —
  `tests/integration/world/props/test_tree_oak.gd` already covers the numeric
  `RectangleShape2D`/bounding-rect math precisely (including deriving the exact "silhouette but not
  footprint" zone from the actual canopy geometry at runtime, and proving the canopy contributes
  ZERO collision via a tight tolerance around the full unobstructed distance — see that file's
  `test_move_and_slide_over_canopy_silhouette_is_not_blocked_at_all`). This document exists to catch
  what those can't: whether the gap and the draw order actually *read* correctly on screen.
- **Reference screenshots**: on first run of this scenario (post-Slice-7), save the captures as
  references under `tests/e2e/world-collision/screenshots/`. Compare the Y-sort behavior against
  `boulder_collision_and_sort.md`'s baseline (that scenario's own notes flag this tree scenario as
  the one to check the Y-sort claim against more rigorously, since the canopy makes the
  footprint-vs-silhouette gap far more pronounced than the boulder's ellipse).
- **Transient / comparison frames** — the Setup baseline screenshot, the mid-approach shot in Step 1
  before the "final stop" capture, and any exploratory shots used to locate the tree or confirm
  plateau detection — must be saved to `<reports_dir>/e2e/` (gitignored) UNLESS explicitly named
  above as one of the numbered committed screenshots. Call `get_config` to retrieve `reports_dir`
  before saving any such shot. Only the six named screenshots in Steps 1-5 belong in the committed
  `tests/e2e/world-collision/screenshots/` folder.
- **If the tree cannot be reached from one or more directions**, or there isn't enough clear runway
  north of it to distinguish the canopy-overhang region from the trunk's footprint (e.g. it turns
  out to be placed too close to a map edge or another Solids tile), this is a genuine placement bug
  worth reporting — see this document's "Expected tree placement" section and
  `tests/integration/world/test_tree_placement.gd`'s doc comment for the verified-clear recommended
  spot — rather than something to work around by relocating the player through non-standard means.
- **Scope**: this scenario does not re-verify the `Ground`/`Solids` collision response covered by
  `solids_collision_response.md`, the player's feet-anchor baseline covered by
  `player_feet_anchor_baseline.md`, or the boulder's own footprint-vs-silhouette/Y-sort behavior
  covered by `boulder_collision_and_sort.md` — it is scoped to the tree's trunk-footprint-vs-canopy
  collision behavior and its Y-sort draw order against the player specifically.
