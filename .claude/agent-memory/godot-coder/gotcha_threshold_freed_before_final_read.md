---
name: gotcha-threshold-freed-before-final-read
description: reading an Area2D/Node's exported properties late in a long multi-await coroutine after queue_free() was called on it/its parent is a use-after-free
type: reference
---

In an async transition sequence (freeze → fade → swap → place → reveal, world.gd's threshold and
edge-transition handlers), a trigger node's own exported data (e.g. `Threshold.destination`,
`Threshold.arrival`) must be captured into local variables BEFORE the node's parent area is
`queue_free()`'d — not re-read from the node at the end of the function to build the final
`GameEvents.area_changed` payload.

**Why:** `queue_free()` only *schedules* removal — the node stays valid until the end of the current
frame. In a coroutine with several subsequent `await`s (a fade tween over ~0.3s, a couple of
`await get_tree().physics_frame` for a re-entry guard), enough real frames elapse that the deferred
free actually happens before the function's tail runs. Godot then reports
`Invalid access to property or key '<x>' on a base object of type 'previously freed'` — a runtime
error, not a compile error, so it only surfaces under test/at runtime, and it silently aborts the
rest of the coroutine (so a symptom seen elsewhere is "GameEvents.area_changed never fired" with no
obvious connection to the real cause).

**How to apply:** any handler that (a) reads data off a node, (b) frees that node or an ancestor of
it, then (c) later reads from the same node reference again — capture the needed values into local
`var`s at step (a), before step (b). Grep for the pattern "read a signal-bound node's properties
after this function's own `queue_free()`/`remove_child()` call" when reviewing async transition code.
