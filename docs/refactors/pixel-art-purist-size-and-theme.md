# Pixel-Art-Purist: Viewport, Window, Fonts & Theme — Refactor Design

## Summary

This refactor commits CreamBun to a **pixel-art-purist** presentation: a low base
resolution, integer-scaled window, nearest-neighbour textures everywhere, a crisp
bitmap-style pixel font (monogram), and a shared `Theme` resource that gives every UI
surface — starting with the notebook — a consistent palette and typography.

The goal is that *every pixel on screen is square and sharp*, the world and the UI share
the same visual grammar, and text never blurs. This is a **refactor design doc**: it
captures the target settings, the rationale behind each choice, and the Godot 4.6 best
practices to follow. It does **not** implement code — it is the map an implementer (or the
feature-orchestrator) follows.

The current state already leans this way: `project.godot` sets
`textures/canvas_textures/default_texture_filter=0` (Nearest) and an empty
`resources/theme/base_theme.tres` exists. This doc closes the remaining gaps: the viewport
is currently **640×360** (not 320×180), the stretch mode is `viewport` (this refactor moves it
to `canvas_items`), no integer scale mode or pixel-snap is set, and the theme has no font or
palette yet.

---

## Goals

- **Crisp text** in both UI and world at any window scale — no blur, ever.
- A single **base `Theme`** resource that defines the default font, default font size, and a
  small, named **color palette** reused across the notebook and future in-game dialogs.
- A **320×180** base viewport with a **2× (640×360)** default window, integer-scaled.
- A documented **art constraint**: sprites authored in multiples of 16 px.
- Import the **monogram** font into `resources/theme/` correctly (derived from `art/`, never
  referenced from `art/` at runtime), with the right flags for pixel-perfect glyphs.
- Concrete, diff-against-current project settings so adoption is unambiguous.

## Non-Goals

- Implementing any of this in the editor or in code (this is design only).
- Designing the notebook's content/layout — that lives in
  `docs/features/notebook/design.md`. We only revise its **font sizing** here.
- Per-platform fullscreen/HiDPI tuning, mobile touch UI scaling, or localization font
  fallback. Noted as future work where relevant.
- Audio, gameplay, or save-format changes.

---

## 1. Viewport & Window Sizing

### Target

| Concept | Value | Why |
|---|---|---|
| Base viewport (render resolution) | **320 × 180** | 16:9, tiny enough for a chunky retro look; 320 = 20×16 px tiles wide. |
| Default window size | **640 × 360** (2×) | Comfortable on a laptop; exact integer multiple of the viewport. |
| Aspect ratio | 16:9 | Scales cleanly to 1280×720, 1920×1080, 2560×1440, 3840×2160 with no black bars. |

320×180 is the canonical "small but readable" 16:9 pixel-art base resolution recommended by
GDQuest and the Godot manual. Every common monitor resolution is an **integer multiple** of
it (720p = 4×, 1080p = 6×, 1440p = 8×, 4K = 12×), so integer scaling never letterboxes on a
16:9 display.

### project.godot changes

Current `[display]` block:

```ini
[display]

window/size/viewport_width=640
window/size/viewport_height=360
window/size/window_width_override=1280
window/size/window_height_override=720
window/stretch/mode="viewport"
```

Target `[display]` block:

```ini
[display]

window/size/viewport_width=320
window/size/viewport_height=180
window/size/window_width_override=640
window/size/window_height_override=360
window/stretch/mode="canvas_items"
window/stretch/aspect="keep"
window/stretch/scale_mode="integer"
```

- `viewport_width/height` = the **render resolution** (320×180).
- `window_width_override/height_override` = the **actual window** the player sees at launch
  (640×360 = 2×). The override exists precisely so the render resolution and the launch
  window can differ.
- The `window_scale` field already referenced in the notebook's `GameSettings`
  (`docs/features/notebook/design.md` §3.2, default `4`) maps to this override at runtime —
  the Display settings tab lets the player pick 1×/2×/3×/4×.

> Note: the editor writes these keys via **Project Settings → Display → Window**. Prefer
> editing through the editor UI so it normalizes related keys; the INI above is the expected
> result, useful as a review diff.

---

## 2. Pixel-Perfect Rendering Settings

### Stretch mode: `canvas_items` (decided)

Godot offers two relevant stretch modes for pixel art:

- **`viewport`** — the game renders at 320×180 and the *whole frame* is scaled up. Everything
  is uniformly pixelated. Downside: smooth motion (tweens, camera pans, particles) snaps to
  the 320×180 grid and looks jagged, and — importantly for us — **fonts can render blurry**
  because text is rasterized into the low-res buffer then stretched.
- **`canvas_items`** — sprites are still authored and snapped to the pixel grid, but the UI
  layer and 2D transforms render at the *window's* resolution using 320×180 as a reference.
  Sprites stay crisp, fonts stay crisp, and smooth camera/particle motion is possible.

**We choose `canvas_items`.** It is the GDQuest-recommended default for pixel art and avoids
the blurry-font problem of `viewport` mode, which directly serves this refactor's primary
goal. This is a **change from the current `viewport` setting**.

The cost: with `canvas_items`, fractional camera positions can introduce sub-pixel shimmer on
sprites. We mitigate that with the snap settings below.

### Stretch aspect: `keep`

`keep` enforces the single 16:9 aspect with letterbox bars on odd window shapes — the
simplest, most predictable choice and the right starting point for a beginner project. If we
later want ultrawide / variable framing we can switch to `expand` (shows *more* world rather
than bars). Recorded under Alternatives.

### Scale mode: `integer`

Since Godot 4.3, `Display > Window > Stretch > Scale Mode = integer` constrains the upscale to
whole numbers (2×, 3×, 4×…), guaranteeing perfectly square pixels. Without it, a maximized but
non-multiple window (e.g. 1366×768) would scale by 4.27× and smear the pixel grid. With it,
Godot picks the largest integer factor that fits and letterboxes the remainder.

### Snap 2D transforms & vertices to pixel

In **Project Settings → Rendering → 2D** (advanced toggles on):

```ini
[rendering]

2d/snap/snap_2d_transforms_to_pixel=true
2d/snap/snap_2d_vertices_to_pixel=true
```

These round node/vertex positions to whole pixels at render time, eliminating the sub-pixel
shimmer that `canvas_items` mode can otherwise produce on moving sprites. Pair this with a
`Camera2D` that has **Position Smoothing disabled** (or pixel-snapped) so the camera itself
never lands on a fractional coordinate.

### Default texture filter: Nearest (already set)

`textures/canvas_textures/default_texture_filter=0` (Nearest) is **already present** in
`project.godot` — keep it. This makes every texture, including font atlases, use
nearest-neighbour sampling so scaled pixels stay hard-edged. Individual `Sprite2D`/`TextureRect`
nodes should leave their filter on the project default rather than overriding to Linear.

---

## 3. Fonts: Importing "monogram" Correctly

### What ships in `art/fonts/monogram/`

The downloaded pack contains several variants:

- `ttf/` — `monogram.ttf`, `monogram-extended.ttf` (more glyphs/diacritics), plus italics.
- `bitmap/` — a `monogram-bitmap.png` atlas + JSON descriptors (BitFontMaker export).
- `pico-8/` — a PICO-8 `.p8` port (not used here).
- `credits.txt` — CC0, by Vinícius Menézio (@vmenezio).

**Recommendation: use the TTF (`monogram-extended.ttf`).** In Godot 4 a TTF imported as a
`FontFile` with antialiasing off renders identically crisp to a bitmap font, but is far easier
to work with (any integer size, automatic kerning, the extended glyph set for future
localization). The bitmap PNG is a fine fallback but pins you to its baked size and a manual
BMFont setup. We keep the bitmap variant in `art/` as an archive.

### art/ vs resources/ workflow (project rule)

Per `CLAUDE.md`: `art/` holds **original** assets; runtime references must point at
**`resources/`**. The font is no exception.

Workflow:

1. **Copy** `art/fonts/monogram/ttf/monogram-extended.ttf` into
   `resources/theme/fonts/monogram-extended.ttf`.
2. Let Godot import it (creates `monogram-extended.ttf.import` + a cached `FontFile`).
3. Adjust the import flags (below), then **Reimport**.
4. The base theme (and any node) references **only** the `res://resources/theme/fonts/…`
   copy. Nothing at runtime ever points into `art/`.

> Why copy rather than reference `art/` directly: keeping derived, import-tuned assets under
> `resources/` means the `art/` originals can be re-exported or reorganized without breaking
> the game, and the runtime asset set is self-contained for export builds.

### Import flags for crisp pixel text

Select the imported `.ttf` in the FileSystem dock → **Import** tab → set:

| Import setting | Value | Why |
|---|---|---|
| **Antialiasing** | `None` (Disabled) | The #1 cause of blurry pixel fonts. Off = hard edges. |
| **Hinting** | `None` | Hinting nudges glyph shapes for AA'd rendering; pointless and distorting for pixel fonts. |
| **Subpixel Positioning** | `Disabled` | Forces glyphs onto whole-pixel origins so text never lands between pixels. |
| **Multichannel Signed Distance Field (MSDF)** | `Off` | MSDF is for smooth scaling of vector fonts — the opposite of what we want. |
| **Mipmaps** | `Off` | Mipmaps blend down-scaled text; we never downscale and want no blending. |
| **Force Autohinter** | `Off` | Same reasoning as hinting. |

Project-wide, **Default Texture Filter = Nearest** (already set, §2) ensures the font atlas
itself samples without bilinear smoothing.

### Recommended font sizes

monogram's design size is **16** (or any multiple of 16): at size 16 its glyphs land on a
clean 6×12 px cell with perfect strokes. Off-multiple sizes (e.g. 13, 20) introduce uneven
stems because the rasterizer can't split a pixel.

At a **320×180** base resolution, size 16 is *large* — a 16 px line is ~9% of screen height,
so only ~11 lines fit top to bottom. Guidance:

| Use | Size | Notes |
|---|---|---|
| **Body / default** | **8** | Half the design size — still an exact divisor, renders crisp 3×6 glyphs. ~22 lines fit vertically. The everyday notebook/dialog text size. |
| **Headings / titles** | **16** | Full design size; use sparingly (tab titles, quest titles, dialog speaker names). |
| **Captions / hints** | **8** | Same as body; differentiate with color, not size. |

Stick to **8 and 16** only. Both are exact divisors/multiples of the 16 design size, so both
stay pixel-perfect. Avoid 12 — it is *not* a clean multiple and will look slightly off at this
font's native grid. (If 8 proves too small in playtest, the fallback is to bump the body to 16
and accept fewer lines, rather than introducing a non-multiple size.)

---

## 4. Theme Resource

### Structure

`resources/theme/base_theme.tres` (already exists, currently empty) becomes the **one base
theme** for all UI. It defines:

- **Default Font** → `res://resources/theme/fonts/monogram-extended.ttf` (the imported copy).
- **Default Font Size** → `8` (body text; §3 recommended sizes).
- A set of **named colors** (palette below), exposed as theme *colors* so nodes reference them
  by role rather than by literal hex.
- Per-control-type overrides as needed later (e.g. `Panel` stylebox for the page background,
  `Button` hover color). Phase 1 keeps these minimal.

### How nodes consume the theme

In Godot, a `Theme` set on a `Control` **cascades to all its `Control` descendants** unless a
child overrides it. So the notebook's root (`BookFrame`/the notebook `CanvasLayer`'s top
Control) gets `theme = base_theme.tres`, and every label, button, and panel beneath it
inherits the font, size, and colors automatically. Future in-game dialog boxes set the same
base theme on their root and inherit the identical look for free.

For one-off tweaks, a node uses a **theme type variation** (e.g. a `Label` variation named
`"Heading"` that sets font size 16) rather than hard-coding overrides on the node — keeping all
typography decisions centralized in the theme resource.

> Migration note: the notebook design currently points at
> `resources/data/notebook_theme.tres` (`docs/features/notebook/design.md` §9). That reference
> should be **redirected to `resources/theme/base_theme.tres`** so the notebook and future
> dialogs share one theme rather than each owning a private one. See §6.

### Proposed color palette (named roles)

A small, cozy palette — warm paper and ink tones, with a gentle accent. These are **roles**,
so the literal hex can be retuned once art lands without touching node code. Values are
starting points (soft, low-contrast, life-sim friendly), not final art direction.

| Role (theme color name) | Hex | Used for |
|---|---|---|
| `paper_bg` | `#f4e9d8` | Page background (notebook pages, dialog body). |
| `paper_bg_shadow` | `#e3d4bd` | Subtle inner page edge / alternating rows. |
| `ink` | `#3b2f2a` | Primary text — warm dark brown, not pure black. |
| `ink_muted` | `#7a6a5d` | Secondary text, hints, completed/dimmed items. |
| `accent` | `#c8743c` | Selection highlight, active tab, focus ring (warm orange). |
| `accent_soft` | `#e7b07e` | Hover state, lighter accent fills. |
| `success` | `#6f8f4a` | Completed quest checkmarks, positive feedback. |
| `frame_line` | `#2a201c` | 1 px borders / dividers between page sections. |
| `disabled` | `#b6a892` | Greyed-out buttons (e.g. Recycle when not recyclable). |

Notes:
- Text is `ink` on `paper_bg` — a warm, soft pairing that reads as "old notebook," avoiding the
  harsh pure-black-on-white that fights the cozy tone.
- `accent` is the single selection/focus color shared by every UI surface, so focus always
  reads the same whether the player is in the notebook or a dialog.
- This is the **starter** set. Adding a dialog box later means reusing these roles, not
  inventing new ones — extend the palette only when a genuinely new role appears.
- The `/colors/*` entries above are named **roles** — they exist so a value can be looked up or
  retuned by name, but declaring a color role does not by itself make anything render with it.
  Each Control type needs its own concrete theme property pointing at a role before the palette
  is visible: `Panel/styles/panel` and `PanelContainer/styles/panel` (both `StyleBoxFlat`
  sub-resources) apply `paper_bg` / `paper_bg_shadow` as backgrounds with a `frame_line` border,
  and `Label/colors/font_color` applies `ink` as the default text color. `PanelContainer` needs
  its **own** stylebox entry — Godot's theme type inheritance chain is
  `PanelContainer → Container → Control`, which never passes through `Panel`, so a
  `Panel/styles/panel` entry alone does not theme `PanelContainer` nodes (e.g. the equipment
  slot icon frames, `page_panel.tscn`). `Button` theming (styleboxes and all font states) is
  intentionally **not yet applied** — see issue #48 — because Button's built-in dark stylebox
  needs matching stylebox work before a font color change would stay legible.

---

## 5. Sprite / Art Constraints

**Rule: author all world/sprite art in multiples of 16 px** (16, 32, 48, …). The base tile is
**16×16**.

Rationale: the 320×180 viewport is exactly **20 tiles wide** (320 ÷ 16) and **11.25 tiles tall**
(180 ÷ 16). Width tiles perfectly. Height does **not** — that trailing `.25` (a 4 px sliver) is
deliberate and fine:

- **The world scrolls** via a `Camera2D`, so the vertical viewport never needs to show a whole
  number of tiles — the camera simply shows a 180 px-tall slice of a larger map. The `.25` is
  invisible in play.
- For **anything that must align to the full screen height** (a full-screen UI background, a
  fixed HUD bar), design against **180 px**, not "11.25 tiles." UI is measured in pixels, not
  tiles, so the fractional tile count is a non-issue there.
- The notebook book-frame art, being UI, is sized in pixels (e.g. ~280×160 with margins inside
  320×180) and ignores the tile grid entirely.

So: **16 px multiples for world tiles and sprites; raw pixel sizes for UI.** The 11.25 wrinkle
only matters if someone tries to tile the *background of a static screen* vertically — in which
case use a 16×16-tiling region plus a 4 px filler strip, or simply a single 320×180 art piece.

If a future system ever needs a tile count that divides 180 evenly, 180 = 12 tiles of 15 px or
20 tiles of 9 px — but **we are not changing the tile size**; 16 px stays the standard and the
camera absorbs the remainder.

---

## 6. Notebook Adjustments

The notebook design (`docs/features/notebook/design.md`) predates this refactor and assumes a
320×180 viewport already (§9 "Pixel-perfect" mentions 320×180 with `stretch=viewport`). This
refactor confirms 320×180 but **changes stretch to `canvas_items`** and pins concrete font
sizing and the shared theme. Required updates to that doc:

1. **Stretch mode** — §9 says `stretch=viewport`; update to `canvas_items` (§2 here).
2. **Theme path** — §9 points at `resources/data/notebook_theme.tres`; redirect to
   `resources/theme/base_theme.tres` so the notebook inherits the shared base theme rather than
   owning a private copy.
3. **Font sizes** — adopt **body 8 / heading 16** (§3). Concretely:
   - Tab titles, quest titles, Story names, dialog speaker names → **16** (`Heading` variation).
   - Inventory rows, weight readout, quest descriptions, settings labels, the close hint
     (`"I to open/close • Esc to close"`), objective bullets → **8**.
   - The `Weight: 12.4 / 30.0` header and similar → **8**; differentiate by `ink` vs `ink_muted`
     color, not size.
4. **Layout implication** — at 320×180 with 8 px body text, a notebook page is small. Expect
   roughly **18–20 short rows** per page maximum. The inventory/quests `ScrollContainer`s
   (already in the design) are therefore load-bearing, not optional — long lists must scroll.
   Two-page spreads should budget ~140×150 px per page after the book frame margins.
5. **Page cycling** — unaffected by this refactor. The recent change to `PageUp`/`PageDown`
   (`notebook_page_next`/`notebook_page_prev`, commit `d012fba`) stands; only typography and
   theme references change here.

No notebook *behavior* changes — purely presentation (resolution context, font, theme, sizes).

> **Single source of truth (for now):** this refactor doc is authoritative for the
> stretch mode, theme path, and font sizes. `docs/features/notebook/design.md` is **not** yet
> updated to match. Bringing it in line (the four edits above: stretch → `canvas_items`, theme
> path → `resources/theme/base_theme.tres`, body 8 / heading 16) is a **required deliverable of
> executing this refactor** — see §7 Step 8. Until that execution happens, defer to this doc
> wherever the two disagree.

---

## 7. Migration / Phasing Plan

Ordered so the game never ends up in a broken intermediate state. Each step is independently
verifiable in the editor.

**Step 1 — Font import (no visible change yet).**
Copy `monogram-extended.ttf` to `resources/theme/fonts/`, set the import flags (§3), reimport.
Verify the `FontFile` previews crisp in the editor.

**Step 2 — Populate the base theme.**
Open `resources/theme/base_theme.tres`: set Default Font to the imported font, Default Font Size
to 8, and add the named palette colors (§4). Add a `Heading` `Label` type variation at size 16.
Still no scene references it — safe.

**Step 3 — Apply theme to the notebook root.**
Set `theme = base_theme.tres` on the notebook's top-level `Control`. Update the notebook design
doc's theme reference (§6.2). Verify the notebook renders in monogram. Do this **before**
changing the viewport, so font legibility is confirmed at the current 640×360 first.

**Step 4 — Viewport + window resize.**
Change `[display]` to 320×180 / 640×360 (§1), but **keep `stretch=viewport` for this step** to
isolate the resolution change. Launch; confirm the world and notebook fit and the camera frames
correctly at the new render size. Fix any UI that assumed 640×360.

**Step 5 — Switch stretch mode + add snap/scale settings.**
Set `stretch/mode=canvas_items`, `stretch/aspect=keep`, `stretch/scale_mode=integer`, and the
two `2d/snap/*` flags (§2). Confirm fonts are now crisp (the payoff of `canvas_items`) and
sprites don't shimmer when the camera moves. Disable camera position smoothing if shimmer
appears.

**Step 6 — Notebook font-size pass.**
Apply body 8 / heading 16 across notebook tabs via the theme + `Heading` variation (§6.3).
Verify legibility at 1× (320×180) — the worst case. If 8 is unreadable, escalate to the §3
fallback.

**Step 7 — Document the art constraint.**
Record the "multiples of 16 px, camera absorbs the 11.25" rule (§5) wherever art guidelines
live (README or an `art/README`). Communicate to anyone authoring sprites.

**Step 8 — Reconcile `docs/features/notebook/design.md` (required, not optional).**
Update the notebook design doc so it matches the *final* settings this refactor lands, keeping
the two docs consistent once execution is complete. Apply all of §6's required edits to that doc:
- Stretch mode: §9's `stretch=viewport` → **`canvas_items`**.
- Theme path: §9's `resources/data/notebook_theme.tres` → **`resources/theme/base_theme.tres`**.
- Font sizes: pin **body 8 / heading 16** per §6.3 (and the layout implication in §6.4).
This step is a **deliverable of the refactor**, not a follow-up nicety — do not consider the
refactor done until the notebook design doc reflects canvas_items, the redirected theme path,
and 8/16 sizing. (Steps 3 and 6 touch parts of this inline; Step 8 exists to guarantee the doc
is fully reconciled and nothing is left stale.)

Rollback at any step is a single settings/theme revert; no code depends on these values except
the notebook's `GameSettings.window_scale` mapping, which already expects an integer multiplier.

---

## Alternatives Considered

- **640×360 native (no 320×180 base)** — rejected: less chunky/retro, larger sprites to author,
  and we want the purist low-res look. 320×180 still scales cleanly to all 16:9 targets.
- **`viewport` stretch mode** — rejected: blurs fonts and jags smooth motion; `canvas_items`
  gives crisp text + smooth camera, directly serving this refactor's goal.
- **`expand` stretch aspect** — deferred: shows variable content on odd aspect ratios; `keep`
  is simpler and predictable for now. Revisit if ultrawide support is wanted.
- **Fractional scale mode** — rejected: smears the pixel grid on non-multiple windows; integer
  scaling is the whole point.
- **Bitmap (.fnt/PNG) monogram instead of TTF** — rejected for default use: pins us to a baked
  size and manual BMFont setup; the AA-off TTF is equally crisp and far more flexible. Bitmap
  kept as an `art/` archive.
- **A per-feature theme (notebook owns its own `.tres`)** — rejected: duplicates palette/font
  decisions; one shared `base_theme.tres` keeps the notebook and future dialogs consistent.
- **Body font size 12** — rejected: not a clean multiple of monogram's 16 design grid, so stems
  render unevenly. Use 8 or 16 only.

---

## Sources / References

- Godot Manual — Multiple resolutions (stretch mode, aspect, integer scale): <https://docs.godotengine.org/en/stable/tutorials/rendering/multiple_resolutions.html>
- GDQuest — Setting up pixel art graphics in Godot 4 (texture filter, viewport, integer scale): <https://www.gdquest.com/library/pixel_art_setup_godot4/>
- Godot Manual — Importing fonts (antialiasing, hinting, bitmap vs dynamic): <https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_fonts.html>
- Godot Manual — Using Fonts: <https://docs.godotengine.org/en/stable/tutorials/ui/gui_using_fonts.html>
- Godot Manual — Using the theme editor / GUI skinning: <https://docs.godotengine.org/en/stable/tutorials/ui/gui_using_theme_editor.html>
- itch.io — Godot 4.4 settings for pixel art (snap-to-pixel, scale mode): <https://itch.io/blog/806788/godot-44-settings-for-pixel-art>
- Mina Pêcheux — Doing pixel-perfect in Godot the right way: <https://medium.com/codex/doing-pixel-perfect-in-godot-the-right-way-77cd39f8f23d>
- Godot proposals — Pixel perfect games discussion: <https://github.com/godotengine/godot-proposals/discussions/9256>
- monogram font (datagoblin, CC0) — design size 16 / 6×12 glyph cell: <https://datagoblin.itch.io/monogram>
