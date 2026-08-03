---
name: gotcha-find-child-owned-flag
description: Node.find_child(..., owned=true) prunes the ENTIRE subtree under any owner-less node, so descendants of a runtime-instanced scene are invisible unless owned=false
metadata:
  type: project
---

`Node.find_child(pattern, recursive := true, owned := true)` does **not** merely filter
out owner-less nodes — it stops recursing into them. A node instantiated from script
(`PackedScene.instantiate()` + `add_child()`) has `owner == null`, so with the default
`owned = true` **every descendant of that instance is unreachable**, even though those
descendants each have a non-null `owner` (the instance root).

**Verified** (Godot 4.6, `world/world.tscn` after the WorldArea shell split): with the
meadow area instanced at runtime under `ActiveArea`,
`world.find_child("Ground", true, true)` and `world.find_child("Player", true, true)`
both return `null`; the same calls with `owned = false` resolve correctly.

**Why it matters:** a test that searches a scene tree spanning a runtime-instanced
sub-scene must pass `owned = false` explicitly. Getting it wrong yields `null`, which
usually surfaces as a confusing "scene should contain a node named X" failure rather than
anything pointing at the owner flag.

**A related fact from the same probe:** `Node.reparent()` *preserves* `owner` when the old
owner is an ancestor of the new parent (`preserve_owner` in the engine), so a reparented
node keeps `owner == <original scene root>` — it is the owner-less *instance root* in the
middle of the chain that breaks the search, not the reparented node itself.

**How to apply:**
- Reviewing a `find_child` call in a test: confirm the third argument is `false` whenever
  the target may live under a script-instanced scene. `find_child(name, true)` (two args)
  silently defaults to `owned = true`.
- A `get_node_or_null("Child")` direct-child lookup in an older test is the *other* half of
  this: it breaks the moment a scene restructure moves the node one level deeper. Swapping
  it for `find_child(name, true, false)` is a pure lookup-mechanism fix, not a weakened
  assertion — but check that the assertion text and the assertions themselves are untouched.

## `find_children`'s `type` filter DOES understand `class_name` — `owned` is the real culprit

**Verified, Godot 4.6.2.** A `class_name Threshold extends Area2D` node added at runtime
(`add_child()`, no `set_owner()`) under a plain `Node2D`:

| call | result |
|---|---|
| `find_children("*", "Threshold", true, false)` | **1** — found |
| `find_children("*", "Threshold", true, true)`  | **0** — missed |

So `find_children`'s `type` argument resolves scripted global class names fine. The *only* reason a
scripted-class search "silently matches nothing" is the `owned` default above. Treat any comment or
memory claiming "`type` is checked with `is_class()`, which only knows native engine classes" as
**false** — a hand-rolled recursive `if child is X` walk is still defensible (it returns a properly
typed `Array[X]`, which `find_children` does not), but not for that reason.

**Review lesson:** when a diff's comment states an *engine behaviour* as the justification for a
hand-rolled workaround, probe the behaviour before passing it. A wrong engine fact written into a
doc comment propagates — it gets copied into the next slice's rationale and into agent memory.

## Related

[[testing-conventions]] — GUT conventions and scene-instantiation facts.
[[CreamBun Code Patterns]] — general Godot/GDScript engine facts.
[[gotcha-gut-helper-silent-passes]] — the other family of "the search returned nothing and nobody
noticed" failures.
