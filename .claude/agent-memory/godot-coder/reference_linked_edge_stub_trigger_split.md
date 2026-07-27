---
name: reference-linked-edge-stub-trigger-split
description: WorldArea's linked-edge geometry is a stub/trigger/stub split, not one full-span Area2D with handler-side corner suppression
metadata:
  type: reference
---

`world/areas/shared/world_area.gd`'s `_build_edge()` builds a linked edge (a filled `neighbour_*`
slot) as **three separate collision nodes**, not one Area2D spanning the whole edge:

- A small `StaticBody2D` "stub" (world layer) over each of the two 32×32px corner dead-zone
  squares (design doc §12.4).
- An `Area2D` trigger (interactable layer) over only the active stretch in between.

`_edge_rect(edge, bounds)` still computes the full-span rect an unlinked wall would use (and is
`static`, pure — no scene-tree dependency). `_linked_edge_rects(edge, bounds)` splits that same
rect into `[first-end stub, middle trigger, second-end stub]` and is also static/pure — both are
unit-testable without a live WorldArea, and the three pieces exactly tile the full-span rect with
no gap/overlap.

**Why this shape and not a full-span trigger with the corner check in `body_entered`:** an earlier
version built one Area2D over the whole edge and suppressed corner crossings only inside the
handler. That left the corner squares with **no solid geometry at all** — a player reaching a
corner was denied the `edge_reached` signal but was completely free to keep walking through it and
off the map entirely (measured ~1000px past `bounds.end.x` on a real probe). It also made
`body_entered` fire only once per overlap: entering near a corner (suppressed) and then walking
along the edge into the active stretch without ever leaving the Area2D never re-fired the signal,
since nothing new was "entered." Splitting into real stub/trigger/stub geometry fixes both at once
— the stubs behave exactly like an ordinary perimeter wall segment (design doc §12.4's "corner
squares are ordinary walkable ground you just can't transition from" becomes literally true), and
crossing into the trigger piece specifically is what fires the signal, so walking along the edge
from a corner into the active stretch is a genuine new-Area2D-entry.

**How to apply:** if a future feature needs similar "solid at the ends, sensor in the middle"
geometry (e.g. a dock/pier prop, a one-way gate), reach for the same static
rect-splitting-then-building-multiple-collision-nodes pattern rather than one collider plus
handler-side suppression logic — handler-side suppression can deny a *signal* but can never deny
*movement*, and any "player must not be able to pass here" requirement needs actual solid geometry
somewhere.

**Related gotcha (test-authoring trap):** a corner-dead-zone test/e2e step on a **vertical**
(east/west) edge must target the **south** end, not the north. The north end of any vertical edge
falls inside the north wall/trigger's own `NORTH_WALL_HEADROOM_INSET_PX` zone (see
`_playable_boundary()`'s doc comment) — a player placed there gets depenetrated by that solid
geometry before ever reaching the edge under test at all, which makes the check pass for the wrong
reason. Horizontal (north/south) edges have no equivalent trap at either end.

**Related implementation gotcha:** `_linked_edge_rects()`'s vertical-edge branch must measure its
NORTH-end dead zone from `_playable_boundary(Edge.NORTH, bounds)` (i.e.
`bounds.position.y + NORTH_WALL_HEADROOM_INSET_PX`), not from the raw `bounds.position.y` — the
north wall/trigger's own player-facing surface already sits `NORTH_WALL_HEADROOM_INSET_PX` south of
the true edge, so a dead zone measured from the raw edge silently has **zero px of actual
exclusion** at the NE/NW corners (the player's collider bottoms out inside the still-solid headroom
strip before ever reaching a coordinate the naive band covered). A round-2 code review caught this
by physically walking a player along the north wall to the NE corner and confirming a transition
fired — the unit test for `is_in_corner_dead_zone()` alone didn't catch it, since that pure function
never exercised `_playable_boundary()`'s asymmetry. (`is_in_corner_dead_zone()` itself was later
deleted as dead code once corner exclusion fully moved into this stub/trigger/stub geometry — don't
go looking for it.) The south end has no such inset and is unaffected.
