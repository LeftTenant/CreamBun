# Slice 7 — Tree: footprint ≠ silhouette — Test Plan

### E2E
- [ ] Walking behind the tree's canopy — where the sprite visually overlaps the player — does not block movement.
- [ ] Walking into the trunk's 1x1 footprint tile blocks movement.
- [ ] The player draws in front of the tree when standing below (south of) its ground anchor.
- [ ] The player draws behind the tree when standing above (north of) its ground anchor.

### Integration
- [x] The tree instance in `world.tscn` is a direct child of the Y-sorted area root, not nested under an intermediate node.
- [x] The tree's `collision_layer` is `world` and `collision_mask` is 0, per the `WorldProp` base class default.
- [x] A player probe driven by a real `move_and_slide()` loop is stopped at the trunk's 1×1 footprint edge, travelling neither past the edge (upper bound) nor sitting motionless short of it (lower bound).
- [x] The same probe, approaching along a path that only overlaps the canopy's visual overhang and never crosses the trunk's footprint, travels the full unobstructed distance — proving the canopy exerts no collision at all, not merely reduced collision.

### Unit
- [x] `tree_oak.tscn`'s `footprint` is `Vector2i(1, 1)`.
- [x] The canopy `Polygon2D` is visibly wider than the one-tile footprint and positioned above (negative local Y) the trunk, so the placeholder's silhouette genuinely diverges from its footprint rather than being a footprint-sized box.
- [x] The trunk `Polygon2D` sits at/near the ground-anchor origin, sized to roughly the 1×1 footprint's screen extent, distinct from the much larger canopy shape above it.
