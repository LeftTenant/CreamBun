# Slice 5 — `WorldProp` Base Class — Test Plan

### E2E
- [ ] No end-to-end coverage for this slice — there is no concrete prop scene or placeholder visual yet (slice 6), so nothing renders that a screenshot could meaningfully verify; the class's behavior is fully observable through direct instantiation.

### Integration
- [ ] No cross-system coverage for this slice — `WorldProp` is not yet wired into `world.tscn` or any area root (slice 6), so there is no signal flow, autoload interaction, or multi-node wiring to exercise beyond the single class covered under Unit.

### Unit
- [x] A footprint of `(1, 1)` produces a `RectangleShape2D` whose `size` equals `Vector2(32, 16)` — one tile's worth of ground.
- [x] A footprint of `(2, 3)` produces a `RectangleShape2D` whose `size` equals `Vector2(64, 48)` — width and depth both scale with `TILE_SIZE`.
- [x] The generated collider's `position.y` equals `-shape.size.y / 2.0` in both cases above, so the collider spans `y ∈ [-depth, 0]` — entirely behind the ground anchor, never in front of it.
- [x] The generated collider's `position.x` remains `0.0` regardless of footprint, so the collider is horizontally centred on the origin — consistent with the origin being the footprint's *front-centre*, not its corner.
- [x] Setting `footprint` to `Vector2i(0, -1)` clamps to `Vector2i(1, 1)` — a designer cannot author a zero or negative footprint on either axis.
- [x] Reassigning `footprint` on an already-`_ready` node rebuilds the collider shape to match the new value — the setter, not just initial construction, drives the live editor preview described in the class docs.
- [x] Constructing a `WorldProp` and setting `footprint` before it enters the scene tree (before `@onready _collision` resolves) does not error — the rebuild is a no-op until the collision child exists, per the guard in `_rebuild_collider()`.
- [x] `collision_layer` equals the `world` layer bit and `collision_mask` equals `0` — static solids collide with nothing themselves (design doc §11); asserted explicitly since the engine's default mask of `1` coincidentally equals the `world` bit.
