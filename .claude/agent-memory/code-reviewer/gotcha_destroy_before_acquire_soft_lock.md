---
name: gotcha-destroy-before-acquire-soft-lock
description: In a scene-swap sequence behind a fade/freeze, acquire and validate the replacement BEFORE tearing down the current one — a late null-guard is a soft-lock, not a guard
metadata:
  type: project
---

Any sequence that (a) freezes input or covers the screen, (b) destroys live state, and (c) builds
its replacement must **acquire and validate the replacement first**. A null-check placed after the
teardown is not a recoverable error path — it is a soft-lock behind whatever the freeze/cover step
put up. `world.gd`'s `_on_edge_reached()` is the worked example: `_load_neighbour_area()`
(`load()` + `.instantiate() as WorldArea`) runs while the old area is still fully live and the
player is still its child, so a bad `neighbour_*` path just fades back to transparent, restores
`GameState.PLAYING`, and returns with nothing moved.

**Why:** this codebase hit the same bug twice in a row on the same function — the first fix added
a null-guard, but left it after the reparent-out + `remove_child` + `queue_free`, so the "guard"
fired into an empty tree with the player stranded behind an opaque `ColorRect` and no area at all.
Reviewing the guard's *existence* is not enough; its *position in the sequence* is the whole
finding.

**How to apply:**

- When reviewing a swap/teleport/level-load, read the sequence in order and mark the point of no
  return (the first destructive call). Every `null`/failure check must sit strictly before it.
- Watch for the destructive trio in particular: `reparent()` away from the outgoing node,
  `remove_child()`, `queue_free()`. Note also that `queue_free()` alone does **not** detach — an
  explicit `remove_child()` first is what stops the old and new nodes coexisting for a frame.
- Don't accept it from reading the code. Probe it: point a path export at a nonexistent scene,
  drive the trigger in a throwaway GUT test, and assert the *recovered* state — original area
  still the active child, player still parented into it, fade alpha back to 0, state back to
  `PLAYING`, and the player still able to walk. All five, because the first four can hold while
  input stays dead. (GUT reports the deliberate `push_error` as an "Unexpected Errors" failure —
  read the `Asserts n/m` line, not the pass/fail flag.)

## Related

[[gotcha-open-edge-trigger-corner-gaps]] — the other recurring failure shape in this transition
code.
