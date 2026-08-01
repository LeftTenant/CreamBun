# Player Collider Capsule + Terrain Edge Collision — Test Plan

Design doc: `docs/features/world-collision/design.md` §6.1 (which tile layer a collidable tile
belongs on), §9 (Y-sort anchor consequence), §10 (the player collider), §12.4 (north headroom
inset), §12.5 (opposite-edge spawn margin).

## What changed

Three related changes, made by hand in the Godot editor, that this plan covers:

1. **The player's collider is now a capsule aligned to the drawn character.**
   `player/player.tscn`'s `CollisionShape2D` went from `RectangleShape2D(20, 10)` at `(0, 0)` to
   `CapsuleShape2D(radius 5, height 22)` rotated 90° at `(0, -9)` — a 22×10 horizontal capsule
   spanning `x ∈ [-11, 11]`, `y ∈ [-14, -4]` relative to the origin. The width matches the drawn
   character exactly (32×32 frames with 5px transparent padding all round), and the rounded ends
   let `move_and_slide()` deflect off staggered tile-edge polygons instead of snagging on them.

2. **`meadow.tscn`'s `Ground` layer now carries collision.** The `grass` atlas gained eight edge
   variants (`1:0`–`8:0`) whose physics polygons are thin strips along one or two tile borders.
   Nine of them are painted into `Ground`, fencing off two small regions. Previously only the
   `Solids` layer had any collision at all. One of the two `Solids` scaffolding cells — `(11, 11)`
   — was also reverted to plain non-solid grass, leaving `(12, 11)` as the only `Solids` cell.

3. **`NORTH_WALL_HEADROOM_INSET_PX` dropped from 32 to 16.** Raising the collider moved the
   player's stopping point relative to the camera's `limit_top`, so the inset needed to keep the
   whole drawn character on screen shrank to one tile depth.

4. **The inset constant was then removed entirely** in favour of deriving it, per area build, from
   the player's own published geometry (`WorldArea.north_headroom_inset()` fed by
   `Player.get_visual_extent()` / `get_collider_extent()`). Deriving it immediately surfaced that
   16 is too small once walk animations are used — see the note at the end of this plan.

## Risk focus

The changes interact, and two spots are tight enough to deserve their own checks:

- **The north-entry spawn margin is now 2px.** A north entry lands at `bounds.position.y + 32`;
  the collider's top edge sits 14px above the origin, at `+18`; the north trigger zone ends at
  `+16`. Correct, but it is the smallest margin in the transition system — a regression here shows
  up as an immediate bounce-back on every north-entering transition, not as a crash.
- **Ground collision invalidates hard-coded test lanes.** Several movement tests drove the player
  along coordinates chosen to dodge every obstacle "as of this writing." Those lanes now cross the
  newly-fenced regions, so the tests fail for a reason that has nothing to do with what they
  assert. The fix is to derive a clear lane from the area's actual collision at run time, not to
  pick new magic numbers that will go stale the next time a designer paints something.

---

### Unit

- [x] `WorldArea.compute_entry_position()` for a NORTH entry returns
      `bounds.position.y + NORTH_WALL_HEADROOM_INSET_PX + 16` — asserted against the constant, not
      a literal, so the expectation follows the code if the inset is retuned again.
- [x] `WorldArea.compute_entry_position()` for SOUTH/EAST/WEST entries is unaffected by the inset
      change (those edges' playable boundary is still the raw painted edge).
- [x] The north entry position clears the north trigger zone by the player collider's own top
      offset — i.e. `entry_y - 14 > bounds.position.y + NORTH_WALL_HEADROOM_INSET_PX`. This is the
      2px margin above, written down as an assertion so shrinking it fails a test rather than
      silently reintroducing bounce-back.
- [x] `grass.png` is a whole number of 32×16 tiles wide and exactly 16px tall (it is now a 9-tile
      strip, not a single tile). Guards the tile-size invariant without re-asserting the old
      single-tile assumption.

### Integration

**Player scene shape (`tests/integration/player/test_player_scene.gd`)**

- [x] `CollisionShape2D.shape` is a `CapsuleShape2D` (a rectangle's corners catch on staggered
      tile-edge polygons — design §10).
- [x] The capsule is `radius = 5`, `height = 22`, i.e. 22px along its long axis and 10px across.
- [x] The `CollisionShape2D` is rotated 90° so the capsule lies horizontally (long axis on X).
- [x] `CollisionShape2D.position` is `(0, -9)`, lifting the collider off the origin to sit against
      the bottom of the drawn character rather than straddling the ground anchor.
- [x] The collider's world-space extent relative to the player origin is `x ∈ [-11, 11]`,
      `y ∈ [-14, -4]` — asserted on the derived extent, so a change to radius/height/position/
      rotation that happens to preserve the individual properties still can't drift the footprint.
- [x] The collider's 22px width matches the drawn character's width in the sprite frames (32px
      frame, 5px transparent padding each side), tying the collider to the art it was traced from.
- [x] `AnimatedSprite2D.offset` is still `(0, -16)` — unchanged, but it is half of the derivation
      above, so it stays asserted.
- [x] `collision_layer` is `player` only and `collision_mask` is `world` only (unchanged; the
      `.tscn` no longer spells `collision_mask` out because it matches the engine default, so the
      assertion is the only thing holding the intent).

**Terrain collision (`tests/integration/world/test_solids_collision.gd`)**

- [x] At least one `Ground` cell carries a collision polygon — the newly-supported "flat boundary
      on the unsorted layer" pattern (design §6.1).
- [x] At least one `Solids` cell still carries a collision polygon.
- [x] The player is stopped by a collidable `Ground` edge tile when driven into it.
- [x] The player is stopped by a collidable `Solids` tile when driven into it.
- [x] The player crosses a genuinely collision-free tile uninterrupted. The "collision-free"
      search must consider **both** layers — checking only `Solids` (as it did) can now pick a
      cell whose approach corridor crosses a collidable `Ground` tile, which fails the test for
      the wrong reason.

**Perimeter, triggers, and transitions**

- [x] The player is blocked by the west perimeter wall, driven along a lane derived from the
      area's real collision rather than a hard-coded row.
- [x] The player is blocked by the north perimeter wall (same lane derivation).
- [x] `edge_reached` fires exactly once when crossing the clear middle of meadow's linked south
      edge, driven along a derived clear column.
- [x] `edge_reached` fires exactly once when crossing the clear middle of meadow's linked east
      edge.
- [x] The linked east edge's `Area2D` trigger occupies the expected rect, whose north end now
      follows the 16px inset (`bounds.top + 16 + 32`, not `+ 32 + 32`).
- [x] Crossing meadow's south edge transitions to orchard and spawns the player at
      `orchard_bounds.position.y + NORTH_WALL_HEADROOM_INSET_PX + 16`.
- [x] Crossing meadow's east edge transitions to orchard's west edge, unaffected by the inset.
- [x] After a north entry, the player does not immediately bounce back — the existing
      "immediate walk back to just-entered edge does not bounce" and "walking well away then back
      re-arms" tests cover the debounce; the 2px geometric margin is what keeps them from being
      the only thing standing between the player and a bounce loop.

### E2E (meadow, via the testing sandbox)

Run 2026-07-31. Results recorded inline; measured values are player-origin world coordinates read
back from the live scene.

- [x] The player spawns in the meadow and the whole character is visible, not clipped.
- [x] Walking north to the boundary: stops at **y = 46.003**, exactly the predicted
      `bounds.top (16) + inset (16) + collider top offset (14)`. Screenshot at `limit_top` shows
      the entire character on screen with ~3px to spare — the direct visual check on the 16px
      headroom inset.
- [x] The boulder blocks the player and still draws in front of them: driven south from spawn, the
      player stopped at **y = 227.99**, putting their collider's bottom edge on the boulder
      collider's top edge (y = 224). No regression from moving the collider off the origin.
- [x] The fenced `Ground` regions render as visible fences and enclose the regions they should
      (screenshots show the west pen open to the south, the east pen open to the north).
- [x] Walking east off the meadow's east edge: swaps to `orchard.tscn`, player reparented into it.
- [x] Walking west off orchard's west edge: swaps back to `meadow.tscn` — the link is two-way.
- [x] Walking south off the meadow's south edge: swaps to orchard and lands the player at
      **(416.0, 32.0)**. The Y is exactly `orchard bounds.top (0) + inset (16) + one tile (16)`.
      The X shows the §12.5 clamp working: the exit X was past orchard's width, so it clamped to
      one corner-dead-zone in from its east edge.
- [x] No bounce-back after the north entry: position held at exactly (416.0, 32.0) with state
      `PLAYING` across 60 further frames. The 2px margin holds in practice.
- [x] Corner dead zones never transition, and are solid: verified at three separate corners — the
      meadow's NE (stopped at x = 532.93 against the corner stub with no transition), the meadow's
      SW (wedged against both the west wall and the south corner stub), and orchard's NE (held at
      y = 30.003 by the north corner stub). Sliding west out of orchard's NE corner zone fired the
      transition the moment the collider cleared the stub — the corner rule gates the trigger, it
      doesn't disable the edge.
- [~] Walking *along* a staggered run of edge tiles without snagging: **not isolated.** Several
      full-map diagonal traverses brushed prop and fence geometry and never stuck anywhere except
      at genuine dead ends (corners and walls), which is consistent with the capsule working — but
      the sandbox's input round-trip is ~1.5s of held movement (~290px), far coarser than the 64px
      pens, so the player could not be parked against a specific fence run to isolate the seam
      crossing. The integration test `test_player_stops_at_a_ground_edge_tile_with_collision`
      covers the blocking half of this with the stop attributed to within one tile of the target;
      the anti-snag half rests on the shape assertions in `test_player_scene.gd` plus the design
      rationale. Worth re-checking by hand in the editor, where movement is precise.


---

## Follow-up surfaced by the derivation

Replacing the hand-maintained inset with a computed one changed the answer from 16 back to **32**,
for a reason nobody had written down: **the player sprite sheet's top padding is uneven.**

| Animation | Frames | Least top padding |
| --- | --- | --- |
| `idle` | 4 | 2px (frame 3) |
| `walk backward` | 18 | 1px |
| `walk forward` | 9 | 1px |
| `walk side` | 9 | 1px |

`idle` frame 0 — the frame everyone measured, including the original derivation in this plan — has
5px. The tallest frame across the sheet reaches 31px above the player's origin, not 27, which needs
17px of headroom and rounds up to 32.

**This is latent, not live.** `player.gd` has no animation switching yet, so only `idle` is ever
drawn; a 16px inset is genuinely correct today. It starts clipping ~1px off the top of Cream Bun's
antenna the moment walk animations are wired up — 4 screen px at the project's 4× scale.

Three ways to settle it, in the order I'd suggest considering them:

1. **Even out the art** — pad the walk sheets to match `idle`'s 5px. Makes 16 correct forever and
   costs nothing at runtime. Probably the real fix.
2. **Keep the all-frames union (current state)** — inset 32, safe forever, costs every map a second
   non-walkable backdrop row today for animations not yet in use.
3. **Drop the round-up-to-a-whole-tile rule** — use the raw 17px. Cheapest in map space, but the
   backdrop strip stops being a countable number of tile rows, which §12.4 leans on for designers.

Left at option 2 pending a decision, since it is the only one that is safe without an art change.
