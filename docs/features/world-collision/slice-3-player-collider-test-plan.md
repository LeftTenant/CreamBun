# Slice 3 — Player Ground Anchor and Collider Fix — Test Plan

### E2E
- [ ] With the player idle in `world.tscn`, a screenshot shows Cream Bun's feet resting on the ground plane at the node's origin — no visual floating or sinking relative to the tile grid — establishing the feet-anchored baseline that later Y-sort slices (6–7) will be checked against.
  - Ran this scenario: it found a real ~5px gap between Cream Bun's feet and the ground anchor. Root cause is transparent padding below the character in the current placeholder sprite art, not the `AnimatedSprite2D.offset = Vector2(0, -16)` value, which matches the design doc exactly. Decision: keep the offset as designed and accept the small gap as a placeholder-art quirk; revisit once real sprite art replaces the placeholder. Leaving this checkbox unticked since the gap is a known, deferred issue rather than a resolved one.

### Integration
- [x] `player.tscn`'s `CollisionShape2D` uses a `RectangleShape2D` shape sized `Vector2(20, 10)`.
- [x] `player.tscn`'s `CollisionShape2D` node position is `Vector2(0, 0)` — centred on the player's origin, not offset like a `WorldProp`.
- [x] `player.tscn`'s `AnimatedSprite2D` has `offset == Vector2(0, -16)`, placing the 32×32 frame above the origin.
- [x] `player.tscn`'s root collision node has `collision_layer` set to the `player` layer only.
- [x] `player.tscn`'s root collision node has `collision_mask` set to the `world` layer only.

### Unit
- [x] No isolated logic to verify — this slice only changes node configuration in `player.tscn` (collider shape/position, sprite offset, physics layers); `player.gd` has no code changes (design §10).
