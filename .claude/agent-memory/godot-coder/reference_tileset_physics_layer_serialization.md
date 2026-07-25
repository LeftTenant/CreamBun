---
name: tileset-physics-layer-serialization
description: Exact .tscn/.tres text format for TileSet physics layers and per-tile TileData collision polygons, plus a safe workflow for authoring it by hand
type: reference
---

Godot 4.6 serializes TileSet physics layers and per-tile collision polygons as plain
resource-text properties — confirmed by scripting the TileSet/TileSetAtlasSource APIs
headlessly and reading back the saved `.tres` text (`ResourceSaver.save()`), rather than
guessing the key format:

```
[sub_resource type="TileSetAtlasSource" id="..."]
texture = ExtResource("...")
texture_region_size = Vector2i(32, 16)
0:0/next_alternative_id = 2
0:0/0 = 0
0:0/1 = 1
0:0/1/physics_layer_0/polygon_0/points = PackedVector2Array(-16, -8, 16, -8, 16, 8, -16, 8)

[sub_resource type="TileSet" id="..."]
tile_size = Vector2i(32, 16)
physics_layer_0/collision_layer = 1
physics_layer_0/collision_mask = 0
sources/1 = SubResource("...")
```

- `physics_layer_N/collision_layer` and `physics_layer_N/collision_mask` live on the
  **TileSet** resource itself, not on any TileMapLayer node.
- The collision polygon lives on the **TileData** for a specific
  `<atlas_x>:<atlas_y>/<alternative_id>`, keyed `physics_layer_N/polygon_M/points` as a
  `PackedVector2Array` in tile-local coordinates centered on the tile (a full 32×16 tile's
  rectangle is `(-16,-8, 16,-8, 16,8, -16,8)`).
- `TileMapLayer.tile_map_data` (a `PackedByteArray`) can be written either as a base64
  string (`PackedByteArray("...")`, confirmed as what a real `ResourceSaver.save()` round
  trip produces — the editor's own save path produces this too) or a decimal byte list
  (`PackedByteArray(0, 0, 11, 0, ...)`, seen from a different code path — e.g. `var_to_str()`/
  `print()` — not from `ResourceSaver.save()` itself) — both parse identically; don't try to
  hand-encode this byte array by reasoning about the field layout, see "safe workflow" below.
  Prefer the base64 form when hand-splicing text so a later editor save doesn't produce a
  driveby diff nobody authored.

**Safe workflow for hand-editing `.tscn` text**: don't guess this format or hand-derive
`tile_map_data` byte layouts. Instead, script the target behavior with the Godot binary
directly (`/Applications/Godot.app/Contents/MacOS/Godot --headless --script probe.gd`,
using an `extends SceneTree` script), call the real API (`TileSet.add_physics_layer()`,
`TileData.add_collision_polygon()`, `TileMapLayer.set_cell()`), `ResourceSaver.save()` the
result to a throwaway `res://probe_*.tres`/`.tscn`, read back the exact serialized text, then
splice that exact text into the real scene file by hand (to preserve unrelated content like
node `unique_id` attributes that a full instantiate-and-repack round trip risks losing or
regenerating). Delete the probe file afterward — `ResourceSaver.save()` writes real files
under the project root, they don't self-clean.

**Gotcha — giving an existing painted tile a collision polygon retroactively blocks every
cell already painted with it.** Collision is a property of `(atlas_coords, alternative_id)`
on the shared TileSet, not of the layer or the specific cell. If a design/slice says "just
add collision to one of the existing grass tiles for a test," check whether that exact
`(source_id, atlas_coords, alt=0)` is already painted elsewhere as walkable terrain (a
GUT/headless probe calling `layer.get_cell_source_id()`/`get_cell_atlas_coords()` over
`get_used_cells()` answers this in seconds) — it likely is, since the same handful of
placeholder tiles get reused everywhere. Adding collision directly to alt 0 silently turns
existing "Ground" cells solid. Fix: `TileSetAtlasSource.create_alternative_tile(coords)` a
new alternative id sharing the same texture region, put the collision polygon only on that
alternative, and paint new test/Solids cells with that alternative id. Existing cells
(alt 0) are untouched; the new alternative is visually identical but exists solely to carry
collision.
