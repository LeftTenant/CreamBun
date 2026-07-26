---
name: gotcha-tscn-default-valued-props
description: Godot drops .tscn properties whose value equals the class default on editor re-save — e.g. collision_mask=1 vanishes; such lines cannot document intent
metadata:
  type: project
---

A `.tscn` cannot durably record a property set to its **class default value**. Godot's
`PackedScene.pack()` only serializes properties that differ from the node class's default,
so the line disappears the first time anyone opens and saves the scene in the editor.

**Verified** (Godot 4.6, `player/player.tscn`): a pack → `ResourceSaver.save()` round-trip
kept `collision_layer = 2` and `AnimatedSprite2D.offset = Vector2(0, -16)` but **dropped
`collision_mask = 1`**, because `CollisionObject2D.collision_mask` defaults to 1.

**The same rule applies to `@export` vars, compared against the *script's* default.** Verified
(Godot 4.6, `world/props/boulder.tscn`): a pack round-trip dropped `footprint = Vector2i(1, 1)`,
because `world_prop.gd` declares `@export var footprint: Vector2i = Vector2i.ONE`. A designer
opening and saving that scene loses the authored line even though the slice spec names the value
explicitly. Note that plain `ResourceSaver.save(load(path))` does **not** reproduce this — it
resaves the stored bundle verbatim. To see what the editor would write, instantiate, `add_child`,
then `PackedScene.new().pack(instance)` and save that.

**Why it matters:**
- Writing such a line "to document intent" does not work — the intent evaporates on the next
  editor save, and a test asserting the runtime value (`collision_mask == 1`) still passes, so
  nothing flags the loss.
- The reverse also matters for review: a diff that *removes* a default-valued property line is
  editor normalization, not a regression. Don't flag it as [[gotcha-tscn-editor-drift]].

**How to apply:**
- CreamBun's physics layer 1 is `world`, whose bit value (1) coincides with the engine default
  `collision_mask`. Any node that "collides with world only" therefore looks correct even if it
  was never configured — assert it in a test *and* explain the intent in the test's comment,
  which is the only durable home.
- Non-default values (`collision_layer = 2` for `player`, sprite offsets, sizes) do persist and
  are safe to rely on in `.tscn`.

## Related

[[gotcha-tscn-editor-drift]] — the opposite failure mode: the editor *adding* stray props.
[[testing-conventions]] — where scene-as-data assertions live.
