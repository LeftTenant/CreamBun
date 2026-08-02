# World Thresholds — Slice Breakdown

Source design: `docs/features/world-thresholds/design.md`. Scope is **Phase 1 only** (design §10:
"the mechanism, at parity") — every Phase 2 item (pits, multiple exits per edge, transition styles,
arrival facing, editor conveniences) is explicitly out of scope for every slice below.

**Why this breakdown looks the way it does.** The design replaces a derived, edge-shaped mechanism
with a placed one, and §9 gives an exhaustive deletion list against the *current* implementation
(`world_area.gd`'s `neighbour_*` exports, `edge_reached`, the corner/debounce/headroom machinery;
`world.gd`'s old sequence driver; `player.gd`'s `get_visual_extent()`). That old mechanism is fully
wired into the live `meadow.tscn` ↔ `orchard.tscn` link today, with ~46 passing tests asserting it.
The new `Threshold`/`Arrival` mechanism can be built, wired into `world.gd`, and fully tested
**without touching `WorldArea`, `meadow.tscn`, or `orchard.tscn` at all** — a `Threshold` is just an
`Area2D` a designer (or a test) drops into any area scene, independent of the perimeter-wall system.
That independence is what lets slices 1–3 below build the entire new mechanism additively, proven
against small test-only fixtures, while the old mechanism and its test suite stay untouched and
green throughout. Only slice 4 actually removes the old mechanism and migrates real content — see
that slice's note on why it cannot be split further without leaving the suite red partway through.

---

## Slice 1 — `player_bounds` layer and the player's `ThresholdBounds` collider

**Goal:** Give the player a second collider — `ThresholdBounds`, an `Area2D` sized to the union of
opaque pixels across every animation frame — used later (slice 3) for Threshold detection. This
slice only builds and proves the collider's geometry; nothing detects it yet, so it changes no
observable game behavior.

**Concrete values:**
- `project.godot`: add `2d_physics/layer_4="player_bounds"` under the existing `[layer_names]`
  section (currently ends at `layer_3="interactable"`).
- `player/player.tscn`: add `ThresholdBounds` as a new `Area2D` child of `Player` (sibling of the
  existing `CollisionShape2D`, `Camera2D`, `AnimatedSprite2D`), with:
  - `collision_layer = player_bounds` (bit 4, value 8), `collision_mask = 0` (design §6 — it is
    only ever detected, never detects anything itself).
  - A child `CollisionShape2D` with a `RectangleShape2D`, `size = Vector2(26, 27)`,
    `position = Vector2(0, -17.5)` — the authored union bbox from design §6
    (`x ∈ [-13, 13], y ∈ [-31, -4]`), not derived at runtime.

**Also in this slice — retire a now-false test of the *movement* collider (settled, not part of the
`ThresholdBounds` work above, but assigned here because this slice already measures the sprite's
opaque-pixel union).** `tests/integration/player/test_player_scene.gd`'s
`test_collider_width_matches_the_drawn_character_width()` is tautological — it asserts
`capsule.height (22) == SPRITE_FRAME_SIZE_PX - 2*SPRITE_TRANSPARENT_PADDING_PX` (i.e. `22 == 32 -
10`), two hand-maintained constants that never touch the art — and the claim it appears to make is
false regardless: the real opaque-pixel union is 26px wide, not 22px. Ruling: a designer should be
free to choose any movement-collider shape whether or not it matches the art's bounds — "what you
see is what collides" is not a rule this project holds for the movement capsule. Delete this test
and, if nothing else in the file references them, its now-unused `SPRITE_FRAME_SIZE_PX` /
`SPRITE_TRANSPARENT_PADDING_PX` constants. This does **not** touch design §6's requirement that
`ThresholdBounds` cover the art's union bbox (the invariant below) — that one guards a functional
guarantee (a transition fires before the sprite leaves the view), not a cosmetic correspondence
between the movement collider and the art.

**Files likely touched:** `project.godot`, `player/player.tscn`,
`tests/integration/world/test_collision_geometry_invariants.gd` (add the new invariant — see below;
this file's *existing* tests are untouched here, they retire in slice 4),
`tests/integration/player/test_player_scene.gd` (delete the tautological test and its two now-unused
constants, per the ruling above).

**Out of scope:** Anything that reads or reacts to `ThresholdBounds` — no `Threshold` node exists
yet (slice 2), and nothing connects to it (slice 3). Any other change to the existing
`CollisionShape2D` (movement capsule) or to `player.gd`.

**Test plan shape:** A new invariant test (design §9: "`test_collision_geometry_invariants.gd` ...
gains the `ThresholdBounds`-covers-the-art assertion from §6") that independently measures the
opaque-pixel union across every sprite frame (mirroring the file's existing
`_drawn_character_extent()` helper) and asserts `ThresholdBounds`'s `CollisionShape2D` rect fully
contains it — the same "read the art, don't mirror a constant" convention the rest of that file
already uses, so a future sprite redraw that grows the union fails this test loudly instead of
silently under-covering the art. A smaller unit-style check can assert the layer/mask bits and the
authored size/position directly. Plus the deletion above, verified by `test_player_scene.gd` still
passing with the tautological test and its dead constants gone.

**Dependencies:** None. This is first because it is the one piece of the new mechanism the design
calls out as needing its own proof independent of everything else (§2 recommendation 3: "its size is
authored, and a test proves it still covers the art").

---

## Slice 2 — The `Threshold` node

**Goal:** Build the placeable `Threshold` scene per design §4 — an `Area2D` with exactly the two
exports the design specifies, on the right physics layers, ready to be dropped into any area scene.
Not yet placed anywhere real, not yet wired to `world.gd`.

**Concrete values:**
- New `world/thresholds/threshold.gd`:
  ```gdscript
  class_name Threshold
  extends Area2D

  @export_file("*.tscn") var destination: String = ""
  @export var arrival: StringName = &""
  ```
  (design §4's exact snippet — a `String` path, not a `PackedScene`, for the same load-order
  reason `neighbour_*` used one, per §4's doc comment).
- New `world/thresholds/threshold.tscn`: root `Area2D` using `threshold.gd`, `collision_layer =
  interactable` (bit 3), `collision_mask = player_bounds` (bit 4, from slice 1), with a child
  `CollisionShape2D` (a `RectangleShape2D`, unsized/placeholder — a designer resizes it per
  placement, per §4: "an `Area2D` a designer drags into an area scene and sizes").

**Files likely touched:** `world/thresholds/threshold.gd` (new), `world/thresholds/threshold.tscn`
(new), `tests/unit/world/thresholds/test_threshold.gd` (new).

**Out of scope:** Any re-entry-guard/armed-state logic (design §5's "re-entry guard" paragraph) —
see slice 3's note on why that behavior is deferred there, where it can actually be exercised
against a live transition. Placing a `Threshold` in `meadow.tscn`/`orchard.tscn` (slice 4). Any
`Arrival` node or convention — a plain `Marker2D` needs no script and no dedicated slice; it is
introduced by name in slice 3's fixtures and used for real in slice 4.

**Test plan shape:** Unit test instantiating `threshold.tscn` standalone and asserting: `destination`
and `arrival` default to empty/`&""`; `collision_layer`/`collision_mask` match the `interactable`/
`player_bounds` bits; the root is an `Area2D`. No physics-frame simulation needed — this slice has
no runtime behavior to observe yet, only shape.

**Dependencies:** Slice 1 — `player_bounds` must be a named layer before `Threshold`'s
`collision_mask` can reference it meaningfully.

---

## Slice 3 — `world.gd` drives the sequence off a placed `Threshold`

**Goal:** The mechanism's actual behavior: crossing a placed `Threshold` runs the same freeze →
fade → swap → place → reveal sequence the old edge-derived system did, but lands the player on a
named `Arrival` instead of a computed offset, and fails safe (per design §5's validate-before-destroy
order) on a bad destination path or a missing/misnamed `Arrival`. Proven entirely against small
test-only fixture scenes — `meadow.tscn`/`orchard.tscn` are not touched in this slice, so the
existing edge-derived mechanism and its ~46 tests stay green throughout.

**How to prove this without touching real content:** instantiate `world.tscn` as usual (it still
loads the real `meadow.tscn` — untouched), then at test time inject a `Threshold` instance as a
runtime child of the already-instantiated meadow (`area.add_child(threshold_instance)`), pointing
`destination` at a small fixture `WorldArea` scene (living under
`tests/integration/world/thresholds/fixtures/`, sized ≥ 10×12 tiles per the existing minimum-area
rule so camera-limit assertions are meaningful) that contains a named `Arrival` `Marker2D` and,
where a test needs a reverse trip, its own `Threshold` back to another fixture (or back to meadow).
This never modifies `meadow.tscn`/`orchard.tscn` on disk.

**Concrete behavior (design §4–§5):**
- `world.gd`'s `_activate_area()` connects every `Threshold` under the newly-activated area's
  `area_entered` signal (plural — not the single `edge_reached` connection it replaces) to a new
  handler, alongside (not instead of, until slice 4) the still-live `edge_reached` connection.
- On that handler firing for the player's `ThresholdBounds`: freeze (`GameState.current_state =
  LOADING`, same guard against a residual second firing as the old `_on_edge_reached()`), fade to
  opaque, then **resolve-before-destroy** (§5's numbered order): `load(destination)` and
  `instantiate()`; find the named `Arrival` `Marker2D` in the new instance; only if both succeed,
  reparent the player out and free the old area, activate the new one, place the player at the
  `Arrival`'s position, fade back in, restore `PLAYING`, emit `GameEvents.area_changed` with the new
  area's id (computed by a private helper in `world.gd` — see slice 4's "`area_id` — settled" note).
- **Failure path:** a bad `destination` path or a missing/misnamed `Arrival` leaves the player
  exactly where they were, pushes an error, and returns to `PLAYING` with nothing having moved or
  been freed — mirroring the old `_load_neighbour_area()`'s "validate before destroying anything"
  lesson (design §5: "must never strand them behind an opaque fade in an empty world — that bug was
  hit for real").
- **Re-entry guard — settled (design §5, wording corrected to remove the §4/§5 tension flagged in an
  earlier pass of this breakdown):** do not trigger a `Threshold` the player spawned into. A
  `Threshold` the player's `ThresholdBounds` was already overlapping at the moment they arrived stays
  inert until `ThresholdBounds` has fully left it, at which point it arms (normal case: this is a
  no-op, since a well-placed `Arrival` doesn't overlap a `Threshold` at all). **The guard lives in
  `world.gd`, not in `threshold.gd`** — a per-`Threshold` "ignore until they leave" flag, set by
  checking overlap right after placing the player at each newly-activated area's `Threshold`s and
  cleared on that `Threshold`'s `area_exited`. This keeps slice 2's "the two exports are the whole
  node" true — `Threshold` stays a bare `Area2D` with no internal armed-state or public query
  surface.

**Files likely touched:** `world/world.gd`, `tests/integration/world/thresholds/test_threshold_transition.gd`
(new), `tests/integration/world/thresholds/fixtures/` (new fixture `WorldArea` scenes with placed
`Threshold`/`Arrival` nodes).

**Out of scope:** Deleting or modifying anything about the old `edge_reached`-driven path — it keeps
running in parallel this slice, untouched. Placing a `Threshold` in real content. `WorldArea`
changes of any kind (its unconditional-wall collapse is slice 4, and must not happen before then —
see that slice's note on why).

**Test plan shape:** Integration tests against the fixtures above: happy-path sequence (`GameState`
LOADING→PLAYING timing, fade overlay opacity, old area freed, new area instanced and player
reparented into it, camera limits reset to the new area's bounds, player lands exactly at the named
`Arrival`'s position, `GameEvents.area_changed` emitted once with the right id, after the swap/
reparent/camera work is already done); failure-path recovery (bad `destination` path leaves
`GameState` at `PLAYING` and the player unmoved with an error pushed; a fixture whose `Threshold`
names a non-existent `Arrival` behaves the same way); the re-entry guard (an `Arrival` placed
overlapping a `Threshold` in a fixture does not immediately re-fire; walking away and back does).

**Dependencies:** Slices 1–2 (`ThresholdBounds` and `Threshold` must both exist). This is the
largest of the additive slices — if it proves too large for one session, the natural internal split
is "happy-path sequence" vs. "failure-path recovery + re-entry guard," both still provable against
the same fixtures without any dependency ordering issue between them.

---

## Slice 4 — Switchover: collapse `WorldArea`, remove the old path, migrate real content

**Goal:** The atomic "flip the switch" slice (design §10's own phase-1 end state: "the existing
two-way meadow ↔ orchard link works exactly as it does today, via placed Thresholds and Arrivals").
Delete the entire edge-derived mechanism (design §9's table), migrate `meadow.tscn` and
`orchard.tscn` from `neighbour_*` slots to placed `Threshold`/`Arrival` pairs reproducing today's
four links (meadow east → orchard, meadow south → orchard, orchard north → meadow, orchard west →
meadow), and retire/rewrite every test that referenced the deleted machinery.

**Why this cannot be split further and stay green throughout:** `WorldArea.build_perimeter_walls()`
collapsing to "every edge always gets a wall" (design §7) is what makes an edge's old
`neighbour_*`-driven trigger stop existing — the moment that lands, `meadow.tscn`/`orchard.tscn`
produce *no* transition at all until their new `Threshold`/`Arrival` nodes are placed in the same
commit. There is no safe intermediate state where both halves of this slice are done but not the
other, unlike slices 1–3.

**Concrete deletions (design §9's table, applied to `world_area.gd` unless noted):**
`neighbour_north/east/south/west`, `neighbour_for_edge()`, `edge_reached` signal, `opposite_edge()`,
`compute_entry_position()`, `_playable_boundary()`, `_linked_edge_rects()`, `_add_edge_trigger()`/
`_on_edge_trigger_body_entered()`, `_build_edge()`'s linked/unlinked branch, `north_headroom_inset()`,
`is_debounce_armed()`/`begin_entry_debounce()`/`_physics_process()`/`_debounce_*`,
`CORNER_DEAD_ZONE_PX`/`ENTRY_OFFSET_EAST_WEST_PX`/`ENTRY_OFFSET_NORTH_SOUTH_PX`/
`DEBOUNCE_EAST_WEST_PX`/`DEBOUNCE_NORTH_SOUTH_PX`; `player.gd`'s `get_visual_extent()`; `world.gd`'s
`_north_headroom_inset()` and the entire old `_on_edge_reached()`/`_load_neighbour_area()` path
(superseded by slice 3's handler, which stays). `build_perimeter_walls()` drops its
`headroom_inset_px` argument and its per-edge branch — design §7's collapsed API is `TILE_SIZE`,
`WORLD_LAYER_BIT`, `PERIMETER_WALL_THICKNESS_PX`, `get_bounds_px()`, `build_perimeter_walls()`,
`_edge_rect()`, `_add_perimeter_wall()`.

**`area_id` — settled:** the collapsed `WorldArea` API (§7) has no `area_id_from_scene_path()`-
equivalent. `world.gd` computes the `StringName` `GameEvents.area_changed` expects from
`Threshold.destination` as a private one-line helper directly in `world.gd` — no static is
resurrected on `WorldArea` for it.

**Content migration:** `meadow.tscn` gains a `ThresholdToOrchard` (east) and a second Threshold on
its south edge, each `destination = "res://world/areas/orchard.tscn"`, pointing at named `Arrival`s
placed in `orchard.tscn`; `orchard.tscn` gains the reciprocal pair back to `meadow.tscn`. Treat
"reproduces today's crossing points and landing spots" as the acceptance bar, not bit-for-bit matches
of the old computed coordinates. The north-edge headroom clipping design §8 accepts is expected on
any edge that isn't covered by a `Threshold` or painted terrain.

**Threshold depth — settled:** the `Threshold`s that replace the existing map-edge boundaries are
**2px deep**, so the player is very close to the true map edge before one triggers. This is not a
tunnelling risk: the detector is the 26×27px `ThresholdBounds` box (slice 1), not a point, so the box
overlaps a 2px-deep region across roughly 29px of approach travel — about 9 physics ticks at the
player's 200px/s. Leave it at 2px; do not "fix" a perceived tunnelling risk by thickening the region.

**Files likely touched:** `world/areas/shared/world_area.gd`, `world/world.gd`, `player/player.gd`,
`world/areas/meadow.tscn`, `world/areas/orchard.tscn`; delete
`tests/integration/world/test_edge_triggers.gd` and
`tests/unit/world/areas/shared/test_world_area_edge_transition.gd` outright (both are entirely about
the deleted machinery); heavily rewrite `tests/integration/world/test_area_transition.gd` into a
parity suite driven by the real `meadow`/`orchard` `Threshold`s (or retire it in favor of a new file,
if slice 3's fixture-based suite already covers the generic sequence and this only needs to prove
meadow ↔ orchard specifically); trim `tests/integration/world/test_collision_geometry_invariants.gd`
— remove `test_north_headroom_inset_keeps_the_whole_character_on_screen`,
`test_north_headroom_inset_is_the_tightest_whole_tile_row`,
`test_the_built_north_boundary_actually_uses_the_derived_inset`,
`test_north_headroom_inset_responds_to_geometry_rather_than_being_fixed` (all reference deleted
`WorldArea.north_headroom_inset()`), `test_corner_dead_zone_is_larger_than_the_player_collider`
(references deleted `WorldArea.CORNER_DEAD_ZONE_PX`), and the `get_visual_extent()` half of
`test_player_publishes_extents_matching_an_independent_measurement`; keep
`test_player_collider_fits_through_a_one_tile_gap` and
`test_the_thinnest_painted_collision_strip_still_stops_the_player` unchanged (genuine collider-shape
and terrain checks, per design §9).

**Out of scope:** Any Phase 2 item (§10). Rewriting `docs/reference/creating-world-areas.md` (slice
5 — doc-only, no code/test coupling, safe to do after this slice lands).

**Test plan shape:** The rewritten/new integration suite must prove parity: walking off meadow's
east and south edges reaches orchard at the right spot; walking off orchard's north and west edges
reaches meadow; the reverse trips work; `GameEvents.area_changed` fires with the right id each time;
camera limits reset correctly. A quick full-suite run (not just this feature's files) is worth doing
at the end of this slice specifically, since a stale reference to a deleted `WorldArea` static member
or the `Edge` enum anywhere else in the test tree would be a parse-time failure for the whole suite,
not just one file.

**Dependencies:** Slices 1–3 (the new mechanism must already work, proven against fixtures, before
the old one is safe to delete).

---

## Slice 5 — Designer reference doc: linking areas with placed Thresholds

**Goal:** Rewrite `docs/reference/creating-world-areas.md` §4 ("Linking two areas with the
`neighbour_*` slots") to describe placing `Threshold`/`Arrival` pairs instead, and refresh the Quick
Reference table (drops the north-headroom-inset and corner-dead-zone rows, adds the `player_bounds`
layer and `ThresholdBounds` size). Pure documentation, no code or test changes — mirrors the original
world-collision feature's own final slice (a dedicated reference-doc pass, done last).

**Concrete changes to `docs/reference/creating-world-areas.md`:**
- §4 rewritten: how to place a `Threshold` (drag `threshold.tscn` into an area root, size it, set
  `destination`/`arrival`), how to place a named `Arrival` `Marker2D` in the destination area, and
  the "both directions need their own placed pair" note (replacing "each slot is one-directional").
- §2's "north edge always eats a couple of rows" paragraph updated per design §8: the inset is gone;
  designers now choose per area whether to paint terrain, place a `Threshold`, or accept the clip.
- §5 "Common mistakes" — replace "setting only one side of a `neighbour_*` link" with the placed-pair
  equivalent.
- Quick Reference table — remove the "North-edge headroom inset" and "Corner dead zone" rows; add
  `player_bounds` to the physics-layers row; add a `ThresholdBounds` row (26×27 px at (0, -17.5)).

**Files likely touched:** `docs/reference/creating-world-areas.md`.

**Out of scope:** Any code change. Documenting Phase 2 features that don't exist yet (pits, multiple
exits, transition styles).

**Test plan shape:** No GUT test — prose. Verification is a read-through confirming every reference
to `neighbour_*`, the north headroom inset, and the corner dead zone is gone or correctly
recontextualized, and that the guide is sufficient on its own to link two areas using the finished
mechanism.

**Dependencies:** Slice 4 — this documents the finished, real-content mechanism, so it must be
written after that mechanism exists.
