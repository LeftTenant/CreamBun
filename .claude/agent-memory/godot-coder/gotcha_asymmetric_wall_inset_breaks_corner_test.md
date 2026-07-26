---
name: asymmetric-wall-inset-breaks-corner-test
description: insetting one perimeter wall (camera headroom fix) silently un-covers part of a generic symmetric corner-gap test on the adjacent edges
metadata:
  type: project
---

`world/areas/shared/world_area.gd`'s `build_perimeter_walls()` insets the north wall's
player-facing surface `NORTH_WALL_HEADROOM_INSET_PX` (32px) south of the true painted edge — a
deliberate fix so `Camera2D.limit_top` (which clamps the view rect flush to the painted floor,
not the camera node) always has a sprite-height of headroom above the feet-anchored player. See
[[gotcha-camera-edge-lock-vs-tall-sprite]] for the full derivation of why the wall needed to move
rather than the camera limit.

**The knock-on effect on tests:** `tests/integration/world/test_perimeter_walls.gd`'s corner-gap
test collects wall bodies per edge via a detection *band*, so bodies belonging to one edge (e.g.
the north wall) legitimately show up as covering part of the *adjacent* edge's band too (the
north wall's x-extension past each corner is what closes the west/east walls' corner gap — see
`build_perimeter_walls()`'s first doc comment for why that extension exists at all). A generic
symmetric widened-span check (`bounds ± PERIMETER_WALL_THICKNESS_PX` on every side) that passed
before the inset started failing specifically on the north corner afterward, because the inset
wall no longer reaches PERIMETER_WALL_THICKNESS_PX past `bounds.position.y` — only
`PERIMETER_WALL_THICKNESS_PX - NORTH_WALL_HEADROOM_INSET_PX` (here, exactly 0, since the two
constants are equal).

**How to apply:** whenever an edge's wall gets an inset/offset for some other reason (camera
headroom, art bleed, whatever), don't assume a "widen by one thickness on every side" corner-gap
check stays valid — recompute the widened span per-edge from that wall's *actual* reach past
`get_bounds_px()`, not a shared constant. Verify empirically (temporarily set an assertion's bound
absurdly high to capture the real number in the failure message, GUT reports actual values in
`{script, test, message}`) rather than trusting arithmetic on paper — this is also the fastest way
to get an exact px figure out of a `SceneTree`-script probe when autoloads aren't reliably
available to a bare `-s` script (they compile-error with "Identifier not found: GameState" when
loaded that way; the actual GUT test run already has autoloads live, so hijacking an existing test
is more reliable than writing a new headless probe script).

## Related

[[gotcha-camera-edge-lock-vs-tall-sprite]] — why the north wall needed the inset in the first place.
[[gotcha-worldarea-bounds-coordinate-space]] — the other `get_bounds_px()` consumer gotcha.
