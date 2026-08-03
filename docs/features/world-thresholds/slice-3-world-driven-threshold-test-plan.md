# Slice 3 — `world.gd` Drives the Sequence off a Placed `Threshold` — Test Plan

### E2E
- [x] No end-to-end coverage for this slice — the mechanism is proven entirely against small
      test-only fixture scenes injected at test time; no placed `Threshold` exists yet in any real,
      playable area (`meadow.tscn`/`orchard.tscn` are untouched until slice 4), so there is nothing
      a player could encounter on screen. Revisit once slice 4 migrates real content to placed
      `Threshold`/`Arrival` pairs.

### Integration
- [x] Crossing a placed `Threshold` with the player's `ThresholdBounds` sets `GameState.current_state`
      to `LOADING` immediately, before the fade begins.
- [x] A residual second `area_entered` firing while `GameState` is already `LOADING` is a no-op — no
      overlapping second transition, no double free, no double `GameEvents.area_changed` (mirrors the
      old `_on_edge_reached()` guard).
- [x] The fade overlay becomes visibly opaque while `GameState` is `LOADING`, before the area swap.
- [x] `GameState.current_state` returns to `PLAYING` only once the full freeze → fade → swap → place →
      reveal sequence has completed.
- [x] The fade overlay is back to fully transparent once `GameState` is `PLAYING` again.
- [x] The source area is freed and the fixture area named by `Threshold.destination` is instanced in
      its place under `ActiveArea` after the sequence completes.
- [x] The player is reparented into the newly-instanced destination area.
- [x] Camera limits are reset to the destination area's own bounds, not left at the source area's.
- [x] The player's position on arrival exactly matches the named `Arrival` marker's global position —
      not a computed offset.
- [x] `GameEvents.area_changed` is emitted exactly once per crossing, carrying the destination area's
      id.
- [x] `GameEvents.area_changed` fires only after the swap, reparent, and camera-limit work are already
      done — asserted from a snapshot taken at the moment the signal fires, not merely "eventually
      after."
- [x] A `Threshold` whose `destination` path fails to load leaves `GameState` at `PLAYING`, the player
      exactly where they were, and pushes an error — nothing freed, nothing swapped.
- [x] A `Threshold` whose `destination` loads but whose `arrival` names no matching `Marker2D` in the
      new scene fails the same way — `GameState` back to `PLAYING`, player unmoved, error pushed,
      nothing freed or swapped.
- [x] In both failure cases, the fade overlay returns to fully transparent rather than stranding the
      player behind an opaque screen.
- [x] In both failure cases, `ActiveArea` still holds exactly the original source area — not freed,
      not duplicated.
- [x] An `Arrival` placed overlapping a `Threshold` in a fixture does not fire a transition on arrival.
      (Currently also passes with the dedicated ignore-set mechanism neutered to a no-op — today's
      `LOADING`-state early-return already suppresses the same initial signal this guard targets, so
      this test doesn't yet distinguish "the guard suppressed it" from "the `LOADING` window
      suppressed it." The guard stays in as defence-in-depth for design §5's "regardless of where a
      designer put the Arrival" requirement — see the comment on `world.gd`'s `_ignored_thresholds`.)
- [x] After the player's `ThresholdBounds` fully leaves that overlapping `Threshold`, walking back
      across it fires a transition normally. (Same coverage caveat as above — see that note.)
- [x] A second, non-overlapping `Threshold` in the same destination area fires normally on first
      crossing — the arm-on-arrival guard only suppresses the `Threshold` the player spawned into, not
      every `Threshold` in the area.
- [x] A fixture area with two distinct `Threshold`s each independently drives a transition to its own
      destination when crossed — proving `_activate_area()` connects every `Threshold` under the area,
      not just one.
- [x] A `Threshold` placed back in a destination fixture (a reverse trip to another fixture, or back to
      the source area) drives a normal transition, proving the mechanism isn't hardcoded to one
      direction.

### Unit
- [x] No unit coverage for this slice — the behavior under test is `world.gd` driving a live scene
      tree (`GameState`, the fade `Tween`, area swap, physics-layer overlap detection), which has no
      meaningful isolated-logic seam yet. The `StringName` id `GameEvents.area_changed` carries is
      computed by a new private helper in `world.gd` (design §7) that isn't unit-testable by name —
      its output is asserted via the emitted signal value above instead.
