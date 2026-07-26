# Slice 6 — Boulder: first real prop, proven end-to-end — Test Plan

### E2E
- [ ] Approaching the boulder from the north stops the player at the footprint's edge, not the visual ellipse's edge.
- [ ] Approaching the boulder from the south stops the player at the footprint's edge, not the visual ellipse's edge.
- [ ] Approaching the boulder from the east stops the player at the footprint's edge, not the visual ellipse's edge.
- [ ] Approaching the boulder from the west stops the player at the footprint's edge, not the visual ellipse's edge.
- [ ] The player draws in front of the boulder when standing below (south of) its ground anchor.
- [ ] The player draws behind the boulder when standing above (north of) its ground anchor.

### Integration
- [x] The boulder instance in `world.tscn` is a direct child of the Y-sorted area root, not nested under an intermediate node.
- [x] The boulder's `collision_layer` is `world` and `collision_mask` is 0, per the `WorldProp` base class default.
- [x] A simulated `move_and_slide()` step into the boulder's 1×1 footprint is blocked.
- [x] A simulated `move_and_slide()` step that only overlaps the placeholder ellipse's visual silhouette (outside the footprint) is not blocked.

### Unit
- [x] `boulder.tscn`'s `footprint` is `Vector2i(1, 1)`.
- [x] The boulder's placeholder visual child is anchored above the ground-anchor origin (negative local Y), never centred on it.
