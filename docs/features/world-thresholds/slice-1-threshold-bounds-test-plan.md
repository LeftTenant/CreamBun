# Slice 1 — `player_bounds` Layer and the Player's `ThresholdBounds` Collider — Test Plan

### E2E
- [x] None — design §2/§6 and the slice goal state this change is purely additive with no
      observable behavior difference (nothing reacts to `ThresholdBounds` until slice 3), so there
      is nothing new to see on screen. Revisit once a `Threshold` node exists to cross.

### Integration
- [x] `ThresholdBounds` is an `Area2D` child of `Player`, with a `CollisionShape2D` using a
      `RectangleShape2D` sized `Vector2(26, 27)` at `position = Vector2(0, -17.5)` — the authored
      design §6 rect, i.e. `x ∈ [-13, 13], y ∈ [-31, -4]` relative to the player origin.
- [x] `ThresholdBounds`'s `collision_layer` is set to the `player_bounds` layer only.
- [x] `ThresholdBounds`'s `collision_mask` is `0` — it detects nothing itself (design §6);
      Thresholds will mask it in a later slice.
- [x] `ThresholdBounds`'s authored rect fully contains the opaque-pixel union measured
      independently across every frame of every animation in the player's `SpriteFrames` — on
      failure, the test reports the measured bounding box and how far short the authored rect
      falls, rather than recomputing or auto-sizing anything (design §6: "the size is authored,
      not derived — and this is deliberate").
- [x] The player `CharacterBody2D`'s own `collision_layer` (`player`) and `collision_mask`
      (`world`) are unchanged by the addition of `ThresholdBounds`.
- [x] Driving the player into an existing solid obstacle stops them at the same position and
      behavior as before `ThresholdBounds` was added — the new `Area2D` on a masked-off layer does
      not perturb `move_and_slide()` or the movement capsule.

### Unit
- [x] `project.godot`'s `[layer_names]` section names `2d_physics/layer_4` as `player_bounds`.

> Note: `test_player_scene.gd`'s `test_collider_width_matches_the_drawn_character_width()` and its
> now-unused `SPRITE_FRAME_SIZE_PX` / `SPRITE_TRANSPARENT_PADDING_PX` constants are deleted this
> slice (tautological — it compared two hand-maintained constants and never touched the art; see
> the slice doc's ruling). That deletion is a one-time edit with no code path that could
> reintroduce the false claim, so it isn't itself a regression-suite check — the code reviewer
> should confirm it's gone as part of reviewing this slice. The `ThresholdBounds`-coverage
> assertion above is not a replacement for it: it guards a different, functional guarantee (a
> transition fires before the sprite leaves the view), not a cosmetic correspondence between the
> movement collider and the art.
