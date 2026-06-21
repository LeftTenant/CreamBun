# Pixel-Art-Purist Slice 4 — Pixel-Perfect Stretch + Snap Settings: Test Plan

Design reference: `docs/refactors/pixel-art-purist-size-and-theme.md` §2 and §7 Step 5

## What this slice does

Flips five `project.godot` keys that deliver the refactor's core "crisp text, square pixels"
promise:

- `display/window/stretch/mode` → `"canvas_items"`
- `display/window/stretch/aspect` → `"keep"`
- `display/window/stretch/scale_mode` → `"integer"`
- `rendering/2d/snap/snap_2d_transforms_to_pixel` → `true`
- `rendering/2d/snap/snap_2d_vertices_to_pixel` → `true`

The world `Camera2D` lives in `player/player.tscn` as a child of the player node. Its
`position_smoothing_enabled` property is **not present** in the `.tscn` file, which means it
inherits Godot's engine default of `false` — position smoothing is already off. The e2e shimmer
check therefore verifies sprites remain stable without needing a settings change; if shimmer
does appear, the coder should set `position_smoothing_enabled = false` explicitly in the scene
as a documented fix.

---

## Guard-rail assertions that must change in this slice

`tests/unit/test_display_settings.gd` (written for Slice 3) contains **three guard-rail
assertions that directly contradict the Slice 4 target state**. They must be updated — not
silently deleted — so the file's intent remains clear:

| Existing test method | What it currently asserts | Required change in Slice 4 |
|---|---|---|
| `test_stretch_mode_is_still_viewport()` | `window/stretch/mode="viewport"` | Replace: assert the value is now `"canvas_items"`. Rename to `test_stretch_mode_is_canvas_items()`. |
| `test_stretch_aspect_key_is_absent()` | `window/stretch/aspect` key does not exist | Replace: assert the key equals `"keep"`. Rename to `test_stretch_aspect_is_keep()`. |
| `test_stretch_scale_mode_key_is_absent()` | `window/stretch/scale_mode` key does not exist | Replace: assert the key equals `"integer"`. Rename to `test_stretch_scale_mode_is_integer()`. |

These were intentional slice-boundary guards. Updating them is a required part of Slice 4, not
optional cleanup.

---

### E2E

- [ ] At 1x window size (640x360), a screenshot of the notebook open with text visible shows
      hard pixel edges on every glyph — no blur, no anti-aliasing fringe.
- [ ] At a scaled window (e.g. 1280x720, the 4x integer scale), a screenshot of the same
      notebook text shows the same hard-edged glyphs without any smoothing or color fringing.
- [ ] After the player walks several tiles (camera pan), a screenshot shows world sprites
      without shimmering or sub-pixel jitter — edges remain consistent between frames.

Scenario file: `tests/e2e/pixel-art-purist/text_is_crisp.md`

---

### Integration

- [ ] Loading `player/player.tscn` as a PackedScene confirms the Camera2D child node does not
      have `position_smoothing_enabled` set to `true` (ensuring no scene override silently
      re-enables smoothing after the default is relied upon).

---

### Unit

All assertions below belong in `tests/unit/test_display_settings.gd`, extending the file from
Slice 3. The three guard-rail methods listed in the table above are replaced; the Slice 3
dimension tests (`viewport_width_is_320`, etc.) are left untouched.

**New / replaced assertions:**

- [ ] `window/stretch/mode` equals `"canvas_items"` (replaces the Slice 3 guard that asserted
      this was still `"viewport"`).
- [ ] `window/stretch/aspect` equals `"keep"` (replaces the Slice 3 guard that asserted this
      key was absent).
- [ ] `window/stretch/scale_mode` equals `"integer"` (replaces the Slice 3 guard that asserted
      this key was absent).
- [ ] `rendering/2d/snap/snap_2d_transforms_to_pixel` equals `true` in the `[rendering]`
      block of `project.godot`.
- [ ] `rendering/2d/snap/snap_2d_vertices_to_pixel` equals `true` in the `[rendering]` block
      of `project.godot`.

**Existing Slice 3 tests that must still pass (no changes):**

- [ ] `window/size/viewport_width` is `320` — unchanged.
- [ ] `window/size/viewport_height` is `180` — unchanged.
- [ ] `window/size/window_width_override` is `640` — unchanged.
- [ ] `window/size/window_height_override` is `360` — unchanged.
- [ ] `textures/canvas_textures/default_texture_filter` is `0` (Nearest) — already set before
      Slice 1 and must remain untouched. Note: Godot writes this key in short form (without the
      `rendering/` prefix) under the `[rendering]` header in project.godot; the test matches the
      short form accordingly. The snap keys above (`rendering/2d/snap/…`) are written WITH the
      `rendering/` prefix even though they also live in `[rendering]` — this is Godot's
      convention for that sub-path.

---

## Judgment calls and scope notes

**Guard-rail flip is the main risk.** The three guard-rail tests are failing by design after
Slice 3 (they will fail the moment Slice 4 keys are written). The coder and reviewer must
confirm the replacements are exact inversions of the old assertions — not weaker versions. If
there is any ambiguity, flag before merging.

**Camera2D smoothing: verify-then-act.** Position smoothing is off by default and is not
explicitly set in `player/player.tscn`, so no scene edit is expected. The e2e shimmer test is
the safety net. If that test reveals shimmer, the fix is a one-line scene property set — it is
not in scope until the e2e proves it is needed.

**`canvas_items` vs `viewport` — the payoff.** The switch from `viewport` to `canvas_items`
is why the font-crispness e2e test matters. Under `viewport` mode the font rasterized at
320x180 then stretched; under `canvas_items` the UI renders at window resolution using 320x180
as a reference, so glyphs are sharp at any scale. The screenshot tests are the only way to
verify this rendering difference — no in-process GUT assertion can confirm it.

**`keep` aspect = letterbox on non-16:9 windows.** The e2e test does not need to verify
letterboxing explicitly; that is a deferred concern (design §8 Alternatives). This slice only
checks that the setting is written correctly.

**Snap flags are in `[rendering]`, not `[display]`.** The helper in `test_display_settings.gd`
currently searches the full file text, not a specific INI section, so it will find
`rendering/2d/snap/*` keys by their full key path regardless of section header. No new helper
is needed, but the test description and comments should name the correct section to avoid
confusion.
