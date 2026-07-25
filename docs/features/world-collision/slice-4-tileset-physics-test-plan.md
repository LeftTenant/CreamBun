# Slice 4 — TileSet Physics Layer + Ground/Solids Y-Sort Structure — Test Plan

### E2E
- [ ] Walking the player toward a painted `Solids` tile shows them stop at its edge — a screenshot taken mid-approach and one taken after several more frames of held input look identical, confirming the tile visually blocks further movement rather than merely slowing it.
- [ ] Walking the player onto a `Ground`-only tile (no `Solids` tile painted there) shows uninterrupted movement across it, for contrast with the blocked case above.

### Integration
- [x] `world.tscn`'s root `Node2D` still has `y_sort_enabled == true` after the restructure.
- [x] `world.tscn` contains a `Ground` `TileMapLayer` with `y_sort_enabled == false`.
- [x] `world.tscn` contains a `Solids` `TileMapLayer` with `y_sort_enabled == true`.
- [x] The tiles previously painted on the single original layer are all present on `Ground` after the split — the restructure moved data, it didn't drop any.
- [x] The shared `TileSet` resource has at least one physics layer, and that physics layer's `collision_layer` is set to the `world` bit (bit 1, from slice 2) and nothing else.
- [x] At least one tile in the atlas used by `Solids` has a collision polygon defined on that physics layer.
- [x] Instantiating `world.tscn` and driving the player toward a tile painted on `Solids` with that collision polygon: the player's position stops at the tile's edge instead of advancing into it.
- [x] Instantiating `world.tscn` and driving the player toward a tile painted only on `Ground`: the player's position advances onto and across it without being stopped.

### Unit
- [ ] No isolated logic to verify — this slice only adds a TileSet physics layer and restructures `world.tscn`'s tile layers; there is no new script code, so all behavior above can only be observed with the real scene and TileSet resource loaded (Integration/E2E).
