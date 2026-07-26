---
name: gotcha-tool-ready-writes-serialize
description: A @tool script's _ready() writes on an instance ROOT get baked into the placing .tscn on editor save; writes to the instance's children never are
metadata:
  type: project
---

When a `@tool` script runs `_ready()` in the editor, whatever it assigns to the node
is dirty state that the editor **serializes into the scene that placed the instance**
— but only for properties on the **instance root**. Property writes to the instance's
own *children* are never stored, because children of a non-`editable_instance` node
carry no override block.

**Verified** (Godot 4.6, `world/props/shared/world_prop.gd` placed in
`world/areas/meadow.tscn`). `_ready()` sets `collision_layer`, `collision_mask`, and
rebuilds `$CollisionShape2D.shape` / `.position`. After an editor save (and confirmed
by an instantiate → `add_child` → `PackedScene.pack()` round-trip):

| written by `_ready()` | serialized into meadow.tscn? | why |
| --- | --- | --- |
| `collision_mask = 0` on the root | **yes** | differs from `StaticBody2D`'s default of 1 |
| `collision_layer = 1` on the root | no | equals the class default (see [[gotcha-tscn-default-valued-props]]) |
| `$CollisionShape2D.shape` / `.position` | no | child of an instance, no override block emitted |

**Why it matters:** the serialized line is *behaviourally* harmless — the script's
`_ready()` re-runs at load and unconditionally overwrites it, so it can never drift
into a wrong runtime value. The hazards are the other two kinds:
- **Silently-ineffective inspector edit.** A designer who changes that property on the
  placed instance sees their value stored in the `.tscn` and then overwritten at runtime.
  Contrast an `@export` like `footprint`, which *is* honoured.
- **It invites deletion of the real source of truth.** The `.tscn` line makes the script's
  assignment look redundant; removing it silently changes every *future* instance.

**How to apply:**
- Don't flag such a line as unexplained editor drift — check whether an `@tool` `_ready()`
  in the instanced scene's script writes it, and confirm the runtime end-state is unchanged
  by instantiating the scene in a probe test and printing pre-/post-`_ready()` values.
- To stop the noise at source, gate the invariant writes on
  `if not Engine.is_editor_hint():` and leave the genuinely editor-useful work (collider
  rebuilds, previews) ungated. `Engine.is_editor_hint()` is `false` under
  `godot --headless -s`, so GUT assertions on the runtime values still hold.
- Whichever way it lands, the script comment is the only durable home for the intent.

## Related

[[gotcha-tscn-default-valued-props]] — the companion rule about default-valued props.
[[gotcha-tscn-editor-drift]] — the "is this .tscn hunk intentional?" checklist.
