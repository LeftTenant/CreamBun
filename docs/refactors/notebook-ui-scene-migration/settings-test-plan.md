# Settings Tab — Scene Migration Test Plan

Regression-prevention plan for **Slice 1** of the Notebook UI Scene Migration refactor.
The goal is not to test new behaviour but to confirm that moving the settings layout
from GDScript into `settings_tab.tscn` does not silently break anything that works today.

---

### E2E

- [ ] Opening the notebook and navigating to the Settings tab renders the same visible layout
      as before the migration (two section headers, four sliders, one drop-down, two reset
      buttons) — confirmed by comparing a post-migration screenshot against the pre-migration
      reference screenshot.

---

### Integration

The tests below are a mix of **existing tests that must keep passing** (marked **[existing]**) and
**new tests** that guard migration-specific risks.

- [ ] **[existing]** `test_settings_tab_layout.gd :: test_left_page_sliders_within_margin` — all
      four `HSlider` nodes on `LeftPage` remain within the 10 px horizontal inset after the scene
      is instantiated via the new `populate_left()` implementation.

- [ ] **[existing]** `test_settings_tab_layout.gd :: test_right_page_option_button_within_margin` —
      the `WindowScaleOption` `OptionButton` on `RightPage` remains within the 10 px horizontal
      inset after migration.

- [ ] **[existing]** `test_settings_tab_layout.gd :: test_left_page_vbox_respects_margin_on_all_sides` —
      the root `VBoxContainer` reparented into `LeftPage` by the new `populate_left()` is inset by
      exactly 10 px on left, top, and right edges and does not overflow the bottom edge.

- [ ] **[existing]** `test_settings_tab_layout.gd :: test_right_page_vbox_respects_margin_on_all_sides` —
      the root `VBoxContainer` reparented into `RightPage` by the new `populate_right()` meets the
      same margin constraints.

- [ ] **[existing]** `test_settings_tab_layout.gd :: test_sliders_use_expand_fill` — every `HSlider`
      in `LeftPage` still carries `SIZE_EXPAND_FILL` after the scene instantiation path (property
      set in the `.tscn` rather than in code) takes effect.

- [ ] Moving a master volume slider to 0 propagates a `set_bus_volume_db` call on the Master audio
      bus (index 0) — the audio handler survives the migration from code-built nodes to
      scene-resolved `@onready` / named-node references.

- [ ] Moving the music volume slider propagates the correct dB value to audio bus index 1 (guarded
      by bus count).

- [ ] Moving the SFX volume slider propagates the correct dB value to audio bus index 2 (guarded
      by bus count).

- [ ] Selecting a window scale option in `WindowScaleOption` calls `DisplayServer.window_set_size`
      with the correct scaled pixel dimensions.

- [ ] Pressing the left-page reset button restores all four sliders to their default values (master
      100, music 100, sfx 100, text speed 100) and updates `_settings` accordingly.

- [ ] Pressing the right-page reset button sets `WindowScaleOption` selection to index 1 (the 2×
      default) without emitting `item_selected`.

---

### Unit

The tests below are a mix of **existing tests that must keep passing** (marked **[existing]**) and
**new tests**.

- [ ] **[existing]** `test_settings_tab.gd :: test_settings_tab_is_a_notebook_tab` — `SettingsTab`
      still extends `NotebookTab` after the script rewrite.

- [ ] **[existing]** `test_settings_tab.gd :: test_settings_tab_populate_left_adds_audio_sliders` —
      calling `populate_left()` on a bare parent `Control` still produces at least three `HSlider`
      descendants (master, music, sfx) via recursive search; the count is unaffected by the node
      names now coming from the `.tscn`.

- [ ] **[existing]** `test_settings_tab.gd :: test_settings_tab_populate_right_adds_option_button` —
      calling `populate_right()` still adds at least one `OptionButton` with at least 4 items.

- [ ] **[existing]** `test_settings_tab.gd :: test_settings_tab_window_scale_option_has_four_items` —
      the `OptionButton` still carries exactly 4 items after migration.

- [ ] **[existing]** `test_settings_tab.gd :: test_settings_tab_initial_volume_matches_game_settings` —
      `_master_slider.value` equals `GameSettings.master_volume * 100` immediately after
      `populate_left()` runs; the scene-declared `max_value` and initial binding are correct.

- [ ] **[existing]** `test_settings_tab.gd :: test_game_settings_defaults_are_correct` — spot-check
      that `GameSettings` defaults (master/music/sfx 1.0, window_scale 2) have not drifted;
      unchanged by the migration but still serves as a canary.

- [ ] **[new]** `settings_tab.tscn` can be loaded as a `PackedScene` without errors — verifies the
      file is valid and parseable before any instantiation happens.

- [ ] **[new]** `settings_tab.tscn` declares a node named `MasterSlider` of type `HSlider` — the
      stable named-node contract that `settings_tab.gd` depends on is encoded in the file, so a
      developer cannot accidentally delete the node in the editor without breaking this test.

- [ ] **[new]** `settings_tab.tscn` declares nodes named `MusicSlider`, `SfxSlider`, and
      `TextSpeedSlider`, each of type `HSlider`.

- [ ] **[new]** `settings_tab.tscn` declares a node named `WindowScaleOption` of type `OptionButton`.

- [ ] **[new]** `settings_tab.tscn` declares at least two `Button` nodes (the two reset buttons)
      somewhere in its subtree.

- [ ] **[new]** `settings_tab.tscn` declares at least two `Label` nodes with non-empty text whose
      content matches the section header strings `"Audio"` and `"Display"` — confirms the section
      headers are baked into the scene rather than injected at runtime.

- [ ] **[new]** `populate_left(null)` returns without error or crash after the migration (the null-
      guard in the script is preserved).

- [ ] **[new]** `populate_right(null)` returns without error or crash after the migration.
