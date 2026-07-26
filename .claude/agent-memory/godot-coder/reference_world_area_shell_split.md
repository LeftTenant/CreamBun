---
name: world-area-shell-split
description: how world.tscn's persistent-shell/WorldArea split works after slice 8, and the get_node_or_null pitfall it creates for older tests
type: reference
---

`world/world.tscn` is a persistent shell (`World (Node2D)` with `ActiveArea`,
`Player`, `Notebook`, `Transition`); each concrete place (meadow, market, …)
is its own scene rooted on `world/areas/shared/world_area.gd`
(`@tool class_name WorldArea extends Node2D`), instanced under `ActiveArea` at
runtime by `world.gd._ready()`. `world.gd` then calls
`_player.reparent(area)` so the player joins the area's Y-sort scope — Y-sort
only interleaves *direct* children, so Ground/Solids/props/Player must all
share the WorldArea root, not World.

**Consequence for tests written before this split:** any test doing
`world.get_node_or_null("Ground"/"Solids"/"Player")` (a direct-child lookup)
breaks once those nodes move under the instanced WorldArea — the fix is
`world.find_child("Ground", true, false)` (recursive, not owner-restricted),
not a hunt for the "right" node path. `test_tile_geometry.gd` already used a
recursive helper and needed no change; `test_solids_collision.gd` needed the
`find_child` swap on every such lookup.

**WorldArea.get_bounds_px()** derives area extent from
`$Ground.get_used_rect()` scaled by `TILE_SIZE (32,16)` — bounds are never
hand-declared, only the four `neighbour_north/east/south/west: PackedScene`
export slots are (unfilled = hard boundary wall, per design; wiring lands in
a later slice).

**Moving a TileMapLayer's data into a new scene**: to preserve tile data
byte-for-byte when splitting a scene, copy the `tile_map_data =
PackedByteArray(...)` string and the `TileSet` sub_resource block verbatim
into the new .tscn — do not regenerate via the editor, which can silently
renumber sub_resource ids or reformat the byte array.

See also [[reference-scene-uid-generation]], [[worldprop-placeholder-visual-convention]].
