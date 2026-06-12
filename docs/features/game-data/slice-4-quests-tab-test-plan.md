# Slice 4 — QuestsTab reads from PlayerData; seeding moves to PlayerDataResource — Test Plan

### E2E
(none — `tests/e2e/notebook/quests_detail.md` already covers the placeholder → detail flow
with the seeded foraging-book quest; the seeded shape is unchanged by this slice, so no new
scenario is needed. Its "seeded in `QuestsTab._ready()`" framing comment becomes stale and
should be updated to point at `PlayerDataResource._seed_starter_content()` as a docs-only
follow-up, not a new test item.)

### Regression
Slice 4 deletes `QuestsTab._quest_log` and its `_ready()` seeding block, replacing reads with
`PlayerData.quest_log`. The following existing tests construct or inspect `QuestsTab` directly
and are most at risk of breaking if the new `PlayerData`-backed read path is wired incorrectly
or `before_each()` doesn't seed `PlayerData` the way a fresh game does:
- [ ] `tests/unit/ui/notebook/quests/test_quests_tab.gd::test_quest_log_pre_populates_with_foraging_book` — currently asserts `tab._quest_log.states.has(&"the_foraging_book")`; `_quest_log` no longer exists on `QuestsTab` after this slice, so this test must be rewritten to assert against `PlayerData.quest_log` (or removed if redundant with a new PlayerData-facing test)
- [ ] `tests/unit/ui/notebook/quests/test_quests_tab.gd::test_quests_tab_populate_left_adds_rows` — depends on the foraging-book quest being present and COMPLETED so `populate_left()` produces a row; will render an empty list if `PlayerData.quest_log` isn't seeded in `before_each()`
- [ ] `tests/unit/ui/notebook/quests/test_quests_tab.gd::test_view_button_press_drives_selection` — requires at least one visible quest row with a ViewButton to press; same seeding dependency as above
- [ ] `tests/integration/notebook/test_quests_tab.gd::test_completed_rows_in_completed_section_and_separator_visibility` — explicitly asserts the foraging-book row lands in `CompletedSection` and the separator is hidden; this is the most direct guard on the seeded COMPLETED shape surviving the migration
- [ ] `tests/integration/notebook/test_quests_tab.gd::test_view_button_press_transitions_right_page_to_detail` — needs a row to click; same seeding dependency
- [ ] `tests/integration/notebook/test_quests_tab.gd::test_reselect_does_not_duplicate_quest_detail_subtree` — same seeding dependency (needs a clickable row)
- [ ] `tests/integration/notebook/test_quests_tab.gd::test_populate_left_and_right_round_trip` — baseline smoke test; lower risk but still depends on `QuestsTab` constructing without the deleted `_quest_log` field
- [ ] `tests/unit/ui/notebook/quests/test_quests_tab_scene.gd` (all tests) — lower risk since these are scene-as-data tests independent of `_quest_log`, but `_make_scene_instance()` adds a bare `QuestsTab` to the tree, so confirm `_ready()` no longer references the deleted field without crashing

### Integration
- [ ] A `QuestsTab` added to the tree with `PlayerData` seeded via `reset_to_new_game()` (fresh-game state) renders the foraging-book quest as COMPLETED in `CompletedSection`, with `CompletedSeparator` hidden — the same outcome the old self-seeded tab produced
- [ ] Pressing the foraging-book row's ViewButton renders the right-page detail view with the title, description, and all three objectives shown as `[x]` (sourced from `PlayerData.quest_log.states[&"the_foraging_book"]["completed_objectives"]`)
- [ ] `QuestsTab` no longer exposes a `_quest_log` member (deleted), and `populate_left`/`populate_right` work correctly when the only quest-progress source is `PlayerData.quest_log`
- [ ] Two independently-instantiated `QuestsTab`s reading the same seeded `PlayerData.quest_log` render identical quest progress (single shared source of truth — the scenario the migration is meant to enable)

### Unit
- [ ] `QuestsTab._get_status(quest_id)` returns `QuestLog.Status.COMPLETED` for `&"the_foraging_book"` when reading from `PlayerData.quest_log` seeded via `reset_to_new_game()`, and `HIDDEN` for an unknown quest id not present in `PlayerData.quest_log.states`
- [ ] `PlayerDataResource._seed_starter_content()`'s `quest_log.states[&"the_foraging_book"]` entry shape (`{"status": QuestLog.Status.COMPLETED, "completed_objectives": [0, 1, 2]}`) matches exactly what `QuestsTab._refresh_right_page()` reads (`entry["status"]` for sectioning via `_get_status`, `entry["completed_objectives"]` as an `Array` for the objectives checklist) — confirms the single seeding location produces the same shape the tab previously hand-seeded
- [ ] Quest *definitions* still load from `the_foraging_book.tres` via `load()` in `_ready()`, unaffected by the `quest_log` source change (`_quests` array is populated as before)
