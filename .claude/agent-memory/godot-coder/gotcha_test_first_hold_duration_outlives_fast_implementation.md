---
name: gotcha-test-first-hold-duration-outlives-fast-implementation
description: a generously long test-first movement hold can end up sampling well after a correct, fast implementation already finished (and kept moving on the same held input)
type: reference
---

Integration tests written test-first (before the real implementation exists) sometimes hold a
movement input for a long, fixed tick count chosen to *guarantee* a crossing/trigger fires
regardless of geometry — e.g. `DRIVE_TICKS = 300` (~5s at 60Hz) to cross a few-hundred-px map,
chosen generously because at authoring time there was no working implementation to calibrate
against. Once a correct, appropriately fast implementation exists (e.g. a "cozy," ~0.3s each-way
transition fade), that hold duration can dwarf it: the crossing, and the entire
freeze/fade/swap/spawn/reveal sequence, completes in a small fraction of the held ticks — and,
critically, if the input is still held afterward (never released early), the player keeps moving
*inside the new area* for the remainder of the hold, walking into whatever's on the other side
(often that area's own far wall).

**Symptoms this produces, all against a CORRECT implementation:**
- A check for "state should be X immediately/shortly after the crossing," sampled only after the
  full hold ends, instead observes the state *after* the whole sequence already completed (and
  reverted) — e.g. expects `LOADING`, finds `PLAYING` again.
- A check for "the fade should be partway opaque," sampled the same way, finds `alpha == 0` (the
  reveal already finished).
- A spawn-position check finds the player somewhere else entirely — not because the spawn math
  was wrong, but because the still-held input drove the player further from the spawn point
  before the test read its position (the reported number often matches "spawn point + remaining
  hold-time distance," clamped by whatever wall/obstacle is next in that direction).
- A test that expects the crossed area's own node reference to still be valid/queryable afterward
  gets a "previously freed instance" error instead, because a correct implementation legitimately
  freed the old area during the hold.

**How to tell this apart from a real bug:** work out the actual tick budget. If (ticks-to-reach-
the-trigger) + (transition duration in ticks) is well under the total hold, and the failing
number is consistent with "spawn position, then continued travel at the known speed for the
leftover ticks," it's this pattern, not an implementation defect. Don't fix it by artificially
slowing the transition down to match an oversized test hold — that trades real game feel for a
test-timing artifact. Flag the test's timing assumption instead (ideally: release the held input
as soon as the expected transition would plausibly have started, or sample inside a polling loop
right as the relevant state changes, rather than only after a fixed long hold ends).

See also `[[gotcha-queue-free-deferred-removal]]` — a related-looking "freed instance" failure
that turned out to be a real bug rather than this pattern; worth ruling out queue_free() ordering
issues before concluding a "freed object" failure is just this timing artifact.
