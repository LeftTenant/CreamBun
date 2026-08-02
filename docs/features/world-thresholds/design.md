# World Thresholds — Placed Area Transitions

**Status:** Design (not yet implemented)
**Author:** Design pass, 2026-08-01
**Supersedes:** `docs/features/world-collision/design.md` §12.2 (neighbour slots), §12.4 (open edges
vs. walls), §12.5 (the transition and the opposite-edge spawn). Those sections stay in place as
history — they record *why* the edge-derived model was shaped the way it was, which is worth
keeping legible. This document replaces the mechanism they describe.
**Related:** `world/areas/shared/world_area.gd`, `world/world.gd`, `player/player.tscn`,
`docs/reference/creating-world-areas.md` §4

---

## 1. Overview

Today, moving between areas is **derived from the shape of the map**. Each `WorldArea` declares up
to four `neighbour_*` scenes; the perimeter build step turns each filled slot into a full-span
`Area2D` along that edge, carves 32×32px dead zones out of its corners, and computes where the
player lands on the far side by carrying their exit coordinate across and offsetting it one tile in
from the destination edge's "playable-facing boundary."

It works. It is also the most fragile thing in the codebase, and the fragility is structural rather
than incidental:

- Three separate computations must agree about where an edge "really" begins. Two review rounds on
  the original implementation found bugs where one of them re-derived that boundary from the raw
  painted edge instead of the shared helper — first leaving the corners physically open, then
  leaving the NE/NW corner exclusions at zero pixels.
- The north edge is inset to keep the camera from clipping the player's head, so the inset depends
  on the player's collider, which depends on the player's *art*. A sprite edit silently changes
  correct map geometry. This is not hypothetical: the current sheet needs 17px of headroom, not the
  13px an earlier measurement suggested, because the walk frames are 2px taller than the idle pose.
- The spawn point lands 2px clear of the trigger the player just came through. That margin is the
  tightest number in the system and nothing about it is obvious.
- One edge maps to exactly one destination. A pit, a doorway, or two exits on the same side of a
  map cannot be expressed at all.

**This design replaces the derivation with placement.** A designer drops a **Threshold** where the
player should leave, points it at a destination scene and a named **Arrival** inside that scene, and
that is the whole mechanism. No edge math, no corner rule, no spawn arithmetic, no coupling between
sprite art and map geometry.

The guiding principle, mirroring §5 of the world-collision design: **a transition is a thing a
designer places, not a property of the map's shape.**

---

## 2. Recommendation (read this first)

Five decisions drive everything else:

1. **Transitions are placed `Threshold` nodes, not derived edges.** `neighbour_north/east/south/west`
   are removed outright — there is no auto-generated convenience path. See §4.
2. **Destinations name an `Arrival` marker.** The player lands exactly where a designer put a
   `Marker2D`, not at a computed offset from an edge. See §5.
3. **The player gets a second collider covering their whole drawn extent**, used only for detecting
   Thresholds. Its size is authored, and a test proves it still covers the art. See §6.
4. **Every edge of every area gets a perimeter wall, unconditionally.** The wall becomes a pure
   backstop — you can never walk off the painted floor — and Thresholds sit inset from it, so the
   player always meets the Threshold first. No branching. See §7.
5. **The north headroom inset is deleted.** The player's art is allowed to clip above the camera's
   top limit; keeping it on screen becomes a content rule, not a computed one. See §8.

Two consequences worth stating up front, because they are the parts most likely to surprise:

- **Walking to an unlinked north edge now clips the top of the character.** That is accepted, not a
  bug. It is immediately visible and fixed by painting terrain or placing a Threshold. Contrast the
  current failure mode, where a wrong constant clips one pixel and nobody notices.
- **Every exit is now authoring work.** Filling one `neighbour_east` slot used to wire a whole edge.
  Now a designer places a `Threshold` and a matching `Arrival`. That cost is the price of pits,
  doorways, and multiple exits per side.

---

## 3. Naming

The feature is named after what it is. A **threshold** is the place you cross to leave somewhere —
it covers a map edge, a doorway, and the lip of a pit equally well, and it reads as plain English in
a sentence a designer would say out loud: *"put a threshold on the east side of the meadow."*

| Concept | Name | Node type |
| --- | --- | --- |
| The region you cross to leave | `Threshold` | `Area2D` |
| The point you land on | `Arrival` | `Marker2D` |
| The player's drawn extent, for detection | `ThresholdBounds` | `Area2D` (child of Player) |

"Transition" is kept for the *sequence* (freeze → fade → swap → place → reveal), which is what
`world.gd` still owns. A Threshold is the trigger; the transition is what happens next. Do not use
"exit" or "portal": the first is directional and wrong for a two-way doorway, the second implies
instantaneous magic this game does not have.

---

## 4. The `Threshold` node

`world/thresholds/threshold.tscn` — an `Area2D` a designer drags into an area scene and sizes.

```gdscript
# threshold.gd
class_name Threshold
extends Area2D

## The area scene this Threshold leads to, as a path.
##
## A String, not a PackedScene, for the same reason neighbour_* was: two scenes
## holding live PackedScene references to each other deadlock Godot's loader at
## parse time. Resolved with load() at crossing time only.
@export_file("*.tscn") var destination: String = ""

## The name of the Arrival node inside `destination` to place the player on.
@export var arrival: StringName = &""
```

- Placed as a **direct child of the area root**, alongside props.
- `collision_layer = interactable`, `collision_mask = player_bounds` (§6).
- Emits nothing of its own; `world.gd` connects to its `area_entered` and drives the sequence.

**Those two exports are the whole node.** A Threshold declares *where you go* and *where you land*,
and nothing about how the transition looks — every crossing uses the same fade. An export for
per-Threshold transition styles is deliberately not added until a second style exists to select
(§10 Phase 2), since an enum with one value is a decision nobody has made yet dressed up as
configuration.

**Thresholds sit inset from the perimeter wall, not flush against it.** How far in is a design
choice per Threshold, and it is the knob that replaces the old headroom inset: draw it far enough
in that the player crosses before their art would leave the view.

**A Threshold standing in for a map-edge boundary is 2px deep**, hugging the inside of the
perimeter wall. Thin on purpose: the player should be genuinely at the edge of the map before one
fires, not a tile short of it. The depth of the region is not what decides how early the crossing
happens — `ThresholdBounds` is (§6), since it reaches 31px ahead of the player's origin going north
and roughly to their feet going south.

Thin regions are safe here, and it is worth saying why so nobody later "fixes" this by thickening
them: the detector is a 26×27 box, not a point. That box overlaps a 2px strip across ~29px of
travel — about nine physics ticks at the player's 200px/s — so there is no window in which it can
pass through between samples. A *point* detector against a 2px region would tunnel at these
speeds; a box cannot.

**Nothing stops two Thresholds on the same edge pointing at different destinations.** That is the
point.

---

## 5. The `Arrival` node

A plain `Marker2D`, placed in the destination area and named. `Threshold.arrival` names it.

**Position only.** An Arrival says where the player appears, not which way they face. `player.gd`
has no directional animation state to set — the sprite plays `idle` regardless of movement — so a
facing field would be a property nothing reads. It is picked up alongside walk animations
(§10 Phase 2).

```
Orchard (WorldArea)
├── Ground
├── ArrivalFromMeadowWest   (Marker2D)
├── ArrivalFromMeadowNorth  (Marker2D)
└── ThresholdToMeadow       (Threshold → meadow.tscn, arrival = &"ArrivalFromOrchard")
```

Resolution order in `world.gd`, carrying forward the validate-before-destroy lesson from the
existing implementation:

1. `load(destination)` and `instantiate()`.
2. Find the named `Arrival` in the new instance.
3. **Only if both succeed**, free the old area and swap.

A bad path or a missing/misnamed `Arrival` leaves the player exactly where they were, with a pushed
error. It must never strand them behind an opaque fade in an empty world — that bug was hit for
real under the previous design.

**Re-entry guard.** The old 0.5-tile arrival debounce is replaced by a simpler and more general
rule: **do not trigger a Threshold the player spawned into.** A Threshold that the player's
`ThresholdBounds` was already overlapping at the moment of arrival stays inert, and arms only once
that box has fully left it.

`world.gd` owns this, not `threshold.gd` — it is the only thing that knows the moment of arrival, and
keeping it there preserves §4's promise that a Threshold is nothing but its two exports. Concretely:
after placing the player on the Arrival, `world.gd` records which Thresholds in the new area are
overlapping, and ignores crossings from those until each reports the player has left.

This holds regardless of where a designer put the Arrival — including badly,
inside a Threshold — and needs no distance constant. A `@tool` warning when an `Arrival` overlaps a
`Threshold` in the same scene is a nice-to-have on top, not a substitute.

---

## 6. The player's `ThresholdBounds` collider

The player gains a second collider, used *only* for Threshold detection. It never touches world
geometry.

```
Player (CharacterBody2D)            collision_layer = player, mask = world
├── CollisionShape2D                the 22x10 movement capsule (unchanged)
├── ThresholdBounds (Area2D)        collision_layer = player_bounds, mask = 0
│   └── CollisionShape2D            RectangleShape2D, size (26, 27), position (0, -17.5)
├── AnimatedSprite2D
└── Camera2D
```

**Why (26, 27) at (0, -17.5):** that is the union of opaque pixels across *every frame of every
animation*, in the player's local space — `x ∈ [-13, 13]`, `y ∈ [-31, -4]`. Crossing a Threshold
when this box touches it means the transition fires as the art reaches the region, so the player's
sprite is never half-off-screen mid-walk.

**The size is authored, not derived — and this is deliberate.** The whole failure mode being
retired is *sprite art silently changing map geometry*. Here the direction of dependency is
reversed: the number lives in `player.tscn`, and a test asserts it still contains the art's union
bbox. If an artist redraws Cream Bun taller, a test fails and a human resizes one rectangle. Nothing
recomputes itself under the map.

**A new named physics layer.** `project.godot` gains
`2d_physics/layer_4="player_bounds"`. Reusing `player` would work — a Threshold could connect only
`area_entered` and ignore `body_entered` — but that makes correctness depend on which signal is
connected rather than on what the layers say. Naming the layer costs nothing (§11 of the
world-collision design makes the same argument for `interactable`).

**Known asymmetry, accepted for now.** The box reaches 31px above the origin and only 4px below.
Walking south it leads at roughly the feet; walking north it leads by 31px. For map edges this is
invisible — you approach an edge from one side. For an interior Threshold approached from several
sides (a pit), a region tuned for one direction fires early from another. See §10 Phase 2.

---

## 7. What `WorldArea` becomes

Nearly everything in `world_area.gd` exists to serve edge-derived transitions. With those gone, it
collapses to bounds and walls:

```gdscript
const TILE_SIZE, WORLD_LAYER_BIT, PERIMETER_WALL_THICKNESS_PX

func get_bounds_px() -> Rect2                 # unchanged
func build_perimeter_walls() -> void          # four identical walls, no branching
static func _edge_rect(edge, bounds) -> Rect2 # symmetric now — no north special case
func _add_perimeter_wall(name, rect) -> void  # unchanged
```

`build_perimeter_walls()` no longer takes an argument and no longer branches: **every edge always
gets a wall.** The wall is a backstop that guarantees the player cannot leave the painted floor.
Thresholds are inset from it, so a linked edge is crossed before the wall is ever reached.

**Walls stay automatic even though designers now paint edge terrain themselves (§8).** The two are
not redundant: painted terrain is a *framing* choice made per area to keep the character on screen,
while the perimeter wall is a *correctness* guarantee the rest of the system depends on.
`Camera2D.limit_*` is clamped to `get_bounds_px()` on the assumption that the player can never stand
outside it; without a wall, an area whose author forgot to paint an edge would let the player walk
into unpainted void with the camera pinned behind them. Making walls conditional would put that
guarantee in the hands of whoever painted the map last.

`get_bounds_px()` stays because the camera limits still need it.

**`area_id_from_scene_path()` does not survive as a `WorldArea` static.** `world.gd` still needs a
`StringName` id for `GameEvents.area_changed`, but with `WorldArea` reduced to bounds and walls the
function no longer has anything to do with the class it lived on. It becomes a private one-liner in
`world.gd`, next to its only caller.

---

## 8. Consequences for area authors

**The north edge clips the character by default.** The perimeter wall sits flush at the painted
edge, and `Camera2D.limit_top` clamps the view to that same line — so a player standing against a
north wall has the top of their sprite drawn outside the view. Designers fix this per area, by
either:

- painting impassable terrain a row or two in from the north edge, or
- placing a Threshold there, which fires before the art can leave the view, or
- accepting it, where the north edge is somewhere the player has no reason to stand.

This replaces a code rule with a content rule, deliberately. The old inset made the top rows of
*every* map a non-walkable backdrop whether the author wanted it or not, and tied the size of that
strip to the player's sprite. Now the author decides per area, and the failure mode when they forget
is obvious on screen rather than one pixel deep.

**A pit needs no collision.** Draw the hole, leave the floor non-solid, and put a Threshold inside
it drawn far enough in that the player is visually over the hole when it fires. There is no
"edge of the pit" to make solid and no geometry to line the trigger up with.

---

## 9. What this deletes

For the implementer's benefit, the full list — all from `world_area.gd` unless noted:

| Removed | Why it existed |
| --- | --- |
| `neighbour_north/east/south/west` | edge → destination mapping |
| `neighbour_for_edge()` | lookup for the above |
| `edge_reached` signal | replaced by `Threshold.area_entered` |
| `opposite_edge()` | which edge you enter from |
| `area_id_from_scene_path()` | moves to `world.gd` as a private helper, not deleted (§7) |
| `compute_entry_position()` | carried-over coordinate + clamp + offset |
| `_playable_boundary()` | shared "where does this edge begin" helper |
| `_linked_edge_rects()` | stub/trigger/stub corner split |
| `_add_edge_trigger()`, `_on_edge_trigger_body_entered()` | building/handling edge triggers |
| `_build_edge()`'s branch | linked vs unlinked |
| `north_headroom_inset()` | camera clipping fix |
| `is_debounce_armed()`, `begin_entry_debounce()`, `_physics_process()`, `_debounce_*` | arrival debounce |
| `CORNER_DEAD_ZONE_PX`, `ENTRY_OFFSET_EAST_WEST_PX`, `ENTRY_OFFSET_NORTH_SOUTH_PX`, `DEBOUNCE_EAST_WEST_PX`, `DEBOUNCE_NORTH_SOUTH_PX` | constants for the above |
| `Player.get_visual_extent()` (player.gd) | fed the inset derivation |
| `World._north_headroom_inset()` (world.gd) | wired art to map geometry |

Roughly 46 tests across `test_edge_triggers.gd`, `test_area_transition.gd`, and
`test_world_area_edge_transition.gd` retire or are rewritten against the new mechanism.
`test_collision_geometry_invariants.gd` keeps its collider-shape and terrain checks and loses its
inset checks; it gains the `ThresholdBounds`-covers-the-art assertion from §6.

---

## 10. Phasing

**Phase 1 — the mechanism, at parity.** `Threshold` and `Arrival` scenes; `ThresholdBounds` on the
player; unconditional perimeter walls; `world.gd` driving the same freeze → fade → swap → place →
reveal sequence off `Threshold.area_entered`. Migrate `meadow.tscn` and `orchard.tscn` from their
`neighbour_*` slots to placed Thresholds and Arrivals. Delete everything in §9. **Playable and
testable end state: the existing two-way meadow ↔ orchard link works exactly as it does today.**

**Phase 2 — the things this unlocks.** Named, not vague:

1. **Pits.** Non-solid floor plus an interior Threshold. Needs the direction-asymmetry question in
   §6 answered — most likely by giving the player a second, feet-sized detection area on its own
   layer, so a Threshold masks whichever it wants.
2. **Multiple exits per edge.** Free, mechanically; needs no code. Listed so it is not forgotten as
   a thing to actually build content for.
3. **Transition styles.** A `Threshold` gains an export declaring how its crossing looks — fade
   (today), a fall for pits, a slide for open edges. The sequence in `world.gd` is already the seam
   for this. Deliberately not added in Phase 1 (§4): one style is not a choice.
4. **Arrival facing.** An `Arrival` gains a direction so the player exits a doorway facing sensibly
   rather than in whatever pose they arrived in. Blocked on `player.gd` having directional
   animation state at all — it currently plays `idle` no matter which way you walk — so this lands
   with walk animations, not before (§5).
5. **Per-edge authoring convenience.** If placing a Threshold per map edge proves tedious across
   many areas, the answer is an *editor* helper that creates and positions the node — not a runtime
   `neighbour_*` path back into derived geometry (§11).

---

## 11. Alternatives considered and rejected

**Keep `neighbour_*` as sugar that auto-generates a full-edge Threshold.** Tempting — it keeps the
common grid case to one line. Rejected: it preserves two code paths for one concept, and the
generated path is precisely the edge-derived geometry this design exists to delete. If placing a
Threshold per edge proves genuinely tedious in practice, revisit it as an *editor* convenience (a
button that creates and positions the node) rather than a runtime mechanism.

**Keep the north headroom inset.** Rejected: it is the only thing that makes map geometry depend on
sprite art, and it buys a guarantee designers can achieve themselves with a row of terrain. See §8.

**Give the player the feet-sized detection area now, alongside the art-sized one.** Rejected as
premature. Nothing in Phase 1 needs it; the asymmetry it solves only bites on interior Thresholds,
which do not exist yet. Named in §10 Phase 2 rather than built speculatively.

**Derive `ThresholdBounds` from the sprite at runtime.** Rejected for the reason the whole design
exists — see §6. Authored value, asserted by test.

**Spawn at a computed offset from the Threshold instead of a named `Arrival`.** Rejected: it
reintroduces spawn arithmetic, and it cannot express "you fall into the pit and land by the door,"
which is the entire point of separating the two ends of a link.
