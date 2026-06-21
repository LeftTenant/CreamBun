# Slice 1 — Populate the base theme: Test Plan

Feature: **pixel-art-purist** · Slice: **1 — Populate the base theme (font, size, palette)**
Design doc: `docs/refactors/pixel-art-purist-size-and-theme.md` (§3 font, §4 theme/palette)
Slice spec: `docs/features/pixel-art-purist/slices.md` (Slice 1)

## What this slice delivers

`resources/theme/base_theme.tres` goes from a bare `Theme` to the single base theme:
default font = the imported `monogram-extended.ttf`, default font size = 8, the nine named
palette colors from §4, and a `Heading` `Label` type variation at font size 16. Nothing
references the theme yet (that is Slice 2), so this slice is visually invisible in-game and is
verified entirely by loading the resource and asserting its contents — pure resource-as-data.

## Verification strategy

This is data, not behavior. There is nothing to render and no signal flow, so there are **no
e2e or integration tests** for this slice — they would add cost without adding proof. All
verification is unit-level: load the `.tres`, assert each field. The font *import* is already
done (verify-only, per the approved plan), so one unit check guards that the import flags
haven't regressed rather than re-doing the import.

### E2E

_None._ No scene consumes the theme in this slice; there is nothing visible to screenshot.
Crispness/legibility payoff is proven in Slices 2, 4, and 5.

### Integration

_None._ No cross-system wiring, autoload signal, or scene instantiation is involved — the
theme is an inert resource until Slice 2 applies it.

### Unit — `tests/unit/resources/theme/test_base_theme.gd`

Loading & default font:

- The theme resource at `res://resources/theme/base_theme.tres` loads successfully and is a `Theme`.
- The theme has a default font set (default font is not null).
- The theme's default font resolves to the imported `res://resources/theme/fonts/monogram-extended.ttf` (the runtime copy under `resources/`, never an `art/` path).
- The theme's default font size is `8`.

Palette colors (each is a named theme color of type `Color`, present and equal to its §4 hex):

- `paper_bg` is defined and equals `#f4e9d8`.
- `paper_bg_shadow` is defined and equals `#e3d4bd`.
- `ink` is defined and equals `#3b2f2a`.
- `ink_muted` is defined and equals `#7a6a5d`.
- `accent` is defined and equals `#c8743c`.
- `accent_soft` is defined and equals `#e7b07e`.
- `success` is defined and equals `#6f8f4a`.
- `frame_line` is defined and equals `#2a201c`.
- `disabled` is defined and equals `#b6a892`.
- The theme defines exactly these nine palette color names and no extra/stray color entries (no scope creep into per-control colors this slice).

`Heading` type variation:

- A `Heading` `Label` type variation exists in the theme (the theme reports `Heading` as a known type, with base type `Label`).
- The `Heading` variation sets font size `16`.
- The `Heading` variation does not override the default font (it reuses the monogram default — only the size differs from body), so headings stay in the same typeface.

Font import guard (verify-only — import already done):

- The font file's import config (`monogram-extended.ttf.import`) has `antialiasing=0`, `hinting=0`, `subpixel_positioning=0`, `generate_mipmaps=false`, `multichannel_signed_distance_field=false`, and `force_autohinter=false` — guarding the §3 pixel-perfect flags against regression.

## Out of scope (do not test here)

- Applying the theme to the notebook or any scene, or descendant inheritance — Slice 2.
- Any rendered/visual assertion (font crispness, legibility) — Slices 2, 4, 5.
- Per-control styleboxes, button states, or palette roles beyond the nine §4 colors — design defers these.
- Re-tuning or art-direction review of the hex values — these are the §4 starter values verbatim.
- Viewport/window/stretch/snap settings — Slices 3 and 4.

## Notes for the test author

- Hex values above are the §4 table verbatim; assert against these exact strings (use Godot's
  `Color(hex_string)` or `Color.html()` for comparison so `#`-prefix handling is consistent).
- Read the default font's source path via the loaded `FontFile` so the test fails loudly if a
  future edit ever points the theme back into `art/`.
- For the import-flag guard, parsing the `.import` file's `[params]` as text is acceptable —
  this is the same data-shaped assertion the rest of the slice uses.
