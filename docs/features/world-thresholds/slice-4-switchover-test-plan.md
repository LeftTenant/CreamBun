# Slice 4 — Switchover: Collapse `WorldArea`, Remove the Old Path, Migrate Real Content — Test Plan

**Acceptance bar (design §10):** the existing two-way meadow ↔ orchard link works exactly as it
does today, via placed `Threshold`/`Arrival` pairs — reproducing today's crossing points and
landing spots, not bit-for-bit matching the old computed coordinates. This slice deletes far more
than it adds; see "Deletion/rewrite verification" below for the checklist half of this plan.

> **Parse-failure warning, worth stating plainly:** GUT drops a script that fails to parse and
> still reports the run as green. This slice deletes `neighbour_*`, `edge_reached`, the `Edge`
> enum's callers, and several `WorldArea` constants/methods that other test files may still
> reference by name. A stray reference anywhere in `tests/` to a now-deleted symbol is a
> parse-time failure for *that file*, silently, not a visible red assertion — so the full-suite
> run at the end of this slice (not just this feature's files) is load-bearing, and its output
> should be read for "did every script actually load," not just "did every assertion pass."

### E2E
- [ ] Walking Cream Bun off meadow's east edge fades to orchard and lands the player exactly at the
      authored `Arrival` marker's position on orchard's west side; walking back off orchard's west
      edge returns the player exactly at the authored `Arrival` marker's position on meadow's east
      side. The marker's authored position is the source of truth — no comparison against the old
      mechanism's computed offset. First e2e coverage for this feature — everything before this
      slice was fixture-only and had none.

### Integration
- [ ] Walking off meadow's east edge triggers a transition and lands the player exactly at
      `ArrivalFromMeadowEast` (or equivalently-named marker)'s position in orchard — the marker's
      authored position is the pass/fail bar, not any preserved offset from the old edge-derived
      mechanism.
- [ ] Walking off meadow's south edge triggers a transition and lands the player at orchard's north
      arrival marker.
- [ ] Walking off orchard's north edge triggers a transition and lands the player back at meadow's
      south-side arrival marker.
- [ ] Walking off orchard's west edge triggers a transition and lands the player back at meadow's
      east-side arrival marker (the reverse trip).
- [ ] Each of the four crossings emits `GameEvents.area_changed` exactly once, carrying the correct
      destination id (`"orchard"` or `"meadow"`), computed via `world.gd`'s new private helper.
- [ ] Each of the four crossings resets `Camera2D` limits to the destination area's own
      `get_bounds_px()`, not left at the source area's.
- [ ] Each of the four crossings runs the full freeze → fade → swap → place → reveal sequence
      (`GameState` LOADING → PLAYING, fade opaque then transparent) against the real `meadow.tscn`/
      `orchard.tscn` content, not a fixture.
- [ ] Arriving at each of the four real `Arrival` markers does not immediately re-fire the
      `Threshold` the player just spawned into (re-entry guard holds for real content, not just
      fixtures).
- [ ] `WorldArea.build_perimeter_walls()` builds a wall on all four edges of both `meadow.tscn` and
      `orchard.tscn` unconditionally — including the edges that carry a placed `Threshold` — proving
      the wall is no longer conditional on whether an edge is "linked."
- [ ] On each of the four linked edges, the placed `Threshold` sits inset from that edge's
      perimeter wall (per its 2px-deep, settled placement) so the player always meets the
      `Threshold` before the wall under normal approach.
- [ ] An edge with no placed `Threshold` (meadow north/west, orchard south/east) still stops the
      player at its perimeter wall and produces no transition — parity with today's "unlinked edge
      just walls" behavior, now expressed as "no `Threshold` there" rather than an empty
      `neighbour_*` slot.

### Deletion/rewrite verification
Not regression assertions — a one-time checklist for this slice's cleanup, to be confirmed during
implementation and code review rather than encoded as GUT tests that assert something was deleted.

- [ ] `tests/integration/world/test_edge_triggers.gd` deleted outright.
- [ ] `tests/unit/world/areas/shared/test_world_area_edge_transition.gd` deleted outright.
- [ ] `tests/integration/world/test_area_transition.gd` heavily rewritten into the real-content
      parity suite above (or retired in favor of a new file, if the parity coverage above fully
      replaces it).
- [ ] `tests/integration/world/test_collision_geometry_invariants.gd` trimmed: removed —
      `test_north_headroom_inset_keeps_the_whole_character_on_screen`,
      `test_north_headroom_inset_is_the_tightest_whole_tile_row`,
      `test_the_built_north_boundary_actually_uses_the_derived_inset`,
      `test_north_headroom_inset_responds_to_geometry_rather_than_being_fixed`,
      `test_corner_dead_zone_is_larger_than_the_player_collider`, and the `get_visual_extent()` half
      of `test_player_publishes_extents_matching_an_independent_measurement`.
- [ ] `test_player_collider_fits_through_a_one_tile_gap` and
      `test_the_thinnest_painted_collision_strip_still_stops_the_player` kept unchanged in that same
      file (genuine collider/terrain checks, not part of the deleted machinery).
- [ ] No remaining reference anywhere in `tests/` to: `neighbour_north/east/south/west`,
      `neighbour_for_edge()`, `edge_reached`, `opposite_edge()`, `compute_entry_position()`,
      `_playable_boundary()`, `_linked_edge_rects()`, `_add_edge_trigger()`/
      `_on_edge_trigger_body_entered()`, `north_headroom_inset()`, `is_debounce_armed()`/
      `begin_entry_debounce()`/`_debounce_*`, `CORNER_DEAD_ZONE_PX`/`ENTRY_OFFSET_EAST_WEST_PX`/
      `ENTRY_OFFSET_NORTH_SOUTH_PX`/`DEBOUNCE_EAST_WEST_PX`/`DEBOUNCE_NORTH_SOUTH_PX`,
      `Player.get_visual_extent()`, or `World._north_headroom_inset()`.
- [ ] Full test suite (unit + integration, every folder — not just `tests/**/world/`) runs clean
      after all deletions land, confirmed by reading the run's script/test counts (not just
      "passed") to catch a script GUT silently dropped for failing to parse.

### Unit
- [ ] `WorldArea.build_perimeter_walls()` takes no argument (drops the removed
      `headroom_inset_px` parameter) and contains no linked/unlinked branch.
- [ ] `WorldArea._edge_rect()` is symmetric across all four edges — no north-specific case remains.
- [ ] `WorldArea.get_bounds_px()` is unchanged and still correct (camera limits still depend on it).
- [ ] No further unit coverage for `world.gd`'s new private area-id helper — same reasoning as
      slice 3's plan: it's a private one-liner with no name to call by, and its output is already
      asserted indirectly via the real `area_changed` ids checked in Integration above.
