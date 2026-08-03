---
name: reference-threshold-arrival-placement
description: Measured geometry and naming conventions for placed Threshold/Arrival pairs in meadow/orchard — 2px depth, 4px gap from the wall, 8px corner inset, and the arithmetic that proves an Arrival reproduces the old landing spot
metadata:
  type: project
---

Area-to-area transitions are **placed**, not derived: a `Threshold` (`Area2D`,
`world/thresholds/threshold.tscn`) declares `destination` + `arrival`, and an `Arrival`
(`Marker2D`) in the destination says exactly where the player lands. `world.gd` drives the
sequence; `WorldArea` is bounds-and-walls only. `neighbour_*`, `edge_reached`,
`compute_entry_position()`, the corner dead zones and the arrival debounce are all gone.

## The authored numbers a review should re-measure, not assume

For a Threshold standing in for a **map edge** (as opposed to a doorway or pit):

- **Depth 2px**, settled. Do not thicken it to "fix" tunnelling — the detector is the player's
  26×27 `ThresholdBounds` box, not a point, so it cannot pass through between physics samples.
- **4px gap** between the Threshold's outer face and the perimeter wall's inner face (the wall's
  player-facing surface is flush with the painted edge). Uniform on all four shipped Thresholds.
- **8px inset from each end** of the edge span, so a Threshold never reaches the corners.
- Perimeter walls are unconditional and full-span on **every** edge, including edges that carry a
  Threshold — a Threshold is crossed before the wall is ever reached, not instead of it.

## The two shipped areas' bounds (re-derived from `tile_map_data`, so you don't have to)

- `meadow.tscn` — `get_used_rect()` cells `(0,1)` size `(17,20)` → **`Rect2(0, 16, 544, 320)`**
- `orchard.tscn` — → **`Rect2(0, 0, 448, 256)`**

Meadow's bounds do NOT start at y=0 — the top painted row is `y=1`. Any hand-check of a north-edge
number that assumes `bounds.position == Vector2.ZERO` will be 16px wrong. The 2px/4px/8px
conventions above check out against both: e.g. meadow's east Threshold at `x=539` with a 2-wide
shape has its outer face at 540, four pixels inside `bounds.end.x == 544`.

## Proving an Arrival's position is right, not merely self-consistent

An integration test that reads the marker's own position as ground truth cannot catch a
wrong-but-self-consistent placement. Check the **crossed axis** against the retired formula
(`_playable_boundary(entry_edge) ± one tile inward`, 32px east/west, 16px north/south) — the four
shipped Arrivals match it exactly (orchard `x=32` / `y=48`; meadow `y=320` / `x=512`). The
**tangential** axis had no fixed old value (it carried the exit coordinate over), so the
convention adopted is *the centre of the corresponding Threshold on the other side*. Consequence
worth knowing: a round trip no longer returns you to where you left.

Also verify an Arrival is (a) on a non-collidable tile — decode `tile_map_data` and check the
atlas coord against the TileSet's `physics_layer_0` polygons — and (b) not overlapping any
`Threshold` in its own area; the re-entry guard would cover (b), but design §5 prefers clearance.

## Related

[[reference-world-area-authoring-facts]] — bounds are a bounding box; TileSets are per-scene.
[[gotcha-camera-edge-lock-vs-tall-sprite]] — the north-edge clip this mechanism replaced a code
fix for with a content rule.
[[gotcha-tilemap-geometry-review]] — how to decode `tile_map_data` for the checks above.
