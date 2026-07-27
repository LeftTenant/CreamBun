# Slice 10 — Edge Transition (Fade) and a Second Area — Test Plan

Design doc: `docs/features/world-collision/design.md` §12.2 (bounds derived, neighbours
declared), §12.3 (one-viewport-minimum area size), §12.4 (open edges vs. walls, corner dead
zones, arrival debounce, the north-wall headroom inset), §12.5 (the freeze/fade/swap/spawn/reveal
sequence and the opposite-edge spawn math).

Slice source: `docs/features/world-collision/slices.md`, Slice 10.

The mechanism is symmetric across both axes (design §12.4–§12.5): this plan proves it on an
east/west link (`meadow.neighbour_east` ↔ `second_area.neighbour_west`) and, separately, on a
north/south link (`meadow.neighbour_south` ↔ `second_area.neighbour_north`), reusing the same
second-area fixture on both edges rather than requiring a third area.

### E2E
- [ ] Walking the player to the meadow's linked east edge fades the screen to fully opaque before the new area's content is shown.
- [ ] After the fade covers the screen, the player reappears entering from the second area's opposite (west) edge, at the same on-screen height they exited at, and the fade clears back to transparent.
- [ ] Walking the player to the meadow's linked south edge triggers the same fade-swap-spawn sequence on the vertical axis, confirming the mechanism is not east/west-only.
- [ ] After the south-edge transition, the player reappears entering from the second area's opposite (north) edge, at the same on-screen horizontal position they exited at.
- [ ] During the covered portion of either transition, player input does not move the character (movement is frozen until the fade clears).
- [ ] Once the fade clears, the player can move freely again in the second area (control is restored, not left frozen).
- [ ] Walking along a linked edge close to one of its corners does not trigger a transition, on both the east/west link and the north/south link (the corner dead zone holds on both axes).
- [ ] Immediately after arriving through a linked edge, walking back toward that same edge before covering the debounce distance does not bounce the player back to the previous area — on both the east/west link and the north/south link.
- [ ] Walking away from the just-entered edge far enough re-arms it: leaving and re-entering through the same edge later works normally (the debounce is a distance check, not a permanent lockout).
- [ ] The reverse trip (from the second area's west edge back to the meadow's east edge, and separately from its north edge back to the meadow's south edge) triggers the same fade-swap-spawn sequence correctly in both directions.
- [ ] An edge of the meadow with no `neighbour_*` scene still behaves exactly like slice 9 — the player is stopped by an invisible wall, with no fade and no transition (regression check against slice 9).
- [ ] The camera in the second area frames the player correctly on arrival through either entry edge (centred with dead-zone slack, limited to the new area's bounds) rather than revealing area outside the painted floor.

### Integration
- [x] `WorldArea` exposes an `Edge` enum with `NORTH`, `EAST`, `SOUTH`, `WEST` values and a signal `edge_reached(direction: Edge)`.
- [x] For an edge whose `neighbour_*` slot is filled, the perimeter-build step creates an `Area2D` (not a `StaticBody2D`) on the `interactable` layer, occupying the active (non-corner) stretch of the rect `build_perimeter_walls()` would use for a wall on that edge (including the north headroom inset where applicable), with a small `StaticBody2D` stub covering each of the two corner squares — replacing slice 9's wall.
- [x] For an edge whose `neighbour_*` slot is empty, the perimeter-build step still creates a `StaticBody2D` wall on the `world` layer, matching slice 9's unmodified behavior.
- [x] When the player's body enters an open-edge trigger, `WorldArea` emits `edge_reached` exactly once with the `Edge` value matching the crossed edge — verified on both an east/west edge and a north/south edge.
- [x] A horizontal edge's (north/south) trigger excludes a 32×32px square inset 1 tile horizontally from each of its two ends; the player cannot cause `edge_reached` to fire while positioned inside either excluded corner square.
- [x] A vertical edge's (east/west) trigger excludes a 32×32px square inset 2 tiles vertically from each of its two ends; the player cannot cause `edge_reached` to fire while positioned inside either excluded corner square.
- [x] Immediately after spawning through a given edge, that edge's trigger does not emit `edge_reached` even while the player overlaps its geometry, until the player's distance from it exceeds the debounce threshold (16px for an east/west edge, 8px for a north/south edge) — confirmed as a distance check, not a timer (it stays inert indefinitely if the player never covers the distance).
- [x] Once the player has moved the required debounce distance away from the entry edge, that edge's trigger re-arms and fires normally on a later approach.
- [x] `meadow.tscn`'s `neighbour_east` references the second area's scene and the second area's `neighbour_west` references `meadow.tscn` — the east/west link is wired reciprocally.
- [x] `meadow.tscn`'s `neighbour_south` references the second area's scene and the second area's `neighbour_north` references `meadow.tscn` — the north/south link is wired reciprocally.
- [x] The second area's `get_bounds_px()` covers at least one full viewport (≥ 320×180px, ≥ 10×11 tiles), so the camera dead zone and edge lock behave identically to the meadow once the player arrives.
- [x] On `edge_reached`, `world.gd` sets `GameState.current_state = LOADING` before the fade begins, and it remains `LOADING` for the entire freeze/fade/swap/spawn sequence.
- [x] The `Transition` overlay fades to fully opaque before the area swap occurs, and fades back to transparent only after the player has been placed in the new area — matching the freeze → cover → swap → place → reveal ordering.
- [x] `GameState.current_state = PLAYING` is set only after the reveal fade completes, not before.
- [x] After the transition, the old `WorldArea` instance has been freed (no longer in the tree / queued for deletion) and the neighbour's scene has been instanced under `ActiveArea` in its place.
- [x] After the transition, the player has been reparented into the new area (same Y-sort-scope check pattern as slice 8's test).
- [x] After the transition, the new area's own perimeter is rebuilt (walls on its unlinked edges, correct triggers on its linked edges, including the reciprocal edge back to the meadow).
- [x] After the transition, the player's `Camera2D.limit_left/top/right/bottom` are reset to the new area's `get_bounds_px()`, not left at the meadow's stale values.
- [x] Leaving the meadow's east edge at a given perpendicular (Y) coordinate places the player on the second area's west edge at the same Y, offset 32px inward (one tile, east/west entry).
- [x] Leaving the meadow's south edge at a given perpendicular (X) coordinate places the player on the second area's north edge at the same X, offset 16px inward (one tile, north/south entry).
- [x] The reciprocal trips (second area's west edge → meadow's east edge; second area's north edge → meadow's south edge) preserve the coordinate and apply the correct inward offset symmetrically.
- [x] When the new area is smaller than the one departed on the crossed axis, the carried-over coordinate is clamped into the new area's valid range, and the clamped result still falls outside that area's own corner dead zones, rather than landing exactly on a boundary or inside an excluded corner.
- [x] `GameEvents.area_changed` is emitted with `area_id` equal to the newly-loaded area's scene file name without its `.tscn` extension (e.g. `"meadow"`, or whatever the second-area fixture is named).
- [x] `GameEvents.area_changed` is emitted exactly once per transition.
- [x] `GameEvents.area_changed` is emitted only after the area swap, reparent, perimeter rebuild, and camera-limit rebuild have all completed — not before the swap and not mid-fade.
- [x] While a transition is already underway (`GameState.current_state == LOADING`), a second `edge_reached` (e.g. from residual trigger overlap) does not start an overlapping second transition, free an already-freed area, or double-emit `area_changed`.

### Unit
- [x] Given an exit edge, the opposite-edge lookup returns the correct entry edge per design §12.5's table (`EAST`→`WEST`, `WEST`→`EAST`, `NORTH`→`SOUTH`, `SOUTH`→`NORTH`) as a pure mapping, independent of any scene state.
- [x] Given a scene file path, the `area_id` derivation returns the file name without its `.tscn` extension, as a pure function independent of scene state.
- [x] Given an edge and a position along it, the corner-dead-zone check correctly classifies whether that position falls within the 32×32px exclusion at either end — verified for both the 1-tile horizontal inset (north/south edges) and the 2-tile vertical inset (east/west edges).
- [x] Given the crossed edge and the player's current distance from it, the debounce check correctly reports armed/inert on either side of the exact 0.5-tile threshold (16px for east/west, 8px for north/south).
- [x] Given an exit coordinate, edge, and new-area bounds where the coordinate already falls inside the new area's valid range, the computed entry position preserves that coordinate verbatim, offset by the correct one-tile inward amount for the crossed axis (32px east/west, 16px north/south).
- [x] Given an exit coordinate, edge, and new-area bounds where the coordinate would fall outside the new (smaller) area's valid range, the computed entry position is clamped into that range while remaining outside the new area's corner dead zones.
- [x] This unit coverage assumes the opposite-edge lookup, `area_id` derivation, corner check, debounce check, and spawn computation are each implemented as isolable pure functions — if any ships inlined into `world.gd`/`world_area.gd` instead, that piece becomes an integration-only check per slice 9's precedent for inseparable scene-wiring logic. Confirmed: all five shipped as static functions on `WorldArea`, unit-tested directly in `test_world_area_edge_transition.gd`.
