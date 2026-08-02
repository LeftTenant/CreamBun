---
name: gotcha-test-subresource-mutation-leak
description: A test that mutates a scene's [sub_resource] in place leaks process-wide for the whole run; add_child_autofree does not undo it, and "sized per placement" template scenes need resource_local_to_scene
metadata:
  type: project
---

`PackedScene.instantiate()` does **not** copy embedded `[sub_resource]` resources. Every
instantiation of a `.tscn` in a process hands back the **same** `RectangleShape2D` /
`StyleBox` / etc. object, because `load()` also caches the `PackedScene` itself. Verified in
Godot 4.6.2: two `instantiate()` calls on the same scene return `shape_a == shape_b` → `true`,
and mutating one is visible in the next instance. Setting `resource_local_to_scene = true` on
the sub-resource flips this — each `instantiate()` then gets its own copy (verified: `a == b`
→ `false`, mutating `a` leaves `b.size` untouched).

**Why it matters — two distinct failure modes:**

1. **Test-side leak.** A GUT helper that does
   `(cs.shape as RectangleShape2D).size = Vector2(64, 64)` to give a placeholder collider a
   usable size has just resized that shape for **every later test in the same run** that
   instantiates the scene. `add_child_autofree()` frees the *node*, not the resource — the
   resource lives in the ResourceLoader cache until the process exits. The on-disk `.tscn` is
   untouched (`CACHE_MODE_IGNORE` still reads the authored value), so nothing shows in `git
   status` and the suite stays green *until* someone adds an assertion about the authored
   placeholder value — which then passes or fails depending on test file order.
   **Fix:** assign a fresh resource (`cs.shape = RectangleShape2D.new()`) instead of mutating
   the loaded one. Treat any in-place write to a resource reached through `load(...)
   .instantiate()` as cross-test global state.

2. **Authoring-side trap in "designer sizes it per placement" template scenes.** A `.tscn`
   meant to be dragged into many scenes and resized individually cannot ship a plain
   `[sub_resource]` shape: two placements share one shape object, so sizing the second
   resizes the first and dirties the template. The codebase's own precedent is
   `world/props/shared/world_prop.gd`, which allocates `RectangleShape2D.new()` per instance
   from an exported `footprint` for exactly this reason. `resource_local_to_scene = true` is
   the lighter-weight alternative. Singleton scenes instanced once (e.g. `player.tscn`) are
   unaffected — the distinction is multi-instance template vs. one-off.

**How to apply:** when reviewing a new placeable `.tscn` that ships a collider/style
sub-resource a designer is expected to tune per placement, check for
`resource_local_to_scene = true` (or per-instance allocation in script). When reviewing a test
helper that "sizes" a loaded scene, check it assigns rather than mutates.

## Related

[[CreamBun Code Patterns]] — the `@tool`-side statement of the same sharing rule.
[[testing-conventions]] — where scene-as-data and physics-overlap tests live.
