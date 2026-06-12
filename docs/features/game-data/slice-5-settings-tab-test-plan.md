# Slice 5 — SettingsTab uses SaveManager.settings (per-device split) — Test Plan

### E2E
- [ ] Changing a setting (e.g. moving the Master Volume slider), closing the notebook, and
      reopening it to the Settings tab shows the changed value — not the `GameSettings`
      default — because the tab now reads `SaveManager.settings` instead of a fresh instance.

### Regression
- [ ] `tests/unit/ui/notebook/settings/test_settings_tab.gd` — `test_settings_tab_initial_volume_matches_game_settings`
      and `test_game_settings_defaults_are_correct` construct a bare `GameSettings.new()` as
      their expectation baseline; once `_ready()` sources `_settings` from `SaveManager.settings`,
      these tests need `SaveManager.settings` reset to defaults (or a fresh `GameSettings`
      assigned to it) in `before_each()` so the "defaults" precondition still holds.
- [ ] `tests/unit/ui/notebook/settings/test_settings_tab_scene.gd` — scene-as-data node lookups
      (`MasterSlider`, `MusicSlider`, `SfxSlider`, `TextSpeedSlider`, `WindowScaleOption`, reset
      buttons) are unaffected by the settings source change; confirm `populate_left`/`populate_right`
      still resolve and bind correctly when `_settings` is `SaveManager.settings` rather than a
      locally-constructed resource.
- [ ] `tests/integration/notebook/test_settings_tab_handlers.gd` — all six handler tests
      (master/music/sfx slider → AudioServer bus, window-scale → DisplayServer, left reset,
      right reset) still pass when `_tab._settings` is `SaveManager.settings`; reset assertions
      must restore `SaveManager.settings` to its documented defaults, not just `_tab._settings`'s
      in-memory copy, if any test reuses `SaveManager.settings` across cases.
- [ ] `tests/integration/notebook/test_settings_tab_layout.gd` — layout/anchoring assertions
      (slider margins, VBox insets, `SIZE_EXPAND_FILL`) are independent of the settings data
      source and must remain green; confirms this slice is data-sourcing only, no layout drift.
- [ ] `tests/integration/notebook/test_notebook_shell.gd` — open/close/state-machine tests
      (especially `test_notebook_close_emits_notebook_closed_signal` and the pause/unpause
      pair) still pass once `notebook.gd`'s close path gains a `save_settings()` (or equivalent)
      side effect — no new pause leakage, no new required scene dependencies for tests that
      don't open the Settings tab.
- [ ] `tests/e2e/notebook/settings_controls.md` — the existing settings-controls scenario
      (defaults populated, sliders move, both resets restore documented defaults) still passes
      against `SaveManager.settings`-backed state; reset assertions compare to `GameSettings`
      defaults exactly as before.

### Integration
- [ ] `SettingsTab._ready()` (or `populate_left`/`populate_right`, whichever runs first) sets
      `_settings` to `SaveManager.settings` — the same object identity, not a copy — so slider
      edits mutate the shared per-device settings directly.
- [ ] A value changed via a `SettingsTab` slider/option (e.g. `master_volume`, `window_scale`)
      is immediately reflected on `SaveManager.settings` (read independently of the tab),
      confirming there is no separate copy drifting from the shared instance.
- [ ] Closing the notebook (`notebook.gd`'s close path / `GameEvents.notebook_closed`) triggers
      `SaveManager.save_settings()`, writing the current `SaveManager.settings` to
      `user://settings.tres`.
- [ ] After a settings change + notebook close + `SaveManager.load_settings()` into a fresh
      `GameSettings` instance, the reloaded values match what was changed (round-trip via the
      shared settings file) — proving persistence works end-to-end through the notebook's
      close hook, not just via a direct `save_settings()`/`load_settings()` call.
- [ ] Reopening the notebook to the Settings tab after a close+reopen cycle shows the persisted
      (non-default) values on the sliders/option button — `SettingsTab` does not reset to
      `GameSettings` defaults on a second `populate_left`/`populate_right` pass.
- [ ] Settings changes do NOT touch `PlayerData` — `PlayerData.to_resource()` (inventory, quest
      log, map state, gold) is unchanged after a settings-only edit + notebook close, confirming
      the per-device/per-save split holds.
- [ ] If `notebook.gd` gains a single shared close hook (per the Slice 5/6 coordination note),
      that hook fires exactly once per `close()` call and triggers `save_settings()` regardless
      of which tab was last active when the notebook closed.

### Unit
- [ ] `SettingsTab` with `SaveManager.settings` pre-set to non-default values (e.g.
      `master_volume = 0.3`, `window_scale = 4`) populates its sliders/option button from those
      values on `populate_left`/`populate_right` — not from `GameSettings.new()` defaults.
- [ ] The left-page and right-page "Reset to Defaults" buttons still reset `_settings` (now
      `SaveManager.settings`) to the documented `GameSettings` defaults (`master_volume = 1.0`,
      `music_volume = 1.0`, `sfx_volume = 1.0`, `text_speed = 1.0`, `window_scale = 2`) — reset
      behavior is unchanged by the data-source swap.
- [ ] `SettingsTab` does not construct its own `GameSettings.new()` in `_ready()` when
      `SaveManager.settings` is already populated (guards against the old fresh-instance code
      path silently surviving alongside the new one).

---

## Open questions for the user

1. **Exact close hook (design §11 Step 4).** The design doc says "persist via
   `SaveManager.save_settings()` on notebook close" and notes `notebook.gd` already emits
   `notebook_closed`. Two plausible hooks exist:
   - **(a)** `notebook.gd`'s `close()` method calls `SaveManager.save_settings()` directly
     (or via a small private helper), alongside its existing `GameEvents.notebook_closed.emit()`.
   - **(b)** A listener (e.g. `SettingsTab` itself, or a new top-level connection) subscribes to
     `GameEvents.notebook_closed` and calls `save_settings()` in response.

   Per the slices.md coordination note, Slice 6 (Sessions tab) also wants to act on notebook
   close (saving the active slot). **This plan assumes option (a) — a single hook inside
   `notebook.gd`'s `close()`** that both slices extend, since that avoids two independent
   `notebook_closed` listeners doing unrelated persistence work with no defined ordering. If the
   implementation instead goes with (b) or introduces two separate listeners, the integration
   tests above ("closing the notebook triggers `save_settings()`" and "the shared close hook
   fires exactly once") should be adjusted to match — but the *outcome* (settings persisted on
   close) stays the same either way.

2. **Reset-button defaults vs. shared instance.** The reset buttons currently reset the local
   `_settings.*` fields and slider widgets. Once `_settings` is the shared `SaveManager.settings`
   object, a reset writes those defaults into the shared instance immediately (even before
   notebook close/save). This seems correct and is what the Integration section above tests for,
   but flagging it in case the team wants reset-then-close to behave differently (e.g. reset is
   provisional until save).

---

## Summary

This slice swaps `SettingsTab._settings` from a per-session `GameSettings.new()` to the shared
`SaveManager.settings` (already populated by Slice 2's `load_settings()`), and adds a
`save_settings()` call to the notebook's close path so edits survive a close+reopen via
`user://settings.tres`. The plan leans on the existing settings-tab and notebook-shell suites as
regression guards — they should all stay green — plus new integration coverage for the
read-from-shared-instance and save-on-close round trip. The exact close-hook shape (item 1 above)
is the main open question, since it is the shared touchpoint with Slice 6.
