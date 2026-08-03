# Scenario: Meadow ↔ Orchard threshold crossing (World Thresholds Slice 4)

Verifies World Thresholds Slice 4's acceptance bar (design.md §10: "the existing two-way meadow ↔
orchard link works exactly as it does today, via placed Thresholds and Arrivals") from the player's
seat: does walking off meadow's east edge genuinely fade, swap, and land Cream Bun at the authored
`ArrivalFromMeadowEast` marker's position — not a computed offset — and does the reverse trip back
over orchard's west edge feel the same way. **This is the first e2e coverage for the World
Thresholds feature.** Slices 1–3 were fixture-only (proven entirely by GUT against small
test-only `WorldArea` scenes — see `tests/integration/world/thresholds/test_threshold_transition.gd`)
and had no visual/input-driven coverage at all; this document is the first scenario that exercises
real `meadow.tscn`/`orchard.tscn` content end to end.

The precise numeric bar — landing exactly at the Arrival's authored position, `GameEvents.area_changed`
firing once with the right id, camera limits reset to the destination's bounds, the re-entry guard
holding — is already asserted by GUT in `tests/integration/world/test_area_transition.gd`. This
scenario exists to catch what a numeric assertion can't: whether the fade genuinely hides the swap,
whether the player is visibly frozen while covered, and whether the whole thing reads as a cozy
transition rather than a jarring cut or a visible pop — the same division of labor
`tests/e2e/world-collision/edge_transition.md` used for the old edge-derived mechanism it superseded.

Design doc reference: `docs/features/world-thresholds/design.md` §4 (the `Threshold` node), §5 (the
`Arrival` node, resolve-before-destroy, the re-entry guard), §7 (unconditional perimeter walls), §10
(Phase 1's acceptance bar).
Test plan: `docs/features/world-thresholds/slice-4-switchover-test-plan.md`.

**Real-content authoring contract this scenario assumes** (settled by
`tests/integration/world/test_area_transition.gd`'s header, since slices.md's Slice 4 section names
the linked edges but not every node's exact name):

```
meadow.tscn
  ThresholdToOrchardEast   (east edge)  -> orchard.tscn, arrival &"ArrivalFromMeadowEast"
  ThresholdToOrchardSouth  (south edge) -> orchard.tscn, arrival &"ArrivalFromMeadowSouth"
  ArrivalFromOrchardNorth  (Marker2D, near meadow's south edge)
  ArrivalFromOrchardWest   (Marker2D, near meadow's east edge)
orchard.tscn
  ThresholdToMeadowNorth   (north edge) -> meadow.tscn, arrival &"ArrivalFromOrchardNorth"
  ThresholdToMeadowWest    (west edge)  -> meadow.tscn, arrival &"ArrivalFromOrchardWest"
  ArrivalFromMeadowEast    (Marker2D, near orchard's west edge)
  ArrivalFromMeadowSouth   (Marker2D, near orchard's north edge)
```

**RUNNABLE.** World Thresholds Slice 4's implementation has landed: `meadow.tscn`/`orchard.tscn` now
carry the placed `Threshold`/`Arrival` pairs this scenario's authoring contract (above) describes,
and `tests/integration/world/test_area_transition.gd`'s GUT suite is green. This scenario has not yet
been executed via the testing sandbox, though — no screenshots exist yet (see "Notes for the
executor" below); run it end to end and promote the named screenshots once captured and reviewed.

## Setup

- Call `get_config` to obtain `reports_dir` (transient/comparison frames go there, never into
  `tests/e2e/`).
- Call `launch_game`.
- Wait: 20 frames (allow the world scene, tilemap, player, and camera to fully initialize).
- Get node property: `World/ActiveArea/Meadow/Player.position`. Record as **spawn_position**.
- Get node property: `World/ActiveArea/Meadow/Player/Camera2D.limit_left/top/right/bottom`. Treat
  those four values as **meadow_bounds** (same technique as
  `tests/e2e/world-collision/camera_dead_zone_and_edge_lock.md` and `edge_transition.md`'s own Setup).
- Screenshot → save to `<reports_dir>/e2e/` (not the committed tree): a baseline reference.
- **If `World/ActiveArea/Meadow` cannot be found at this path at all**, the world shell has
  regressed — stop and report that rather than attempting the steps below.

## Steps

### Step 1: Crossing meadow's east edge fades, swaps, and lands exactly at the authored Arrival

- Reposition the player (via `reset_state` + reposition, or direct teleport if the sandbox supports
  it) to the clear middle of meadow's east edge's approach lane: roughly
  `(meadow_bounds.limit_right - 100, (meadow_bounds.limit_top + meadow_bounds.limit_bottom) / 2)`.
- `press_action move_right`.
- `wait_frames` in small increments (e.g. 10 at a time), screenshotting every increment, watching for
  the screen to fade toward fully opaque. Save the fully (or near-fully) covered frame to
  `<reports_dir>/e2e/threshold_crossing_step_01_faded_out.png` — a transient comparison shot, not part
  of the committed set.

**Visual checkpoint:** the screen visibly covers to an opaque colour before any new area content is
shown — no glimpse of the swap should be visible through the fade.

- Continue waiting in small increments, polling `get_game_state` after each increment, until it
  reports `PLAYING` again. The MOMENT it does, `release_action move_right` in the very next call —
  no additional `wait_frames` in between (see `edge_transition.md`'s identical note on why this
  ordering matters: holding past the reveal walks the player past the "just arrived" moment this
  checkpoint describes).
- Get node property: `World/ActiveArea/Orchard/Player.position`. Record as **orchard_entry_position**.
- Get node property: `World/ActiveArea/Orchard/ArrivalFromMeadowEast.position`. Record as
  **arrival_position**.
- Get node property: `World/ActiveArea/Orchard/Player/Camera2D.limit_left/top/right/bottom`. Record
  as **orchard_bounds**.
- Screenshot → save to
  `tests/e2e/world-thresholds/screenshots/threshold_crossing_step_01_arrived_in_orchard.png`.

**Visual/numeric checkpoints:**

1. **orchard_entry_position must equal arrival_position** (within ~1px) — this is the actual pass/
   fail bar the design doc and test plan both insist on: the player lands exactly where the `Arrival`
   marker is authored, not at any computed offset. This is the one hard numeric check this otherwise
   qualitative document makes, because it's the whole point of the feature.
2. Cream Bun visibly enters from the west side of orchard's painted floor, walking inward — not
   centred in the map and not clipped by the camera.
3. No unpainted void is visible around the player — the camera is already correctly framed within
   orchard's own bounds (`orchard_bounds` should match `get_bounds_px()` read via GUT, but this
   checkpoint is the visual confirmation).
4. The fade has fully cleared (screen fully visible, not left partially covered).

### Step 2: Movement is frozen while covered, resumes once revealed

- Repeat Step 1's approach to meadow's east edge from `spawn_position` (reset first).
- `press_action move_right` and **keep holding it** through the entire fade/swap/place sequence — do
  not release.
- While the screen is at or near fully covered, get node property:
  `World/ActiveArea/Orchard/Player.position` (or `World/ActiveArea/Meadow/Player.position` if the
  swap hasn't happened yet) twice, several frames apart, and confirm the position does **not** change
  between the two reads.

**Visual checkpoint:** while the screen is covered, the player is frozen — holding `move_right` must
not continue to move Cream Bun during the covered portion (design.md §5's freeze step).

- Continue waiting for the reveal, then — still holding `move_right` — wait 20 more frames.
- Get node property: `World/ActiveArea/Orchard/Player.position` again.

**Visual checkpoint:** once the fade has cleared, the position **should** now be changing again.
Screenshot → save to `<reports_dir>/e2e/threshold_crossing_step_02_resumes_after_reveal.png` —
transient, not part of the committed set.

- `release_action move_right`.

### Step 3: The reverse trip — orchard's west edge back to meadow's authored Arrival

- Reset to `spawn_position`, then repeat Step 1's crossing into orchard (wait for full reveal,
  release input the instant `PLAYING` is observed).
- Walk well away from the just-entered west edge first: `press_action move_right`, `wait_frames`
  ~120, `release_action move_right` (clears any re-entry-guard ambiguity — see
  `edge_transition.md`'s identical note for why this matters, though the new mechanism's guard,
  design.md §5, is a "has fully left" check rather than a distance debounce).
- Now walk back through orchard's west edge for real: `press_action move_left`, poll `get_game_state`
  in small increments until `PLAYING`, `release_action move_left` in the very next call.
- Get node property: `World/ActiveArea/Meadow/Player.position`. Record as **meadow_entry_position**.
- Get node property: `World/ActiveArea/Meadow/ArrivalFromOrchardWest.position`. Record as
  **return_arrival_position**.
- Screenshot → save to
  `tests/e2e/world-thresholds/screenshots/threshold_crossing_step_03_returned_to_meadow.png`.

**Visual/numeric checkpoints:**

1. **meadow_entry_position must equal return_arrival_position** (within ~1px) — same pass/fail bar
   as Step 1, for the reverse direction.
2. Cream Bun visibly enters from the east side of meadow's painted floor, walking inward.
3. The fade covered the swap fully; no void visible; camera correctly framed within
   `meadow_bounds`.

### Step 4: An edge with no placed Threshold still just walls, with no transition (regression)

- Reset to `spawn_position`.
- `press_action move_left` (toward meadow's unlinked west edge — no Threshold placed there per this
  scenario's authoring contract), wait for plateau (position stops changing) or ~5 seconds,
  `release_action move_left`.
- Get node property: `World/ActiveArea/Meadow/Player.position`.

**Visual checkpoint:** the player is stopped by an ordinary invisible wall — **no fade plays at any
point**, and the player never leaves `World/ActiveArea/Meadow`. This should look identical to
`tests/e2e/world-collision/edge_transition.md`'s own unlinked-edge regression step. Screenshot →
save to
`tests/e2e/world-thresholds/screenshots/threshold_crossing_step_04_unlinked_edge_regression.png`.

---

## Notes for the executor

- **Assert in every step:** no red engine error/assertion overlay visible anywhere in any frame.
- **This scenario intentionally does not assert exact fade timing, signal emission counts, or
  `GameState` transition sequencing beyond "did it reach `PLAYING`"** —
  `tests/integration/world/test_area_transition.gd` already covers those numerically and exhaustively,
  including the re-entry guard and camera-limit resets for all four real crossings (not just the two
  this document exercises). This document exists to catch what GUT can't: whether the fade genuinely
  hides the swap, whether control freezes/resumes visibly correctly, and whether the two Arrival
  landings this scenario checks numerically (Steps 1 and 3) actually look and feel like arriving
  somewhere authored, not computed.
- **Only Steps 1 and 3's "must equal" checkpoints are hard numeric assertions.** Everything else in
  this document is a qualitative visual judgment call, per this project's e2e convention.
- **Transient / comparison frames** — the Setup baseline and the incremental fade-progress shots in
  Steps 1–2 — must be saved to `<reports_dir>/e2e/` (gitignored), never into the committed
  `tests/e2e/` tree. Call `get_config` to retrieve `reports_dir` before saving any such shot. Only the
  four explicitly named screenshots above (steps 01, 03, 04 committed; step 02 is transient — see its
  own line) belong in the committed folder, and only once this scenario has actually been run and the
  captures reviewed against the checkpoints above. **No screenshots exist yet** — this scenario has
  never been executed (see "RUNNABLE" above); do not fabricate placeholder images.
- **Scope**: this scenario does not re-verify the meadow's south edge or orchard's north edge (the
  second linked pair) — `test_area_transition.gd`'s GUT suite already proves that pair numerically,
  and design.md's fade sequence has no reason to differ by which edge triggered it. It also does not
  cover a third area, nor does it re-verify the camera dead zone established by
  `tests/e2e/world-collision/camera_dead_zone_and_edge_lock.md` except where this feature specifically
  changes behavior (the Threshold-driven crossings, and the regression check in Step 4).
- **If `World/ActiveArea/Meadow/Player` cannot be found at all in Setup**, or if the game errors on
  launch, this scenario cannot proceed — report the missing implementation rather than forcing the
  remaining steps.
- **If crossing meadow's east edge does not fade / does not change the player's area at all**, or if
  `World/ActiveArea/Orchard/ArrivalFromMeadowEast` does not resolve as a node property, something has
  regressed since the Slice 4 content migration landed (see "RUNNABLE" above) — stop after confirming
  this once and report it, rather than repeating the same failing crossing for every subsequent step.
