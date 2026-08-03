---
name: gotcha-load-missing-path-noisy-engine-errors
description: load() on a nonexistent res:// path pushes its own pair of low-level ResourceLoader engine errors, breaking an exact assert_push_error_count(1) expectation
type: reference
---

Calling GDScript's `load(path)` builtin on a path with no backing resource does not fail silently —
it internally trips `ResourceLoader`'s own `ERR_FAIL_COND_V_MSG`-style checks (observed as two
distinct engine errors: `Condition "err != OK" is true...` and `Condition "found" is true...`), in
addition to whatever `push_error()` the calling code adds for the failure. GUT's
`assert_push_error_count(N)` / "Unexpected Errors" reporting counts ALL of these, so a test asserting
"exactly one error on a bad destination path" (design intent: fail clean, one clear message) fails
even though the calling code's own `push_error()` count is correct — the extra 2 are flagged as
"Unexpected Errors" GUT didn't expect the test to consume.

**Why:** `load()` is written to be noisy about missing resources by design (it's meant for asset
paths that should always resolve); `ResourceLoader.exists(path, type_hint)` is the quiet variant
meant exactly for "does this exist" checks with no engine-level error spam.

**How to apply:** whenever code needs to validate a user/designer-supplied `res://` path before
`load()`-ing it (Threshold.destination, a save-slot path, any `@export_file` string) and the design
calls for a single clean custom error on failure, guard with
`if not ResourceLoader.exists(path, "PackedScene"): return null` (or the relevant type hint) before
calling `load()` — don't rely on `load()`'s own null return to detect "missing" if the surrounding
code (or its tests) cares about exactly how many errors got pushed. Seen in
`world/world.gd`'s `_load_threshold_area()` (World Thresholds Slice 3).
