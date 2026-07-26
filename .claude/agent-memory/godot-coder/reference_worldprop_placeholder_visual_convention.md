---
name: worldprop-placeholder-visual-convention
description: how concrete WorldProp scenes (boulder.tscn and future tree/cottage scenes) structure their placeholder visual child per design doc §7.1
type: reference
---

`world/props/boulder.tscn` (world-collision feature, Slice 6) is the first concrete `WorldProp`
(base class: `world/props/shared/world_prop.gd`) and sets the pattern later props (e.g.
`tree_oak.tscn`, Slice 7) should follow:

- Root node: `type="StaticBody2D"` with `script = ExtResource(...)` pointing at `world_prop.gd` —
  same as the base class's own test fixture
  (`tests/unit/world/props/shared/fixtures/test_world_prop.tscn`). Don't set the node `type` to
  the class name itself; instance as the base engine type + script, matching every other scene in
  the project.
- One or more placeholder visuals (`Polygon2D` or `ColorRect`, any name other than
  `CollisionShape2D`) plus a bare `CollisionShape2D` named exactly `CollisionShape2D` (no shape
  resource needed in the file — `world_prop.gd`'s `_rebuild_collider()` populates it in `_ready()`
  from `footprint`). boulder.tscn has one visual (`Silhouette`); tree_oak.tscn (Slice 7) has two
  (`Trunk` + `Canopy`), since a tree needs to visually distinguish the footprint-sized trunk from
  the wider, taller canopy that must NOT collide.
- The rule that actually matters is on the **bounding box**, not the node's `position` property:
  each visual's bounding box must sit above the ground anchor (design §8.1's origin), never
  centred on or hanging below it (design §7.1). There are two equally valid ways to achieve this:
  (a) author the polygon's own points directly in anchor-local space (so they already span
  negative/zero y) and leave `position` at the default `(0, 0)` — tree_oak.tscn's `Trunk` does
  this, with points spanning `y ∈ [-16, 0]`; or (b) author the polygon centred on its own local
  origin and offset it upward via a strictly-negative `position.y` — boulder.tscn's `Silhouette`
  and tree_oak.tscn's `Canopy` (`position = Vector2(0, -30)`) do this. Don't assume a visual with
  `position.y == 0` is wrong — check where its actual bounding box lands before flagging it.
- The visual's silhouette must be authored **wider/taller than the footprint's generated collider**
  on purpose — for a 1×1 footprint the collider spans local `y ∈ [-16, 0]`, `x ∈ [-16, 16]`
  (`TILE_SIZE = Vector2i(32, 16)`). Tests for these scenes deliberately probe for a "silhouette
  overlap but footprint clear" gap (walking through the visual but not being blocked) — a
  placeholder that's just a footprint-sized box proves nothing (design §7.1's second honesty
  rule). boulder.tscn uses a 16-point ellipse `Polygon2D` (semi-axes 22×16) offset to
  `position = Vector2(0, -16)`, giving a bounding box of `y ∈ [-32, 0]`, `x ∈ [-22, 22]` — its
  base touches the ground anchor (y=0) exactly, while still extending 16px north of the
  footprint's near edge for the north-approach silhouette-vs-footprint gap.
  **Gotcha:** get the silhouette's south (base) edge to land exactly on the anchor (y=0) unless
  the design explicitly wants a gap there — a silhouette floating even a few px above y=0 (e.g. an
  ellipse whose local bottom is above 0 after its `position.y` offset) reads as "hovering" and
  fails any "little to no vertical gap on the near-approach side" checkpoint. Check by computing
  `position.y + (the shape's own local max-y)`; it should equal 0 for a flush base, or be
  negative only by the intended gap amount.
- Props go in as **direct children of the world/area root**, never nested under an intermediate
  "Props" node — Y-sort (design §6.1/§9) only interleaves a node's direct children, so nesting
  silently breaks per-object depth sorting.

See also [[gut-simulate-needs-scripted-physics-process]] for how these scenes' integration tests
drive a probe body against the generated collider.
