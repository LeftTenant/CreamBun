# CLAUDE.md — UI

Godot Control-layout rules learned the hard way. Apply when building any notebook tab, menu, or composed Control in this folder.

## 1. Plain `Control` parents do not lay out their children

A plain `Control` is not a `Container` — adding a `VBoxContainer` (or any child Control) to it gives the child no rect. The child sizes from its `combined_minimum_size` and renders against whatever *ancestor* has an anchored rect, often crashing through whatever visual boundary the parent appeared to define.

**Fix:** after `parent.add_child(vbox)`, explicitly call
```gdscript
vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
```
The `inventory_tab.gd` and `settings_tab.gd` populate functions both do this — match the pattern when adding a new notebook tab.

## 2. Negative offsets pull edges inward after `PRESET_FULL_RECT`

For an N-pixel inset on all sides:
```gdscript
vbox.offset_left = N
vbox.offset_top = N
vbox.offset_right = -N
vbox.offset_bottom = -N
```
The right/bottom offsets are subtracted from the anchor (which is at 1.0 after the full-rect preset), so positive values would push *outward*. This sign flip is easy to get wrong.

## 3. Containers grow past their anchor when children demand it

A `Container`'s effective size is `max(anchored_size, combined_minimum_size)`. Anchoring is **not** a hard upper bound — if a child reports a wider min-width than the anchor gives, the whole container overflows. Anchoring alone won't keep a `VBoxContainer` inside its page; child min-widths must also fit.

If a layout still overflows after anchoring, the culprit is almost always a child's min-width — see rule 4.

## 4. Long Labels and Buttons are the usual min-width culprit

A `Label` with un-wrapped text reports its full text width as `minimum_size.x`, which propagates up through every `Container` ancestor. Same for `Button` with long text.

For Labels in a tight column:
```gdscript
label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
```
This lets the label take whatever column width is available rather than forcing the column wider.

**When to apply:** only to Labels whose text could plausibly exceed the column width — long descriptions, dynamic strings, localizable text that might grow. Do NOT apply to short fixed labels like section headers ("Audio", "Display") or field captions ("Master Volume") — those will fit on one line at any reasonable column width, and enabling autowrap on them triggers Godot's "Labels with autowrapping enabled must have a custom minimum size" warning without providing any benefit.

For Buttons: either shorten the text or set `clip_text = true`.

Note: `HSlider`'s default `size_flags_horizontal` is `FILL` (1), **not** `EXPAND_FILL` (3). If you want the slider to claim slack space alongside other expanding children, set `Control.SIZE_EXPAND_FILL` explicitly.

## When building layouts in the editor

The same rules above apply, but several of them are easier to apply as editor properties than runtime calls:
- `Layout → Anchor preset → Full Rect` on any container that should fill its parent (rule 1).
- Labels in narrow columns: `Autowrap → Word, Smart` and `Size Flags → Expand + Fill` (rule 4).
- `HSlider` and `VSlider`: `Size Flags → Expand + Fill` (the default is `FILL`, not `EXPAND_FILL` — must be set explicitly; rule 4 note).
- Inset offsets (rule 2) still get applied at runtime in `populate_left/right` for now; see issue #10.
