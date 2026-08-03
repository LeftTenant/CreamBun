---
name: reference-find-children-owned-default-prunes-runtime-nodes
description: Node.find_children()'s owned parameter defaults to true and silently prunes runtime-added, owner-less nodes — not a class_name/is_class() problem
type: reference
---

`Node.find_children(pattern, type, recursive, owned)`'s `type` filter DOES correctly match a
scripted `class_name` — confirmed by direct probe: `area.find_children("*", "Threshold", true,
false)` finds a runtime-added `Threshold` (`class_name Threshold extends Area2D`) just fine. (An
earlier version of this memory claimed `is_class()` only understands native classes and would
silently miss `class_name` types — that claim was wrong and has been corrected here; do not repeat
it.)

The real trap is the **`owned` parameter's default of `true`**: a node added at runtime via
`add_child()` without an explicit `set_owner()` call has no owner, so `find_children`/`find_child`
silently miss it unless `owned: false` is passed explicitly. Test fixtures that inject nodes at
runtime (`area.add_child(threshold_instance)`) always fall into this case — this is exactly the
"proof strategy" pattern World Thresholds' integration tests use (inject a `Threshold` as a runtime
child of an already-instantiated area).

**How to apply:** when searching a subtree for runtime-injected or otherwise owner-less nodes, pass
`owned: false` explicitly to `find_children`/`find_child`. A manual recursive walk using GDScript's
`is` operator (`if child is Threshold: ...`) sidesteps the `owned` trap entirely AND is the only way
to get back a properly-typed `Array[Threshold]` (`find_children` always returns a plain
`Array[Node]`) — prefer the manual walk when the caller wants a typed result, not just to work
around `owned`. Seen in `world/world.gd`'s `_find_thresholds()` (World Thresholds Slice 3).
