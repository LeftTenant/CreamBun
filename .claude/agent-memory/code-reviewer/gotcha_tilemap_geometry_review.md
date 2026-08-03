---
name: gotcha-tilemap-geometry-review
description: Reviewing TileSet/tile_size/collision changes — decode tile_map_data, check alt-tile collision scope, re-check pixel-authored positions, round-trip hand-spliced .tscn text
metadata:
  type: project
---

Two things to check whenever a diff touches `TileSet.tile_size`, `texture_region_size`, or the
`sources/N` keys in an area scene's embedded TileSet (`world/areas/*.tscn`; formerly
`world/world.tscn`).

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

## 3. TileSet collision belongs to `(atlas_coords, alternative_id)`, not to a layer or a cell

Adding a `physics_layer_N/polygon_M/points` entry to a tile makes **every already-painted cell
using that exact `(source_id, atlas_coords, alt)` solid**, retroactively and on every
`TileMapLayer` sharing the TileSet — including a non-Y-sorted `Ground` layer. The safe pattern
(used for the Ground/Solids split) is `TileSetAtlasSource.create_alternative_tile()`: a new
alternative id sharing the same texture region carries the polygon, `alt 0` stays walkable, and
only newly painted cells reference the new alt. Serialization looks like `0:0/next_alternative_id
= 2`, `0:0/1 = 1`, `0:0/1/physics_layer_0/polygon_0/points = ...`.

**How to review:** decode `tile_map_data` on *every* layer sharing the TileSet and confirm no
existing cell uses the alt that gained a polygon; then confirm at runtime with a probe —
`src.get_tile_data(coords, alt).get_collision_polygons_count(0)` should be `0` for alt 0.
Polygon points are tile-local and centred: a full 32×16 tile is `(-16,-8, 16,-8, 16,8, -16,8)`.

Watch the *visual* consequence too: an alternative of a flat ground texture used as a Solids
tile is an invisible wall, and because `Solids` is Y-sorted the player sorts *behind* it when
standing north of the tile centre. Fine as slice scaffolding, worth flagging as a follow-up.

### `get_collision_polygons_count(0)` ERRORS on a TileSet with zero physics layers

It does not return `0` — it emits an engine-level `Index p_layer_id = 0 is out of bounds` error,
once per queried cell. Any helper that walks arbitrary `TileMapLayer`s must guard with
`layer.tile_set != null and layer.tile_set.get_physics_layers_count() > 0` first. This bites the
moment a second area scene exists: TileSets are per-scene sub-resources, so one area can have a
physics layer configured while another has none at all
([[reference-world-area-authoring-facts]]).

## 4. Verify hand-spliced `.tscn` text with a ResourceSaver round trip

When a coder hand-writes serialized text into a `.tscn` (to avoid regenerating `unique_id`s and
`ext_resource` ids), prove the splice is canonical: `load()` the scene and
`ResourceSaver.save()` it to a throwaway path, then `diff` the two. Everything except
`ext_resource` ids/uids (which the resaver regenerates) should match byte-for-byte.

Save to `user://` (`ResourceSaver.save(load(path), "user://roundtrip.tscn")`, then diff the
globalized path) so the probe never litters the project tree. The complete benign-difference
set is: the `[gd_scene]` header's `uid=` attribute (dropped on resave), the `[ext_resource]`
lines themselves, and every `ExtResource("...")` id reference. Anything else — a physics
layer key, an alternative-tile key, a `PackedByteArray` blob — differing means the splice
was not canonical.

Known-benign difference from that diff: `PackedByteArray` accepts both the base64 string form
and a decimal byte list, and they parse identically — but Godot always *writes* base64, so a
decimal list will be rewritten on the next editor save and show up as a spurious diff. Ask for
it to be pre-normalized to the base64 form.

`TileMapLayer.tile_map_data`'s 2-byte header is `0` in current Godot (TileMapLayer has its own
data-format enum starting at 0 — not the old `TileMap` FORMAT_3); a `0` header is correct, not
a stale format.

## Related

[[gotcha-tscn-editor-drift]] — other `.tscn` hunks worth treating as suspect.
[[perspective-terminology]] — `TILE_SIZE` is `Vector2i(32, 16)`, square lattice.
