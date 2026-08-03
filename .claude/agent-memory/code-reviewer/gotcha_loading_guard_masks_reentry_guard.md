---
name: gotcha-loading-guard-masks-reentry-guard
description: world.gd's GameState==LOADING guard swallows the spawned-into Threshold's area_entered, making the ignore-set guard untestable and too late to stand alone; plus the exact physics_frame emission order, and how bracketing a startup coroutine in LOADING leaks that autoload flag if the node is freed mid-await
metadata:
  type: project
---

`world.gd` runs a transition as a coroutine that sets `GameState.current_state = LOADING`
synchronously and only restores `PLAYING` after the reveal fade. Nothing in this project pauses the
`SceneTree` for `LOADING` (`game_state.gd` only sets a variable; `player.gd` polls it), so **physics
and Area2D overlap detection keep running for the whole frozen window**.

Consequence: when the player is placed on an `Arrival` that overlaps a `Threshold`, that
`Threshold`'s `area_entered` fires on the very next physics step — still inside the `LOADING`
window — and the `LOADING` early-return already discards it. `Area2D` only re-emits `area_entered`
on a clear→overlapping transition, so no further signal ever arrives while the player stands there.

**Therefore the separate per-Threshold ignore set (design §5's re-entry guard: `_ignored_thresholds`,
`_ignore_threshold()`, `_arm_reentry_guards()`, `_on_ignored_threshold_exited()`) has no observable
effect under the current ordering.** Verified by mutation: neutering `_ignore_threshold()` to a
no-op left `test_threshold_transition.gd` at **22/22 passing**, including
`test_arrival_overlapping_a_threshold_does_not_fire_on_arrival` and
`test_leaving_and_re_entering_an_overlapping_threshold_fires_normally`.

**Why:** two guards in series where the outer one is unconditional make the inner one untestable
through the public sequence. The inner guard is not useless — it is the thing that keeps the
behaviour correct if the fade duration ever goes to zero, if `PLAYING` is restored earlier, or if
overlap detection is ever deferred — but a test suite cannot tell the two apart from outside.

**How to apply:**
- Any test named for the re-entry/ignore-set guard must be mutation-checked (neuter the ignore set,
  re-run) before you accept it as coverage. If it still passes, say so — the honest options are a
  targeted test that drives `_on_threshold_entered()` directly with `GameState` forced to `PLAYING`,
  or a comment on the ignore set stating it is defence-in-depth that the sequence's own ordering
  currently makes unreachable.
- The same shape recurs whenever a coroutine sets a global "busy" flag first and then adds a
  narrower guard later in the same sequence. Ask which guard actually fires.

## The guard also arms too late to stand on its own

`_arm_reentry_guards()` `await`s **two** `get_tree().physics_frame`s before querying
`get_overlapping_areas()` — necessary, because Area2D pairs are recomputed once per physics step and
a query issued right after a `global_position` write still sees the pre-move state. But the
`area_entered` it is trying to pre-empt is emitted by that *same* recompute.

**Probe (Godot 4.6.2, headless):** add an `Area2D` overlapping a `Threshold` in one frame, connect
`area_entered`, and start a coroutine that awaits two `physics_frame`s then queries overlap. Result:
`area_entered` fires **once, before** the coroutine resumes; the coroutine then correctly reports
the overlap. So the signal always wins the race.

Consequence: an "arm the guard on arrival" scheme is *only* effective while some other,
synchronously-set flag (here `GameState == LOADING`) covers the two-frame window. On any code path
that arms guards **without** setting that flag first — e.g. a startup/`_ready()` path, where
`GameState.current_state` would otherwise still be its `PLAYING` default
(`autoloads/game_state.gd`) — the guard provides no protection at all, and worse, its coroutine can
resume holding a reference to an area that the transition it failed to prevent has already
`queue_free()`d. `world.gd`'s startup path therefore holds `LOADING` across its own
`_arm_reentry_guards()` call for exactly this reason; verify any *new* arming call site does the
same.

**How to apply:** when you see `await ...physics_frame` before a guard is armed, ask what protects
the window. If the answer is "nothing on this path", the guard is decorative there — the fix is to
set the busy flag for the duration (mirroring the covered path) or to suppress at the handler using
state that is known synchronously, not to add more frames of waiting. Reject doc comments that claim
such a call "closes the gap" without naming the flag that covers the window.

**Exact frame ordering (measured, Godot 4.6.2 headless).** `SceneTree` emits `physics_frame` at the
*start* of a physics iteration, **before** node `_physics_process` callbacks and before the Area2D
overlap flush. So for a coroutine started outside `_physics_process` that awaits two
`physics_frame`s: resume #1 happens at the top of frame 1, `area_entered` fires later in frame 1's
flush, resume #2 happens at the top of frame 2. The busy flag must therefore stay set through the
top of frame 2 — exactly one frame of margin over the signal. Don't reason about this from "two
awaits = two frames of cover"; the emission point is what decides it.

## Bracketing a startup coroutine in a global flag leaks that flag if the node is freed mid-await

Wrapping an async startup path in `flag = BUSY … await … flag = IDLE` fixes the race above, but
introduces a new one: `GameState` is an **autoload**, so it outlives the node. If the node is freed
while the coroutine is suspended, the coroutine is cancelled and the restore line never runs —
the autoload is stuck at `LOADING` for the rest of the process.

**Measured with GUT:** a test that does `add_child_autofree(load("res://world/world.tscn").instantiate())`
and then returns without awaiting leaves `GameState.current_state == LOADING` for the *next* test in
the file. Symptom in the victim test is bafflingly indirect — `player.gd` gates movement on
`current_state == PLAYING`, so the failure reads as "the player won't move" in a suite that never
touched `GameState`.

The transition paths have the same structural hazard, but only a test that *drives a transition* is
exposed. A startup bracket exposes **every** test that instantiates the world scene.

**How to apply:**
- When a review adds a global busy-flag bracket around an `await`, always ask "what restores the flag
  if this node dies mid-await?" GDScript has no `defer`/`finally`; nothing in the script can clean up.
  The only owner able to reset it is the harness.
- The established mitigation in this repo is `GameState.change_state(GameState.State.PLAYING)` in the
  suite's `before_each()`. Several world suites already do this; several that instantiate
  `world.tscn` do not. Treat "instantiates the world scene but does not reset `GameState` in
  `before_each`" as a review finding.
- Full-suite green does **not** clear this — the leak is test-order dependent and currently masked by
  the suites that do reset. Prove it with a two-test probe file, not by running everything.

## Related

[[gotcha-vacuous-blocked-movement-assertions]] — the other "the assertion is satisfied for the wrong
reason" family.
[[gotcha-destroy-before-acquire-soft-lock]] — the other recurring finding in `world.gd`'s transition
sequences.
