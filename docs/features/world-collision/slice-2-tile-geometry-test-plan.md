# Slice 2 — Tile Geometry (32×16 tiles + named physics layers) — Test Plan

### E2E
- [ ] The world scene rendered at the 320×180 viewport shows roughly a 10×11 tile grid (double the density of the old 64×32 tiles, which showed ~5 tiles across), confirming the rescale is visually in effect.

### Integration
- [x] Loading `world/world.tscn` yields a `TileSet` whose `tile_size` is `Vector2i(32, 16)`.
- [x] Every `TileSetAtlasSource` on that `TileSet` has `texture_region_size` equal to `Vector2i(32, 16)`.
- [x] No `TileSetAtlasSource` in `world.tscn`'s `TileSet` references `ground_placeholder.png` (the placeholder source and its `ext_resource` are gone).
- [x] `world.tscn` instantiates without errors or missing-dependency warnings after the texture and TileSet edits.

### Unit
- [x] `resources/sprites/terrain/grass.png` reports image dimensions `32×16`.
- [x] `resources/sprites/terrain/flower grass.png` reports image dimensions `32×16`.
- [x] `project.godot`'s `[layer_names]` section reads back `2d_physics/layer_1 == "world"`, `2d_physics/layer_2 == "player"`, `2d_physics/layer_3 == "interactable"`.

> Note: removal of `resources/tilesets/ground_placeholder.png` is a one-time deletion with no code path that could reintroduce it — it isn't a standing regression risk, so it's not a GUT test. The code reviewer should confirm the file is gone as part of reviewing this slice.
