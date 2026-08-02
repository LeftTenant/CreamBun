---
name: gotcha-resource-local-to-scene-for-template-shapes
description: A .tscn meant to be instanced many times and resized per-placement (a designer-dragged Area2D/collider template) must mark its sub_resource shape resource_local_to_scene=true, or every instance shares and resizes the same shape
metadata:
  type: project
---

`PackedScene.instantiate()` does **not** deep-copy embedded `[sub_resource]`s — every instance
gets the *same* `RectangleShape2D`/`StyleBox`/etc. object, and `load()` caches the `PackedScene`
itself, so this holds across the whole process, not just within one scene tree. For a template
scene a designer drags in and resizes per placement (e.g. `world/thresholds/threshold.tscn`),
this means resizing one instance resizes every other instance and dirties the on-disk template.

**Fix, authoring-side:** add `resource_local_to_scene = true` on the `[sub_resource]` block in
the `.tscn` — each `instantiate()` then gets its own copy. This is the declarative counterpart
to `world/props/shared/world_prop.gd`'s code-side fix (`RectangleShape2D.new()` per instance from
an exported `footprint`); use the `.tscn` flag when there's no generation code yet, the code-side
allocation when there already is.

**Fix, test-side:** a GUT helper that "sizes" a loaded template's shape must assign a fresh
resource (`collision.shape = RectangleShape2D.new(); shape.size = ...`), never mutate
`collision.shape.size` in place — `add_child_autofree()` only frees the *node*, not the shared
`Resource`, so an in-place mutation leaks into every later instantiation of that scene for the
rest of the test process (silent until some other test asserts on the "authored" placeholder
value, then flaky depending on file run order).

**How to apply:** whenever adding a new placeable `.tscn` with a collider/shape a designer tunes
per placement, set `resource_local_to_scene = true` on that sub-resource up front. When writing
or reviewing a test that resizes a loaded scene's shape, check it assigns rather than mutates.

See also code-reviewer's more detailed memory on the same pattern (`gotcha-test-subresource-mutation-leak` in `.claude/agent-memory/code-reviewer/`).
