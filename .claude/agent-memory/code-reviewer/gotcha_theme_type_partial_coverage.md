---
name: theme-type-partial-coverage
description: Godot theme types don't cross-inherit — Panel/styles/panel never reaches PanelContainer, and Button/colors/font_color leaves 5 sibling state colors + all Button styleboxes at engine defaults; also lists which types base_theme.tres now covers vs still-default
metadata:
  type: project
---

Adding a per-control-type entry to `resources/theme/base_theme.tres` fixes exactly one
theme item for exactly one class chain. Review every such addition for the *siblings it
leaves behind*, because the un-covered siblings keep resolving Godot's dark built-in
default theme — which on this project's cream `paper_bg` page reads as a visible artifact,
not as "unstyled".

**Why:** verified empirically in Godot 4.6.2 against `base_theme.tres`.

**How to apply:** when a diff adds a `Type/items/name` line to a Theme `.tres`, run the
three checks below before passing.

## 1. Theme type lookup follows the ClassDB chain only — not "looks like a panel"

`Control.get_theme_stylebox()` walks the node's own class inheritance chain. So:

- `Panel/styles/panel` reaches `Panel` (and subclasses). It does **not** reach
  `PanelContainer` (`PanelContainer → Container → Control`), `PopupPanel`, or `PopupMenu` —
  each is its own theme type with its own `panel` slot.
- `base_theme.tres` now carries `Panel/styles/panel` (`paper_bg`), a **separate**
  `PanelContainer/styles/panel` sub-resource (`paper_bg_shadow`), and `Label/colors/font_color`
  (`ink`). The only `Panel` in the project is `notebook.tscn`'s `Book`; the only mounted
  `PanelContainer` is `equipment_slot.tscn`'s `IconFrame` (`ui/notebook/shared/page_panel.tscn`
  is a `PanelContainer` too but is currently instantiated nowhere, despite
  `docs/features/notebook/design.md` §2 calling it "a page Panel with paper background").
- Still on engine defaults and visibly off-palette on cream: `Button` (see §2/§3 — tracked as its
  own issue), plus `OptionButton`, `HSlider`, `VSeparator`. The e2e goldens show these as grey
  rounded plates on the cream page, which is expected-but-unfinished, not a regression.
- The theme resource is assigned in exactly one place — `ui/notebook/notebook.tscn`'s `Book` —
  so any new per-type entry only affects the notebook subtree until someone sets the theme
  elsewhere (or in `project.godot`'s `gui/theme/custom`). Check that scope claim before
  worrying about ripple.
- `Button/colors/font_color` **does** reach `OptionButton`, `CheckBox`, `MenuButton` etc.
  (they subclass `Button`) — verified.
- Theme *type variations* (`Heading/base_type = &"Label"`) do fall back to their base type,
  so a `Heading` Label picks up `Label/colors/font_color`.

## 2. `Button/colors/font_color` is one of six font-state colors

Setting only `font_color` leaves these at engine defaults (measured):

| item | engine default |
|---|---|
| `font_hover_color` | `(0.95, 0.95, 0.95)` |
| `font_pressed_color` | `(1, 1, 1)` |
| `font_focus_color` | `(0.95, 0.95, 0.95)` |
| `font_hover_pressed_color` | `(1, 1, 1)` |
| `font_disabled_color` | `(0.875, 0.875, 0.875, 0.5)` |

So a "themed" Button flips from `ink` to near-white the moment the mouse enters it.

## 3. Button styleboxes are a separate axis, and the contrast maths flips

Engine default Button styleboxes (measured `bg_color`): `normal (0.1,0.1,0.1,0.6)`,
`hover (0.225,0.225,0.225,0.6)`, `pressed (0,0,0,0.6)`, `disabled (0.1,0.1,0.1,0.3)`,
`focus (1,1,1,0.75)` — all with the default theme's rounded corners.

Composited over `paper_bg`, the normal plate is ≈`(0.443, 0.425, 0.399)`. Against that:

- old engine `font_color` 0.875 → **≈3.9:1**
- new `ink` → **≈2.5:1**

i.e. giving a Button `ink` text *without* also giving it a paper stylebox is a legibility
**regression**, not a fix. Say so, and recommend either deferring the `Button` font color to
the same pass that styles the button plate, or landing both together. Same trap for
`HSlider`/`VSeparator`, whose light-gray engine defaults become near-invisible on cream.

## 4. Notebook visual changes invalidate the committed e2e goldens

`tests/e2e/notebook/screenshots/` holds ~21 tracked PNGs of the notebook. Any theme change
that repaints the Book/pages makes all of them stale even though GUT stays green. Require
regeneration (or an explicit deferral note) in the same change.

## Related

[[runtime-theme-override-vs-scene-guard]] — per-node overrides and vacuous scene guards.
[[theme-palette-roles-and-contrast]] — which palette color belongs in which role.
[[gotcha-tscn-editor-drift]] — `;` comments and default-valued props vanish from `.tres` too.
