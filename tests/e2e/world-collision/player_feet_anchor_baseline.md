# Scenario: Player renders feet-anchored on the ground plane (Slice 3)

Verifies that after Slice 3 (player ground anchor and collider fix, design doc
§10), Cream Bun's idle sprite reads as standing *on* the tile grid — feet
resting on the ground plane at the node's origin — with no visual floating or
sinking relative to the tiles beneath. This is a purely visual check: the
integration tests (`tests/integration/player/test_player_scene.gd`) already
assert the exact `CollisionShape2D` shape/position, `AnimatedSprite2D.offset`,
and collision layer/mask values; this scenario confirms the anchor change is
actually *legible on screen*, not just correct in data.

This screenshot is also the **feet-anchored baseline** that later Y-sort
slices (5–7, once props and Y-sort scopes exist) will be checked against —
if the player ever visibly floats or sinks relative to a prop's ground contact
point in a future slice, this is the reference to compare back to.

Design doc reference: `docs/features/world-collision/design.md` §8.1 (ground
anchor), §9 (depth sorting), §10 (player collider).
Test plan: `docs/features/world-collision/slice-3-player-collider-test-plan.md`.

## Setup

- Call `get_config` to obtain `reports_dir` (transient/comparison frames go
  there, never into `tests/e2e/`).
- Call `launch_game`.
- Wait: 20 frames (allow the world scene, player, and camera to fully
  initialize, and the idle animation to reach a settled frame, before the
  first screenshot).

## Steps

### Step 1: Idle player's feet rest on the ground plane, not floating or sunk

- Screenshot → compare / save reference:
  `tests/e2e/world-collision/screenshots/player_feet_anchor_step_01_idle.png`
- Get node property: `World/Player.position` (or the actual Player node path
  in world.tscn — check the scene tree if the path differs)
- Assert: no red engine error/assertion overlay visible anywhere in the frame.

**Visual checkpoints for this screenshot:**

1. **Cream Bun's feet appear to contact the tile the player is standing on.**
   Before this slice, the sprite was centred on the node origin with no
   upward offset, so the whole 32×32 frame — including a chunk of empty space
   below the feet — sat centred on the player's position. After the fix
   (`AnimatedSprite2D.offset = Vector2(0, -16)`), the frame is pushed upward
   so the visual feet line up with the origin. Judge this by comparing the
   apparent contact point of the feet against the seam between the player's
   current ground tile and the tile in front of (below, on screen) it — the
   feet should sit right at or just above that seam, not visibly floating
   above it or sunk below it into the tile behind.
2. **No half-tile vertical drift compared to a flat idle stance on other
   tiles.** If you nudge the player (via `press_action`/`release_action` on
   `move_up`/`move_down`/`move_left`/`move_right`, waiting a few frames
   between) to a couple of different tiles and re-screenshot, the apparent
   foot-to-tile contact point should look the same relative offset each time
   — confirming the anchor is a property of the player node, not an artifact
   of one particular tile's position.
3. **The sprite itself is not clipped or distorted.** Moving the frame via
   `offset` must not crop any part of the 32×32 idle frame — the whole
   character should render, just shifted upward.

---

## Notes for the executor

- **This scenario intentionally does not check collider or physics-layer
  values** (no collision assertions) — the integration tests already cover
  the exact `RectangleShape2D` size/position and `collision_layer`/
  `collision_mask` numeric values. This document exists to catch what those
  numeric checks can't: whether the anchor change is visually convincing.
- **Reference screenshot**: on first run of this scenario (post-Slice-3),
  save the capture as the reference under
  `tests/e2e/world-collision/screenshots/`. There is no pre-Slice-3 reference
  committed for direct pixel-diff comparison — judge the feet/tile contact
  qualitatively against the checkpoints above, not against an older
  screenshot. Do keep this reference around, though: slices 5–7 (Y-sort
  against props) should be checked against it.
- **Transient / comparison frames** captured while iterating must be saved to
  `<reports_dir>/e2e/` (gitignored), never into the committed `tests/e2e/`
  tree. Call `get_config` to retrieve `reports_dir` before saving any
  comparison shot.
- **Scope**: this scenario does not verify collision *response* (walking into
  a solid tile or prop) — no `Solids` physics layer or props exist yet at
  Slice 3 (those land in later slices per design doc §15 phasing items 2–4).
  It checks the player's visual ground anchor only.
