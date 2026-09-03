---
name: runtime-theme-override-vs-scene-guard
description: A script that sets a theme color override in _ready() silently makes the .tscn-baked scene-as-data color guard vacuous; plus how to read base_theme.tres palette colors at runtime (note - §1's white-fallthrough no longer holds since issue #47)
metadata:
  type: project
---

Three linked facts about per-node theme color overrides in this project's notebook UI.

**Why:** `resources/theme/base_theme.tres` defines a palette (`/colors/ink`, `/colors/ink_muted`, …)
at the *empty* theme type, which Controls never resolve. Per-node colors are applied as
`theme_override_colors/font_color` in each `.tscn`. That single override slot is shared by the
editor-baked value and any runtime `add_theme_color_override()`, which creates the traps below.

**How to apply:** check all three whenever a review touches font colors, theme overrides, or a
notebook `.tscn` label.

## 1. Where does `remove_theme_color_override("font_color")` land? — verify, don't assume

`base_theme.tres` now defines `Label/colors/font_color` and `Button/colors/font_color` (both `ink`),
so removal falls through to **`ink`**, not to the baked per-node value and not to white.

Historically it fell through to `Color(1,1,1,1)` because no `Label/font_color` existed at all. Either
way, removal never restores the `.tscn`-baked color — any "revert to the muted baseline" logic must
**re-apply** the baseline color explicitly. Flag `remove_theme_color_override()` on a Label as a
probable wrong-color bug, and re-check the current theme before naming the fallthrough color.

## 2. An override applied in `_ready()` makes the .tscn color guard vacuous

`tests/unit/ui/notebook/test_notebook_typography.gd` asserts baked colors via `_make_instance()`,
which **adds the instance to the tree** — so `_ready()` runs and any runtime override wins. Verified
by probe: stomping `ItemNameLabel`'s override to red before `add_child()` yields `ink_muted` after,
i.e. the guard would still pass if the `.tscn` value were deleted entirely.

When a script starts writing a color that a typography test guards, the guard must read a **detached**
instance — properties are applied at `instantiate()`, `_ready()` only runs on tree entry:

```gdscript
var instance: Node = packed.instantiate()   # do NOT add_child
autofree(instance)
var actual: Color = label.get("theme_override_colors/font_color")
```

`autofree()` on a never-added instance is correct and does **not** show up in GUT's orphan count
(verified: the typography suite reports 0 orphans with this pattern), so there is no reason to
reach for `add_child_autofree()` just to keep the counter clean.

Same caveat applies to any new "…keeps ink_muted" test: added to the tree, it cannot distinguish the
baked value from the runtime one. It guards rendered output, not the scene file.

### The tempting WRONG fix: calling `setup()` to force the asserted state

When a script starts owning a color conditionally, an in-tree typography guard begins failing because
the instance defaults to the *other* branch. The fix that makes it green again — calling
`setup(...)` to drive the node into the state the test name expects — leaves the guard **still
in-tree, still vacuous**, and now merely duplicates a behavior test that already lives in
`tests/unit/ui/notebook/inventory/test_equipment_slot.gd`. The only fix that restores the guard's
purpose is the detached-instance pattern above (no `setup()` needed — the bake is state-independent).
`test_equipment_slot_item_name_label_color_is_ink_muted()` is the worked example of the right shape;
check any sibling test in that file against it.

Second-order question this always raises: **which** state should the `.tscn` bake now depict? The
scene's own default (children hidden/empty) is the honest editor preview, so the bake should match
the empty-state color — a bake left on the populated color makes the editor show a self-inconsistent
half-filled slot.

## 3. Palette colors ARE readable at runtime — the hardcoded hexes are a choice, not a necessity

`load("res://resources/theme/base_theme.tres").get_color(&"ink", &"")` works (empty StringName as the
theme type) and compares `==` exactly to `Color("#3b2f2a")`, despite the `.tres` storing 8-digit
floats. Note `Control.get_theme_color("ink")` does **not** reach these — the Control theme-type chain
never looks at the empty type; you must go through the `Theme` resource.

The house pattern is still to duplicate the hexes as `const COLOR_INK`/`COLOR_INK_MUTED`
(`test_notebook_typography.gd`, `test_base_theme.gd`, `equipment_slot.gd`). Accept it, but ask for one
assertion tying the duplicate back to `base_theme.tres` so palette edits fail loudly.

**Hex is exact — reject any "raw floats are needed for bit-for-bit precision" claim.** `Color` stores
`float32`, and both `Color("#b6a892")` and the `.tres`'s `Color(0.7137255, 0.65882355, 0.57254905, 1)`
land on the identical float32 triple (verified in Godot 4.6.2 for `disabled`, `ink`, and the `.tscn`'s
17-digit-double form of `ink`). `tests/unit/resources/theme/test_base_theme.gd` already asserts the
whole palette as hex strings against `Theme.get_color()` and passes. So a new palette constant should
be written as a hex string like its neighbours; writing raw floats "for precision" is cargo-culted and
the comment justifying it is factually wrong.

## Related

[[testing-conventions]] — scene-as-data guards and how they go vacuously green.
[[CreamBun Code Patterns]] — general theme/Control conventions.
