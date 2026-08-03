---
name: gotcha-perimeter-corner-gap-test-inert
description: A widened-span corner-gap check on a rectangular wall ring cannot detect a missing corner extension — RESOLVED by a per-corner point-containment check; use that shape, not span coverage, for corner closure
metadata:
  type: project
---

A "widen the checked span past `get_bounds_px()` by one wall thickness, so a missing corner
extension shows up as a real gap" check on a closed wall **ring does not work.** Proven by
mutation: deleting the north *and* south walls' `± PERIMETER_WALL_THICKNESS_PX` x-extension
entirely left every such test green.

**Why:** the per-edge helper collects every wall body whose rect intersects that edge's detection
band, not just the wall named for that edge. On a closed rectangle the perpendicular walls are
always inside the band and always supply exactly the widened ends — the west wall spans
`x ∈ [bounds.left − thickness, bounds.left]`, which *is* the north edge's widened left end, and
symmetrically everywhere else. Such a test still catches a genuine **mid-edge** gap (halving the
north wall's width fails it); it just proves "each edge has continuous coverage", not closure.

## The shape that does work (shipped)

`tests/integration/world/test_perimeter_walls.gd`'s
`test_perimeter_walls_close_all_four_corners()` asserts **point containment**: for each corner it
takes a point 1px diagonally *outside* `get_bounds_px()` and requires some world-layer
`StaticBody2D`'s rect to contain it. On the 17×20 meadow (`bounds = Rect2((0,16),(544,320))`)
`NW = (-1, 15)` falls inside the north wall's `x ∈ [-32, 576], y ∈ [-16, 16]` **only** because of
the `±thickness` extension — the west wall runs `y ∈ [16, 336]` and misses it. Remove the
extension and all four corner assertions fail. Full-span coverage lives separately in
`test_area_transition.gd`'s `_covers_full_span()`; the two are complementary, not duplicates.

**How to apply:**

- Reject any comment claiming a span-widening exercises corner closure on a wall *ring*. Corner
  closure needs a per-corner containment check, or a per-body check ("the north wall's own rect
  extends past `bounds.position.x`") — not a union-coverage check.
- **Verify a test's claimed catch by mutating the implementation**, not by reading it: back up the
  source file, break the specific behaviour the test claims to guard, run `-gselect=` on that one
  file, restore. Paper reasoning about union coverage is easy to get wrong in both directions.

## Related

[[gotcha-vacuous-blocked-movement-assertions]] — same family: an assertion shape that is satisfied
by the broken case it claims to catch.
[[gotcha-camera-edge-lock-vs-tall-sprite]] — the north-wall inset that once motivated an
asymmetric term here; that inset is now deleted and all four edges are symmetric.
