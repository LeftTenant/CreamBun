# Creating World Areas — A Designer's Guide

This is a how-to guide for building CreamBun's world by hand in the Godot editor: painting
terrain, placing props, laying out a new area, and linking areas together. It assumes no prior
reading of the design doc — if you want the *why* behind any rule here, the full rationale lives
in the relevant feature design doc (referenced by section below) — mostly
`docs/features/world-collision/design.md`, with `docs/features/world-thresholds/design.md`
covering how areas link to each other (§4) — but everything you need to actually do the work is on
this page.

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
   **Physics Layers**, add an entry, open the expanded menu (⋮ button) and tick the **world**
   checkbox under Collision Layer (the named checkboxes — `world` / `player` / `interactable` — 
   come from `project.godot`'s `[layer_names]` section, already set up project-wide; you don't 
   need to touch raw layer numbers). Leave Collision Mask empty — terrain doesn't need to detect 
   anything, only to be detected.
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
A collidable tile blocks movement wherever you paint it — `Ground` included. The layer names
(`Ground`/`Solids`) are an organizational convention for Y-sorting (§2 below), not a collision
boundary. Keep solid tiles visually distinct from walkable ones so nobody paints one by accident.

**Which layer should a collidable tile go on?** Ask "does it need to draw *in front of* the
player?", not "is it solid":

- **`Solids`** — anything with height the player can walk behind: a cliff face, a wall, a water
  edge with a raised lip. `Solids` is Y-sorted, which is what makes that work.
- **`Ground`** — flat, ground-level boundaries the player walks up to but never behind: the edge
  of a raised bank, a fence line, the lip of a path. `meadow.tscn` does this — the `grass` atlas
  has eight **edge variants** (atlas coords `1:0` through `8:0`) whose polygons are thin strips
  along one or two of the tile's borders rather than the full cell. Paint a run of them and you
  fence off a region while the tiles still read as ordinary walkable grass. There's nothing to
  sort against, so they belong on the unsorted layer.

**Edge-strip polygons don't need to line up perfectly between tiles.** Adjacent edge variants
often meet with a pixel or two of stagger — the player's collider is a capsule precisely so it
slides along a run like that instead of catching on every step (see the Quick reference table and
design doc §10). Draw the strips to look right; don't chase pixel-exact continuity.

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
"bounds" still cover the full rectangle that encloses it, and the perimeter wall goes around *that*
rectangle — leaving the parts of it you didn't paint as unwalled void a player can wander into.
Keep `Ground` a solid rectangle so the computed bounds match what you actually see.

**Whether the north edge clips the character is now something you decide per area, not something
the code computes for you.** Every edge of every area gets a perimeter wall automatically (below),
and it sits flush at the true painted edge on all four sides — there's no inset anywhere any more.
The camera's limits clamp to that same line, and because Cream Bun is feet-anchored (the
ground-anchor rule above — the sprite is drawn *above* the node origin, not centred on it), that
interacts very differently edge by edge. At the **north** edge, a player standing flush against it
has roughly the top two-thirds of the drawn sprite pushed above `Camera2D.limit_top` — a real,
visible clip. At the **east/west**
edges the equivalent clip is only a couple of pixels — easy to miss and not worth mitigating. At
the **south** edge there's no clip at all: the feet-anchor means the drawn sprite never reaches
past the camera's `limit_bottom` in the first place. So this is a north-edge-specific decision, not
a general "every edge" one — don't spend effort inset-painting or Threshold-placing a south (or
east/west) edge that has no problem to fix. Fix the north edge per area, as needed, by:

- painting a row or two of impassable terrain in from the north edge (§1), so the player is stopped
  before they'd clip,
- placing a `Threshold` there (§4) — it fires as soon as the player's `ThresholdBounds` reaches it,
  before their sprite would leave the view, or
- accepting the clip, if the north edge isn't somewhere the player has a reason to stand.

`meadow.tscn`'s own north edge is a live example of the third option: it has neither inset terrain
nor a placed Threshold, so a player standing at the true north wall today shows the top of Cream
Bun's sprite clipped above the camera's `limit_top`. This is deliberate, not an oversight — the
starting area's north edge isn't somewhere a player lingers — and it's worth looking at once in
the editor to see what "accepted" actually looks like before deciding whether your own new area
needs one of the other two options instead.

**Nothing else needs manual wiring.** The camera's two-tile dead zone and edge-lock limits, and the
perimeter walls, are all built automatically from `Ground`'s painted extent the first time
`world.gd` activates the area — there's no per-area camera setup to do. The one thing that *is*
manual is reachability: a wall alone never lets the player through, so an area with no `Threshold`
placed anywhere in it is a dead end (§4).

Design rationale: `docs/features/world-collision/design.md` §6.1, §8 (the ground-anchor rule),
§9, §12.1, §12.3; `docs/features/world-thresholds/design.md` §7 (perimeter walls, now
unconditional on every edge), §8 (the north edge clipping by default — now a content decision, not
a code one). Note both docs happen to have their own §8, covering different things — the citations
above name which doc each belongs to on purpose, so don't merge them.

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

## 4. Linking two areas with placed Thresholds

**A new area isn't reachable in-game until something links to it.** Finishing §2 gets you a
complete area scene, but the game always starts in `meadow.tscn` (`STARTING_AREA_SCENE` in
`world/world.gd`) and has no other way to discover an area scene sitting unused on disk. The last
step of building a new area is always this section: place a `Threshold` in an existing, reachable
area that leads to it.

**A `Threshold` is a placed trigger, not a property of the map's shape.** There's no per-edge
Inspector slot to fill in on `WorldArea` any more — every crossing between areas, including the
meadow ↔ orchard link, is a `Threshold`/`Arrival` pair a designer drags into the scene tree by
hand, positioned and sized like any other placed thing (compare to how a `WorldProp` is placed,
§3).

**To place a Threshold that leads from area A to area B:**

1. Open area A and drag `world/thresholds/threshold.tscn` into the scene tree as a **direct child
   of the area root** (§2's prop-placement rule applies here too — never nested under a sub-node).
2. Select it and resize its `CollisionShape2D` in the 2D viewport to cover whatever region should
   trigger the crossing — a thin strip along a map edge, the mouth of a doorway, the lip of a pit.
   Each placed Threshold gets its own independent shape, so resizing one instance never affects any
   other Threshold placed from the same template.
3. In the Inspector, set **Destination** to area B's `.tscn` file (a file-picker button — you
   don't type the path by hand) and **Arrival** to the *name* of the Marker2D you're about to place
   in area B (next step). Type it exactly: it's matched by name at crossing time, not picked from a
   list, so a typo here fails silently until you actually test the crossing.

   **Destination is stored as a plain path string, not a scene reference** — the file-picker
   button is a convenience for typing it, but under the hood it's just text in the `.tscn`, not an
   `ext_resource`/`uid://` link Godot's FileSystem dock tracks and updates. If you later rename or
   move area B's scene file, nothing warns you and nothing gets updated: this Threshold quietly
   keeps pointing at the old path. The only symptom is a `push_error` at crossing time (see §5),
   with the player left standing exactly where they were. After renaming or moving any area scene,
   grep the project for the old path and fix up every Threshold that referenced it by hand.
4. Open area B and add a plain **Marker2D** anywhere under its root — no script, no other setup —
   at the exact spot the player should land. Name it to match what you typed into **Arrival**
   above.
5. That's the whole link. The first time the player's `ThresholdBounds` collider (an invisible box
   that tracks Cream Bun's whole drawn extent, separate from and larger than the movement capsule
   — see the Quick reference table) overlaps the Threshold's shape, the game fades out, swaps the
   active area, places the player at the named Marker2D, and fades back in.

**If you're placing a Threshold to stand in for a map edge** (the common case, and the direct
replacement for what used to be a `neighbour_*` slot), position it a couple of pixels in from the
painted edge — inside the perimeter wall every area gets automatically (§2), not flush against it.
The wall is a backstop the player should never actually reach; the Threshold should fire first.
`meadow.tscn`'s `ThresholdToOrchardEast` and `ThresholdToOrchardSouth` are the reference examples:
each is a thin, 2px-deep strip hugging the inside of its wall.

**Both directions need their own placed pair.** A `Threshold` only works one way — crossing it
takes you to its `destination` and drops you at its `arrival`, full stop. There is no automatic
reverse link. A two-way doorway between area A and area B is **two** Thresholds, one placed in
each area, each with its own `destination` and `arrival` pointing back the other way. Forgetting
the second one is the single easiest mistake to make here — see §5.

**Worked example — meadow ↔ orchard**, the project's one real link today:

```
meadow.tscn
├── ThresholdToOrchardEast   (Threshold → orchard.tscn, arrival = &"ArrivalFromMeadowEast")
├── ThresholdToOrchardSouth  (Threshold → orchard.tscn, arrival = &"ArrivalFromMeadowSouth")
├── ArrivalFromOrchardNorth  (Marker2D)
└── ArrivalFromOrchardWest   (Marker2D)

orchard.tscn
├── ThresholdToMeadowNorth   (Threshold → meadow.tscn, arrival = &"ArrivalFromOrchardNorth")
├── ThresholdToMeadowWest    (Threshold → meadow.tscn, arrival = &"ArrivalFromOrchardWest")
├── ArrivalFromMeadowEast    (Marker2D)
└── ArrivalFromMeadowSouth   (Marker2D)
```

Four Thresholds and four Arrivals across two areas — that's what a fully-reciprocal two-area link
looks like on disk once you count both directions.

**A couple of things to know about how a placed Threshold behaves**, neither of which need action
from you, but which explain what you'll see when testing a new link:

- **Landing exactly inside a Threshold doesn't immediately send you back.** The re-entry guard
  covers only true overlap: whatever the player's `ThresholdBounds` is already touching at the
  moment they arrive stays inert until they've actually walked clear of it. It does **not** extend
  to an Arrival placed merely near a Threshold without overlapping it — one step in that direction
  fires the crossing normally, same as anywhere else. Treat this as a safety net, not a reason to
  place them loosely: if you do end up with an Arrival inside a Threshold, it won't immediately
  bounce the player back out — but place them clearly apart from each other regardless. All four
  of this project's shipped Arrivals are placed well clear of any Threshold, and design doc §5
  notes a future `@tool` editor warning for the inside-a-Threshold case precisely because it's
  considered a bad placement, not a supported pattern.
- **Nothing stops two Thresholds sharing an edge, or even overlapping, pointing at different
  destinations.** There's no rule limiting one edge — or one area — to a single exit.

**Nothing else needs manual wiring on the code side.** Any Threshold placed anywhere under an area
is found and connected automatically the moment that area becomes active — there's no signal to
hook up by hand.

Design rationale: `docs/features/world-thresholds/design.md` §4 (the `Threshold` node), §5 (the
`Arrival` node and the re-entry guard).

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
- **Painting a solid tile onto `Ground` by accident.** Collision lives on the tile in the TileSet,
  not on whichever layer you happened to paint it on (§1) — a collidable tile blocks movement
  wherever it's painted, `Ground` included. Painting one there *on purpose* is a supported pattern
  for flat boundaries (§1's layer-choice note); the mistake is doing it without meaning to, since
  the tile can look identical to its walkable neighbours.
- **Placing a Threshold but forgetting its destination's Arrival, or forgetting the
  reverse-direction Threshold.** A `Threshold` only works one way — it needs a matching,
  correctly-named `Marker2D` waiting in its `destination` scene, and a real two-way link needs a
  *second*, independent `Threshold` placed in the other area pointing back (§4). Get the Arrival's
  name wrong (or leave it out) and the game fails safe: it still starts the transition, so you see
  the screen fade to black and fade back in (the same ~0.3s cover/reveal as a working crossing),
  the player is left exactly where they were, and an error is pushed to the Output panel. That
  fade is actually the tell that the Threshold *did* fire and the Arrival lookup failed — it isn't
  "crossing does nothing," it just doesn't finish. Forget the reverse Threshold and walking back
  toward that same spot just hits an ordinary wall, with no fade and no error at all. Neither
  reads as a missing authoring step unless you already know to look for one.
- **Renaming or moving an area `.tscn` after a Threshold already points at it.** `destination` is
  a plain string path (§4), not a tracked scene reference — Godot's FileSystem dock has no way to
  notice the move and update it for you. The Threshold silently keeps the stale path; the only
  symptom is a `push_error` at crossing time, with the player left in place, which looks identical
  to any other bad-destination mistake above. Grep the project for the old path after any such
  rename/move and fix up every Threshold that referenced it.

---

## Quick reference

| Constant | Value | Where |
| --- | --- | --- |
| Tile size | 32×16 px | `world_area.gd`, `world_prop.gd` — `TILE_SIZE` |
| Minimum area size | 320×180 px (10 wide × 12 tall tiles) | one full viewport |
| Physics layers | `world` (terrain + props), `player`, `interactable` (Thresholds), `player_bounds` (`ThresholdBounds` only) | `project.godot` `[layer_names]` |
| Player collider | `CapsuleShape2D`, 22×10 px (radius 5, height 22, rotated 90°), at `(0, -9)` | `player/player.tscn` |
| `ThresholdBounds` | `RectangleShape2D`, 26×27 px, at `(0, -17.5)` — the player's whole drawn extent, used only to detect Thresholds | `player/player.tscn` |
| Player sprite offset | `(0, -16)` | `player/player.tscn` |

Full design rationale for all of the above: `docs/features/world-collision/design.md`; area-linking
specifically: `docs/features/world-thresholds/design.md`.
