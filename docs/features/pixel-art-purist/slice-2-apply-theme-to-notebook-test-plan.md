# Slice 2 — Apply the theme to the notebook: Test Plan

Feature: **pixel-art-purist** · Slice: **2 — Apply the theme to the notebook**
Design doc: `docs/refactors/pixel-art-purist-size-and-theme.md` (§4 Theme Resource, §6.2 theme path)
Slice spec: `docs/features/pixel-art-purist/slices.md` (Slice 2)

## What this slice delivers

`resources/theme/base_theme.tres` (populated in Slice 1) gets wired onto the notebook so every
`Control` in the notebook — including the `LeftPage`/`RightPage` subtrees that each tab
reparents in via `populate_left`/`populate_right` — renders in monogram with the §4 palette.
The notebook design doc's theme reference (§9, currently
`resources/data/notebook_theme.tres`) is redirected to `resources/theme/base_theme.tres` (the
§6.2 edit). No notebook behavior changes — this is presentation only, verified at the
**current 640×360 window** before Slice 3 shrinks the viewport.

## Where the theme must actually be set (read before writing tests)

`Notebook` (`ui/notebook/notebook.tscn`) is a **`CanvasLayer`**, which is not a `Control` and has
no `theme` property — `Theme` cascading only happens through the `Control` tree
(<https://docs.godotengine.org/en/stable/tutorials/ui/gui_using_theme_editor.html>). The first
`Control` in the notebook's tree is **`Book`** (a `Panel`, parent of `Pages` → `LeftPage` /
`RightPage`). Setting `theme = base_theme.tres` on `Book` is therefore the cascade point that
reaches `LeftPage`/`RightPage` and everything tabs reparent into them at runtime — per
`ui/CLAUDE.md` rule 4, those subtrees are the *only* parts of a tab scene that are mounted
in-game, so the theme must be live on an ancestor that is present at runtime, not just on a tab
scene's editor-preview root.

Tests below are written against `Book.theme` (or whichever ancestor `Control` the coder
chooses, provided it is an actual runtime ancestor of `LeftPage`/`RightPage` inside
`notebook.tscn`) — **not** against any tab `.tscn`'s root node.

## Verification strategy

This slice is "wire one resource onto one node, redirect one doc reference." The proof that
matters is: (1) the theme assignment is data on the scene that survives instantiation, (2) the
cascade actually reaches a reparented tab subtree at runtime — the exact thing that would
silently fail if the theme were set on the wrong node (e.g. a tab's editor-only root) — and (3)
it visibly renders in monogram. One scene-as-data unit test covers (1) and (2); one e2e scenario
covers (3). No integration test is warranted — there is no cross-autoload signal flow or
multi-system wiring here, just a single scene's theme property and its `Control` cascade, which
the unit test already exercises by instantiating the real scene.

### E2E

- [ ] Opening the notebook (any tab) at the current 640×360 window renders its visible text in the monogram font, not the default Godot UI font — confirmed by visual comparison against a reference screenshot.
- [ ] The notebook's page background and text colors match the §4 palette (warm paper background, dark warm-brown ink text) rather than default theme colors (white/black) — confirmed by the same screenshot.

### Integration

_None._ This slice is a single scene's theme assignment and its `Control`-tree cascade — no
autoload signal flow, no cross-scene wiring, and no multi-node interaction beyond what
instantiating `notebook.tscn` already exercises in the unit test below. An integration test here
would duplicate the unit test's instantiation without proving anything additional.

### Unit — `tests/unit/ui/notebook/test_notebook_theme.gd`

- [ ] `notebook.tscn` loads as a valid `PackedScene` and instantiates without error.
- [ ] The runtime-ancestor `Control` of `LeftPage`/`RightPage` (`Book`, or whichever node the
  coder assigns) has its `theme` property set to `resources/theme/base_theme.tres` once the
  scene is instantiated.
- [ ] After instantiating the notebook and switching to a tab (so `populate_left`/
  `populate_right` reparent that tab's `LeftPage`/`RightPage` subtree into the notebook's
  pages, as `_show_tab()` does), a `Control` inside the reparented subtree (e.g. a `Label`)
  resolves `get_theme_font("font", "")` / `get_theme_default_base_scale()`-equivalent to the
  base theme's monogram font and default size 8 — i.e. `Control.theme` lookups on a
  *reparented* node walk up to the notebook's theme, not just a node that was already in the
  scene at edit time.
- [ ] A tab scene's own root node (the editor-preview-only root, per `ui/CLAUDE.md` rule 4) is
  **not** required to carry `theme` itself — the cascade comes from the notebook ancestor after
  reparenting, so this test does not assert anything about tab scene roots.

### Documentation — `docs/features/notebook/design.md`

- [ ] §9's theme reference no longer points at `resources/data/notebook_theme.tres`; it reads
  `resources/theme/base_theme.tres` (the §6.2 edit), matching the resource this slice actually
  wires onto the notebook.

## Out of scope (do not test here)

- Viewport/window resize to 320×180 / 640×360 — Slice 3. This slice verifies at the *current*
  640×360 window deliberately, to isolate font legibility from the resolution change.
- Stretch mode / aspect / scale_mode / 2D snap settings — Slice 4.
- Per-widget `Heading` variation usage and the body-8/heading-16 font-size pass across tabs —
  Slice 5. This slice only confirms the *default* (body, size 8) font cascades; it does not
  audit individual labels for correct size or variation.
- §9's stretch-mode (`viewport` → `canvas_items`) and font-size (body 8 / heading 16) doc edits
  — Slice 6 (and Slice 5 respectively). Only the theme-path sentence in §9 is in scope here.
- Re-tuning palette hex values or adding new theme roles — Slice 1 already landed the §4
  starter set verbatim; this slice only wires it up.

## Notes for the test author

- To exercise the reparenting cascade, drive it the same way the real flow does: instantiate
  `notebook.tscn`, add it to the tree (so `_ready()` runs and `@onready` refs resolve), then call
  `_switch_tab(NotebookTab.INVENTORY)` (or `open(NotebookTab.INVENTORY)`) so
  `InventoryTab.populate_left/populate_right` reparent `LeftPage`/`RightPage` content in — then
  inspect a node from that reparented content for its resolved theme font/size. Asserting on a
  node that was never reparented would not prove the cascade reaches tab content.
- For the e2e scenario, reuse the existing `tests/e2e/notebook/` lifecycle pattern (load
  `world.tscn`, press `open_notebook_inventory`, wait frames, screenshot) — no new setup
  machinery is needed. Save the reference screenshot under
  `tests/e2e/pixel-art-purist/screenshots/`.
- Per the harness conventions, any transient/comparison screenshots taken while iterating go to
  `.godot-test-reports/e2e/`, not the committed `tests/e2e/` tree — only the final agreed
  reference frame is committed.

## Judgment calls made while writing this plan

- **Cascade-point node name.** The design doc and slice spec say "the notebook root" without
  naming a node; `Notebook` itself (a `CanvasLayer`) cannot hold a `theme`. I identified `Book`
  (the top-level `Panel`/`Control`, ancestor of `Pages` → `LeftPage`/`RightPage`) as the concrete
  runtime cascade point from reading `notebook.tscn`, and wrote the unit test against "the
  runtime ancestor of LeftPage/RightPage" rather than hardcoding `Book` by name — the coder may
  reasonably choose a different ancestor `Control` (e.g. add a new top-level `Control` wrapper),
  and the test should hold either way as long as it's a real runtime ancestor.
- **No integration test.** The slice spec doesn't explicitly call for one, and I considered
  whether the reparenting cascade (notebook ↔ tab subtree) counts as "cross-system" enough to
  warrant one. I judged it does not — it's a single scene's `Control` tree and the existing
  scene-as-data unit-test pattern (see `test_inventory_tab_scene.gd`) already instantiates the
  real scene and exercises `populate_left/right`, so a separate integration test would just
  re-run the same instantiation without new proof.
- **e2e scope kept to one scenario, two checks.** The slice spec lists one e2e file
  (`notebook_renders_monogram.gd`/`.md`); I kept it to font-family and palette-color checks only
  (the two things this slice actually changes), rather than re-screenshotting every tab — that
  breadth belongs to Slice 5's legibility pass once font *sizes* are also in play.
- **`equipment_slot.tscn` hardcoded font sizes (12/10) not flagged as a blocker.** I noticed
  `ui/notebook/inventory/equipment_slot.tscn` has `theme_override_font_sizes` of 12 and 10,
  which will visually clash once the base theme's size-8 default cascades in. This is a Slice 5
  (font-size pass) concern, not a Slice 2 test — flagging here only as a heads-up so it isn't
  lost, not as an item on this plan's checklist.
