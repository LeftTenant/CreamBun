---
name: theme-tres-serialization
description: How Theme .tres resources serialize global colors, type variations, and color precision for GUT equality tests
type: reference
---

When hand-writing a `Theme` `.tres` (Godot 4.6), the property-path format for
`Theme::_set`/`_get` is `<type>/<data_category>/<name>`. Key gotchas:

- **Global-scope ("") theme colors** serialize as `"/colors/<name>" = Color(...)`
  — note the **leading slash** (empty type prefix), quoted because of the
  leading `/`. Writing `<name>/colors = Color(...)` instead causes
  `ERROR: Invalid item name: ''` at `Theme::set_color` on load (the parser
  reads `<name>` as the *type*, not the color name).
- **Type variations**: `<VariationName>/base_type = &"<BaseType>"` declares
  the variation; `<VariationName>/font_sizes/font_size = 16` (etc.) sets
  overrides scoped to that variation type — this part follows the normal
  `<type>/<data_category>/<name>` pattern.
- **`Color(...)` constructor in `.tres` only accepts float args**, not
  `Color("hexstring")` — that's a `Parse Error: Expected float in constructor`.
  To match a GUT test's `Color("#rrggbb")` for exact equality, convert hex to
  floats with **full double precision** (≥17 significant digits, e.g. via
  Python `repr(int(hex,16)/255.0)`). 9-digit truncation (`0.125490196`) can
  round to a *different* float32 than `32/255.0` and fail `assert_eq` on
  `Color ==` — bit-exact float32 round-tripping requires the extra digits.
- **`Theme.has_font("font", AnyType)` returns `true` whenever
  `theme.has_default_font()` is `true`**, for *any* type including the base
  `Label` type itself — this is default-font fallback, not an explicit
  per-type override. A test asserting
  `assert_false(theme.has_font("font", "Heading"))` is unsatisfiable once a
  theme has a default font. The correct check for "no explicit override" is
  `theme.get_font_list("Heading").is_empty()` (lists only explicit overrides,
  no fallback).
