# Slice 3 — Resize Viewport to 320×180 / Window to 640×360 — Test Plan

Scope: change `[display]` in `project.godot` to render at 320×180 with a 640×360 launch window
(2×), **keeping `stretch/mode="viewport"`** (unchanged this slice). Confirm the world and notebook
still fit and frame correctly at the new render size; fix any UI that hard-assumed 640×360.

Design reference: `docs/refactors/pixel-art-purist-size-and-theme.md` §1 and §7 Step 4.

---

### E2E

- [ ] Launching the game opens a 640×360 window with the world scene visible and no engine error
      overlay (confirms the viewport/window pair is accepted by Godot).
- [ ] The world tilemap and player sprite are fully visible inside the viewport at game start — no
      tile row or player sprite is clipped by the new 320×180 render boundary.
- [ ] Opening the notebook (I key) shows the Book panel filling most of the 320×180 canvas with no
      content clipped outside the window edges and no horizontal or vertical overflow scrollbars
      appearing on the Book container itself.
- [ ] The Dimmer `ColorRect` behind the notebook covers the full viewport with no uncovered corners
      (anchors_preset=15 on a 320×180 canvas, verified visually).
- [ ] The Player's spawn position at world-space `(640, 360)` — the old viewport centre — is still
      reachable and the camera frames it without placing the player off-screen at the new render
      size. (This is an e2e concern because it depends on camera framing, not just settings; the
      coder may change the spawn or camera offset as a fix — the test verifies the outcome, not the
      fix approach.)

---

### Integration

*(No cross-system flows are introduced or broken by a pure `project.godot` settings change — the
only runtime interaction that reads the viewport size is `settings_tab.gd`'s
`_scaled_window_size()`, and that function reads from `ProjectSettings` dynamically, so it
self-corrects once the setting changes. No integration test is warranted for this slice.)*

---

### Unit

- [ ] `project.godot` `[display]` block sets `window/size/viewport_width` to `320`.
- [ ] `project.godot` `[display]` block sets `window/size/viewport_height` to `180`.
- [ ] `project.godot` `[display]` block sets `window/size/window_width_override` to `640`.
- [ ] `project.godot` `[display]` block sets `window/size/window_height_override` to `360`.
- [ ] `project.godot` `[display]` block still has `window/stretch/mode` equal to `"viewport"` (the
      stretch change is Slice 4 — assert it was NOT changed here).
- [ ] `project.godot` `[display]` block does NOT yet contain `window/stretch/aspect` or
      `window/stretch/scale_mode` keys (those are Slice 4 additions — assert absence to prevent
      accidental over-application).

All six items are verified by `tests/unit/test_display_settings.gd`, which parses `project.godot`
as text and asserts the key=value pairs directly (no Godot runtime needed — this is the
file-as-data pattern used by prior slices in this refactor).

---

## Judgment calls

**Player spawn position `(640, 360)`.** `world.tscn` places the Player node at
`position = Vector2(640, 360)` — the centre of the old 640×360 viewport. At 320×180 this is four
viewport-lengths to the right and two down, so it starts off-screen unless the camera follows the
player from the start. This is an e2e concern (camera/framing), not a unit-test concern — the
unit tests cannot determine whether the camera compensates. The e2e item above flags this
specifically. If the coder finds the player off-screen, the fix is most likely moving the spawn to
`Vector2(160, 90)` (the new viewport centre) or confirming the camera is already tracking. That
decision is deferred to the coder; the test only verifies the observable outcome.

**`settings_tab.gd` fallback defaults.** `_scaled_window_size()` uses `640` and `360` as fallback
defaults when `ProjectSettings.get_setting` fails (i.e. in isolated unit tests that never load
`project.godot`). After this slice the real settings will return `320`/`180`, so the fallbacks are
now stale but harmless — they only fire when the setting is absent entirely (test isolation). A
unit test for `_scaled_window_size` would need to mock `ProjectSettings`, which is disproportionate
for a two-line utility. Noted here as a known inaccuracy in the fallback values; a follow-up
can update them to `320`/`180` for documentation clarity, but it is not a correctness issue.

**Stretch mode assertion direction.** The unit test asserts `stretch/mode` is still `"viewport"`
to act as a guard rail against accidentally merging Slice 4's changes into this PR. If both slices
are executed together, this assertion will fail and prompt the author to revisit scope.

**No integration test.** The only consumer of the viewport dimensions at runtime (`settings_tab.gd`
`_scaled_window_size`) reads `ProjectSettings` dynamically — no hardcoded constant, no cached
value. After the settings change it will naturally return `320`/`180`-based window sizes. An
integration test would require spinning up the full notebook/settings tab to call one function that
has no branching logic — not worth the fixture complexity for this slice.
