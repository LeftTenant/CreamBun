---
name: tileset-source-id-renumbering
description: Removing a TileSetAtlasSource from a .tscn must not renumber the remaining sources' keys — painted tile_map_data references source_id by value, not array position
type: reference
---

A `TileSet` sub-resource's `sources/N = SubResource(...)` lines use `N` as
the actual `source_id` — not a positional index. A `TileMapLayer`'s painted
`tile_map_data` (a `PackedByteArray`, 12 bytes/cell: x, y, source_id,
atlas_coord.x, atlas_coord.y, alternative_tile, all `int16` LE) references
tiles by that `source_id` value directly.

**Why this matters:** deleting `sources/0` (e.g. dropping a placeholder
atlas) and then renaming the remaining `sources/1`/`sources/2` down to
`sources/0`/`sources/1` silently reassigns every painted cell that used to
point at source 1 or 2 to a *different* atlas — the map still "loads" with
no error, but paints the wrong texture on existing tiles. There is no
validation error for this; it only shows up visually (or by diffing
`get_cell_source_id()` counts before/after).

**How to apply:** when removing one `TileSetAtlasSource` from a `TileSet`
that already has painted `tile_map_data`, delete only that source's
`sources/N` line and leave the other sources' `N` keys unchanged (gaps in
the numbering are fine — Godot doesn't require them contiguous or
zero-based). Don't run editor-style clean-up renumbering unless you also
rewrite `tile_map_data`.

To verify a change like this instead of trusting the diff by eye: run the
scene headless via `godot --headless --path <project> --script <tmp.gd>`
with a `SceneTree`-based script that loads the `.tscn`, walks
`TileMapLayer.get_used_cells()`, and tallies `get_cell_source_id(cell)`
counts — compare the tally before and after the edit (via `git stash`) to
confirm every cell still resolves to the same logical source (e.g. "236
cells on source 1, 32 on source 2" unchanged). Autoload-dependent compile
errors (`Identifier not found: GameState`, etc.) are expected noise in this
mode since `--script` doesn't load `project.godot` autoloads — ignore them,
the TileSet/TileMapLayer inspection still works.
