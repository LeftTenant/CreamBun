# Scenario: Edge transition (fade) and a second area (Slice 10)

> **SUPERSEDED** by `tests/e2e/world-thresholds/threshold_crossing.md`. This document describes the
> edge-derived transition mechanism (`neighbour_*` slots, `edge_reached`, corner dead zones, the
> arrival debounce) that World Thresholds Slice 4 deleted outright
> (`docs/features/world-thresholds/design.md` §9) and replaced with placed `Threshold`/`Arrival`
> nodes. `meadow.tscn`/`orchard.tscn` no longer have any of the machinery this scenario exercises —
> do not attempt to run it. Kept for history, the same way `docs/features/world-collision/design.md`
> §12.2/§12.4 stay in place as history in that design doc. New meadow ↔ orchard e2e coverage lives
> entirely in `threshold_crossing.md`.

Verifies Slice 10 — "Edge transition (fade) and a second area" — the parts of design doc §12.4
(open edges vs. walls, corner dead zones, arrival debounce) and §12.5 (the freeze/fade/swap/spawn/
reveal sequence, opposite-edge spawn maths) that a GUT test cannot confirm: whether the fade
actually *reads* as a cozy cover-and-reveal on screen, whether the player is genuinely frozen while
covered, and whether arriving in the new area feels seamless rather than jarring. The numeric
mechanics this depends on (`WorldArea.Edge`/`edge_reached`, the Area2D trigger geometry, the corner
dead zones, the debounce distance, the opposite-edge spawn coordinate maths, `GameState` sequencing,
and `GameEvents.area_changed`) are already covered precisely by
`tests/integration/world/test_edge_triggers.gd` and `tests/integration/world/test_area_transition.gd`
— this document exists to catch what those can't: does the cover genuinely hide the swap, does
control freeze and resume correctly, and does the whole thing look and feel right.

Design doc reference: `docs/features/world-collision/design.md` §12.4 (open edges vs. walls, corner
dead zones, arrival debounce), §12.5 (the transition sequence, opposite-edge spawn).
Test plan: `docs/features/world-collision/slice-10-edge-transition-test-plan.md`.

**Second area / node path convention**: this slice adds `world/areas/orchard.tscn` as the second
area, linked to the meadow on two edges — `meadow.neighbour_east` &harr; `orchard.neighbour_west`
(east/west link) and `meadow.neighbour_south` &harr; `orchard.neighbour_north` (north/south link).
Following slice 8's reparenting convention, the live player node path is
`World/ActiveArea/Meadow/Player` while in the meadow and `World/ActiveArea/Orchard/Player` once
transitioned into the second area — the executor should re-resolve the player's path after any
transition rather than assuming it stays fixed.

**Bounds for reference (confirm live, don't assume):** meadow's `get_bounds_px()` should read
`Rect2(position=(0, 16), size=(544, 320))` (see `camera_dead_zone_and_edge_lock.md` for the same
note). Orchard's `get_bounds_px()` should read `Rect2(position=(0, 0), size=(448, 256))` — 14×16
tiles, comfortably over the one-viewport-minimum floor (design.md §12.3). Read both live via
`get_node_property` in Setup rather than trusting these numbers, since either area's painted extent
could change after this document is written.

## Setup

- Call `get_config` to obtain `reports_dir` (transient/comparison frames go there, never into
  `tests/e2e/`).
- Call `launch_game`.
- Wait: 20 frames (allow the world scene, tilemap, player, and camera to fully initialize).
- Get node property: `World/ActiveArea/Meadow/Player.position`. Record as **spawn_position**.
- Get node property: `World/ActiveArea/Meadow.` (the area) — if a `get_bounds_px()`-equivalent
  property isn't directly readable, instead read
  `World/ActiveArea/Meadow/Player/Camera2D.limit_left/top/right/bottom` and treat those four values
  as **meadow_bounds** (same technique as `camera_dead_zone_and_edge_lock.md`'s Setup).
- Screenshot → save to `<reports_dir>/e2e/` (not the committed tree): a baseline reference.
- **If `World/ActiveArea/Meadow` (or `.../Orchard`) cannot be found at these paths at all**, the
  slice 8 shell/area structure has regressed — stop and report that rather than attempting the
  steps below.

## Steps

### Step 1: Crossing the linked east edge fades, swaps, and spawns on the opposite edge

- Reposition the player (via `reset_state` + reposition, or direct teleport if the sandbox
  supports it) to the clear middle of the meadow's east edge's approach lane: roughly
  `(meadow_bounds.limit_right - 100, (meadow_bounds.limit_top + meadow_bounds.limit_bottom) / 2)` —
  clear of both corner dead zones (design.md §12.4: 2-tile/32px vertical inset on an east/west edge).
- `press_action move_right`.
- `wait_frames` in small increments (e.g. 10 at a time), screenshotting every increment, watching
  for the screen to fade toward fully opaque. Save the fully (or near-fully) covered frame to
  `<reports_dir>/e2e/edge_transition_step_01_faded_out.png` — not yet part of the committed
  screenshot set (see "Notes for the executor" below); promote it into
  `tests/e2e/world-collision/screenshots/` only once this step has actually been run and reviewed.

**Visual checkpoint:** the screen visibly covers to an opaque colour before any new area content is
shown — no glimpse of the swap (old area disappearing / new area appearing) should be visible
through the fade.

- Continue waiting in SMALL increments (e.g. 5–10 frames at a time, up to ~3–5 seconds total
  simulated time), polling `get_game_state` after each increment, until it reports `PLAYING` again —
  this is the authoritative "the sequence has fully completed" signal (design.md §12.5 step 5), not
  a visual judgment call of "looks resumed."
- The MOMENT `get_game_state` first reports `PLAYING`, `release_action move_right` — do this in the
  very next call, with no additional `wait_frames` in between. **This ordering matters**: a prior
  version of this scenario held `move_right` through extra wait/drive time after the reveal before
  releasing and screenshotting, so the committed reference screenshot ended up showing the player
  already walked deep into orchard (pinned against the far wall) instead of the "just arrived, still
  near the entry edge" moment this checkpoint describes. Release first, THEN read properties and
  screenshot — don't keep driving or waiting once `PLAYING` is observed.
- Get node property: `World/ActiveArea/Orchard/Player.position`. Record as
  **orchard_entry_position**.
- Get node property: `World/ActiveArea/Orchard/Player/Camera2D.limit_left/top/right/bottom`. Record
  as **orchard_bounds**.
- Screenshot → save to `tests/e2e/world-collision/screenshots/edge_transition_step_02_arrived_in_orchard.png`.

**Visual checkpoints:**

1. The player has reappeared entering from the **west** edge of the new area (near
   `orchard_bounds.limit_left`), not at some arbitrary position — Cream Bun should be close to the
   left edge of the painted floor, walking inward, not centred in the map.
2. **orchard_entry_position.y** should be close to the Y the player exited meadow's east edge at
   (roughly the middle of `meadow_bounds`'s vertical span) — a continuous walk should feel
   continuous, not teleport to a different height.
3. No unpainted void is visible around the player — the camera should already be correctly framed
   within orchard's own bounds (this is what
   `tests/integration/world/test_area_transition.gd`'s camera-limit test confirms numerically; this
   checkpoint is the visual confirmation).
4. The fade has fully cleared (screen fully visible, not left partially covered).

### Step 2: Movement is frozen while covered, resumes once revealed

- Repeat Step 1's approach to the meadow's east edge from `spawn_position` (reset first).
- `press_action move_right` and **keep holding it** through the entire fade/swap/spawn sequence —
  do not release.
- While the screen is at or near fully covered (a few frames after the fade visibly starts),
  get node property: `World/ActiveArea/Orchard/Player.position` (or
  `World/ActiveArea/Meadow/Player.position` if the swap hasn't happened yet) twice, several frames
  apart, and confirm the position does **not** change between the two reads.

**Visual checkpoint:** while the screen is covered, the player's position is frozen — holding
`move_right` must not continue to move Cream Bun during the covered portion, per design.md §12.5
step 1 ("the player already zeroes its velocity whenever the state is not PLAYING").

- Continue waiting for the reveal, then — still holding `move_right` — wait 20 more frames.
- Get node property: `World/ActiveArea/Orchard/Player.position` again.

**Visual checkpoint:** once the fade has cleared, the position **should** now be changing again
(control resumed) — Cream Bun visibly walking further into orchard, not left stuck. Screenshot →
save to `<reports_dir>/e2e/edge_transition_step_03_resumes_after_reveal.png` — not yet part of the
committed set (see "Notes for the executor").

- `release_action move_right`.

### Step 3: A corner dead zone holds — no transition starts from near a corner

- Reset to `spawn_position`.
- Reposition the player to just inside the east edge's **SOUTH** corner dead zone: roughly
  `(meadow_bounds.limit_right - 60, meadow_bounds.limit_bottom - 10)` (well under the 32px vertical
  exclusion from design.md §12.4).
  **Not the north end**: the north end of any vertical edge sits inside the north wall/trigger's own
  camera-headroom inset zone (design.md §12.4, `NORTH_WALL_HEADROOM_INSET_PX`) — a player placed
  there gets pushed back south by that solid geometry before ever reaching the east edge at all, so
  the step would pass without actually exercising the east edge's corner exclusion. The south end has
  no such interference and is where a real containment bug was previously found (a player could walk
  straight through the corner and end up over 1000px outside the map) — this step exists specifically
  to catch a regression of that.
- `press_action move_right`, `wait_frames` ~60, `release_action move_right`.
- Get node property: `World/ActiveArea/Meadow/Player.position` (should still resolve — if this path
  no longer exists, a transition wrongly happened).

**Visual checkpoint:** the player must still be contained within the meadow's painted floor —
explicitly confirm `player.position.x <= meadow_bounds.limit_right + 5` and
`player.position.y <= meadow_bounds.limit_bottom + 5` (a few px of slack for physics settling; a
position meaningfully beyond either limit means the player walked off the map through an open
corner, which is a hard failure of this step, not "drifted along the corner"). The player should be
stopped by ordinary solid collision, and no fade should have been visible at any point during this
step. Screenshot →
save to `<reports_dir>/e2e/edge_transition_step_04_corner_no_transition.png` — not yet part of the
committed set (see "Notes for the executor"); this is the **highest-priority screenshot to capture
in the next e2e run**, since this exact scenario is where the containment bug lived.

### Step 4: Immediate bounce-back is suppressed; re-approaching later works

- From `spawn_position`, repeat the Step 1 crossing into orchard (wait for full reveal).
- Immediately `press_action move_left` for a short burst (~20 frames) — walking back toward the
  just-entered west edge — then `release_action move_left`.
- Wait 30 more frames.
- Get node property: `World/ActiveArea/Orchard/Player.position` (confirm this path still resolves —
  if it doesn't, the debounce failed to suppress an immediate bounce-back).

**Visual checkpoint:** the player should still be in orchard, near the west edge, with **no fade**
having played during this short back-step.

- Now walk the player well away from that edge: `press_action move_right`, `wait_frames` ~120,
  `release_action move_right`.
- Then walk back through the same west edge for real: `press_action move_left`, wait for the fade/
  swap/reveal sequence (as in Step 1), `release_action move_left`.
- Get node property: `World/ActiveArea/Meadow/Player.position`.

**Visual checkpoint:** this second, deliberate return trip **should** fade and land the player back
in the meadow, near its east edge — confirming the debounce is a distance check that re-arms, not a
permanent lockout. Screenshot →
save to `<reports_dir>/e2e/edge_transition_step_05_rearmed_return_trip.png` — not yet part of the
committed set (see "Notes for the executor").

### Step 5: The north/south link works the same way

- Reset to `spawn_position`.
- Reposition to the clear middle of the meadow's south edge approach lane: roughly
  `((meadow_bounds.limit_left + meadow_bounds.limit_right) / 2, meadow_bounds.limit_bottom - 100)`.
- `press_action move_down`, then poll `get_game_state` in small increments (as in Step 1) until it
  reports `PLAYING` again. `release_action move_down` in the very next call — no extra wait/drive
  after `PLAYING` is observed and before releasing (see Step 1's note on why this ordering matters:
  holding past the reveal walks the player further in than the "just arrived" checkpoint describes).
- Get node property: `World/ActiveArea/Orchard/Player.position`.

**Visual checkpoints:** same shape as Step 1 — fades to opaque before the swap, player reappears
entering from orchard's **north** edge (near the top of the painted floor), at roughly the X
coordinate they exited meadow's south edge at, fade clears fully. Screenshot →
save to `tests/e2e/world-collision/screenshots/edge_transition_step_06_north_south_link.png`.

### Step 6: An unlinked edge still behaves exactly like slice 9 (regression)

- Reset to `spawn_position`.
- `press_action move_left` (toward meadow's UNLINKED west edge), wait for plateau (position stops
  changing) or ~5 seconds, `release_action move_left`.
- Get node property: `World/ActiveArea/Meadow/Player.position`.

**Visual checkpoint:** the player is stopped by an ordinary invisible wall — **no fade plays at any
point**, and the player never leaves `World/ActiveArea/Meadow`. This should look identical to
`camera_dead_zone_and_edge_lock.md`'s Step 5 (west edge) from slice 9. Screenshot →
save to `tests/e2e/world-collision/screenshots/edge_transition_step_07_unlinked_edge_regression.png`.

---

## Notes for the executor

- **Assert in every step:** no red engine error/assertion overlay visible anywhere in any frame.
- **This scenario intentionally does not assert exact pixel positions, collider geometry, signal
  emission counts, or `GameState` transitions precisely** — `test_edge_triggers.gd` and
  `test_area_transition.gd` already cover those numerically. This document exists to catch what
  those can't: whether the fade genuinely hides the swap, whether control freezes/resumes visibly
  correctly, and whether the whole sequence reads as a cozy transition rather than a jarring cut or
  a visible pop.
- **Reference screenshots**: three of the seven named captures already exist under
  `tests/e2e/world-collision/screenshots/` — `edge_transition_step_02_arrived_in_orchard.png`,
  `edge_transition_step_06_north_south_link.png`, `edge_transition_step_07_unlinked_edge_regression.png`.
  **`step_02` and `step_06` were captured but do not match their checkpoints above** — both were
  captured while still holding movement input through the entire reveal-fade wait, so by the time
  the screenshot was taken the player had walked well past the just-entered position the checkpoint
  describes (`step_02` shows Cream Bun pinned at the orchard's far *right* edge; the checkpoint
  above describes arrival near the *left* edge). The intended procedure — poll `GameState` and
  release input the instant it leaves `LOADING`/returns to `PLAYING`, then screenshot immediately —
  is documented above in Steps 1 and 5, but a live recapture attempt found the manual tool
  round-trip latency (~1.4s per press/release/query) too coarse to hit that precision (see
  `.claude/agent-memory/godot-coder/gotcha_e2e_manual_input_latency_floor.md`). Treat both as
  **known-incorrect placeholders, not trustworthy references** — replace them on the next capture
  pass rather than diffing against them. (`step_07` is unaffected — no transition occurs in that
  scenario, so there was no input-hold-through-fade window to get wrong.)
  The remaining four (step_01, step_03, step_04, step_05) have not been captured yet — their steps
  above save to `<reports_dir>/e2e/` in the meantime rather than pointing at a committed path that
  doesn't exist. Run this scenario end-to-end and promote those four into
  `tests/e2e/world-collision/screenshots/` once captured and reviewed against the checkpoints above;
  **step_04 (the corner scenario) is the highest priority of the four**, since a real containment bug
  (player walking off the map through an open corner) previously lived exactly there. There is no
  pre-Slice-10 reference to diff any of these against — judge each against the checkpoints described
  above.
- **Transient / comparison frames** — the Setup baseline, the incremental fade-progress shots in
  Step 1, and any exploratory shots used to locate edges or re-check bounds — must be saved to
  `<reports_dir>/e2e/` (gitignored), never into the committed `tests/e2e/` tree. Call `get_config`
  to retrieve `reports_dir` before saving any such shot. Only the seven explicitly named
  screenshots above belong in the committed folder.
- **If `World/ActiveArea/Meadow/Player` cannot be found at all in Setup**, or if the game errors on
  launch, this scenario cannot proceed — report the missing implementation rather than forcing the
  remaining steps.
- **If crossing the east or south edge does not fade / does not change the player's area at all**
  (i.e. `World/ActiveArea/Orchard` never appears), the edge-trigger or transition-sequence
  implementation doesn't exist yet or isn't wired up — stop after confirming this once and report
  it, rather than repeating the same failing crossing for every subsequent step.
- **Scope**: this scenario does not re-verify the camera dead zone or the four ordinary perimeter
  walls established in slice 9 (covered by `camera_dead_zone_and_edge_lock.md`) except where slice
  10 specifically changes behavior (the linked edges, and the regression check in Step 6). It also
  does not cover a third area or any edge beyond the two links this slice establishes — design.md
  §12.5's "Phase 1 uses a fade" note explicitly defers slide/scroll transitions to Phase 2, out of
  scope here.
