---
name: gotcha-queue-free-deferred-removal
description: queue_free() doesn't detach a node from its parent synchronously — a same-frame replacement child sees a stale sibling
type: reference
---

`Node.queue_free()` only *marks* a node for deletion; the node stays in the tree (and stays a
child of its parent) until the end of the current frame. If you free an old node and, in the same
function, immediately `add_child()` a replacement onto the SAME parent, that parent has TWO
children for the rest of the frame — the stale outgoing one is still `get_child(0)`.

**Why this matters:** any code that reads `parent.get_child(0)` (or `get_child_count()`) between
the `queue_free()` call and the end of the frame sees the wrong node. This bit the world-collision
area-transition sequence (`world/world.gd`'s `_on_edge_reached()`): a signal listener connected
directly to `GameEvents.area_changed` (fired synchronously right after the swap) snapshotted
`ActiveArea.get_child(0)` expecting the new area, and got the still-present old one instead,
because `area.queue_free()` had been called but not yet resolved.

**How to apply:** when replacing a child under the same parent within one function/frame, call
`parent.remove_child(old_node)` (synchronous) *before* `old_node.queue_free()`, and before adding
the new child. Reserve plain `queue_free()` for "this can go away whenever the engine gets to it"
cases where no code will inspect the parent's children before the frame ends.
