# Scenario: Notebook renders in monogram font (Slice 2)

Verifies that after Slice 2 (Apply theme to notebook), opening the notebook at
the current 640×360 window shows text rendered in the monogram pixel font and
that the base theme is loaded and active — not Godot's default UI font and
fallback theme.

Design doc reference: `docs/refactors/pixel-art-purist-size-and-theme.md` §4
(palette) and §6.2 (theme path).
Slice spec: `docs/features/pixel-art-purist/slices.md` Slice 2.

The window is **640×360** (the current project size before Slice 3 shrinks it to
320×180), so reference screenshots are taken at that resolution. Re-running this
scenario after Slice 3 will require new baselines.

## Setup

- Load scene: `res://world/world.tscn`
- Wait: 10 frames
- Assert: node property `Notebook.visible` == `false`

## Steps

### Step 1: Open the notebook on the Inventory tab

- Press action: `open_notebook_inventory`
- Wait: 15 frames (allow the tab's populate_left/populate_right to finish and
  the renderer to settle before capturing)
- Assert: node property `Notebook.visible` == `true`
- Assert: `GameState.current_state` == `NOTEBOOK`
- Screenshot → save / compare reference:
  `tests/e2e/pixel-art-purist/screenshots/notebook_monogram_step_01_inventory.png`

**Visual checkpoints for this screenshot:**

1. **Font family (monogram, not default UI font):**
   - Text in the notebook — slot labels ("Backpack", "Clothing", …), weight
     display ("Weight: … / ∞"), and any heading — must render in the monogram
     pixel font: boxy, low-resolution letterforms with no antialiasing or
     subpixel hints. The default Godot UI font is a smooth sans-serif at higher
     resolution; the contrast is immediately visible.
   - Failure signature: text appears smooth, rounded, or at a noticeably larger
     pixel size than the surrounding UI chrome.

2. **Theme resource loaded and active (not raw engine defaults):**
   - The notebook's text and background colors may differ from the raw Godot
     engine fallback, confirming that `base_theme.tres` has been assigned and
     is cascading to the notebook. Exact color values are not asserted here.
   - Failure signature: every visual property exactly matches an unthemed
     Godot project (e.g. default grey Control background, default white Label
     color), indicating the theme resource is not reaching the notebook at all.
   - **Note:** Full §4 palette coloring — paper-cream Panel background
     (`#f4e9d8`) via a StyleBoxFlat and ink text color (`#3b2f2a`) via
     `default_color` — is intentionally deferred to a later per-control
     override phase and is NOT verified by this slice.

### Step 2: Close the notebook and clean up

- Press action: `ui_cancel`
- Wait: 10 frames
- Assert: node property `Notebook.visible` == `false`
- Assert: `GameState.current_state` == `PLAYING`

## Notes for the executor

- **Reference screenshots** committed under `tests/e2e/pixel-art-purist/screenshots/`
  are the single agreed baseline. On first run (before any reference exists),
  save the captured frame as the reference and review it manually against the
  visual checkpoints above before committing.
- **Transient / comparison frames** captured while iterating must be saved to
  `.godot-test-reports/e2e/` (gitignored), never into the committed
  `tests/e2e/` tree. Use `get_config` to retrieve `reports_dir`.
- The scenario's scope is limited to **font family** and **theme presence** only.
  It does not audit exact palette colors (deferred to a later per-control phase),
  font size correctness per-widget (Slice 5), stretch mode (Slice 4), or viewport
  dimensions (Slice 3). Do not expand the screenshot checks to those concerns here.
- If `GameEvents` or `GameState` are not available (e.g. the sandbox cannot
  resolve autoloads), the visual font and color checks on the screenshot remain
  the primary proof of pass/fail for this scenario.
