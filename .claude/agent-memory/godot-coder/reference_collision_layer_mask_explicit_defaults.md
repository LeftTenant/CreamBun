---
name: reference-collision-layer-mask-explicit-defaults
description: Godot's engine default collision_mask=1 numerically coincides with the "world" physics layer bit — set collision_layer/mask explicitly in .tscn for runtime clarity, but know Godot strips a written value that matches the class default on next save.
type: reference
---

Godot's `CollisionObject2D` engine defaults are `collision_layer = 1` and
`collision_mask = 1` (bit 0 only). In CreamBun's world-collision layer scheme
(project.godot `[layer_names]`, see `docs/features/world-collision/design.md`
§11), layer bit 0 happens to be named "world". That means a body relying on
the unset engine default will numerically match "collides with world" purely
by coincidence.

**Correction (verified 2026-07-25):** writing `collision_mask = 1` explicitly
into a `.tscn` does NOT durably "preserve intent in source control" the way
it first appears to. Godot's scene serializer only writes properties that
differ from the class default — since `collision_mask`'s class default is
already `1`, an explicit `collision_mask = 1` line is silently dropped the
next time the editor re-saves the scene (e.g. any unrelated edit-and-save in
the inspector). So there is no lasting diff to point to; the line is only
present until the next editor save touches that node. The *runtime* value is
still correct either way (1 = world layer), but don't rely on the .tscn text
as the durable record of intent.

**Why it matters:** if the layer numbering is ever reshuffled (a new layer
inserted before "world", or `[layer_names]` reordered), a node relying on
the default value (whether or not it was ever written explicitly) silently
collides with the wrong layer, and the .tscn gives no reliable signal either
way once the editor has re-saved it.

**How to apply:** setting `collision_layer`/`collision_mask` explicitly when
authoring a `.tscn` node is still good practice for a human reading that one
save of the file, and costs nothing. But treat the actual source of truth for
"this value is intentional, not a coincidence" as the test suite — e.g.
`tests/integration/player/test_player_scene.gd`'s
`test_collision_mask_is_world_only`, whose assertion and comment spell out
*why* the value must be `WORLD_LAYER_BIT` regardless of what the engine
default happens to be. A test survives editor re-saves; a default-matching
`.tscn` line does not.
