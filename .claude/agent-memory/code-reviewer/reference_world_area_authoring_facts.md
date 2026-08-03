---
name: world-area-authoring-facts
description: Hard facts for reviewing WorldArea/TileSet/prop authoring — TileSets are per-scene embedded sub-resources, minimum area is 10x12 tiles (not 11), bounds are a bounding box
metadata:
  type: project
---

Facts that keep coming up when reviewing world-area geometry, docs, or new area scenes.

## TileSets are embedded per-area sub-resources — there is no shared `.tres`

`world/areas/meadow.tscn` embeds `SubResource("TileSet_h5o24")`; `world/areas/orchard.tscn`
embeds its own, unrelated `TileSet_orchard`. No `.tres` TileSet exists anywhere in `resources/`.

**Why it matters:** collision authored on a tile ("draw the polygon once") is scoped to *that
area scene's* TileSet copy only. Meadow's TileSet has `physics_layer_0` configured; orchard's has
none. Duplicating an area scene forks the TileSet, so later physics/tile edits do not propagate
between areas.

**How to apply:** reject any claim (in code comments or docs) that tile collision is authored
once project-wide. When a new area is added, check whether it needs the physics layer re-added.
If a shared `.tres` TileSet ever lands, this memory is stale — verify before citing it.

## Minimum area size is 10 tiles wide x 12 tall, not 11

The constraint is "at least one viewport" = 320x180 px, with `TILE_SIZE = Vector2i(32, 16)`.
- 320 / 32 = 10.0 -> 10 columns exactly meets it.
- 180 / 16 = 11.25 -> **12 rows**. 11 rows is 176 px, 4 px short.

`docs/features/world-collision/design.md` §12.3 states "roughly >= 10 wide x 11 tall", and that
error propagates into anything written from it. Nothing in code validates area size — there is
no runtime check or `push_warning`, so an undersized area fails silently (Godot just centres it
and the camera dead zone stops mattering).

## `get_bounds_px()` returns a bounding box, not the painted silhouette

`WorldArea.get_bounds_px()` is `$Ground.get_used_rect()` scaled by `TILE_SIZE`. Perimeter walls,
edge triggers, and `Camera2D` limits are all built from that rectangle. A ragged or L-shaped
painted `Ground` therefore gets walls around its bounding box, leaving unpainted void inside the
walkable region. Areas are expected to be painted as filled rectangles.

## Related

[[gotcha-tilemap-geometry-review]] — how to decode `tile_map_data` and verify alt-tile collision.
[[gotcha-worldarea-bounds-coordinate-space]] — which coordinate space that rect is in.
[[reference-threshold-arrival-placement]] — the placed Threshold/Arrival geometry that replaced derived edges.
