---
name: gotcha-gut-helper-silent-passes
description: Six ways a GUT test silently passes — a failed cast swallowed by a fetch helper, "%" binding to the wrong literal in a concatenated message, a reachable sentinel return, a parse error that drops the whole script, leftover RED-phase Enum.get() scaffolding, and a bare `if resource.has_x()` guard that goes Risky-but-passing
type: project
---

Four recurring hazards in this repo's GUT test helpers. All produce a test that looks green (or
loudly red for the wrong reason) without exercising the behaviour it names.

## 1. `return node as T` in a fetch helper swallows the real failure

The house pattern for "find the child I need" helpers is:

```gdscript
func _get_canopy(tree: WorldProp) -> Polygon2D:
    var node: Node = tree.get_node_or_null(CANOPY_NODE_NAME)
    assert_not_null(node, "...")
    if node == null:
        return null
    return node as Polygon2D          # <-- no assertion on the cast
```

Every caller then does `if x == null: return`. If the node *exists* but is the wrong type, the
cast yields `null`, the helper records **no** failed assertion, the caller returns early, and GUT
reports a test with zero assertions — which it does not fail by default. The whole test evaporates.

**How to apply:** every fetch helper that narrows a type must `assert_not_null()` on the *cast
result* too, not just on `get_node_or_null()`. The correct shape already exists in this repo —
`tests/unit/world/props/test_tree_oak.gd`'s `_get_polygon_child()` asserts both. When you see a
`_get_*` helper duplicated across a unit and an integration file, diff the two copies: the
divergence is usually where the bug is.

## 2. `%` binds tighter than `+`, so it formats only the last literal

GDScript parses `"a %s" + "b" % [arg]` as `"a %s" + ("b" % [arg])`. When the placeholder lives in
the first literal of a multi-line concatenated assert message, the trailing literal has no
placeholder and `%` raises *"not all arguments converted during string formatting"* — an
engine-level error (GUT: "Unexpected Errors: Method/function failed"), raised **eagerly** when the
call arguments are evaluated, so it fires even on the pass path. The fix is parenthesising the
whole concatenation: `("a %s" + "b") % [arg]`.

**How to apply:** whenever a diff adds a multi-line concatenated assert message ending in
`% [...]`, confirm the concatenation is wrapped. Reviewing by eye across 5-line messages is
unreliable — a tokenizing scan is cheap: walk the file tracking bracket depth and string state,
flag any `%` operator where a `+` was seen at the same depth since the last `,` or opening bracket.
Validate the scanner on a known-buggy and known-good snippet before trusting a clean result.

## 3. A sentinel return value that collides with a legitimate authored value

The "return an empty value with the failure already recorded" variant of pattern 1 is safer —
until the sentinel is also a value the scene could legitimately hold. E.g. a helper that returns
`Rect2()` on lookup/type failure, with every caller doing `if rect.size == Vector2.ZERO: return`.
If a designer zeroes the authored `RectangleShape2D.size`, the helper's own assertions all *pass*
(the node exists, is the right type, has a shape), the callers return early, and GUT reports green
tests with several passing assertions — harder to spot than the zero-assertion case.

**How to apply:** when a helper returns a sentinel, ask whether the sentinel is reachable through
normal authoring. If it is, the guard must be an assertion (`assert_ne(rect.size, Vector2.ZERO,
...)`) rather than a bare `return`, or the helper should signal failure out-of-band.

## 4. A parse error deletes the whole test script and the run still says "All tests passed!"

Verified in Godot 4.6.2 / GUT 9.6.0: a test script that fails to parse (e.g. it type-hints
against a `class_name` that no longer exists) is logged as a warning, **dropped from the run**,
and the summary still prints `---- All tests passed! ----` with **exit code 0**. Only a
`Warnings  1` line in the totals hints at it. So "the test would fail to compile" is *not* a
safety net — it is a silent deletion of coverage.

This has a sharp consequence for **guard tests that prove an identifier exists**. A test asserting
`class_name Foo` is registered must live in a script that never writes `Foo` as a type — including
indirectly, via a helper in the same file typed `-> Foo`. Otherwise removing `class_name Foo`
makes the guard *vanish* rather than fail, which is exactly the circularity the guard exists to
prevent. Typing helpers against a project `class_name` is otherwise good (a removed `@export`
then surfaces as a loud GUT `Unexpected Errors: Invalid access to property...` failure, not a
silent `null` from `.get()`) — so the resolution is to isolate the class-resolution test in its
own script, not to untype everything.

**How to apply:** when a diff retypes a test helper from a built-in (`Node`, `Area2D`) to a
project `class_name`, check (a) the cast isn't swallowed — see pattern 1 — and (b) no test in
that file is *about* the existence of that `class_name`. To prove a guard test still catches its
regression, mutate the source and re-run; do not reason about it.

## 5. TDD-era `Enum.get("NAME", -1)` scaffolding left in place after the fix lands

When tests are written RED-first against an identifier that does not exist yet, the house
workaround is a Dictionary lookup with a sentinel — `ItemData.EquipSlot.get("BELT", -1)` — because
a direct `ItemData.EquipSlot.BELT` reference would be a parse error and silently drop the whole
script (pattern 4). That is correct *while red*. Once the enum member exists, the same line is a
vacuous assertion: `inv.unequip(EquipSlot.get("BELT", -1))` asserting `null` passes identically
whether BELT is `4` or missing (`-1` is just an empty slot), so the guard no longer guards.

The tell is the comment, which stays in pre-fix tense: "BELT does not exist in the enum yet",
"is being changed independently of this file", "FAILS pre-fix". Those phrases are also the
cheapest grep for finding the scaffolding.

**How to apply:** on the GREEN review pass of a TDD change, grep the diff for `.get("` on an enum
and for pre-fix tense in comments. Convert each back to a direct member reference (`EquipSlot.BELT`)
unless the file is *specifically* the existence guard for that member — in which case it belongs
in its own script per pattern 4, with an explicit `assert_true(Enum.has("BELT"))`.

## 6. An `if resource.has_x(...)` presence guard with no `assert_true` on the presence

A test whose *whole body* is wrapped in `if theme.has_stylebox("panel", "Panel"):` (or
`has_color`, `has_font`, `has_meta`, …) asserts nothing when the entry is missing. GUT marks it
`[Risky]: <name> did not assert` — but **Risky is not Failing**: the test is still counted in
`Passing Tests` and the run still exits 0. So deleting the very theme entry the test is about
turns it green-with-a-yellow-line, which no CI gate catches.

Verified on `tests/unit/resources/theme/test_base_theme.gd`'s
`test_panel_and_panel_container_styleboxes_have_anti_aliasing_disabled`: removing both
`Panel/styles/panel` and `PanelContainer/styles/panel` from `base_theme.tres` made 10 sibling
tests fail and that one go Risky-but-passing.

**How to apply:** the sibling tests in the same file show the correct shape — `assert_true(
theme.has_stylebox(...), "...")` *then* `if not theme.has_stylebox(...): return`. Whenever a test
guards a resource entry behind a bare `if …has_*()`, require the presence itself be asserted.
Mutating the resource and re-running is the cheap proof, and the `Risky` line in GUT's per-test
output is the tell.

## Related

[[gotcha-vacuous-blocked-movement-assertions]] — the third member of this family: an assertion
shape that a motionless probe satisfies.
[[testing-conventions]] — general GUT conventions, including the stale "RED STATE, EXPECTED"
header rule.
