# Slice 2 — The `Threshold` Node — Test Plan

### E2E
- [ ] No end-to-end coverage for this slice — a `Threshold` is not yet placed in any real, playable
      area scene (that is slice 4) and nothing wires its signal yet (slice 3), so there is nothing a
      player could encounter on screen. Revisit once a `Threshold` is placed in `meadow.tscn`/
      `orchard.tscn` and wired to `world.gd`.

### Integration
- [ ] A `Threshold` on the `interactable` layer detects a body/area on the `player_bounds` layer
      entering it — a minimal physics-frame check (two nodes on the two masked layers, one physics
      step, assert `area_entered`/overlap) proving the layer and mask bits are actually wired to each
      other correctly, not just individually correct in isolation. This is not premature: it is the
      one thing a per-bit unit check cannot catch — two masks can each be "correct" in isolation and
      still fail to see each other if a bit is transposed. No behavior beyond the raw overlap is
      asserted here; nothing in this slice listens to `area_entered` yet (that's slice 3's job).

### Unit
- [ ] `threshold.tscn`'s root node is an `Area2D` with `threshold.gd` attached, and `class_name
      Threshold` resolves to it.
- [ ] `destination` defaults to `""` — an unconfigured `Threshold` names no destination scene.
- [ ] `arrival` defaults to `&""` — an unconfigured `Threshold` names no landing marker.
- [ ] `collision_layer` is the `interactable` layer only — not additionally `player_bounds`,
      `player`, or `world`.
- [ ] `collision_mask` is the `player_bounds` layer only — not `player` (the movement capsule's
      layer), which would be a plausible and dangerous mix-up given both layers exist and a
      `Threshold` masking the movement capsule instead of the art-sized detection box would fire at
      the wrong moment — and not `world` or `interactable`.
- [ ] `threshold.tscn` has a child `CollisionShape2D` using a `RectangleShape2D` — present so a
      designer has something to resize per placement, per design §4 ("an `Area2D` a designer drags
      into an area scene and sizes").
