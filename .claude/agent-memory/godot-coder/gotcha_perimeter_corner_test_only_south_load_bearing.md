---
name: perimeter-corner-test-only-south-load-bearing
description: on a rectangular perimeter-wall ring with one inset edge, a real per-corner point check can only catch a missing x/y-extension mutation at the corners on the NON-inset edges
metadata:
  type: reference
---

While fixing `tests/integration/world/test_perimeter_walls.gd`'s corner-gap test (world-collision
slice 9, 3rd review round) — see `docs/features/world-collision/design.md` §12.4 and
`world/areas/shared/world_area.gd`'s `build_perimeter_walls()` — I built a real per-corner
point-containment test (four points just past each corner, `assert some wall's Rect2 has_point()`)
to replace a widened-span check that a mutation test had shown was inert (could not detect the
north/south walls' `± PERIMETER_WALL_THICKNESS_PX` x-extension being stripped).

**The non-obvious result: only two of the four corners can actually fail that mutation.**

- West/east walls run the exact `bounds.size.y` height, flush at `bounds.position.y` (the true
  north edge — west/east are never inset) through `bounds.end.y` (the true south edge). They do
  not extend past either end on their own.
- The north wall is inset south by `NORTH_WALL_HEADROOM_INSET_PX` (camera-headroom fix, see
  `build_perimeter_walls()`'s doc comment). With today's constants
  (`PERIMETER_WALL_THICKNESS_PX == NORTH_WALL_HEADROOM_INSET_PX`, both 32px), the north wall's row
  happens to start at exactly `bounds.position.y` too — the same y where west/east's columns
  start. So west/east ALREADY cover the NW/NE corner square on their own, independent of whether
  north has any x-extension at all. A corner-point test at NW/NE cannot distinguish "extension
  present" from "extension removed."
- The south wall has no inset. West/east's columns *stop* at `bounds.end.y` and do not reach past
  it. So the SW/SE corner square (south of the true edge) is covered *only* because the south
  wall's own x-extension reaches into west/east's x-range. Removing that extension leaves SW/SE
  genuinely uncovered — a corner-point test there fails correctly.

Confirmed empirically: mutating away both walls' extensions and re-running
`test_perimeter_walls_close_all_four_corners()` produced exactly one failure, at SW, with NW/NE/SE
all still passing (SE also failed in the run, since the same south-wall mutation hits it too —
the point is NW/NE are structurally immune to this particular mutation, not that they happened to
pass by chance in one run).

**How to apply:** when building or reviewing any corner/edge-closure test on a wall ring where one
edge has an inset/offset the others don't, don't assume symmetry across all four corners — trace
each corner's actual covering body back to which wall's *own* extent (not a shared constant)
supplies it, and pick test points (or design the mutation) so at least one asserted corner is
provably dependent on the exact behavior under test. Checking only one representative corner (the
one an example usually gives, typically NW) can silently prove nothing. Verify by mutating the
real implementation and reading GUT's `{script, test, message}` failures — don't trust the
arithmetic on paper (see [[gotcha_asymmetric_wall_inset_breaks_corner_test]] for the sibling gotcha
about widened-span checks breaking after an inset is introduced).

## Related

[[gotcha_asymmetric_wall_inset_breaks_corner_test]] — the widened-span check this replaced, and
why it silently stopped working once the north wall got its inset.
