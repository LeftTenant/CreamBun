---
name: gotcha-gut-helper-silent-passes
description: Two ways a GUT test silently passes — a fetch helper that returns a failed cast without asserting, and a "+" concatenated assert message whose % binds to the wrong literal
type: project
---

Two recurring hazards in this repo's GUT test helpers. Both produce a test that looks green (or
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

## Related

[[gotcha-vacuous-blocked-movement-assertions]] — the third member of this family: an assertion
shape that a motionless probe satisfies.
[[testing-conventions]] — general GUT conventions, including the stale "RED STATE, EXPECTED"
header rule.
