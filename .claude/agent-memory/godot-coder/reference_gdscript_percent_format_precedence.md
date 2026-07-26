---
name: gdscript-percent-format-precedence
description: GDScript's % string-format operator binds tighter than + concatenation; unparenthesized "a" + "b" % [arg] silently applies % only to "b"
type: reference
---

`"a" + "b" % [arg]` in GDScript parses as `"a" + ("b" % [arg])`, NOT `("a" + "b") % [arg]`. If the
`%s`/`%d` placeholder lives in the first string literal and the arg is meant for the whole
concatenated message, this is a real bug: the second string has no placeholder, so `%` raises
"not all arguments converted during string formatting" — an engine-level error (GUT reports it as
"Unexpected Errors: Method/function failed"), not a normal assertion failure, and it fires even
when the assertion itself would have passed, because GDScript evaluates call arguments eagerly
before the function runs.

**How to apply:** Whenever a multi-line concatenated assert message ends in `% [args]`, check that
the whole concatenation is wrapped in parens: `("a" + "b") % [arg]`. Found this exact bug in
`tests/integration/world/props/test_tree_oak.gd`'s `_get_canopy()` (Slice 7 of world-collision) —
a sibling helper in the unit-test file had the correct parenthesized form, which made the missing
parens in the integration-test copy easy to spot by comparison. Fixed as a one-line test-file
edit since it's an unambiguous syntax bug (crashes regardless of node existing), not a
design/behavior disagreement — flag it in the report but it's safe to fix directly rather than
routing back as a "suspect test."
