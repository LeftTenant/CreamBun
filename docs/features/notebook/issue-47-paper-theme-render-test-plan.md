# Notebook Paper Theme Render (Issue #47) — Test Plan

Issue: the pixel-art-purist refactor populated `resources/theme/base_theme.tres`
with the nine §4 palette colors and applied the theme resource to the
notebook's `Book` Panel, but never applied any of those colors as concrete
per-control-type theme properties. `base_theme.tres` only defined the palette
as generic type-`""` named colors (readable via `Theme.get_color(name, "")`
for scripts that opt in) — it had no `Panel/styles/panel` stylebox and no
`Label` `font_color` default. Confirmed via an in-game screenshot: `Book`
rendered as Godot's default dark, semi-transparent `Panel` style, and
un-overridden text fell through to engine-default white.

This is a resource-and-cascade bug, not a user-input flow, so the plan below
is unit-only — no new e2e scenario. `tests/e2e/notebook/inventory_actions.md`
already exercises the notebook visually and shows the paper background now
that this is fixed; it is not duplicated here (see visual verification note
below).

**Button theming out of scope:** a `Button/colors/font_color` addition was
attempted during the fix but reverted during code review — ink text alone on
Godot's still-dark default button background was a legibility regression, not
an improvement. Full Button theming (styleboxes + all font states) is
deferred to issue #48 and has no coverage in this plan.

**PanelContainer added during review:** `PanelContainer` (used by
`equipment_slot.tscn`'s `IconFrame` icon-slot boxes and
`ui/notebook/shared/page_panel.tscn`) does not inherit `Panel`'s stylebox via
Godot's theme type chain (`PanelContainer -> Container -> Control`, never
through `Panel`), so it needed its own `styles/panel` entry — added alongside
the tests below.

### Unit
- [x] `base_theme.tres` defines a `Panel` type `styles/panel` `StyleBoxFlat` whose `bg_color` equals the theme's `paper_bg` color exactly
- [x] That `Panel` stylebox's border color equals the theme's `frame_line` color exactly, with a non-zero border width
- [x] That `Panel` stylebox has zero corner radius on all four corners (pixel-crisp, no rounding)
- [x] `base_theme.tres` defines a `Label` type `colors/font_color` equal to the theme's `ink` color exactly
- [x] The existing nine-named-palette-colors guard (`test_palette_has_exactly_nine_colors_with_no_extras`) still passes — the new stylebox/font-color entries live under their own `Panel`/`PanelContainer`/`Label` types, not added to the `""` type bucket
- [x] Live cascade: the notebook's `Book` Panel resolves its `panel` stylebox via `get_theme_stylebox` to the `paper_bg`-backed `StyleBoxFlat` (not the engine default)
- [x] Live cascade: a plain `Label` reparented into the notebook with no per-node color override resolves `font_color` via theme inheritance to `ink` (not engine-default white)
- [x] `base_theme.tres` defines a `PanelContainer` type `styles/panel` `StyleBoxFlat` whose `bg_color` equals the theme's `paper_bg_shadow` color exactly, whose border color equals `frame_line` exactly, and whose corner radius is 0 on all four corners
- [x] Both the `Panel` and `PanelContainer` styleboxes have `anti_aliasing` disabled (pixel-crisp 1px border, no sub-pixel blending)
- [x] Live cascade: an `EquipmentSlot`'s `IconFrame` (a `PanelContainer`, reached by switching the notebook to the inventory tab) resolves its `panel` stylebox via `get_theme_stylebox` to the `paper_bg_shadow`-backed `StyleBoxFlat`, not the engine default

Two Button-cascade checklist items ("a plain `Button` reparented into the
notebook resolves `font_color` to `ink`" and its resource-level counterpart)
were dropped from this plan — that behavior moved to issue #48 along with the
rest of Button theming.

### Visual verification
- [x] Fresh e2e screenshot via the testing sandbox (inventory tab) confirms the notebook renders with a cream paper background, legible ink-colored text, and cream/shadow-toned (not dark rounded) equipment icon frames
