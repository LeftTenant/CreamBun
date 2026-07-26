# World Collision — Slice Breakdown

Source design: `docs/features/world-collision/design.md`. This breakdown follows the design
doc's own §14/§15 phasing as a starting point but re-sizes it: several of the doc's eight
phase-1 items bundle more than one independently-verifiable behavior, so they are split here into
11 smaller slices. Each slice below is self-sufficient — it repeats the file paths, the concrete
values, and the "why" a specialist agent needs, without requiring it to re-read the whole design
doc from scratch (though it should still skim the referenced §section for full rationale).

Phase 2 and Phase 3 items named in the design doc (§15) are **not** in this breakdown — they are
explicitly deferred and out of scope until a future feature pass.

---

## Slice 1 — Terminology correction (docs only)

**Goal:** Replace every "isometric" reference in `CLAUDE.md` and `README.md` with the correct
"top-down" / "three-quarter top-down" wording, per design doc §3.2. This is a pure documentation
edit — no game code changes.

**Files likely touched:**
- `CLAUDE.md` (line ~5: "cozy isometric RPG" → "cozy top-down RPG"; line ~89 heading "###
  Isometric depth sorting" → "### Depth sorting")
- `README.md` (line ~3: "A cozy isometric RPG about foraging" → "A cozy top-down RPG about
  foraging"; line ~41: replace the isometric-perspective sentence with the three-quarter
  top-down / Stardew Valley wording given verbatim in design §3.2)

**Out of scope:** Any code, scene, or resource change. Renaming classes/folders to avoid "iso"
naming (the design doc notes current identifiers already avoid it — nothing to rename).

**Test plan shape:** No GUT test — this is prose. Verification is a grep/read-through confirming
the four cited locations no longer say "isometric" and match the doc's exact replacement wording.

**Dependencies:** None. This is first because `CLAUDE.md` is read by every specialist agent in
every later slice's build loop — fixing the framing before slice 2 means later agents inherit the
correct mental model instead of an already-known-wrong one.

---

## Slice 2 — Tile geometry: 32×16 tiles and named physics layers

**Goal:** Move the world's tile size from 64×32 to 32×16 (design §4), rescale the two real
terrain textures to match, drop the throwaway placeholder tileset texture, and name the three
global 2D physics layers in `project.godot` (design §11) so every later slice can assign
`collision_layer`/`collision_mask` by name instead of a guessed bit number.

**Concrete values:**
- `world/world.tscn`: the `TileSet` resource's `tile_size` → `Vector2i(32, 16)`; each
  `TileSetAtlasSource`'s `texture_region_size` → `Vector2i(32, 16)`.
- `resources/sprites/terrain/grass.png` and `resources/sprites/terrain/flower grass.png`: resize
  from 64×32 to 32×16 (a plain pixel-art downscale — e.g. `sips -z 16 32` on macOS, or an
  equivalent nearest-neighbour resize; these are flat placeholder textures so no art care is
  needed).
- Remove `resources/tilesets/ground_placeholder.png` (and its `.import` file) and the
  `TileSetAtlasSource`/`ext_resource` in `world.tscn` that reference it — design §4.1 calls it a
  "throwaway placeholder; drop it."
- `project.godot`: add a `[layer_names]` section (currently absent — confirmed by grep):
  ```ini
  [layer_names]
  2d_physics/layer_1="world"
  2d_physics/layer_2="player"
  2d_physics/layer_3="interactable"
  ```

**Files likely touched:** `project.godot`, `world/world.tscn`,
`resources/sprites/terrain/grass.png`, `resources/sprites/terrain/flower grass.png`,
`resources/tilesets/ground_placeholder.png` (deleted), its `.import` file (deleted).

**Out of scope:** Actually assigning `collision_layer`/`collision_mask` on any node (that happens
in slices 3–6, once each node exists to configure) — this slice only *names* the layers.
Player collider/anchor changes (slice 3). TileSet physics-layer collision polygons (slice 4).

**Test plan shape:** Integration test loading `world/world.tscn` and asserting the `TileMapLayer`'s
`TileSet.tile_size == Vector2i(32, 16)`; an e2e screenshot at the 320×180 viewport showing roughly
10×11 tiles on screen (design §4 estimate) instead of ~5 tiles across. A small check (script or
manual `ProjectSettings.get_setting("layer_names/2d_physics/layer_1")`) confirming the three layer
names are readable.

**Dependencies:** Slice 1 (ordering only — no technical dependency, but keeps the doc-then-code
sequence clean).

---

## Slice 3 — Player ground anchor and collider fix

**Goal:** Fix the player's collider and sprite so the node origin sits at Cream Bun's feet, per
design §10. Currently `player.tscn` has a `CircleShape2D` (radius 16) centred on the origin, and
the `AnimatedSprite2D` is also centred on the origin — both wrong for depth sorting (§9) and for
correct ground-level collision once solids exist (slice 4 onward).

**Concrete values (`player/player.tscn`):**
- `CollisionShape2D`: shape → `RectangleShape2D` with `size = Vector2(20, 10)`, node `position =
  Vector2(0, 0)` (i.e. centred on the origin — the player is *not* anchored like a prop; see
  design §9's "known limitation, accepted" and §10's rationale for why centred-not-offset is
  correct here).
- `AnimatedSprite2D`: `offset = Vector2(0, -16)` (32×32 frames sit above the origin).
- Set `collision_layer` = `player` (bit 2) and `collision_mask` = `world` (bit 1) per design §11's
  layer table — this is the first node to consume the layer names slice 2 added.

**Files likely touched:** `player/player.tscn`,
`tests/integration/player/test_player_scene.gd` (extend the existing file with the new
assertions — it already tests this scene's `Camera2D` smoothing flag).

**Out of scope:** `player/player.gd` needs no logic changes (design §10 confirms
`move_and_slide()` already does the right thing once colliders exist). No new player states.

**Test plan shape:** Extend the existing integration test to assert the `CollisionShape2D.shape`
is a `RectangleShape2D` with `size == Vector2(20, 10)` at `position == Vector2(0, 0)`, the
`AnimatedSprite2D.offset == Vector2(0, -16)`, and `collision_layer`/`collision_mask` match the
named bits. No solids exist yet, so no runtime "player is blocked" test belongs here — that is
slice 4.

**Dependencies:** Slice 2 — needs the `player`/`world` layer names to exist before this slice can
assign them meaningfully, and reviewing this slice against the new 32×16 tile scale is what makes
"feet-anchored" visually checkable.

---

## Slice 4 — TileSet physics layer + Ground/Solids Y-sort structure

**Goal:** Prove design §5's core rule for painted terrain: add a physics layer to the world's
`TileSet`, draw a collision polygon on one test tile in the TileSet editor, and restructure
`world.tscn`'s tile layers into the §6.1 shape — a Y-sorted root with a non-Y-sorted `Ground`
layer and a Y-sorted `Solids` layer. This can still live directly in `world.tscn` for now; the
shell/area split is slice 8.

**Concrete values:**
- `world.tscn`'s root `Node2D` already has `y_sort_enabled = true` — confirm/keep it.
- Add a `Ground` `TileMapLayer` (`y_sort_enabled = false`) holding the existing painted grass/path
  tiles.
- Add a `Solids` `TileMapLayer` (`y_sort_enabled = true`) with at least one tile type given a
  collision polygon (full-tile rectangle) on the `TileSet`'s new physics layer, with that physics
  layer's `collision_layer` set to `world` (bit 1, from slice 2). Paint one or two solid tiles
  with it for testing.
- `TileData.y_sort_origin` set on any tile taller than one cell if used (design §6.1) — not
  required if the test tile is a plain 1-cell block.

**Files likely touched:** `world/world.tscn`.

**Out of scope:** Autotiling/terrain sets (design §6.2, explicitly Phase 2). `WorldProp` scenes
(slice 5). The `world/areas/` scene split (slice 8).

**Test plan shape:** Integration or e2e test: instantiate `world.tscn`, move the player toward a
painted solid tile, assert the player's position stops advancing into it (collision blocks
movement) while movement onto a `Ground`-only tile remains unblocked.

**Dependencies:** Slice 2 (32×16 tile size and the `world` layer name must exist before a physics
layer can be authored against them). Benefits from slice 3 being done first so the block is tested
against the corrected feet-anchored collider rather than the old centred circle, but is not
strictly blocked by it.

**Note — the two `Solids` test cells are scaffolding, not real terrain art.** The two painted
cells at `(11,11)`/`(12,11)`, and the new atlas alternative tile (`alternative_tile 1`) they use,
exist solely to prove the collision mechanism end-to-end; the alternative tile is a pixel-identical
copy of the flower-grass texture with no visual distinction from ordinary walkable ground. Expect
these to be replaced or supplemented with real solid-terrain art once slice 6 (the boulder prop) or
later level-design work gives the team a visual convention for "this tile blocks you." Because
`Solids` is Y-sorted, standing north of one of these test cells currently draws the player behind
a flat ground-level sprite with no cliff-like silhouette to justify it — this will read as a
depth-sorting bug rather than intended behavior until real art exists. That's expected for now.

---

## Slice 5 — `WorldProp` base class

**Goal:** Build the base class that makes every discrete prop's collider follow automatically
from a designer-set `footprint`, per design §7–§8. No concrete prop scene yet — that is slice 6.

**Concrete implementation** (design §8.2 gives the full script — use it verbatim, adjusting only
if project conventions require):
- New file `world/props/shared/world_prop.gd`:
  `@tool class_name WorldProp extends StaticBody2D`, with `const TILE_SIZE := Vector2i(32, 16)`,
  an `@export var footprint: Vector2i = Vector2i.ONE` setter that clamps to `>= 1` on each axis
  and calls `_rebuild_collider()`, an `@onready var _collision: CollisionShape2D =
  $CollisionShape2D`, and `_rebuild_collider()` building a `RectangleShape2D` sized
  `Vector2(footprint) * Vector2(TILE_SIZE)` and positioned so the collider spans `y ∈ [-depth, 0]`
  (origin is the footprint's *front* edge, not its centre).
- Set `collision_layer = world` (bit 1) on the base class or expect it set per-scene in slice 6.

**Files likely touched:** `world/props/shared/world_prop.gd` (new). A minimal test fixture scene
(e.g. `tests/unit/world/fixtures/test_world_prop.tscn` or similar GUT convention) with a bare
`CollisionShape2D` child so the class can be instantiated and exercised without a real prop scene.

**Out of scope:** Any concrete prop (`boulder.tscn`, `tree_oak.tscn` — slices 6–7). Sprite/visual
placeholder shapes (design §7.1) — those are authored per-prop, not on the base class.

**Test plan shape:** Unit test instantiating the base class (via the fixture scene) with a couple
of `footprint` values (e.g. `Vector2i(1,1)`, `Vector2i(2,3)`) and asserting the generated
`RectangleShape2D.size == Vector2(footprint) * Vector2(32, 16)` and the collider's `position.y ==
-shape.size.y / 2.0`. Also assert the setter clamps a `Vector2i(0, -1)` input to `Vector2i(1, 1)`.

**Dependencies:** Slice 2 — `TILE_SIZE = Vector2i(32, 16)` must be the settled value before this
class hard-codes it.

---

## Slice 6 — Boulder: first real prop, proven end-to-end

**Goal:** This is the slice design §15 calls out as where the whole design gets proven or falls
over: a real `WorldProp` instance placed in the world, with a placeholder shape, that correctly
blocks the player and Y-sorts against them from all four approach directions.

**Concrete values:**
- New scene `world/props/boulder.tscn`: root `StaticBody2D` using `world_prop.gd` as its script,
  `footprint = Vector2i(1, 1)`, a `CollisionShape2D` child (auto-populated by the base class), and
  a placeholder visual child — per design §7.1, a `Polygon2D` or `ColorRect` grey ellipse, anchored
  so it sits *above* the ground-anchor origin (never centred on it).
- `collision_layer = world` (bit 1).
- Place one `Boulder` instance as a direct child of `world.tscn`'s Y-sorted root (not nested under
  a `Props` node — design §6.1 explains why: Y-sort only interleaves *direct* children).

**Files likely touched:** `world/props/boulder.tscn` (new), `world/world.tscn` (add one boulder
instance for manual/e2e verification).

**Out of scope:** Multiple boulder placements, footprint sizes other than 1×1, real sprite art
(placeholder shape only, per design §7.1).

**Test plan shape:** e2e visual scenario — walk the player toward the boulder from north, south,
east, and west; screenshot each approach confirming (a) the player is blocked at the boulder's
footprint edge, not its visual silhouette, and (b) draw order is correct (player draws in front
when below the boulder's origin, behind when above it). A supporting integration test can assert
the boulder's collider blocks a simulated `move_and_slide()` step.

**Dependencies:** Slice 4 (the `Ground`/`Solids` Y-sorted structure must exist so the boulder has
a Y-sort scope to join) and slice 5 (`WorldProp` base class). Ordered before slice 7 so the
*simple* 1×1 case proves the mechanism cheaply before the harder canopy-overhang case is attempted
(design §15's own stated rationale).

---

## Slice 7 — Tree: footprint ≠ silhouette

**Goal:** Prove the design's central visual claim — a prop's collider is its ground footprint,
not its sprite silhouette (design §8.1's "consequences worth stating up front"). A placeholder
tree has a one-tile trunk footprint but a wide canopy the player can walk behind.

**Concrete values:**
- New scene `world/props/tree_oak.tscn`: same `WorldProp` pattern as the boulder,
  `footprint = Vector2i(1, 1)`, but the placeholder visual (design §7.1) is a brown `Polygon2D`
  trunk with a much wider green canopy `Polygon2D` above it — drawn with the real silhouette-vs-
  footprint shape (a box-shaped placeholder here would prove nothing, per design §7.1's explicit
  warning).
- Placed as a direct child of the world's Y-sorted root, same as the boulder.

**Files likely touched:** `world/props/tree_oak.tscn` (new), `world/world.tscn` (add one tree
instance).

**Out of scope:** Multiple tree variants, real sprite art.

**Test plan shape:** e2e visual scenario — walk the player behind the tree's canopy (where the
sprite visually overlaps the player) and confirm movement is *not* blocked there, then walk into
the trunk's 1×1 footprint tile and confirm it *is* blocked. This is the test that would catch a
collider mistakenly generated from sprite alpha (design §8.3) rather than footprint.

**Dependencies:** Slice 6 — reuses the exact same `WorldProp` mechanism proven there; this slice
only adds the harder canopy-overhang case on top of already-proven collider/sort correctness.

---

## Slice 8 — `WorldArea` extraction and the persistent shell

**Goal:** Split `world.tscn` into a persistent shell and a swappable `WorldArea` scene, per design
§12.1, with the player reparented into the active area on load so Y-sort keeps working. This slice
is purely structural — it should look and play identically to slice 7's end state, just
reorganized, with no camera or transition behavior yet (those are slices 9–10).

**Concrete values:**
- New `world/areas/shared/world_area.gd`: `@tool class_name WorldArea extends Node2D`, with
  `const TILE_SIZE := Vector2i(32, 16)`, the four `@export var neighbour_north/east/south/west:
  PackedScene` slots (declared now even though unused until slice 10 — see design §12.2), and
  `get_bounds_px() -> Rect2` reading `$Ground.get_used_rect()` and scaling by `TILE_SIZE`.
- New scene `world/areas/meadow.tscn`: root uses `world_area.gd`, `y_sort_enabled = true`, holding
  the `Ground`/`Solids` layers and the boulder/tree instances moved out of `world.tscn`.
- `world/world.tscn` becomes the shell: `World (Node2D)` with `ActiveArea (Node2D)`, `Player`
  (unchanged instance), `Notebook` (unchanged), and a new `Transition` `CanvasLayer` (process_mode
  = ALWAYS per `CLAUDE.md`'s pause-UI rule) — empty/unused until slice 10, but structurally present
  now.
- `world/world.gd`: on `_ready()`, instance `meadow.tscn` under `ActiveArea`, then
  `_player.reparent(area)` so the player joins the area's Y-sort scope (design §12.1's exact
  snippet).

**Files likely touched:** `world/areas/shared/world_area.gd` (new), `world/areas/meadow.tscn`
(new), `world/world.tscn` (restructured), `world/world.gd` (area-loading + reparent logic),
`tests/integration/world/test_world_scene.gd` (the existing spawn-position test hard-codes
`Vector2(288, 176)` as the Player's authored position and parent — this will very likely need
updating since the player's parent changes from `World` to the instanced `WorldArea`; flag this to
the test-engineer rather than silently deleting the coverage).

**Out of scope:** Camera dead-zone/edge-lock behavior (slice 9). Perimeter walls (slice 9). Edge
transitions to a second area (slice 10).

**Test plan shape:** Integration test asserting that after `World._ready()` runs, the `Player`
node's parent is the instanced `WorldArea` (not `World` itself), and that the boulder/tree from
slice 6–7 are still direct children of that same `WorldArea` (Y-sort scope confirmed shared). An
e2e re-run of slice 6/7's screenshots confirming Y-sort still looks correct after the restructure
is good regression insurance but not new coverage.

**Dependencies:** Slices 4, 6, 7 (there must be a `Ground`/`Solids` structure and props to move
into the new area scene). This is ordered before camera/transition work (slices 9–10) because
those need the shell/area split to exist first — the camera limits and perimeter walls are set
per-area from `world.gd`, which only makes sense once "area" is a real scene boundary.

---

## Slice 9 — Camera dead zone, edge lock, and perimeter walls

**Goal:** Give the meadow area a proper bounded camera and stop the player leaving it, per design
§12.3–§12.4. Runnable outcome (matching design §15 slice 6's stated target): the player roams the
bounded meadow, camera centred with two tiles of slack and locked at the edges, stopped by
invisible walls on every edge (none are linked to a neighbour yet — that's slice 10).

**Concrete values:**
- `player/player.tscn`'s `Camera2D`: `drag_horizontal_enabled = true`, `drag_vertical_enabled =
  true`, `drag_horizontal_margin ≈ 0.4` (2 tiles × 32px ÷ 160px half-viewport), `drag_vertical_margin
  ≈ 0.356` (2 tiles × 16px ÷ 90px half-viewport) — see design §12.3's derivation table.
  `position_smoothing_enabled = true` for the "soft cozy glide" (note: this *reverses* the
  existing `test_player_scene.gd` assertion that smoothing must be `false` — that test's own
  docstring is scoped to "Slice 4" of the *pixel-art-purist* feature, not this one; flag the
  conflict explicitly to the test-engineer and human reviewer rather than silently changing it).
- `world/world.gd`: after reparenting the player into the area, read `area.get_bounds_px()` and
  set `cam.limit_left/top/right/bottom` per design §12.3's snippet.
- `world/world.gd` or a helper on `WorldArea`: for each of the four edges, since no
  `neighbour_*` slot is filled yet, build a `StaticBody2D` (layer `world`) spanning that edge
  (design §12.4's "no neighbour → an invisible wall" case only, for now).

**Files likely touched:** `player/player.tscn`, `world/world.gd`,
`world/areas/shared/world_area.gd` (if the perimeter-wall helper lives there),
`tests/integration/player/test_player_scene.gd` (resolve the smoothing-flag conflict noted
above).

**Out of scope:** Open-edge triggers and the neighbour hand-off itself (slice 10). Slide/scroll
transitions (Phase 2).

**Test plan shape:** Integration test asserting the computed drag margins and that
`Camera2D.limit_*` match `meadow.get_bounds_px()` after load. e2e visual scenario: walk to each of
the four meadow edges and confirm (a) the camera does not reveal beyond the floor, and (b) the
player is stopped by the boundary wall rather than walking off-screen.

**Dependencies:** Slice 8 (needs the area/shell split so bounds and camera limits can be set
per-area on load).

---

## Slice 10 — Edge transition (fade) and a second area

**Goal:** Deliver the full requested end-to-end behavior (design §15 slice 7): link the meadow to
a second area via a `neighbour_*` slot, open that edge with a trigger instead of a wall, and fade
to the neighbour, spawning the player on the opposite edge at the preserved perpendicular offset.

**Concrete values:**
- `world/areas/shared/world_area.gd`: add `signal edge_reached(direction: Edge)` with an `Edge`
  enum (`NORTH/EAST/SOUTH/WEST`), and for each edge with a filled `neighbour_*` slot, build an
  `Area2D` (layer `interactable`, one tile deep, spanning that edge) instead of the slice 9 wall;
  emit `edge_reached` on player body entry.
- New minimal fixture scene `world/areas/<second_area>.tscn` (e.g. a small second `WorldArea` with
  its own `Ground` layer, no props needed) purely to prove the hand-off — full art/content for a
  "real" second area is not required by this slice.
- Wire `meadow.tscn`'s `neighbour_east` (or whichever edge is convenient) to the new area, and its
  reciprocal `neighbour_west` back to the meadow, so the transition is testable in both
  directions.
- `world/world.gd`: on `edge_reached(dir)` — set `GameState.current_state = LOADING` (reuses the
  existing state per design §12.5, no new state added); fade the new `Transition` `CanvasLayer`
  (from slice 8) to opaque via `Tween`; free the old area, instance the neighbour, reparent the
  player, rebuild the perimeter (slice 9's wall/trigger logic) and camera limits for the new area;
  place the player on the *opposite* edge at the same perpendicular coordinate (clamped to the new
  area's bounds, inset ~1 tile); fade back in; set `GameState.current_state = PLAYING`.
- `autoloads/game_events.gd`: add `signal area_changed(area_id: StringName)` (does not exist yet —
  confirmed by reading the file) and emit it after the swap completes, per design §12.5 step 5
  ("this one *is* cross-scene, so it goes on the bus").

**Files likely touched:** `world/areas/shared/world_area.gd`, `world/world.gd`,
`world/areas/<second_area>.tscn` (new), `world/areas/meadow.tscn` (neighbour slot wiring),
`autoloads/game_events.gd`.

**Out of scope:** Slide/scroll transitions (Phase 2 — fade only). Buildings/doorway triggers using
`shared/interactable.gd` (Phase 2, not yet written). More than the two areas needed to prove the
mechanism.

**Test plan shape:** Integration test on the opposite-edge spawn math (given an exit `y` and the
new area's bounds, the computed entry position matches design §12.5's table, clamped and inset
correctly). e2e visual scenario: walk off the meadow's linked edge, confirm the screen fades,
confirm the player appears at the opposite edge of the new area at the matching offset, confirm
the fade clears and `GameState` returns to `PLAYING`.

**Dependencies:** Slice 9 (perimeter-wall logic is what this slice replaces on open edges) and
slice 8 (the shell/area split and `Transition` `CanvasLayer` placeholder). This is intentionally
the largest slice in this breakdown — it is the smallest unit that is independently *and fully*
testable end-to-end for edge transitions (a half-built trigger-without-a-destination proves
nothing on its own). If it feels too large once underway, the natural internal split is "freeze/
fade mechanics" vs. "opposite-edge spawn math," but both are needed for any runnable test.

---

## Slice 11 — Designer reference documentation

**Goal:** Write `docs/reference/creating-world-areas.md` per design §14.1, documenting the
terrain/prop/area/area-linking workflows built in slices 1–10. This is a documentation-only slice,
deliberately last, mirroring the design doc's own final phase-1 item.

**Files likely touched:** `docs/reference/` (new subfolder), `docs/reference/creating-world-areas.md`
(new).

**Content checklist (from design §14.1), each item verified against the finished mechanism, not
against this design doc's proposal:**
- How to paint terrain and give a tile type collision via the TileSet physics layer (§6, built in
  slice 4).
- How to create a new `WorldProp`: duplicate a prop scene, set `footprint`, swap the placeholder
  shape for real art (§7–§8, built in slices 5–7).
- How to lay out a new `WorldArea` scene — the `Ground`/`Solids` layer structure and the
  ground-anchor/footprint rules that keep depth sorting correct (§6.1, §8, §9, built in slice 8).
- How to link two areas via the `neighbour_*` slots, and what an empty slot means (§12.2, §12.4,
  built in slices 9–10).
- Common mistakes worth flagging up front: sprites not offset from the ground anchor, footprint
  drawn to match silhouette instead of ground contact, areas smaller than one viewport (§12.3).

**Out of scope:** Any code change. Documenting Phase 2/3 features that don't exist yet.

**Test plan shape:** No GUT test. Verification is a read-through by someone (ideally without
prior context on this design doc) confirming they could follow the guide alone to paint a tile's
collision, place a prop, and link a new area — the same bar design §15 slice 8 sets.

**Dependencies:** All of slices 1–10 — this documents finished mechanisms, not a proposal, so it
must be written last.
