# Creating World Areas — A Designer's Guide

This is a how-to guide for building CreamBun's world by hand in the Godot editor: painting
terrain, placing props, laying out a new area, and linking areas together. It assumes no prior
reading of the design doc — if you want the *why* behind any rule here, the full rationale lives
in `docs/features/world-collision/design.md` (referenced by section below), but everything you
need to actually do the work is on this page.

**The one rule everything below serves:** collision is authored once, on the thing itself — a
tile in the TileSet, or a prop's `.tscn` — never drawn separately onto the map. If you ever find
yourself thinking "now I need to go mark this area as blocked," stop: that's not how this system
works, and the answer is almost always "give the *thing* a collider instead."

---

## 1. Painting terrain and making a tile type solid

Terrain (grass, paths, cliffs, water) is painted with a `TileMapLayer`. Whether a tile blocks the
player is a property of that tile in the **TileSet**, not of where you paint it — draw the
collision once *for that area's TileSet* (see the scoping note below), and every future placement
of that tile within the same area is solid automatically.

**To give a tile type collision:**

1. Open the area scene (e.g. `world/areas/meadow.tscn`) and select its `Ground` or `Solids`
   `TileMapLayer` node.
2. Open the **TileSet** bottom panel. Click the TileSet resource in the Inspector to edit it.
3. If the TileSet doesn't have a physics layer yet, add one: in the TileSet inspector, find
   **Physics Layers**, add an entry, and tick the **world** checkbox under Collision Layer (the
   named checkboxes — `world` / `player` / `interactable` — come from `project.godot`'s
   `[layer_names]` section, already set up project-wide; you don't need to touch raw layer
   numbers). Leave Collision Mask empty — terrain doesn't need to detect anything, only to be
   detected.
4. Switch to the **Tiles** tab, select the atlas tile (or **alternative tile**, if you're reusing
   one texture with a solid and non-solid variant — see the note below), then open its **Physics
   Layer 0** section and use the polygon tool to draw the collision shape. For a plain solid tile,
   draw a rectangle covering the full 32×16 cell (corners at roughly `(-16,-8)` to `(16,-8)` to
   `(16,8)` to `(-16,8)` — that's exactly what the project's one real solid-terrain tile currently
   uses).
5. Paint the tile anywhere with that `TileMapLayer` — it's solid everywhere it's painted, forever,
   with nothing further to do.

**Important — collision belongs to the tile, not the layer.** `Ground` and `Solids` *within one
area scene* share one `TileSet` resource, and physics is a property of a tile *in that resource*.
If you accidentally paint a collidable tile onto `Ground`, it will still block movement there —
the layer names (`Ground`/`Solids`) are an organizational convention for Y-sorting (§2 below), not
a collision boundary. Keep solid tiles visually distinct from walkable ones so nobody paints one by
accident.

**The TileSet is embedded per area scene, not shared project-wide.** There's no standalone
`.tres` TileSet file — each area scene (`meadow.tscn`, `orchard.tscn`, …) has its own embedded
copy. This is exactly why §2 tells you to duplicate an existing area rather than build a new one
from scratch: duplicating `meadow.tscn` is how a new area inherits a TileSet that already has the
`world` physics layer and the solid tile's collision polygon set up. A brand-new, from-scratch
`WorldArea` scene starts with no physics-configured TileSet at all — you'd have to do step 3 from
nothing. The flip side: once you've duplicated, edits to one area's TileSet (adding a new solid
tile type, say) do **not** propagate to any other area's copy — you'd need to repeat the edit in
each area scene that should also have it.

**Note on "alternative tiles":** the project's current solid test tile is an *alternative tile* on
the same atlas source as the walkable flower-grass texture (alternative id 1) — a pixel-identical
duplicate texture that only differs by having a collision polygon attached. This was built purely
to prove the mechanism works; it looks identical to ordinary ground. Once real cliff/water art
exists, a solid tile type would normally get its own distinct texture instead of being an
alternate of a walkable one — but the collision-authoring step is identical either way: draw the
polygon once on that atlas tile (or alternative), in the TileSet editor's Physics Layer section.

Design rationale: `docs/features/world-collision/design.md` §6.

---

## 2. Laying out a new `WorldArea` scene

Each place in the world (a meadow, an orchard, a market) is its own scene whose root uses
`world_area.gd`. The easiest way to start a new one is to duplicate an existing area
(`world/areas/meadow.tscn` is the fullest example) via the FileSystem dock (right-click → Duplicate)
and strip out what you don't need, rather than building the node structure from scratch.

**The required structure:**

```
YourArea (Node2D, y_sort_enabled = true, script = world_area.gd)
├── Ground   (TileMapLayer, y_sort_enabled = false)   — required, must be named exactly "Ground"
├── Solids   (TileMapLayer, y_sort_enabled = true)     — optional; only add if you have solid painted terrain
└── (prop instances — Boulder, TreeOak, etc.)          — direct children of the root
```

- **The root's `y_sort_enabled` must be `true`.** This is the area's whole Y-sort scope — when the
  player enters, they're reparented into this exact node so they can sort against everything else
  in it (§9 in the design doc).
- **`Ground` must be named exactly `Ground`.** The area's bounds are read from
  `$Ground.get_used_rect()` (`get_bounds_px()` in `world_area.gd`) — a differently-named or
  missing node breaks bounds, camera limits, and perimeter walls all at once.
- **`Solids` is optional.** `orchard.tscn` (the project's minimal second area) has no `Solids`
  layer at all — add one only once you have painted terrain that needs to block the player.
  `Solids` needs `y_sort_enabled = true` because a cliff face is something the player can walk in
  front of or behind; `Ground` stays unsorted because it's flat floor with nothing to sort against.
- **Props go directly under the area root — never nested inside a sub-node** like a "Props"
  folder. Y-sort only interleaves a node's *direct* children; a nested group would sort as one
  block against the player instead of prop-by-prop.

**Ground-anchor rule (why props and the player sort correctly against terrain):** every solid
thing's node origin sits *on the ground*, and its sprite is offset upward from there — never
centred on the origin. This is what makes Y-sort (which keys off `global_position.y`) produce the
right draw order. See §3 for how this plays out on a prop specifically, and §5 for what happens
if you get it backwards.

**Minimum size — at least one full viewport.** An area's painted `Ground` must be at least
320×180px on both axes — at least **10 tiles wide by 12 tall** (11 rows is 176px — 4px short of a
viewport). Smaller than that on either axis, and Godot can't simultaneously keep the player
on-screen and honour the camera's edge limits; it just centres the small area and the two-tile
dead zone stops meaning anything. This is a constraint on how you paint the floor, not something
the code works around.

**Paint `Ground` as a filled rectangle, not a ragged or L-shaped outline.** Bounds, camera limits,
and the perimeter are all computed from `get_used_rect()` — the bounding box of every painted
cell, not the actual painted silhouette. If you paint an L-shape (or leave gaps), the area's
"bounds" still cover the full rectangle that encloses it, and the perimeter wall/trigger goes
around *that* rectangle — leaving the parts of it you didn't paint as unwalled void a player can
wander into. Keep `Ground` a solid rectangle so the computed bounds match what you actually see.

**The north edge always eats a couple of rows.** The topmost ~2 tile rows of whatever `Ground` you
paint are a **visual-only backdrop** — they render, but the player can never actually stand there.
A built-in 32px inset (`NORTH_WALL_HEADROOM_INSET_PX` in `world_area.gd`) keeps the north wall (or
trigger) that far south of the true painted edge, so the camera always has a full sprite-height of
headroom above the player's feet even when they're stopped at the boundary. Paint that strip as
normal ground for visual continuity — just don't expect the player to walk into it. (South,
east, and west don't have this problem and sit flush with the true edge.)

**Nothing else needs manual wiring.** The camera's two-tile dead zone and edge-lock limits, and
the perimeter walls/triggers, are all built automatically from `Ground`'s painted extent the first
time `world.gd` activates the area — there's no per-area camera setup to do.

Design rationale: `docs/features/world-collision/design.md` §6.1, §8, §9, §12.1, §12.3.

---

## 3. Creating a new `WorldProp` (trees, boulders, buildings)

Every discrete object the player can bump into — a boulder, a tree, eventually a building — is a
small scene built on the shared `world_prop.gd` base class. You never hand-draw its collider.

**Steps:**

1. In the FileSystem dock, duplicate an existing prop scene close to what you want —
   `world/props/boulder.tscn` for a simple one-tile object, `world/props/tree_oak.tscn` if your
   new prop needs a footprint noticeably smaller than its visual silhouette (see below). Rename
   the copy (e.g. `rock_large.tscn`) and open it.
2. Select the root node and set **Footprint** in the Inspector — a `Vector2i` in tile units. A
   boulder is `(1, 1)`; a cottage might be `(4, 3)`. This is the patch of *ground* the prop
   occupies, not the size of its sprite (more on this below). Because the base script is `@tool`,
   the `CollisionShape2D` rebuilds live as you type — you'll see the solid rectangle update in the
   2D viewport immediately.
3. Replace the placeholder `Polygon2D` (or add a `Sprite2D`) with real art once it exists. **The
   one rule that matters here: the visual's *pixels* must sit above the origin, never straddle or
   centre on it.** The origin `(0, 0)` is the ground anchor — the front-centre of the footprint,
   the point nearest the camera — and depth sorting keys directly off it. You can achieve "pixels
   above the origin" two ways, and this project uses both: offset the *node* upward (`boulder.tscn`'s
   `Silhouette` sits at `position = (0, -16)`; `tree_oak.tscn`'s `Canopy` at `(0, -30)`), or draw the
   *shape itself* entirely above y=0 while leaving the node at `(0, 0)` (`tree_oak.tscn`'s `Trunk`
   `Polygon2D` does this — its node position is `(0, 0)`, but every point in the polygon has
   `y ∈ [-16, 0]`). What's actually forbidden is art whose pixels straddle or sit below the origin —
   if your visual reads as centred on `(0, 0)`, the prop will look like it's floating and will sort
   incorrectly against the player.
4. Leave `collision_layer` / `collision_mask` alone. `world_prop.gd` sets these automatically at
   runtime (`world` layer, no mask) — you don't need to (and shouldn't) touch them by hand on the
   prop scene.
5. Drag the finished `.tscn` into an area scene, as a **direct child of the area root** (§2 —
   never nested under a sub-node), and position it. That's the whole workflow — the collider
   travels with the prop wherever you move it.

**Footprint ≠ silhouette — this is deliberate, not a bug to fix.** An oak tree's footprint is
`(1, 1)`: its trunk base. The canopy is drawn far wider, and the player walks *behind* it —
`tree_oak.tscn` is the reference example of this on purpose. Front-facing art on a top-down grid
means tall things sit on small patches of ground; the collider is always the ground contact patch,
never a box that matches the sprite's outline. See the mistake to avoid in §5.

Design rationale: `docs/features/world-collision/design.md` §7, §8.

---

## 4. Linking two areas with the `neighbour_*` slots

**A new area isn't reachable in-game until something links to it.** Finishing §2 gets you a
complete area scene, but the game always starts in `meadow.tscn` (`STARTING_AREA_SCENE` in
`world/world.gd`) and has no other way to discover an area scene sitting unused on disk. The last
step of building a new area is always this section: point an existing, reachable area's
`neighbour_*` slot at it.

Each `WorldArea` root has four Inspector slots — **Neighbour North / East / South / West** — that
pick another area's `.tscn` file. A filled slot is a doorway; an empty slot (the default) is a
solid wall.

**To link area A's east edge to area B:**

1. Open area A, select its root node, and set **Neighbour East** to area B's scene file (the
   Inspector gives you a file-picker button — you don't type the path by hand).
2. **Also open area B and set its Neighbour West back to area A.** This is the step that's easy to
   forget: each slot is one-directional. If you only fill in A's side, walking from A into B works
   fine, but walking back toward that same edge in B just hits an ordinary wall — which reads as a
   bug, not a design choice, unless you intended a one-way passage.
3. That's it. The first time either area loads, the game builds a trigger (instead of a wall) on
   that edge automatically, and walking into it fades the screen, swaps the active area, and
   spawns the player just inside the opposite edge of the new area, at the same perpendicular
   position they exited at. None of this needs further wiring once the two slots are set.

**A few things to know about how the linked edge behaves**, none of which need action from you,
but which explain what you'll see when testing a new link:

- **Corners never trigger a transition.** A 32×32px square at each end of a linked edge stays
  ordinary walkable ground that simply can't start a transition — this exists so the game is never
  ambiguous about which of two edges meeting at a corner you meant to cross. You can stand there;
  you just won't be teleported from there.
- **The north edge's own headroom inset (§2) applies here too.** A north-south link still carries
  the same ~2-row non-walkable backdrop strip on its north side; a north neighbour doesn't remove
  it.
- **Reusing one area on two different edges is fine.** `orchard.tscn` links back to `meadow.tscn`
  on both its north and west edges — a single second area can stand in for multiple neighbours
  while you're prototyping, with no special handling needed.

Design rationale: `docs/features/world-collision/design.md` §12.2, §12.4, §12.5.

---

## 5. Common mistakes to avoid

- **Visual not offset from the ground anchor.** If a prop's sprite (or a placeholder shape) reads
  as centred on `(0, 0)` instead of sitting above it, it will look like it's floating above its own
  footprint and will sort incorrectly against the player and other props. Every real example in the
  project keeps its visual's pixels above the origin — `boulder.tscn` and `tree_oak.tscn`'s canopy
  do it by offsetting the node; `tree_oak.tscn`'s trunk does it by drawing the polygon itself above
  y=0 instead — see §3 for both approaches.
- **Footprint drawn to match the sprite's silhouette instead of its ground contact.** A wide tree
  canopy is not a wide footprint — only the trunk base is solid. Setting `footprint` to match a
  sprite's visual bounding box (instead of where it actually touches the ground) will block more
  of the map than it should, or won't match what the player visually expects to be able to walk
  through.
- **Areas smaller than one viewport (320×180px, 10×12 tiles).** Below that on either axis, the
  camera's two-tile dead zone and edge-lock behavior stop working as designed — Godot just centres
  the undersized area instead.
- **Props nested under a sub-node** (e.g. a "Props" grouping node) instead of being direct
  children of the area root. This silently breaks per-object Y-sort — the whole group sorts as one
  block against the player rather than prop-by-prop.
- **Painting a solid tile onto `Ground`.** Collision lives on the tile in the TileSet, not on
  whichever layer you happened to paint it on (§1) — a collidable tile blocks movement wherever
  it's painted, `Ground` included.
- **Setting only one side of a `neighbour_*` link.** Each slot is one-directional; a real two-way
  doorway needs the reverse slot filled in on the other area too (§4).

---

## Quick reference

| Constant | Value | Where |
| --- | --- | --- |
| Tile size | 32×16 px | `world_area.gd`, `world_prop.gd` — `TILE_SIZE` |
| Minimum area size | 320×180 px (10 wide × 12 tall tiles) | one full viewport |
| North-edge headroom inset | 32 px (one sprite height) | `NORTH_WALL_HEADROOM_INSET_PX` |
| Corner dead zone (linked edges) | 32×32 px | `CORNER_DEAD_ZONE_PX` |
| Physics layers | `world` (terrain + props), `player`, `interactable` (edge triggers) | `project.godot` `[layer_names]` |
| Player collider | `RectangleShape2D`, size `(20, 10)`, centred on origin | `player/player.tscn` |
| Player sprite offset | `(0, -16)` | `player/player.tscn` |

Full design rationale for all of the above: `docs/features/world-collision/design.md`.
