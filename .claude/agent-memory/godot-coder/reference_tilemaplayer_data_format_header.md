---
name: reference-tilemaplayer-data-format-header
description: TileMapLayer.tile_map_data PackedByteArray has a 2-byte format header before the per-cell records — decoding it wrong gives an off-by-one cell count
type: reference
---

`TileMapLayer.tile_map_data` (the `.tscn` `PackedByteArray(...)` blob) is **not** a bare
concatenation of per-cell records. Each cell record is 6 little-endian `int16`s (12 bytes: x, y,
source_id, atlas_coord_x, atlas_coord_y, alternative_tile) — but the array as a whole is prefixed
with a **2-byte format-version header** before the first record starts.

**Why this bites you:** decoding `base64_decode(blob)` and dividing `len(data) / 12` gives a
fractional cell count (e.g. `4082 / 12 = 340.1666...`), which looks like corrupt/truncated data.
It isn't — subtract the 2-byte header first: `(len(data) - 2) / 12` lands on a whole number, and
decoding cell records from `offset = 2` onward gives correct x/y/source_id values. Decoding from
offset 0 instead shifts every field by a few bytes and produces plausible-looking but wrong
source_ids (e.g. reading `15` when only `sources/1` and `sources/2` exist in the TileSet).

**How to apply:** whenever decoding a `TileMapLayer`'s painted cells directly from `.tscn` data
(e.g. to regenerate a GUT test fixture like `GROUND_CELLS_CSV` in
`tests/integration/world/test_solids_collision.gd` after a designer hand-edits the tile layer),
always skip the leading 2 bytes before parsing 12-byte cell records, and sanity-check the result
against `get_used_rect()`'s cell count from a live-loaded scene if possible rather than trusting
the byte math alone.
