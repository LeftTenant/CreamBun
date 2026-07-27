---
name: reference-export-file-vs-packedscene-cyclic-neighbours
description: two scenes that reference each other via @export PackedScene deadlock Godot's loader — use @export_file(String) + load() at use time instead
type: reference
---

If two scenes need to hold a *mutual* reference to each other (e.g. `WorldArea.neighbour_east`/
`neighbour_west` on adjacent areas, `world/areas/shared/world_area.gd`), do **not** declare that
slot as `@export var neighbour: PackedScene`. Godot's resource loader eagerly loads every
`ext_resource` a scene declares as part of loading the scene itself. If scene A's saved
`ext_resource` list includes scene B, and B's own saved list includes A, loading either one
recurses into a genuine cycle the text-scene loader has no re-entrant support for — it fails with
`Parse Error: [ext_resource] referenced non-existent resource`, because the outer load hasn't
finished registering itself yet when the inner reference tries to resolve. This is a real engine
limitation (confirmed empirically), not a hand-authoring mistake, and it breaks on the *second*
link direction the moment two real areas point back at each other — the normal case for a linked
world, not an edge case.

**Fix:** declare the slot as `@export_file("*.tscn") var neighbour: String = ""` instead. A path
string has no resource reference for the loader to eagerly resolve — nothing to form a cycle with.
The Inspector still gives a file-picker button, so the designer-facing workflow ("drag/pick the
neighbour scene") is unchanged. The consuming code calls `load(path)` on it at the point of actual
use (e.g. at transition time in `world/world.gd`), not held live. An empty string is the "unset"
sentinel (test for `.is_empty()`, not `== null`).

**Don't work around this with a `_ready()` load() override on one side instead** (tried and
reverted during this feature) — it only patches the *symptom* on whichever one link direction you
happen to override, still leaves the export typed as `PackedScene` (so every *other* future
two-way link hits the same deadlock), and adds an asymmetric, easy-to-forget subclass just to
route around a loader limitation. Fix the export type once at the base class instead.
