---
name: gotcha-camera-edge-lock-vs-tall-sprite
description: Camera2D.limit_top flush to the painted floor clips the feet-anchored player at a north wall — the old headroom inset that fixed it is DELETED; clipping is now an accepted content problem, so check per-area whether a mitigation was applied
metadata:
  type: project
---

`Camera2D.limit_*` set from `WorldArea.get_bounds_px()` clamps the **view rect**, not the camera
node: the visible region's top edge lands exactly on `limit_top == bounds.position.y`. The player
is feet-anchored (`AnimatedSprite2D.offset = (0, -16)` on a 32×32 frame), so the whole sprite
draws *above* `global_position` — a north perimeter wall flush with the painted edge stops the
player with most of Cream Bun above the view.

## Current state: the inset is GONE — clipping is accepted, per area

`NORTH_WALL_HEADROOM_INSET_PX` / `WorldArea.north_headroom_inset()` /
`Player.get_visual_extent()` / `World._north_headroom_inset()` **no longer exist.** World
Thresholds design §8 deliberately deleted them: tying map geometry to sprite art was the failure
mode that feature exists to retire. `_edge_rect()` is now symmetric — every wall's player-facing
face is flush with the true painted edge, north included.

Design §8's replacement is a **content** rule. An author fixes a north edge by (a) painting
impassable terrain a row or two in, (b) placing a `Threshold` there (it fires before the art
leaves the view), or (c) accepting the clip where the player has no reason to stand.

**Arithmetic to redo per area (do not trust prose that says "the top of the character"):**
player collider `Rect2(-11, -14, 22, 10)`, drawn union `y ∈ [-31, -4]`
([[player-sprite-geometry]]). Stopped against a flush north wall the origin sits at
`bounds.top + 14`, so the character's top pixel lands at `bounds.top - 17` — **17 of its 27 drawn
rows are above `limit_top`.** That is ~63% of the character, not a sliver.

**How to apply:** when reviewing a new or migrated area, check its north edge for one of §8's
three mitigations and say which one was chosen. As of the World Thresholds switchover
`meadow.tscn`'s north edge has *none* — an accepted-by-default clip that nothing (GUT or e2e)
observes. Never "fix" a recurrence by pushing `limit_top` above the painted floor; that reveals
the void the clamp exists to hide.

## `limit_smoothed` is a separate flag from `position_smoothing_enabled`

`Camera2D.limit_smoothed` defaults to `false` and has no effect unless
`position_smoothing_enabled` is `true`. With smoothing on and `limit_smoothed` off the camera
glides while following but **snaps** the instant it hits a limit. Both are `true` in
`player/player.tscn`. This does not risk revealing the void: Godot clamps the *target* and lerps
toward it, and a convex combination of two in-bounds positions stays in bounds.

## Related

[[player-sprite-geometry]] — the measured 26×27 opaque union used above.
[[gotcha-worldarea-bounds-coordinate-space]] — the other `get_bounds_px()` consumer gotcha.
[[reference-threshold-arrival-placement]] — the placed mechanism that replaced the inset.
