---
name: gotcha-open-edge-trigger-corner-gaps
description: A linked edge is [wall stub, Area2D trigger, wall stub]; a vertical edge's NORTH corner stub is 64px tall (not 32) because it is measured from the north headroom-inset boundary, not the raw painted edge
metadata:
  type: project
---

`world_area.gd` builds a **linked** (neighbour_* set) edge as three pieces that exactly tile the
same rect an unlinked wall would occupy — `_linked_edge_rects()` returns
`[StaticBody2D stub, Area2D trigger, StaticBody2D stub]`, the stubs covering the
CORNER_DEAD_ZONE_PX square at each end. Corner exclusion is therefore **structural**, not
enforced in `_on_edge_trigger_body_entered()`. Verified by headless probe on meadow (bounds
`(0,16)–(544,336)`):

```
PerimeterWallNorth        [-32, 16]–[576,  48]
PerimeterWallEastCornerA  [544, 16]–[576,  80]   <- 64px tall, NOT 32
EdgeTriggerEast           [544, 80]–[576, 304]   layer 4 (interactable)
PerimeterWallEastCornerB  [544,304]–[576, 336]
PerimeterWallSouthCornerA [-32,336]–[ 32, 368]   (64px wide — full rect extends past bounds)
EdgeTriggerSouth          [ 32,336]–[512, 368]
PerimeterWallSouthCornerB [512,336]–[576, 368]
PerimeterWallWest         [-32, 16]–[  0, 336]
```

Three things worth knowing before reviewing or changing this:

1. **No seam at any corner.** North/south full rects already extend `PERIMETER_WALL_THICKNESS_PX`
   past `bounds` on each side, so a south stub (64px) overlaps the east stub's column. Probed all
   four corners driving diagonally for 240 ticks: the player is contained every time. Do not
   "fix" a gap here without re-probing — there isn't one.
2. **A vertical (east/west) edge's NORTH corner is asymmetric with its south one, on purpose.**
   `_linked_edge_rects()` computes `north_end = _playable_boundary(Edge.NORTH, bounds) +
   CORNER_DEAD_ZONE_PX` — i.e. `bounds.y + 32 + 32` — while `south_end` uses the raw
   `bounds.end.y - 32`. The extra 32 is the north headroom inset
   ([[gotcha-camera-edge-lock-vs-tall-sprite]]): the band `y ∈ [bounds.y, bounds.y+32]` is inside
   the solid north wall, so measuring the dead zone from the raw painted edge would have counted
   unreachable ground as the exclusion and left **0px of real walkable exclusion** at NE/NW. A
   64px north stub is correct, not a bug — do not "simplify" it to match the south end.
3. **Measured NE behaviour on meadow** (player collider 20×10 centred on origin, so it spans
   `y ± 5`): northernmost reachable player Y is `bounds.y + 37`; the first Y from which driving
   east fires `edge_reached` is `bounds.y + 70`. That is ~33px of reachable, non-triggering
   ground — matching CORNER_DEAD_ZONE_PX. Hugging the north wall and walking east is contained by
   the stub at `x = bounds.end.x` and fires nothing.

**How to apply:**

- Corner-dead-zone tests/e2e steps on an east/west edge work at **either** end now, but the
  north-end version needs the player driven from `bounds.y + 37 … + 66`; a start Y taken naively
  as `bounds.y + 10` still lands inside the north wall and gets depenetrated south, making the
  test pass for the wrong reason. Existing corner tests in `test_edge_triggers.gd` still only use
  the SOUTH end — the north end's guard is the *geometric* stub-rect assertion in
  `test_linked_east_edge_gets_an_interactable_area2d_not_a_wall()`, which does fail if the
  `_playable_boundary` term is removed (mutation-confirmed).
- Re-probe rather than reason: teleport a player into the region, drive it, print the final
  position. Half of this geometry looks correct in the source and isn't.
- Mutation-test corner claims by deleting the stubs in `_build_edge()` — the *geometric* rect
  assertions fail, and so do the *containment* assertions (`assert_lt(player.x, bounds.end.x+5)`),
  but the *behavioural* "no signal fired" assertions stay green
  ([[gotcha-vacuous-blocked-movement-assertions]]). A corner test needs both halves.

## Related

[[gotcha-camera-edge-lock-vs-tall-sprite]] — the north inset that drives the 64px north stub.
[[gotcha-perimeter-corner-gap-test-inert]] — the slice-9 precedent: another corner check that
could not fail.
[[gotcha-destroy-before-acquire-soft-lock]] — the other recurring failure shape in this
transition code.
