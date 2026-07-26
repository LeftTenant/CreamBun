---
name: gotcha-perimeter-corner-gap-test-inert
description: A widened-span corner-gap check on a rectangular wall ring cannot detect a missing corner extension — each edge's detection band always picks up the perpendicular walls
metadata:
  type: project
---

`tests/integration/world/test_perimeter_walls.gd`'s
`test_perimeter_walls_cover_full_edge_length_with_no_corner_gaps()` widens the checked span past
`get_bounds_px()` by one wall thickness, on the stated theory that "a missing corner extension now
shows up as a real gap". **It does not.** Proven by mutation: deleting the north *and* south
walls' `± PERIMETER_WALL_THICKNESS_PX` x-extension entirely leaves all 6 tests green.

**Why:** `_matching_intervals_for_edge()` collects every wall body whose rect intersects that
edge's detection band, not just the wall named for that edge. On a closed rectangular ring the
perpendicular walls are always inside the band and always supply exactly the widened ends —
the west wall spans x ∈ [bounds.left − thickness, bounds.left], which is precisely the north
edge's widened left end, and symmetrically everywhere else. The widening is therefore inert on
all four edges, and the extra `north_reach = thickness − NORTH_WALL_HEADROOM_INSET_PX` term
(= 0 today) is arithmetically right but buys nothing.

The test is not worthless — a genuine mid-edge gap *is* caught (halving the north wall's width
produces exactly 1 failure). It just tests "each edge has continuous coverage", not corner
closure.

**How to apply:**

- Don't accept a comment claiming a span-widening exercises corner closure on a wall *ring*.
  Closing corners on a ring needs a per-corner check (assert a solid body actually contains the
  corner point outside both bounds edges) or a per-body check (assert the north wall's own rect
  extends past `bounds.position.x`), not a union-coverage check.
- **Verify a test's claimed catch by mutating the implementation**, not by reading it: back up the
  source file, break the specific behaviour the test claims to guard, run `-gselect=` on that one
  file, restore. Paper reasoning about union coverage is easy to get wrong in both directions.

## Related

[[gotcha-vacuous-blocked-movement-assertions]] — same family: an assertion shape that is satisfied
by the broken case it claims to catch.
[[gotcha-camera-edge-lock-vs-tall-sprite]] — the north-wall inset that motivated the asymmetric term.
