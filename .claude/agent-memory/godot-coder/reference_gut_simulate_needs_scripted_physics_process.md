---
name: gut-simulate-needs-scripted-physics-process
description: GUT's simulate() only drives an object if it has a scripted _physics_process/_process; a bare CharacterBody2D.new() with no script never moves under it
type: reference
---

GUT's `simulate(obj, times, delta)` (test.gd / gut_to_move.gd) does **not** step the physics
server — it just loops `times` times calling `obj._process(delta)` / `obj._physics_process(delta)`
directly, and only if `obj.has_method(...)` is true. A bare engine node with no attached script
(e.g. `var probe := CharacterBody2D.new()`) has no GDScript-level `_physics_process`, so
`has_method("_physics_process")` is false and `simulate()` silently does nothing to it each tick —
setting `.velocity` on such a probe and calling `simulate()` produces zero real movement, forever,
regardless of collisions.

This is easy to miss because a "should be blocked" assertion (expects small/no travel) passes
*vacuously* when the probe never moves at all — only a "should NOT be blocked, expects real
travel" assertion actually exposes the bug (it reads as the collider being wrongly oversized when
the real problem is the probe never moved in the first place).

**Why:** `move_and_slide()` is not auto-invoked by the physics server for `CharacterBody2D` the way
`RigidBody2D` integrates velocity automatically — something has to call it every physics tick.
`simulate()` provides that "something" only when the target object has a real script override.
`tests/integration/world/test_solids_collision.gd`'s `_drive_player_right_toward()` works
correctly because it drives the real `Player` instance, whose `player.gd` has its own
`_physics_process` calling `move_and_slide()` — `simulate()` calls into that. A hand-built
scriptless probe has no such hook.

**How to apply:** When a GUT test drives a bare `CharacterBody2D`/`RigidBody2D` probe (not a real
scened instance with its own script) via `.velocity` + `simulate()`, replace the `simulate()` call
with a manual loop that calls `probe.move_and_slide()` itself each tick:
```gdscript
for _tick in range(SIMULATION_TICKS):
    probe.velocity = velocity
    probe.move_and_slide()
```
Only use GUT's `simulate()` unmodified when driving a node that genuinely has a scripted
`_physics_process` (a real scene instance, e.g. `Player`).
