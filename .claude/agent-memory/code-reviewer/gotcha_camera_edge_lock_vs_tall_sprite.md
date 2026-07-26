---
name: gotcha-camera-edge-lock-vs-tall-sprite
description: Camera2D.limit_top flush to the painted floor hides the feet-anchored player at the north wall — RESOLVED by insetting the north perimeter wall one sprite-height; redo the arithmetic whenever either constant moves
metadata:
  type: project
---

`Camera2D.limit_*` set from `WorldArea.get_bounds_px()` (design §12.3) clamps the **view rect**,
not the camera node: the visible region's top edge lands exactly on `limit_top ==
bounds.position.y`. The player is feet-anchored (`AnimatedSprite2D.offset = (0, -16)` on a 32×32
frame, §10), so the whole sprite draws *above* `global_position` — a north perimeter wall flush
with the painted edge stopped the player with **zero pixels of Cream Bun on screen**.

## Resolution (shipped): inset the NORTH wall only, by one sprite-height

`world_area.gd`'s `build_perimeter_walls()` offsets the north wall by
`NORTH_WALL_HEADROOM_INSET_PX` (32.0), so its player-facing (south) face sits 32px south of
`bounds.position.y` while its north face stays flush with it. The other three walls stay flush.
Consequence to remember: **the top two tile rows of every area are permanently non-walkable
decorative backdrop.**

Verified arithmetic on the 17×20 meadow (`bounds = Rect2((0,16),(544,320))`, viewport 320×180),
confirmed by a headless probe:

- Wall occupies y ∈ [16, 48]; the player's 20×10 collider (half-depth 5) stops the feet at
  **y = 53**.
- Sprite frame spans world y ∈ [21, 53]; the drawn body (frame rows 5–26,
  [[player-sprite-geometry]]) → y ∈ [26, 47].
- Settled view top = `limit_top` = 16 → **full frame visible with 5px spare** (10px on the body).

**How to apply:** redo exactly this arithmetic whenever `NORTH_WALL_HEADROOM_INSET_PX`,
`PERIMETER_WALL_THICKNESS_PX`, the sprite offset/frame height, or the collider depth changes —
the slack is only 5px and no GUT test observes it (the integration tests only assert
`limit_* == bounds`). Don't "fix" a future recurrence by pushing `limit_top` above the floor;
that reveals the void §12.3 exists to hide.

Anything documenting "the player stops a few px short of `limit_top`" (the e2e scenario's north
checkpoint, design §12.4's "a StaticBody2D spanning that edge") is stale unless it accounts for
the inset — north now stops ~37px short, the other three edges ~5–10px.

## `limit_smoothed` is a separate flag from `position_smoothing_enabled`

`Camera2D.limit_smoothed` defaults to `false` and has no effect unless
`position_smoothing_enabled` is `true`. With smoothing on and `limit_smoothed` off the camera
glides while following but **snaps** the instant it hits a limit. Both are now `true` in
`player/player.tscn`. This does not risk revealing the void: Godot clamps the *target* and lerps
toward it, and a convex combination of two in-bounds positions stays in bounds.

## Related

[[player-sprite-geometry]] — the ~5px bottom padding and 6px side overhang used above.
[[gotcha-worldarea-bounds-coordinate-space]] — the other `get_bounds_px()` consumer gotcha.
[[gotcha-perimeter-corner-gap-test-inert]] — the test-side fallout of the asymmetric inset.
