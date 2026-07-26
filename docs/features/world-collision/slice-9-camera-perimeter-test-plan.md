# Slice 9 — Camera Dead Zone, Edge Lock, and Perimeter Walls — Test Plan

Design doc: `docs/features/world-collision/design.md` §12.3 (camera dead-zone/edge-lock
derivation), §12.4 (the "no neighbour → invisible wall" case only — open-edge triggers are
slice 10, out of scope here).

## Decision: smoothing enabled (resolved)

Resolved: this slice's "soft cozy glide" requirement (design §12.3) supersedes the
pixel-art-purist shimmer guard. `player/player.tscn`'s `Camera2D.position_smoothing_enabled` is
accepted as `true`.

Note for test-generation: `tests/integration/player/test_player_scene.gd`'s
`test_camera2d_position_smoothing_not_enabled()` asserts the old, now-superseded requirement in
both its name and its docstring — it must be renamed and rewritten (not just flipped to assert
`true`) so no misleadingly-named test survives into the suite.

### E2E
- [ ] Walking to the meadow's north edge: the camera stops panning at the map boundary and never reveals area outside the painted floor.
- [ ] Walking to the meadow's south edge: the camera stops panning at the map boundary and never reveals area outside the painted floor.
- [ ] Walking to the meadow's east edge: the camera stops panning at the map boundary and never reveals area outside the painted floor.
- [ ] Walking to the meadow's west edge: the camera stops panning at the map boundary and never reveals area outside the painted floor.
- [ ] At each of the four edges, the player is halted by an invisible wall rather than walking off-screen or past the tile art.
- [ ] While roaming the interior of the meadow (away from any edge), the player can drift within the dead zone before the camera begins to follow, rather than the camera tracking the player pixel-for-pixel.

### Integration
- [x] After the meadow loads, `Camera2D.limit_left/top/right/bottom` on the player's camera equal `meadow.get_bounds_px()`'s position/end in pixels.
- [x] `Camera2D.drag_horizontal_enabled` and `drag_vertical_enabled` are both `true` on the loaded player camera.
- [x] `Camera2D.drag_left_margin`/`drag_right_margin` equal the derived two-tile value (0.4) and `drag_top_margin`/`drag_bottom_margin` equal the derived two-tile value (≈0.356), per design §12.3's table. (Corrected from `drag_horizontal_margin`/`drag_vertical_margin` — Godot 4's `Camera2D` has no such per-axis properties, only the four per-side properties named here; see `test_drag_margins_match_two_tile_dead_zone()`'s own comment for the same correction.)
- [x] `Camera2D.position_smoothing_enabled` is `true` on the loaded player camera, per design §12.3's "cozy glide" requirement.
- [x] `Camera2D.limit_smoothed` is also `true` on the loaded player camera — without it the camera snaps (rather than glides) the instant it reaches a `limit_*` edge, undercutting the same "cozy glide" requirement exactly where it matters most (the map boundary).
- [x] After the meadow loads, a `StaticBody2D` on the `world` collision layer exists spanning each of the four edges of `meadow.get_bounds_px()` (north, east, south, west) — since no `neighbour_*` slot is filled in this slice.
- [x] Each perimeter wall's collision shape covers the full length of its edge (no gaps a player could slip through at the corners).
- [x] The player's `CharacterBody2D` is blocked by each perimeter wall on contact (movement along the wall's normal is stopped) rather than passing through.
- [x] Camera limits and perimeter walls are rebuilt correctly from `get_bounds_px()` regardless of the meadow's specific painted extent (i.e. the logic reads bounds from the area, not a hard-coded rect) — verified by asserting the computed limits/wall positions are a function of `get_bounds_px()`'s actual returned `Rect2`, not fixed constants.

### Unit
- [ ] No isolated unit-level logic in this slice — the drag-margin values are static Camera2D properties set in the scene file (verified via the integration checks above), and the camera-limit / perimeter-wall computation is inseparable from `WorldArea`/`world.gd`'s scene wiring, so it is exercised as integration behavior rather than pure-function logic.
