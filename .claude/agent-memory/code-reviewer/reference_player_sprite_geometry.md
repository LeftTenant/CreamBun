---
name: player-sprite-geometry
description: Measured opaque-pixel geometry of Cream Bun's 32x32 sprite frames — union is 26x27 at local x[-13,13] y[-31,-4]; the widely-repeated "5px padding on every side / 22x22 character" claim is false
metadata:
  type: reference
---

Measured from `resources/sprites/player/*.png` (four 32×32 horizontal strips: idle, walk
forward, walk backward, walk side), with `AnimatedSprite2D.offset = (0, -16)` and
`centered = true`, so a frame occupies player-local `x ∈ [-16, 16], y ∈ [-32, 0]`.

## The numbers (re-verified 2026-08, alpha > 0 bbox per frame, unioned)

**Union of opaque pixels across every frame of every animation:**

| | player-local | size |
| --- | --- | --- |
| x | `[-13, 13]` | 26px |
| y | `[-31, -4]` | 27px |

Per-side transparent padding within the 32×32 frame, at the union's tightest:
**left/right 3px, top 1px, bottom 4px.** Padding is *not* uniform per frame — the idle pose
has ~5px above the head while walk frames have ~1px (the walk cycle's hop raises the body),
which is why any measurement must union across all frames, never sample the idle pose.

This union is exactly the authored `ThresholdBounds` rect in `player.tscn`
(`RectangleShape2D` size `(26, 27)` at `(0, -17.5)`) — zero slack in every direction, by
design (world-thresholds design.md §6: authored, not derived, with a test asserting
containment).

## The false claim to watch for

Several comments and docs state the frames carry **"5px of transparent padding on every
side, so the character occupies the middle 22×22."** That is wrong on all four sides (see
table above), and the 22px figure is really the *movement capsule's* length, not the art's
width. Its origin is the **idle pose specifically**: idle frames 0 and 2 measure exactly
`(5, 5, 27, 27)`, i.e. 5px all round and 22×22 — someone measured one frame and generalised.
It survives in at least `player.gd`'s `get_visual_extent()` docstring,
`docs/features/world-collision/design.md` §10 (which also asserts "what you see is what
collides" for the movement capsule — a rule world-thresholds Slice 1 explicitly overturned),
and `docs/features/world-collision/player-collider-capsule-test-plan.md`'s "What changed"
intro. The test that asserted it
(`test_collider_width_matches_the_drawn_character_width`, comparing two hand-maintained
constants and never touching the art) has been deleted.

**How to apply:** never accept "the character is 22px wide" or "5px padding" as a premise —
re-measure, or cite the table above. And treat the movement capsule's dimensions as a free
design choice: this project explicitly does *not* hold "what you see is what collides" for
the movement collider (only `ThresholdBounds` must cover the art).

## Vertically: the feet float above the origin

The lowest opaque row sits 4px above the frame's bottom edge, i.e. 4px above the node
origin / ground anchor, about a quarter of the 16px tile depth. Invisible to any data-level
test — only an e2e screenshot catches it. If it ever needs fixing the choices are trimming
the art or changing the documented `-16` offset; both are design-doc decisions, not
unilateral edits.

## Horizontally: the sprite overhangs the movement collider by 2px per side

The movement collider is a `CapsuleShape2D` laid on its side — 22×10, extent
`x ∈ [-11, 11], y ∈ [-14, -4]`. Against the 26px-wide art that is only ~2px of overhang per
side (an older note claiming ~6px was measured against a 20px rectangle collider that no
longer exists). North/south approaches have far more slack: the collider is 10px deep
against 27px of art.

## Related

[[perspective-terminology]] — 32×16 square grid, tile depth 16.
