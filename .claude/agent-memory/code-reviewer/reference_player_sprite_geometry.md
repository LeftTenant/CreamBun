---
name: player-sprite-geometry
description: Cream Bun's 32x32 sprite frames have ~5px of transparent padding below the body, so a -16 sprite offset leaves the feet floating above the node origin
metadata:
  type: reference
---

Measured geometry of `resources/sprites/player/*.png` (all 32×32 frames, horizontal strips):

| Sheet | Content rows (0-indexed) |
| --- | --- |
| `idle creambun.png` | 5 – 26 (every frame) |
| `walk forward/backward creambun.png` | lowest row cycles 22 – 27 (hop animation) |
| `walk side creambun.png` | lowest row cycles 20 – 26 |

So the **ground-contact row is ~26–27**, leaving ~4–5 transparent rows at the bottom of the
frame, and the walk cycle lifts the body up to ~5px during the hop.

**Why it matters:** the world-collision design (§10) prescribes
`AnimatedSprite2D.offset = Vector2(0, -16)` — half of the 32px frame height, which puts the
frame's *bottom edge* on the node origin. Because the art does not fill the frame to that edge,
Cream Bun's visible feet land ~4–5px **above** the origin (the ground anchor / collider centre),
about a third of the 16px tile depth. That is invisible to any data-level test — only the e2e
screenshot check catches it.

**How to apply:** when reviewing feet-anchoring, Y-sort, or "player stops at the right place"
work, remember the sprite's visual ground plane is ~4–5px above `global_position.y`. If it needs
fixing, the choices are trimming the art or changing the offset (a design-doc decision, not a
unilateral edit) — don't silently "correct" the documented `-16`.

## Horizontally: the sprite overhangs the collider by ~6px per side

The frame is 32px wide but `player.tscn`'s `RectangleShape2D` is only 20×10, so the sprite sticks
out ~6px on each side of the body that actually collides.

**Why it matters for prop review:** when judging whether a prop's *visual* lines up with its
generated footprint collider, the player's own 6px sprite overhang closes an equal-sized gap. A
prop visual up to ~12px narrower than its collider (e.g. a 20px-wide tree trunk on a 32px 1×1
footprint) still reads as a flush stop on an east/west approach — the player's sprite edge meets
the visual's edge even though their colliders are 6px apart. Do the sprite-vs-collider arithmetic
before flagging "invisible blocking"; the naive collider-vs-visual comparison overstates it.

**North/south approaches have no such slack** — the collider is only 10px deep against a 32px-tall
sprite, so vertical stop positions are dominated by the sprite's ~5px bottom padding instead.

## Related

[[perspective-terminology]] — 32×16 square grid, tile depth 16.
