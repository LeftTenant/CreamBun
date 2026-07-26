---
name: gotcha-worldarea-bounds-coordinate-space
description: WorldArea.get_bounds_px() returns Ground-LOCAL pixels but is consumed as both WorldArea-local and global — correct only while every ancestor sits at (0,0)
metadata:
  type: project
---

`WorldArea.get_bounds_px()` builds its `Rect2` from `$Ground.get_used_rect()` × `TILE_SIZE`, so
the coordinates are in the **`Ground` TileMapLayer's own local space**. Two callers consume the
same rect in two *different* spaces:

- `world_area.gd`'s perimeter walls set `body.position = rect.get_center()` — **WorldArea-local**.
- `world.gd`'s `_set_camera_limits()` assigns it to `Camera2D.limit_*` — **global**.

Both are correct today only because `Ground.position`, the `WorldArea` root's `position`, and
`ActiveArea`'s `position` are all `(0, 0)`. Nothing enforces that.

**Why it matters:** design §12.5's Phase-2 slide/scroll transition explicitly puts two areas
on screen at once at different offsets, and any designer nudging the `Ground` layer in the
editor breaks it silently — walls and camera limits would drift in opposite directions with a
fully green GUT suite (every test compares the camera against the *same* mis-scoped rect).

**How to apply:** when reviewing anything that consumes `get_bounds_px()`, ask which space the
consumer needs. The robust shapes are `_ground.to_global(...)` for a world-space rect (the
pattern `tests/integration/world/test_solids_collision.gd`'s `_cell_to_global()` already uses and
documents), and `to_local(...)` when placing a child of the WorldArea. At minimum the class
docstring should state which space the returned rect is in.

## Related

[[gotcha-camera-edge-lock-vs-tall-sprite]] — the other `get_bounds_px()` consumer gotcha.
