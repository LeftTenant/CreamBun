---
name: enum-rename-partial-test-coverage
description: an approved enum-value/int-backed rename can leave older, out-of-scope tests hardcoded to the old value — expected, not a bug to silently paper over
type: feedback
---

When a fix plan renames or removes an `@export`ed int-backed enum value (e.g.
`ItemData.EquipSlot`) and also changes seed/starter data that used the old
value, older tests elsewhere in the suite that hardcode the old value's name
or derived data (item id, weight, count) can keep failing even after every
test file the task explicitly named is green. This happened on issue #30
(EquipSlot BOOTS/GLOVES/NECKLACE -> GOGGLES/BELT blob redesign): three tests
outside the task's listed scope
(`tests/integration/foundation/test_save_manager_integration.gd`,
`tests/unit/resources/data/test_player_data_resource.gd`,
`tests/unit/ui/notebook/inventory/test_inventory_tab_scene.gd::test_starter_bag_resolves_to_non_zero_weight_via_local_registry`)
hardcoded the old starter item's id (`sample_boots`) and weight (0.8kg) and
failed once the starter item was swapped for a blob-appropriate replacement.

**Why:** the test plan doc that accompanies these multi-file design changes
(e.g. `tests/integration/notebook/test_plan_issue_30.md`) is often explicit
that the starter item's exact name/slot is "being changed independently" and
out of scope for that pass — i.e. the test engineer intentionally left those
assertions unrenovated for a follow-up, rather than it being an oversight.

**How to apply:** after satisfying the explicitly-listed must-pass tests, run
the full unit+integration suite and diff any newly-failing tests against the
task's file list. If a failure hardcodes exactly the old value/id/weight your
approved plan was told to remove, don't edit the test (out of scope, owned by
test engineer) and don't contort the implementation to preserve the old
id/name just to keep it green — check for a test-plan doc first; if it
documents the gap as a known follow-up, implement the design-correct behavior
and flag the specific failing tests + file paths in your final report instead.
