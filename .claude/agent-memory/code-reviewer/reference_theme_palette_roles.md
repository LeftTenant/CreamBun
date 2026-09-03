---
name: theme-palette-roles-and-contrast
description: base_theme.tres palette roles are documented per-color in pixel-art-purist-size-and-theme.md; disabled (#b6a892) is a BUTTON color at ~1.9:1 on paper, ink_muted is the dimmed-TEXT color at ~4.3:1
metadata:
  type: reference
---

The canonical role for every color in `resources/theme/base_theme.tres` is the palette table in
`docs/refactors/pixel-art-purist-size-and-theme.md` (search for `| paper_bg |`). Consult it before
approving a palette color used in a new place — the table assigns each color a *role*, and the doc
explicitly says to extend the palette only when a genuinely new role appears rather than reusing a
color for an unrelated purpose.

Roles that get confused in review:

- `ink_muted` `#7a6a5d` — "Secondary text, hints, **completed/dimmed items**". This is the sanctioned
  *dimmed text* color. ~4.3:1 against `paper_bg`.
- `disabled` `#b6a892` — "**Greyed-out buttons** (e.g. Recycle when not recyclable)". A control-state
  color, not a text color. Only ~**1.9:1** against `paper_bg` (~1.6:1 against `paper_bg_shadow`), i.e.
  far below WCAG AA 4.5:1 for body text, and the notebook body font is 8px.

**How to apply:** when a change dims a *Label*, `ink_muted` is almost always the right color and
`disabled` is almost always wrong — say so with both the doc's role wording and the contrast numbers.
This matters doubly on the notebook UI, where issue #45 was itself a WCAG-AA contrast fix, so
regressing a different label to 1.9:1 in the same PR is self-defeating. If the user asked for the
"disabled control" look by name, surface the trade-off rather than silently accepting or refusing it.

Note the empty equipment slot's heading is the *only* cue telling the player what to drag where
(`equipment_slot.gd::_slot_name()` docstring), so the empty state is where legibility matters most.

## Related

[[runtime-theme-override-vs-scene-guard]] — how these palette colors get applied and mis-guarded.
