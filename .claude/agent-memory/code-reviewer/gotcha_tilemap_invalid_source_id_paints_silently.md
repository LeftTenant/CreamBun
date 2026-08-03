---
name: gotcha-tilemap-invalid-source-id-paints-silently
description: TileMapLayer.set_cell() with a source_id the TileSet does not define still registers the cell in get_used_rect()/get_used_cells(), so bounds-derived tests pass while the tiles are blank and get_cell_tile_data() errors
metadata:
  type: project
---

**Verified, Godot 4.6.2.** `TileMapLayer.set_cell(coords, source_id, atlas_coords)` stores the cell
unconditionally — it does **not** validate `source_id` against the layer's `TileSet`. A layer painted
entirely with a non-existent source id reports:

- `get_used_rect()` → the full painted rect (correct size)
- `get_used_cells().size()` → the full count
- `get_cell_tile_data(cell)` → `null`, plus an engine error
  `Condition "!sources.has(p_source_id)" is true. Returning: nullptr`
- nothing rendered, and no tile collision/terrain data

**Why this matters here:** `WorldArea.get_bounds_px()` is derived from `$Ground.get_used_rect()`, and
camera-limit / bounds assertions are the usual way area tests prove a scene is set up. Those all pass
against a completely invalid paint. The mistake only surfaces the moment something reads tile *data*.

**Godot writes TileSet sources as `sources/1`, `sources/2`, … — the first source id is 1, not 0.**
Every real area scene in this repo (`meadow.tscn`, `orchard.tscn`) uses `sources/1`. Code that paints
in script must therefore pass `1`, or better `tile_set.get_source_id(0)` (which returns the id at
*index* 0, i.e. `1`), never a hard-coded `0`.

**How to apply:** when a diff paints tiles from script (`set_cell` in a `_ready()`, a fixture
generator, a `@tool` helper), cross-check the literal source id against the `sources/N` keys in the
scene's `[sub_resource type="TileSet"]`. Do not accept "the bounds tests pass" as evidence the paint
is valid — assert `get_cell_tile_data(cell) != null` on one cell instead.

## Related

[[gotcha-tilemap-geometry-review]] — the rest of the TileMap/TileSet review checklist, including
"never renumber `sources/N`".
