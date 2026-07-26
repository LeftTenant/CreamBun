# Slice 8 — WorldArea Extraction & Persistent Shell — Test Plan

### E2E
- [ ] Re-running the slice 6/7 screenshot scenario against the restructured scene shows identical framing, tile layout, and boulder/tree draw order (regression check confirming the shell/area split changed nothing visible).

### Integration
- [x] After `World._ready()` runs, the Player node's parent is the instanced `WorldArea` (meadow), not the `World` shell.
- [x] The boulder and tree instances carried over from slices 6–7 remain direct children of that same `WorldArea`, confirming the Player and props share one Y-sort scope.
- [x] `ActiveArea` holds exactly one instanced `WorldArea` (meadow) whose `Ground` and `Solids` layers are its direct children, matching design §6.1's layer layout.
- [x] The `Transition` `CanvasLayer` is present in the instantiated `world.tscn` with `process_mode` set to `ALWAYS`.
- [x] The existing Issue #36 spawn-position regression test still passes against the Player's new parent context — the scene-authored spawn position survives being reparented into `WorldArea`.

### Unit
- [x] `WorldArea.get_bounds_px()` returns `$Ground.get_used_rect()` scaled by `TILE_SIZE` (32×16) for a fixture area with a known painted region.
- [x] `WorldArea` exposes the four `neighbour_north/east/south/west` `PackedScene` export slots, all unset by default (unused until slice 10).
