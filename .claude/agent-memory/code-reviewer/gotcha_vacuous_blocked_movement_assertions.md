---
name: gotcha-vacuous-blocked-movement-assertions
description: "Blocked-by-collision" tests pass vacuously when the probe never moves — always demand a lower bound on travel, and check how the body is actually driven
metadata:
  type: project
---

Any test whose thesis is "this collider **stopped** the body" is one-sided: it asserts an
*upper* bound on travel (`traveled < unobstructed * 0.5`, `final_y < obstacle_y`, …), and
**every such assertion is satisfied by a body that never moved at all**. That is not
hypothetical — it has already shipped once in this repo.

**Why:** the two ways a movement probe silently fails to move are easy to introduce and
invisible in a green suite:

- **GUT's `simulate(obj, ticks, delta)` does not step the physics server.** It loops calling
  `obj._physics_process(delta)` and only if `obj.has_method("_physics_process")` — which is
  true only for a *scripted* override. A bare `CharacterBody2D.new()` probe with no script
  never moves under `simulate()`, forever. `player.tscn` works because `player.gd` has a real
  `_physics_process` that calls `move_and_slide()`. For a scriptless probe the correct driver
  is a manual per-tick loop: set `probe.velocity` then call `probe.move_and_slide()` directly
  (`move_and_slide()` always advances by the engine's real physics delta, so the
  "unobstructed" figure must be `speed * ticks / Engine.physics_ticks_per_second`).
- The body is positioned outside the corridor, mask/layer don't intersect, `_ready()` never
  ran, etc.

**How to apply — when reviewing any collision/movement test:**

1. Require a **lower bound as well as an upper bound** on the blocked case, e.g.
   `assert_between(traveled_px, expected - tol, expected + tol)` or at minimum
   `assert_gt(traveled_px, 0.0)`. The expected stop distance is computable by hand:
   `approach_offset - (obstacle_near_edge_offset + probe_half_depth)`.
2. Confirm the paired "should NOT be blocked" test exists in the same file — it is the only
   assertion shape that *inherently* catches a motionless probe, and it is what exposed the
   `simulate()` bug. A blocked-only test file has no such safety net.
3. Prove it empirically rather than by reading: drop a throwaway
   `tests/**/test_zzz_probe_tmp.gd` that runs the same driver and `gut.p()`s the actual
   `traveled_px`, plus a variant with the collider `queue_free()`d. Run with `-gselect=`,
   read the numbers, delete the file. A correct blocked case prints a specific
   nonzero-but-limited number; the collider-removed variant must print the full unobstructed
   distance.

**Same family: `assert_signal_not_emitted()` as a stand-in for containment.** A test whose
thesis is "standing here must NOT trigger X" is satisfied *both* by "the player was blocked
before reaching the trigger" and by "the player walked clean through the hole where the trigger
isn't and off the map." Proven by mutation on `world_area.gd`: deleting the linked-edge corner
stubs (reopening the exact escape bug slice 10 shipped a fix for) leaves
`test_player_near_east_edge_corner_does_not_trigger_edge_reached` **green** — only the separate
*geometric* rect assertions in `test_edge_triggers.gd` catch it. Pair every
`assert_signal_not_emitted` containment test with an explicit position bound
(`assert_lt(player.global_position.x, bounds.end.x + slack)`) so the behavioural symptom, not
just the geometry that causes it, is regression-guarded.

## Related

[[testing-conventions]] — the "clear corridor must span the whole travel window" rule for
map-driven movement tests; same family of silent-pass failure.
[[gotcha-perimeter-corner-gap-test-inert]] — the corner-closure check shape that actually fails when it should.
