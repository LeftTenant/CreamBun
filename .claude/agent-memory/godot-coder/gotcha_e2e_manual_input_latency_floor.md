---
name: e2e-manual-input-latency-floor
description: Manual step-by-step testing-sandbox tool calls have a real-world latency floor that makes sub-second input release timing (and therefore sub-tile positioning) unachievable
type: reference
---

Driving the live game through the testing-sandbox MCP tools (`press_action`/`release_action`/
`wait_frames`/`get_node_property`) one call at a time, each round trip (the agent issuing a call and
waiting for its result) costs roughly 1-1.5 real seconds regardless of the `wait_frames` count
argument passed — the game keeps running in real time between calls, and an agent's own per-call
latency, not the requested frame count, ends up dominating how far the player travels. Empirically
confirmed on CreamBun's player (200px/s): a single `press_action` -> (next call) `release_action`
pair consistently moved the player ~278px, whether or not a `wait_frames` call was interposed with a
count as low as 5 or as high as 20 — the trip through `press_action` alone was enough real time for
that much travel.

**Why this matters**: any scenario step that requires releasing input (or otherwise reacting)
*immediately* once some polled condition becomes true — e.g. "release the instant GameState returns
to PLAYING, before the player drifts further in" — cannot be hit with useful precision this way. The
very next tool call after observing the condition already costs another latency-floor's worth of
travel (~278px on this project, more than the width of some areas, and far more than the ~32-64px
corner-dead-zone tolerances world-collision's edge-transition mechanic cares about). Finer-grained
`wait_frames` polling does not help — it's the round-trip itself that costs the time, not the
in-engine frame count requested.

**How to apply**: don't attempt frame-precise or sub-tile-precise manual capture (e.g. "screenshot
the exact moment a fade clears" or "stop the player exactly one tile past an edge") via step-by-step
interactive tool calls in a normal reasoning turn — budget for a `~280px` (or equivalent, scaled to
whatever the project's move speed is) overshoot on release, and either (a) accept a coarser
checkpoint tolerance when writing the scenario doc, (b) drive the capture from a tighter, low-
reasoning-overhead loop that can issue calls back-to-back with minimal thinking time between them, or
(c) verify the precise-timing behavior via GUT integration tests (which run in-process, no RPC round
trip) and reserve e2e/testing-sandbox capture for coarser, more forgiving visual checkpoints. Flag the
precision mismatch to the user rather than forcing through a capture likely to reproduce the same
kind of inaccuracy a screenshot recapture was meant to fix.

There is also no teleport/set-position tool on this sandbox (only `get_node_property`, not a setter)
— repositioning the player for a scenario setup means actually walking it there with movement
actions, routing around any props/obstacles in a straight-line path (checked via
`get_node_property` on the prop's `position`/collision, not assumed).
