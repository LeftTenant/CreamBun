# World Collision — Tiles, Props, and Depth Sorting

**Status:** Design (not yet implemented)
**Author:** Design pass, 2026-07-16
**Related:** `world/world.tscn`, `player/player.tscn`, `CLAUDE.md`, `README.md`

---

## 1. Overview

CreamBun's world is a grid the player walks around on. Some of it is walkable (grass, paths,
dirt) and some of it is not (cliffs, water, trees, boulders, buildings). Right now none of it
is solid: `world.tscn` has a single `TileMapLayer` with no physics layer, no props exist, and
the player's collider is a circle centred on their body that touches nothing.

The obvious way to fix that is also the wrong way: paint the art, then go back and mark which
bits are solid. That means every tree placed is two actions, every tree *moved* is two actions,
and every tree someone forgets to re-mark is a bug that ships. The blocked areas drift out of
sync with the art, silently, forever.

This document designs a system where **that second action does not exist**. A level designer
places art. Collision comes with it, because collision was authored once, on the asset, by the
person who made the asset.

The guiding principle: **collision is a property of the thing, not of the map.**

---

## 2. Recommendation (read this first)

Six decisions drive everything else:

1. **The perspective is three-quarter top-down, not isometric.** A square grid viewed at an
   angle with front-facing sprites — the Stardew Valley look. The current docs say "isometric"
   in four places and are wrong. See §3.
2. **Tiles are 32×16.** Square grid, 2:1 foreshortened ground. The player is one tile wide and
   two tall; the 320×180 viewport shows ~10×11 tiles. See §4.
3. **Painted terrain carries collision in the TileSet physics layer.** Draw the collision
   polygon once per tile in the TileSet editor; every future placement of that tile inherits it.
   See §6.
4. **Discrete props are scenes with baked-in collision.** `StaticBody2D` + sprite +
   collider, saved as `boulder.tscn`. The designer drags it in. See §7.
5. **Every solid thing declares a `footprint: Vector2i` in tile units, and its collider is
   generated from that.** Designers never draw a polygon. See §8.
6. **The world is a set of linked areas, not one map.** Each area is a `WorldArea` scene; its
   bounds are derived from the painted floor and its edges are linked to neighbours by dropping a
   scene into a slot. The camera keeps the player centred within a two-tile dead zone and locks
   to the map edge; walking off an open edge fades to the neighbour, entering from the opposite
   side. See §12.

Two consequences worth stating up front, because they are the parts most likely to be got
wrong:

- **A prop's collider is its ground footprint, not its sprite silhouette.** An oak's collider is
  the trunk base. You walk *behind* the canopy. Front-facing art means tall things sitting on
  small patches of ground, so this gap is wide and deliberate.
- **Everything is anchored at its feet.** Node origin sits on the ground contact point; the
  sprite is offset upward from there. Depth sorting keys off the origin, so this is not a style
  preference — get it wrong and trees draw in front of a player who is clearly standing in
  front of them.

---

## 3. Terminology: the perspective is not isometric

`CLAUDE.md` and `README.md` currently describe CreamBun as isometric. It is not, and the word
sends every future contributor (and every agent reading `CLAUDE.md`) toward diamond grids,
rotated axes, and basis-vector maths that this project will never use.

**What we actually have:** a square grid, viewed from above at an angle, with the ground plane
foreshortened 2:1 (one tile of depth draws half as tall as it is wide), and every object drawn
as if seen from the front.

**Why no formal term fits:** this is not a coherent projection. The ground is drawn as if seen
from above at an angle; the trees and characters are drawn as if seen from the front. Two
incompatible viewpoints composited into one image. Projection terminology (isometric,
axonometric, oblique, cabinet) describes consistent projections; this is a deliberate artistic
cheat, which is why the common names for it are informal.

**"Oblique" was considered and rejected.** It is a real term from technical drawing, and its
cabinet variant even foreshortens depth by half — but in oblique projection the depth axis runs
diagonally across the image while the front face stays true-shape. Here the depth axis runs
straight up the screen. The resemblance is coincidental, and the word implies a rigour the
style does not have.

### 3.1 The decided wording

| Context | Use |
| --- | --- |
| Casual mention | "top-down" |
| The one canonical description (README) | "three-quarter top-down perspective" + the Stardew reference |
| Depth-sorting docs | no adjective at all — it is about Y-sort, the projection is irrelevant |
| Identifiers (classes, folders, constants) | **never** name the projection |

That last row is the important one. `WorldProp`, `footprint`, `TILE_SIZE`, and the collision
layers are all *grid* concepts. The grid is square no matter how the art fakes perspective. A
class called `IsoProp` would be making a claim it does not need to make — which is exactly how
the current docs went wrong.

### 3.2 The exact edits

- `CLAUDE.md:5` — "cozy isometric RPG" → "cozy top-down RPG"
- `CLAUDE.md:89` — "### Isometric depth sorting" → "### Depth sorting"
- `README.md:3` — "A cozy isometric RPG about foraging" → "A cozy top-down RPG about foraging"
- `README.md:41` — "The game uses a top-down isometric perspective with a soft, cute pixel art
  aesthetic." → "The game uses a three-quarter top-down perspective — a square grid viewed at an
  angle, with front-facing sprites and foreshortened ground. The Stardew Valley look. The
  aesthetic is soft and cute pixel art."

Naming the reference game does more work than any projection term: "the Stardew Valley look"
tells a new contributor exactly what to build in three words.

---

## 4. Tile geometry

```gdscript
# world/props/shared/world_prop.gd (and anywhere else that needs it)
const TILE_SIZE := Vector2i(32, 16)
```

**Why 32×16:**

- Keeps the 2:1 ground foreshortening the existing terrain art already has.
- The player's sprite frames are 32×32 — exactly one tile wide, two tall. Very Stardew.
- At the project's 320×180 viewport (`project.godot:27-28`), that shows ~10×11 tiles. The
  current 64×32 shows **five tiles across the entire screen**, which is far too zoomed for a
  cozy life-sim.

**The grid is square.** `TileSet.tile_shape` stays at its default `SQUARE` — which is what
`world.tscn` already has. Note that "square grid" and "square tile" are different claims: the
*cells* are 32×16 rectangles on screen, but they tile in a plain rectangular lattice with no
row offset, no diamond, no rotated axes. Screen position is just `tile_coords * TILE_SIZE`.

### 4.1 Art migration

| Asset | Now | Becomes | Notes |
| --- | --- | --- | --- |
| `resources/sprites/terrain/grass.png` | 64×32 | 32×16 | Flat green texture — trivial rescale |
| `resources/sprites/terrain/flower grass.png` | 64×32 | 32×16 | |
| `resources/tilesets/ground_placeholder.png` | 64×32 | — | Throwaway placeholder; drop it |
| `player/player.tscn` sprite frames | 32×32 | 32×32 | Unchanged — now 1×2 tiles |

The `tile_map_data` painted into `world.tscn` keeps its tile *coordinates*; halving `tile_size`
just draws the same map at half the pixel size. It is placeholder terrain, so no migration care
is needed.

---

## 5. The core rule

> **Collision is authored once, on the asset. Never on the map.**

Every mechanism below exists to serve this. There are exactly two kinds of solid things in the
world, and each gets one mechanism:

| Kind | Examples | Mechanism | Authored in |
| --- | --- | --- | --- |
| Painted terrain | cliffs, water, walls | TileSet physics layer (§6) | TileSet editor, once per tile |
| Discrete props | trees, boulders, buildings | `WorldProp` scene (§7) | The prop's `.tscn`, once per prop |

If a task ever requires a third action — "and then mark the blocked area" — the system has
failed and the answer is to fix the asset, not to mark the map.

---

## 6. Mechanism A — painted terrain (TileSet physics layer)

A `TileSet` can carry one or more **physics layers**. Each tile in the atlas gets a collision
polygon drawn once in the TileSet editor's Physics section. Any `TileMapLayer` using that
TileSet then generates static colliders for those tiles automatically, everywhere they are
painted, forever.

This is Godot's built-in answer to exactly this problem and `world.tscn` currently does not use
it at all.

Docs:
- TileSet physics layers: https://docs.godotengine.org/en/stable/tutorials/2d/using_tilesets.html#physics-layers
- `TileSet`: https://docs.godotengine.org/en/stable/classes/class_tileset.html
- `TileMapLayer`: https://docs.godotengine.org/en/stable/classes/class_tilemaplayer.html

### 6.1 Layer structure within an area

This is the structure inside a single `WorldArea` scene (§12.1). `world.tscn` itself is now just
the persistent shell that swaps areas in and out; the tile layers and props belong to the area.

```
WorldArea (Node2D, y_sort_enabled = true)                 # the area's Y-sort scope
├── Ground        (TileMapLayer, y_sort_enabled = false)  # grass, paths, dirt — never solid
├── Solids        (TileMapLayer, y_sort_enabled = true)   # cliff faces, water edges, walls
└── (props placed here directly: Boulder, TreeOak, …)     # WorldProp instances
```

At runtime the player is reparented into this root (§12.1) so it shares the area's Y-sort scope.
Props are placed as **direct children of the area root**, not under a nested `Props` node: Y-sort
only interleaves a node's *direct* children, so a props sub-node would sort as one block against
the player instead of tile-by-tile, prop-by-prop (§9).

**Why `Ground` is not Y-sorted:** it is the floor. It always draws underneath everything and has
no depth relationship to resolve. Leaving Y-sort off keeps it cheap and keeps it from
participating in a sort it can only get wrong.

**Why `Solids` is Y-sorted:** a cliff face is an *object* — the player can stand in front of it
or behind it. Its tiles need to sort against the player and against props.

**Per-tile Y Sort Origin.** For tall tiles (a cliff face drawn 2–3 tiles high in one sprite),
set `y_sort_origin` on the tile in the TileSet editor so it sorts by its *base*, not its centre.
See `TileData.y_sort_origin`:
https://docs.godotengine.org/en/stable/classes/class_tiledata.html

**Note:** props and the player share the area root's Y-sort scope (the player is reparented in —
§12.1), so they sort against each other by `global_position.y`. This is why §8's ground-anchor
rule is load-bearing.

### 6.2 Autotiling (terrain sets)

Square grids make Godot's **terrain sets** genuinely usable — the 16-tile blob and 47-tile
patterns are fiddly on diamond grids but clean here. Combined with tile-authored collision, this
is as close to the stated goal as tooling gets: the designer paints a rough blob of "cliff", and
the edges, corners, and transitions resolve themselves **with correct collision**, from one
brush stroke.

Docs: https://docs.godotengine.org/en/stable/tutorials/2d/using_tilesets.html#terrains

This is Phase 2 (§15) — it needs real cliff art with all the edge cases drawn. But the layer
structure above is chosen so it can drop in without rework.

---

## 7. Mechanism B — discrete props (`WorldProp`)

Trees, boulders, and buildings are not terrain — they are individual objects that get placed,
nudged, and moved. They are scenes.

```
world/
  props/
    shared/
      world_prop.gd        # base class (this section)
    boulder.tscn
    tree_oak.tscn
    cottage.tscn
```

(Folder convention per `CLAUDE.md`: scripts co-located with scenes, shared base classes in a
`shared/` subfolder within the area.)

Each prop scene is:

```
Boulder (WorldProp — StaticBody2D)
├── Sprite2D          (offset upward; the art — or a placeholder shape, §7.1)
└── CollisionShape2D  (generated from `footprint`; never touched by hand)
```

The designer drags `boulder.tscn` into the area root and positions it (§6.1 — props are direct
children of the Y-sorted area root). That is the entire workflow. The collider is inside the
scene, so it cannot be forgotten, cannot drift, and follows the prop when it moves.

### 7.1 Placeholder art from geometric shapes (for now)

Props do not need finished sprites to be built. Where real art isn't ready, the visual child is
a **placeholder made from Godot's own drawing nodes** — a `Polygon2D`, `ColorRect`, or a couple
of them — instead of a `Sprite2D` with a texture. A boulder is a grey ellipse; a tree is a brown
`Polygon2D` trunk with a green blob canopy above it. No external image files, no art pipeline.

The `WorldProp` base class does not care which it is: it owns the `footprint` and the collider
(§8), and is agnostic about the visual node hanging off it. That is what makes the swap clean —
replacing a placeholder with a real sprite later touches only that one visual child in that one
scene, and nothing about collision, footprint, or sorting changes.

Two rules keep placeholders honest so they actually prove the design:

- **Anchor the placeholder exactly where the real sprite will go** — offset upward from the
  ground anchor (§8.1), never centred on it. If the placeholder cheats its position, real art
  will sort differently and the swap won't be a drop-in.
- **Give it the real silhouette-vs-footprint shape.** A placeholder tree must be drawn with a
  wide canopy over a one-tile trunk, so slice 5 genuinely tests walking *behind* the canopy
  (§8.2). A placeholder that is just a `footprint`-sized box proves nothing about the gap that
  makes props interesting.

This applies to prop visuals (and, in Phase 2, cliff faces). Ground tiles already have flat
placeholder textures (§4.1), and the player already has real sprites — neither needs this.

---

## 8. The footprint and the ground anchor

### 8.1 Ground anchor

**The node origin of every solid thing is its ground anchor.** For a prop, that is the
**front-centre of its footprint** — the point on the ground nearest the camera. The collider
extends backward (up-screen) from it; the sprite extends upward from it.

Two reasons:

1. **Depth sorting.** Godot's Node2D Y-sort keys off `global_position.y` directly — there is no
   separate sort-origin property on Node2D (unlike `TileMapLayer`). So the origin *is* the sort
   key. Anchoring at the footprint's front edge means a prop sorts by the edge closest to the
   camera, which is the correct answer for overlap.
2. **Placement.** "Put the origin where it touches the ground nearest you" is a rule a designer
   can hold in their head, and it snaps naturally to a tile's bottom edge.

### 8.2 Footprint

```gdscript
@tool
class_name WorldProp
extends StaticBody2D
## Base class for every solid world prop — trees, boulders, buildings.
##
## Designers place these by dragging the .tscn into the area root (§6.1) and
## setting `footprint`. The ground collider is generated from that. There are no
## hand-drawn polygons and no separately-maintained "blocked area" — collision is
## authored here, once, and travels with the prop wherever it is placed.
##
## The node origin is the GROUND ANCHOR: the front-centre of the footprint, the
## point on the ground nearest the camera. Depth sorting keys off the origin
## (Node2D sorts on global_position.y), so the origin must sit on the ground.
## The sprite is offset upward from it.
##
## @tool means the collider rebuilds live in the editor as `footprint` changes,
## so designers see the solid area while placing.
## https://docs.godotengine.org/en/stable/tutorials/plugins/running_code_in_the_editor.html

const TILE_SIZE := Vector2i(32, 16)

## Ground footprint in tile units. A boulder is (1, 1); a cottage might be (4, 3).
##
## This is the patch of GROUND the prop occupies — not the size of its sprite. An
## oak tree is (1, 1): its trunk base. The canopy is drawn far wider and the player
## walks behind it. Front-facing art means tall things on small patches of ground,
## so footprint and silhouette are meant to diverge.
@export var footprint: Vector2i = Vector2i.ONE:
	set(value):
		footprint = Vector2i(maxi(value.x, 1), maxi(value.y, 1))
		_rebuild_collider()

@onready var _collision: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	_rebuild_collider()


## Regenerate the ground collider from `footprint`.
##
## The grid is square, so this is a plain rectangle — width is footprint.x tiles,
## depth is footprint.y tiles. No projection maths: screen size is just
## footprint * TILE_SIZE.
##
## The shape is offset up-screen by half its depth because the origin is the
## footprint's FRONT edge, not its centre (see class docs). So the collider spans
## y in [-depth, 0], i.e. entirely behind the anchor.
func _rebuild_collider() -> void:
	# The setter can fire before @onready resolves (e.g. when the editor applies
	# an exported value during scene load), so bail until the child exists.
	if _collision == null:
		return
	var shape := RectangleShape2D.new()
	shape.size = Vector2(footprint) * Vector2(TILE_SIZE)
	_collision.shape = shape
	_collision.position = Vector2(0.0, -shape.size.y / 2.0)
```

The designer-facing API is one `Vector2i`. That is the whole point.

### 8.3 Why not auto-generate colliders from sprite alpha?

Considered and rejected. It would make a tree's collider its canopy, and the player would be
blocked by leaves they should be walking behind. Silhouette is not footprint — see §8.2. The
divergence is the design, not an oversight, so it cannot be automated away.

---

## 9. Depth sorting

The area root (`WorldArea`) has `y_sort_enabled = true`. Godot Y-sorts the **direct** children of
a Y-sorted node by their `global_position.y` — it does not reach through a nested node, which is
why the player must be reparented into the area root (§12.1) rather than left in the world shell.

Docs: https://docs.godotengine.org/en/stable/classes/class_node2d.html#class-node2d-property-y-sort-enabled

The rules that make it work:

1. **The area root has `y_sort_enabled = true`**, and props are its direct children (§6.1).
2. **Every prop's origin is on the ground** (§8.1).
3. **The player's origin is at their feet** — currently it is at their centre. See §10.
4. **Sprites are offset upward from the origin**, never centred on it.
5. **Ground is not Y-sorted**; `Solids` is (§6.1).
6. **The player is reparented into the area root on load** (§12.1), so it shares one Y-sort scope
   with that area's tiles and props.

**Known limitation, accepted.** Props anchor at their footprint's *front edge*; the player
anchors at the *centre* of their small ground patch (§10 — a body that moves freely off-grid has
no meaningful front edge). The mismatch is half the player's collider depth, ~5px against a 16px
tile depth. This is the conventional setup and is not visible in practice. If a deep-footprint
prop ever sorts wrong against the player, this is the knob — but do not pre-emptively fix it.

---

## 10. The player collider

`player/player.tscn` currently has a `CircleShape2D` with `radius = 16`, centred on the node
origin, with the sprite also centred on the origin. Both are wrong:

- **A 32px-diameter circle centred on the body** means the player collides using their whole
  body, including their head. Solid things are on the *ground*; the player should collide with
  their feet.
- **The origin is at the body centre**, so Y-sort keys off the player's midriff instead of their
  feet, which will produce visibly wrong sorting against props.

The fix:

```gdscript
# player/player.tscn — node configuration, not code
#
# Player (CharacterBody2D)          origin at the FEET (ground contact point)
# ├── CollisionShape2D              RectangleShape2D, size (20, 10), position (0, 0)
# ├── AnimatedSprite2D              offset (0, -16)  — 32x32 frames sit above the origin
# └── Camera2D                      drag margins for the two-tile dead zone (§12.3);
#                                   limits set per-area by world.gd on load
```

**Why (20, 10):** a little under one tile wide (32) and one tile deep (16), in the same 2:1
ratio as the foreshortened ground. Slightly sub-tile so the player can slip through a one-tile
gap without pixel-perfect alignment — a cozy game should not punish precision.

**Why centred on the origin, not offset like props:** the player moves freely rather than
snapping to the grid, so "the front edge of their footprint" is not a meaningful anchor. The
centre of their ground patch is. See §9 for the accepted consequence.

`player.gd` needs no changes — it already uses `move_and_slide()`, which will simply start
colliding once there is something to collide with.

---

## 11. Collision layers

`project.godot` currently names no physics layers, so every mask is an unlabelled numbered
checkbox and every designer is guessing.

```ini
# project.godot
[layer_names]

2d_physics/layer_1="world"          # solid terrain + props. Static.
2d_physics/layer_2="player"         # Cream Bun.
2d_physics/layer_3="interactable"   # Area2D triggers: doorways, forage spots, NPCs.
```

| Node | `collision_layer` | `collision_mask` |
| --- | --- | --- |
| `WorldProp` | `world` | — (static; collides with nothing itself) |
| `Solids` TileMapLayer | `world` | — |
| `Player` | `player` | `world` |
| Interaction `Area2D`s | `interactable` | `player` |

Docs: https://docs.godotengine.org/en/stable/tutorials/physics/physics_introduction.html#collision-layers-and-masks

`interactable` is declared now but not built here — it is the seam where `shared/interactable.gd`
(described in `CLAUDE.md`, not yet written) will land. Naming it now costs nothing and stops the
number being claimed for something else.

---

## 12. Map areas, the camera, and edge transitions

The world is not one map — it is a set of **areas** (a meadow, a market, a cave mouth) linked at
their edges. The player walks to the edge of one and a short transition carries them to the next,
entering from the opposite edge. This section defines what an area is, how its edges are denoted,
how the camera frames the player within it, and how the hand-off works.

### 12.1 An area is a scene; `world.tscn` is the persistent shell

Each area is its own scene (`world/areas/meadow.tscn`, `world/areas/market.tscn`, …) whose root
is a `WorldArea`. It holds that area's `Ground` / `Solids` tile layers and its props (§6.1).
Areas are loaded and unloaded one at a time.

`world.tscn` stops being "the map" and becomes the **persistent shell** — the things that outlive
any single area:

```
World (Node2D)                      # the shell; persists across areas
├── ActiveArea  (Node2D)            # the current WorldArea is instanced in here
├── Player      (CharacterBody2D)   # persists; reparented into the area on load (below)
├── Notebook    (CanvasLayer)
└── Transition  (CanvasLayer, process_mode = ALWAYS)   # fade overlay (§12.5)
```

**The player is reparented into the active area on load.** This is not optional bookkeeping — it
is what makes depth sorting work. Y-sort only interleaves nodes that share one Y-sorted parent
(§9); the area's tiles and props live under the `WorldArea` root, so the player must join that
scope to sort against them. `world.gd` does this once per load:

```gdscript
# world.gd — on entering an area
_active_area.add_child(area)          # `area` is the freshly-instanced WorldArea
_player.reparent(area)                # move the persistent player into the sort scope
```

`reparent()` preserves the node and all its state — including its child `Camera2D` — so nothing
about the player is rebuilt on a transition. It is the same node, moved.
https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-reparent

### 12.2 Denoting the edges: bounds derived, neighbours declared

Two facts define an area's edges. One can be derived; one cannot — and the split follows the same
ethos as §5 (don't make a designer re-declare what the art already says).

**Bounds are derived from the painted floor.** The designer already painted the ground; the
extent of that paint *is* the area. There is no separate "map boundary" to draw and keep in sync:

```gdscript
@tool
class_name WorldArea
extends Node2D

const TILE_SIZE := Vector2i(32, 16)   # §4

## The scenes reached by walking off each edge. An empty slot is a hard boundary
## (a wall, not a doorway). These are genuine new information — you cannot derive
## which area lies north — so, unlike the bounds, they are declared by hand.
@export var neighbour_north: PackedScene
@export var neighbour_east: PackedScene
@export var neighbour_south: PackedScene
@export var neighbour_west: PackedScene

@onready var _ground: TileMapLayer = $Ground

## Area extent in world pixels, taken from the painted floor. Designers never
## re-declare geometry they already painted (cf. §5).
## get_used_rect() returns the tile-coordinate bounding box of painted cells.
## https://docs.godotengine.org/en/stable/classes/class_tilemaplayer.html#class-tilemaplayer-method-get-used-rect
func get_bounds_px() -> Rect2:
	var cells := _ground.get_used_rect()
	return Rect2(Vector2(cells.position) * Vector2(TILE_SIZE),
			Vector2(cells.size) * Vector2(TILE_SIZE))
```

**Neighbours are declared per edge.** Four `PackedScene` exports on the area root: a filled slot
is a doorway to that scene, an empty slot is a hard edge. That single fact drives both the walls
and the transitions in §12.4 — the designer links areas by dropping a scene into a slot, and
everything else follows.

### 12.3 The camera: centred, with two tiles of slack, locked at the edges

One `Camera2D`, child of the player. Two behaviours, both built in — no custom camera code.

**Centred, within a two-tile dead zone.** The player is not pinned dead-centre; they may drift up
to two tiles from centre before the camera pans to follow. This is Camera2D's *drag margin*,
expressed as a fraction of the half-viewport:

| Axis | Two tiles | Half-viewport | `drag_*_margin` |
| --- | --- | --- | --- |
| Horizontal | 2 × 32 = 64px | 320 / 2 = 160px | 64 / 160 = **0.4** |
| Vertical | 2 × 16 = 32px | 180 / 2 = 90px | 32 / 90 ≈ **0.356** |

The dead zone is symmetric in *tiles* (two each way) but asymmetric in *pixels*, because tiles
are 2:1 — which is exactly right, since the world itself is 2:1. These margins are static and
live in `player.tscn` (`drag_horizontal_enabled` / `drag_vertical_enabled` = `true`, margins as
above). Enable `position_smoothing` for a soft cozy glide as the camera catches up.

**Locked at the map edge.** As the player nears an edge, the camera must not reveal the void
beyond the floor. Camera2D's `limit_left/top/right/bottom` clamp it to the area bounds; the map
edge then sits flush against the viewport edge and the player walks *off-centre* toward it — which
is what lets them reach the edge to leave. The limits are per-area, so `world.gd` sets them from
`get_bounds_px()` on every load:

```gdscript
# world.gd — after reparenting the player into the area
var b := area.get_bounds_px()
var cam := _player.get_node("Camera2D") as Camera2D
cam.limit_left = int(b.position.x)
cam.limit_top = int(b.position.y)
cam.limit_right = int(b.end.x)
cam.limit_bottom = int(b.end.y)
```

Docs: [drag margin](https://docs.godotengine.org/en/stable/classes/class_camera2d.html#class-camera2d-property-drag-horizontal-margin),
[limit](https://docs.godotengine.org/en/stable/classes/class_camera2d.html#class-camera2d-property-limit-left)

**Consequence for area authors: the north edge needs headroom.** `limit_top` clamps the camera's
view rect to the exact pixel of the painted north edge — but the player is feet-anchored (§10), so
a perimeter wall flush with that same edge would let the player stand with their entire sprite
above the clamped view. §12.4 covers the fix (an inset north wall) and the resulting non-walkable
backdrop strip it leaves along every area's north edge; read that note before laying out a new
area's `Ground` extent.

**Areas must be at least one viewport in each dimension** (≥ 320×180px — roughly ≥ 10 wide × 11
tall in tiles). If an area is smaller than the viewport on an axis, Godot cannot both keep the
player on-screen and honour the limits; it centres the small area and the dead zone stops
mattering. This is a constraint on how maps are drawn, not a code case to handle.

### 12.4 Walking off the edge: open edges vs. walls

The perimeter is built from the neighbour declarations (§12.2) once, when the area loads. This is
the *one* sanctioned place collision is not authored on an asset — and it is exactly the exception
§16 already carves out: the map boundary has no art to hang collision on.

For each of the four edges, `world.gd` (or a small helper on `WorldArea`) does one of two things
along that edge of `get_bounds_px()`:

- **No neighbour → an invisible wall.** A `StaticBody2D` on the `world` layer spanning that edge.
  The player simply cannot leave.
- **A neighbour → an open edge with a trigger.** An `Area2D` on the `interactable` layer, one
  tile deep, spanning that edge. When the player's body enters it, the area emits a local signal:

```gdscript
# WorldArea
signal edge_reached(direction: Edge)   # Edge: an enum NORTH / EAST / SOUTH / WEST
```

`world.gd` connects to `edge_reached` and starts the transition (§12.5). This is a plain node
signal, not `GameEvents`: the area is a direct child of the world scene, so a signal-bus hop would
be ceremony (the bus rule in `CLAUDE.md` is for *cross-scene* events).

**North-edge headroom inset — a permanent per-area consequence.** The north perimeter wall's
player-facing surface is not flush with the true painted north edge like the other three walls
are — it sits one sprite-height south of it (`NORTH_WALL_HEADROOM_INSET_PX`,
`world/areas/shared/world_area.gd`). This exists because `limit_top` (§12.3) clamps the camera's
view rect to that exact edge, while the player's sprite is feet-anchored (§10): a wall flush with
the edge would let the player stop with their whole sprite above the clamped view — invisible.
Insetting the wall guarantees the camera always keeps a full sprite-height of headroom above the
player, no matter how far north they walk.

The consequence for every area, present and future: **the topmost ~2 tile rows of painted `Ground`
are a non-walkable decorative backdrop** — visible behind the invisible wall, but never reachable,
since the player is stopped short of it. A designer laying out a new area should paint that strip
as normal ground (it still needs to look right on screen) but should expect the player can never
actually stand on it. Only the north edge needs this: south already leaves headroom below the
player, and east/west only clip a few px of the sprite's transparent side padding (see
`world_area.gd`'s `build_perimeter_walls()` doc comment for the full reasoning).

### 12.5 The transition and the opposite-edge spawn

When `world.gd` hears `edge_reached(dir)`:

1. **Freeze.** Set `GameState.current_state = LOADING`. The player already zeroes its velocity
   whenever the state is not `PLAYING` (`player.gd`), so this both stops movement and blocks the
   notebook — no new "transitioning" state is needed. (Reusing an existing state rather than
   adding one mirrors the notebook design's removal of `PAUSED`: prefer fewer states.)
2. **Cover.** Fade the `Transition` overlay to opaque — a `Tween` on a full-screen `ColorRect`.
   This is the "space for an animation": while the screen is covered, the swap happens unseen.
3. **Swap.** Free the old `WorldArea`, instance `neighbour_<dir>`, add it under `ActiveArea`,
   reparent the player in (§12.1), rebuild the perimeter (§12.4), and set the camera limits
   (§12.3).
4. **Place on the opposite edge.** The player exits one edge and enters from the *opposite* edge
   of the new area, so a continuous walk stays continuous:

   | Exit edge | Enter edge of new area |
   | --- | --- |
   | East | West |
   | West | East |
   | North | South |
   | South | North |

   The perpendicular offset is preserved: leaving the east edge at some `y`, the player enters the
   west edge at that same `y` (clamped to the new area's vertical bounds), inset ~1 tile from the
   edge so they land fully on-screen and walking *inward*.
5. **Reveal & resume.** Fade the overlay back to transparent, then set
   `GameState.current_state = PLAYING`. Emit `GameEvents.area_changed(area_id)` for any
   cross-system listener (autosave, a future minimap) — this one *is* cross-scene, so it goes on
   the bus.

**Phase 1 uses a fade.** It is cozy, cheap, and completely hides the swap. The architecture
leaves room for a fancier **slide/scroll** transition (both areas briefly on-screen, sliding
across) behind the same `edge_reached` → transition seam; that is Phase 2 (§15), and it needs a
small art gutter beyond each open edge so the outgoing area has something to show as it slides
away.

---

## 13. Cliffs

**Cliffs are walls, not elevation.** The cliff face is front-facing art on tiles carrying
full-tile collision; the player walks around. This is not a compromise — it is how the genre
actually does it, and it is available on day one because the grid is square.

What is explicitly **not** being built: real elevation, plateaus the player can stand on top of,
or anything requiring custom depth sorting between height levels. That path means a custom
sorting solution and it will eat weeks. If a standable plateau is ever wanted, the shape is a
second `Solids`-style `TileMapLayer` at a higher `z_index` with its own painted collision — but
that is a future feature with its own design doc, not a foundation to build now.

---

## 14. The designer workflow (the payoff)

This is the whole point of the document. What a level designer actually does:

**To place a tree:** drag `tree_oak.tscn` into the area. Position it. Done.

**To move a tree:** drag it. Done. The collider moved with it.

**To make a new prop:** duplicate `boulder.tscn`, swap the sprite, set `footprint`. The collider
appears live in the editor (`@tool`). Done — and every future placement of it is now free.

**To carve a cliff:** paint cliff tiles. Collision comes from the TileSet. With terrain sets
(§6.2, Phase 2), paint a rough blob and the edges resolve themselves.

**To link two areas:** drop the neighbour's scene into the `neighbour_east` (etc.) slot on the
area root. The wall becomes a doorway; the transition and opposite-edge spawn are automatic (§12).

**To block a region:** you do not. Place the thing that blocks it.

At no point does anyone open a "blocked areas" layer, draw a polygon, or mark a tile as solid.

### 14.1 Reference documentation (for the humans doing this work)

Everything in §14 is a human workflow, not a code path: a level designer paints tiles, drags
prop scenes, and fills in `neighbour_*` slots by hand in the Godot editor. None of that is
exercised by automated tests or code review — it lives in whoever's head last touched it, unless
it is written down. That documentation is a deliverable of this feature, not an afterthought
tacked on once someone gets confused.

**New docs subfolder: `docs/reference/`.** `docs/` currently splits into `features/` (per-feature
design docs like this one), `migrations/`, `refactors/`, and `ideas/` — all implementation
history, not standing how-to material. None of those is the right home for "here is how you, a
human, paint a tile or place a prop." `docs/reference/` is a new sibling category for
operational documentation: written once the mechanism exists, kept current, and read repeatedly
by whoever is doing art or level work — not tied to a single feature's implementation history the
way `docs/features/` entries are.

Deliverable: `docs/reference/creating-world-areas.md`, covering at minimum:

- How to paint terrain and give a tile type collision via the TileSet physics layer (§6).
- How to create a new `WorldProp`: duplicate a prop scene, set `footprint`, swap the placeholder
  shape for real art (§7–§8).
- How to lay out a new `WorldArea` scene — the `Ground`/`Solids` layer structure, and the
  ground-anchor / footprint rules that keep depth sorting correct when placing props (§6.1, §8,
  §9).
- How to link two areas via the `neighbour_*` slots, and what an empty slot means (§12.2, §12.4).
- Common mistakes worth flagging up front: sprites not offset from the ground anchor, footprint
  drawn to match silhouette instead of the ground contact point, areas smaller than one viewport
  (§12.3).

This is written from the finished mechanisms, not from this design doc's proposal — it documents
what got built, once it exists to describe. See the Phasing section below for when it lands.

---

## 15. Phasing

**Phase 1 — the foundation (build now).**

1. **Terminology + geometry.** The §3.2 doc edits; `TILE_SIZE` to 32×16; rescale the two terrain
   textures; drop `ground_placeholder.png`; name the collision layers (§11); fix the player's
   anchor, collider, and sprite offset (§10). Runnable: the player walks a correctly-scaled grid,
   feet-anchored, colliding with nothing yet.
2. **TileSet physics layer + Y-sort scope.** Add the physics layer to the TileSet; give one test
   tile a collision polygon; lay the tilemap out as the §6.1 structure — a Y-sorted root with
   `Ground` / `Solids` and props as direct children. (It can still live directly in `world.tscn`
   for now; the shell/area split comes in slice 6.) Runnable: the player is blocked by a painted
   tile.
3. **`WorldProp` base class.** `world/props/shared/world_prop.gd` with `footprint`, generated
   collider, `@tool` editor preview (§8.2).
4. **One real prop, end-to-end.** A boulder: placeholder shape (§7.1), footprint, correct ground
   anchor. Verify Y-sort against the player from all four sides. This slice is where the design is
   proven — if depth sorting is wrong, it is wrong here, cheaply.
5. **A tree.** The first prop where footprint ≠ silhouette. Placeholder canopy over a one-tile
   trunk (§7.1); verify walking behind the canopy.
6. **Areas + camera.** Extract the map into `world/areas/meadow.tscn` as a `WorldArea`; make
   `world.tscn` the persistent shell (`ActiveArea` / `Player` / `Notebook` / `Transition`);
   reparent the player into the area on load (§12.1); derive bounds (§12.2); wire the camera's
   two-tile dead zone and edge-lock limits (§12.3); build perimeter walls on edges with no
   neighbour (§12.4). Runnable: the player roams a bounded meadow, camera centred with two tiles
   of slack and locked at the edges, stopped by invisible boundary walls.
7. **Edge transition (fade) + a second area.** Link the meadow to a second area via a
   `neighbour_*` slot; open that edge with a trigger; fade to the neighbour and spawn on the
   opposite edge (§12.5). Runnable: walk off the east edge, fade, and appear at the west edge of
   the next area. This delivers the full requested behaviour end-to-end.
8. **Designer reference documentation.** Create the `docs/reference/` subfolder and write
   `docs/reference/creating-world-areas.md` (§14.1), documenting the terrain, prop, area, and
   area-linking workflows built in slices 1–7. Runnable: someone with no prior context on this
   design doc can follow the guide alone to paint a new tile's collision, place a prop, and link
   a new area.

**Phase 2 — named, deferred.**

- Terrain sets / autotiling for cliffs and paths (§6.2) — needs real edge-case art.
- Slide/scroll area transition (§12.5) — both areas on-screen, sliding across; needs an art
  gutter beyond each open edge.
- Buildings: large-footprint props + doorway `Area2D` triggers.
- Real prop and cliff sprites replacing the §7.1 placeholder shapes — a per-scene visual swap,
  no structural change.
- `shared/interactable.gd` on the `interactable` layer.

**Phase 3 — named, deferred.**

- Standable elevation / plateaus (§13). Own design doc. Do not drift into this.
- Navigation meshes for NPC pathfinding. Nothing needs pathfinding yet.

---

## 16. Alternatives considered

**A hidden "blocker" TileMapLayer.** Paint a single invisible solid tile over no-go areas. It
works, and it is tempting. Rejected: it is precisely the separately-maintained blocked area this
design exists to eliminate. It drifts from the art the moment someone moves a tree. *Narrow
exception:* genuinely artless boundaries (the invisible edge of the map) have no asset to hang
collision on, so they may use it. Nothing else.

**Hand-placed `CollisionPolygon2D` per map.** The default thing a beginner does. Rejected: it is
the two-actions-per-tree problem in its purest form.

**Diamond isometric.** Rejected in design discussion in favour of the Stardew look (§3). It would
have required basis-vector collider maths, per-tile diamond polygons, awkward autotiling, and
custom sorting for any elevation.

**Auto-generating colliders from sprite alpha.** Rejected — see §8.3.

**Godot's `NavigationRegion2D` instead of physics.** Rejected for now: nothing pathfinds yet, and
navigation would still need collision for the player. Phase 3 if NPCs need it.

**One giant scrolling tilemap instead of discrete areas.** Seamless, no transitions. Rejected:
it makes every area load at once (memory and edit-time cost that grows with the world), gives no
natural seam for a cozy screen-wipe between locations, and defeats the "each area is a scene a
designer opens and edits in isolation" workflow. Discrete `WorldArea` scenes keep each place
small, self-contained, and independently testable — and the fade is a feature, not a tax.

**Auto-deriving neighbour links from world geometry.** Placing areas on a shared world grid and
inferring adjacency was considered so designers wouldn't fill in slots. Rejected: it trades one
explicit `@export` slot for an invisible global coordinate system that must be kept consistent
across every area — more to get wrong, not less. Adjacency is genuinely new information (§12.2);
declaring it per edge is the honest, local way to say it. (Bounds, which the art *does* already
encode, stay derived.)

---

## 17. Out of scope

- Combat collision of any kind. CreamBun has no combat (`CLAUDE.md`).
- Moving/dynamic props (rolling boulders, closing gates).
- Water the player can swim in — water is a wall in Phase 1.
- Foraging interaction. This doc gives it the `interactable` layer and nothing more.
- Multi-level elevation (§13, Phase 3).
