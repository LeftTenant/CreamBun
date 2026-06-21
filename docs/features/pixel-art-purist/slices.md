# Pixel-Art-Purist — Slice Breakdown

Source design: `docs/refactors/pixel-art-purist-size-and-theme.md`

## Context discovered before slicing

- **Font import is already done.** `resources/theme/fonts/monogram-extended.ttf` exists with a
  `.import` whose flags already match the design's §3 table: `antialiasing=0`, `hinting=0`,
  `subpixel_positioning=0`, `generate_mipmaps=false`, `multichannel_signed_distance_field=false`,
  `force_autohinter=false`. Design Step 1 is therefore effectively complete — slices verify it
  rather than redo it.
- **Theme resource is empty.** `resources/theme/base_theme.tres` is a bare `Theme` with no font,
  size, or colors yet.
- **Current `[display]`** in `project.godot`: viewport 640×360, window override 1280×720,
  `stretch/mode="viewport"`. No aspect / scale_mode / 2d snap keys present.
  `default_texture_filter=0` (Nearest) is already set under `[rendering]`.
- **Notebook root** is a `CanvasLayer` (`ui/notebook/notebook.tscn`); `notebook.gd` builds tabs
  via `TabClass.new()` and reparents only `LeftPage`/`RightPage` subtrees (see `ui/CLAUDE.md`).
  Theme must cascade to those subtrees — applying it on the in-game notebook root Control is the
  reliable cascade point, not a tab scene's editor-only root.

## Slicing rationale

This refactor is settings + one shared resource + a doc reconciliation, with almost no game
logic. The design's own §7 phasing is intentionally ordered to never leave the game broken, so
the slices follow that order closely but group steps that share a verification pass. Tests are
mostly **scene/resource-as-data** assertions (load the `.tres`/`project.godot`, assert keys) plus
**e2e visual** crispness checks where only rendering can confirm the payoff.

Per-slice ordering matters: theme is populated and proven on the notebook at the *current*
resolution first (so font legibility is isolated from the viewport change), then the viewport
moves, then stretch/snap flips, then the font-size pass, then docs.

---

## Slice 1 — Populate the base theme (font, size, palette)

**Goal.** Turn the empty `resources/theme/base_theme.tres` into the single base theme: Default
Font = the imported `monogram-extended.ttf`, Default Font Size = 8, the nine named palette colors
from §4 (`paper_bg`, `paper_bg_shadow`, `ink`, `ink_muted`, `accent`, `accent_soft`, `success`,
`frame_line`, `disabled`), and a `Heading` `Label` type variation at font size 16. No scene
references it yet, so this slice is self-contained and visually invisible in-game — it is verified
by loading the resource and asserting its contents.

**Likely files created/modified.**
- `resources/theme/base_theme.tres` (modified — populated)
- `tests/unit/resources/theme/test_base_theme.gd` (new — resource-as-data assertions)

**Out of scope.** Applying the theme to any scene (Slice 2). Per-control styleboxes/buttons
beyond the `Heading` variation (design defers these). Re-tuning hex values (these are the §4
starter values verbatim).

---

## Slice 2 — Apply the theme to the notebook

**Goal.** Make the notebook render in monogram with the palette by setting the base theme on the
notebook so it cascades to all `Control` descendants (including the `LeftPage`/`RightPage`
subtrees that tabs reparent in). Verify the notebook renders in monogram at the *current* 640×360
window — proving legibility before the viewport shrinks. Redirect the notebook design's theme
reference from `resources/data/notebook_theme.tres` to `resources/theme/base_theme.tres` (the §6.2
edit) as part of this slice, since it is the change that makes this wiring authoritative.

**Likely files created/modified.**
- `ui/notebook/notebook.tscn` and/or `ui/notebook/notebook.gd` (modified — set/assign theme at the
  cascade point; coder picks scene property vs. runtime assignment per `ui/CLAUDE.md` tab rules)
- `docs/features/notebook/design.md` (modified — §9 theme path redirect only)
- `tests/unit/ui/notebook/test_notebook_theme.gd` (new — scene-as-data: notebook applies the base
  theme; descendants inherit it)
- `tests/e2e/pixel-art-purist/notebook_renders_monogram.gd` (new — open notebook, screenshot,
  confirm text renders)

**Out of scope.** Viewport/window resize (Slice 3). Stretch mode change (Slice 4). The per-widget
font-size pass / `Heading` variation usage across tabs (Slice 5). Other §6 doc edits (Slice 6).

---

## Slice 3 — Resize viewport to 320×180 / window to 640×360

**Goal.** Change `[display]` render resolution to 320×180 and the launch window override to 640×360
(2×), **keeping `stretch/mode="viewport"`** for this slice to isolate the resolution change from
the stretch change (design Step 4). Confirm the world and notebook still fit and frame correctly at
the new render size; fix any UI that hard-assumed 640×360.

**Likely files created/modified.**
- `project.godot` (modified — `[display]` viewport_width/height, window_width/height_override)
- any world/UI scene that hard-coded 640/360 positioning (modified only if found broken)
- `tests/unit/test_display_settings.gd` (new — parse `project.godot`, assert viewport 320×180 and
  window override 640×360)
- `tests/e2e/pixel-art-purist/world_frames_at_320x180.gd` (new — launch, screenshot world + open
  notebook, confirm both fit with no clipping)

**Out of scope.** Stretch mode, aspect, scale_mode, and 2D snap flags (Slice 4). Font-size pass
(Slice 5). The art-constraint doc (Slice 6).

---

## Slice 4 — Pixel-perfect stretch + snap settings

**Goal.** Flip to the purist rendering settings: `stretch/mode="canvas_items"`,
`stretch/aspect="keep"`, `stretch/scale_mode="integer"`, and the two 2D snap flags
(`2d/snap/snap_2d_transforms_to_pixel=true`, `2d/snap/snap_2d_vertices_to_pixel=true`). Confirm
fonts are now crisp (the payoff of `canvas_items`) and sprites do not shimmer when the camera
moves; disable `Camera2D` position smoothing if shimmer appears. This is the slice that delivers
the refactor's primary "crisp text, square pixels" goal.

**Likely files created/modified.**
- `project.godot` (modified — `[display]` stretch keys + `[rendering]` 2d/snap keys)
- the world `Camera2D`-owning scene (modified only if shimmer requires disabling smoothing)
- `tests/unit/test_display_settings.gd` (modified — add stretch/aspect/scale_mode + snap assertions)
- `tests/e2e/pixel-art-purist/text_is_crisp.gd` (new — screenshot at 1× and at a scaled window;
  confirm text edges are hard, no blur; sprites stable across a camera move)

**Out of scope.** Font-size tuning per widget (Slice 5). Doc reconciliation (Slice 6). Per-platform
fullscreen/HiDPI (design non-goal).

---

## Slice 5 — Notebook font-size pass (body 8 / heading 16)

**Goal.** Apply the §6.3 typography: headings (tab titles, quest titles, Story names, dialog
speaker names) use the `Heading` size-16 variation; body text (inventory rows, weight readout,
quest descriptions, settings labels, the close hint, objective bullets) uses the size-8 default;
differentiate the weight readout and similar by `ink` vs `ink_muted` color, not size. Verify
legibility at 1× (320×180) — the worst case. If 8 is unreadable in playtest, the design's fallback
is body 16 (do not introduce non-multiple sizes) — surface to the user rather than silently
changing.

**Likely files created/modified.**
- `ui/notebook/**/*.tscn` (modified — assign `Heading` theme type variation on heading Labels;
  rely on theme default 8 for body; set `ink_muted` color where the design calls for it)
- `tests/unit/ui/notebook/test_notebook_typography.gd` (new — scene-as-data: heading Labels carry
  the `Heading` variation; body Labels carry no font-size override)
- `tests/e2e/pixel-art-purist/notebook_legible_at_1x.gd` (new — open notebook at 1×, screenshot
  each tab, confirm heading/body sizes read distinctly)

**Out of scope.** Notebook layout/behavior changes (design says presentation only). The remaining
§6 doc edits (Slice 6). Changing the base font size (only escalate via the user-facing fallback).

---

## Slice 6 — Documentation reconciliation (notebook design + art constraint)

**Goal.** Land the refactor's required documentation deliverables. (1) Reconcile
`docs/features/notebook/design.md` §9 fully (design Step 8): stretch `viewport` → `canvas_items`,
font sizes pinned to body 8 / heading 16, plus the §6.4 layout implication note (theme-path
redirect was done in Slice 2 — confirm it is consistent). (2) Record the §5 art constraint
("author world/sprite art in multiples of 16 px; the 16×16 base tile; the camera absorbs the
11.25-tile vertical remainder") wherever art guidelines live — `README.md` or a new `art/README.md`.

**Likely files created/modified.**
- `docs/features/notebook/design.md` (modified — §9 stretch + font sizes + layout note)
- `README.md` or `art/README.md` (modified/new — the 16 px art constraint)
- (no test files — documentation only; verification is a human read-through)

**Out of scope.** Any settings/code change (all landed in Slices 1–5). New art guidelines beyond
the §5 rule. Per-platform / localization-fallback notes (design non-goals).

---

## Cross-slice notes for the executor

- **Tests are light and data-shaped.** Most slices verify by parsing `project.godot` or loading a
  `.tres`/`PackedScene` and asserting fields — there is little runtime logic to unit-test. e2e
  visual screenshots are the real proof for crispness/legibility (Slices 2, 4, 5).
- **Editor-vs-runtime caution (Slice 2 & 5).** `notebook.gd` mounts only `LeftPage`/`RightPage`
  subtrees via `TabClass.new()`. The coder must set the theme/variations where they actually take
  effect at runtime, per `ui/CLAUDE.md`’s tab rules and the editor-preview policy in agent memory.
- **Beginner-friendly, no scope creep.** Hex values, font sizes, and settings are taken verbatim
  from the design. The only judgment-call escalation is the Slice 5 "body 8 too small" fallback —
  stop and ask the user rather than deciding.
