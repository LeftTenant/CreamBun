---
name: gotcha-tilemap-geometry-review
description: Reviewing TileSet/tile_size changes — decode tile_map_data to verify atlas source_ids, and re-check every pixel-authored world position
metadata:
  type: project
---

Two things to check whenever a diff touches `TileSet.tile_size`, `texture_region_size`, or the
`sources/N` keys in `world/world.tscn`.

## 1. `sources/N` keys are values, not positions — never renumber them

`tile_map_data` stores each painted cell's **`source_id` by value**. Deleting
`sources/0` and renumbering `sources/1` → `sources/0` silently repoints every painted cell at
the wrong texture (or at nothing). Keeping non-contiguous keys (`sources/1`, `sources/2` with
no `sources/0`) is correct and intentional.

**How to verify in review** — decode the PackedByteArray directly:

```python
import base64, struct, re
b = base64.b64decode(re.search(r'tile_map_data = PackedByteArray\("([^"]*)"\)', txt, re.S).group(1))
body = b[2:]                       # first 2 bytes = uint16 format marker
for i in range(0, len(body), 12):  # 12 bytes/cell
    x, y, source_id, atlas_x, atlas_y, alt = struct.unpack_from('<hhhhhh', body, i)
```

Confirm every decoded `source_id` still has a matching `sources/<id>` entry, and diff the
base64 blob against `main` to prove the map was not accidentally repainted.

## 2. Halving `tile_size` breaks every pixel-authored position in the scene

`tile_map_data` is in **tile** coordinates, so painted terrain survives a tile-size change
untouched — but nodes positioned in the `.tscn` (`Player.position`, prop placements, camera
limits) are in **pixels** and do *not* follow. After a 64×32 → 32×16 rescale, a node authored
at `Vector2(576, 352)` moves from tile `(9, 11)` to tile `(18, 22)` — potentially clean off
the painted island, with no test failure to show for it.

**Why:** GUT asserts on `tile_size`, texture dimensions, and node-local positions all stay
green; the breakage is purely "what the camera actually frames". The design doc's "the painted
map needs no migration care" note is about tile coords only and is easy to over-apply.

**How to apply:** when `tile_size` changes by a factor *k*, every world-space pixel constant in
the same scene (and its hard-coded twin in `tests/integration/world/test_world_scene.gd`) must
be divided by *k*. Decode the painted region's tile bbox, convert the authored position to a
tile coord, and confirm it still lands inside the blob before passing the review.

### Verify the camera frame, not just the spawn tile

"Spawn tile is painted" is too weak — the painted region is a ragged island, not a filled
rectangle, so a legal spawn tile can still sit one cell from a hole that fills a third of the
screen. The player carries a `Camera2D` with no limits, so the framed rect is
`spawn ± viewport/2` (viewport is 320×180). Convert that rect to tile coords and assert **every**
cell in it is painted:

```python
tx0, tx1 = floor((sx - 160) / tw), ceil((sx + 160) / tw) - 1
ty0, ty1 = floor((sy -  90) / th), ceil((sy +  90) / th) - 1
holes = [(x, y) for y in range(ty0, ty1 + 1) for x in range(tx0, tx1 + 1) if (x, y) not in cells]
```

Also diff the decoded `tile_map_data` bytes against `main` (sha1 the blob) — an identical hash
proves the geometry change did not repaint or shift a single cell, which is the one thing the
GUT suite genuinely cannot tell you.

## Related

[[gotcha-tscn-editor-drift]] — other `.tscn` hunks worth treating as suspect.
[[perspective-terminology]] — `TILE_SIZE` is `Vector2i(32, 16)`, square lattice.
