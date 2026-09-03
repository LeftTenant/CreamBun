---
name: project-item-data-equipslot-ripple
description: ItemData.EquipSlot enum values (item_data.gd) are load-bearing across many unrelated-looking files — changing/removing a member is a wide, not narrow, change
metadata:
  type: project
---

`ItemData.EquipSlot` (defined inline in `resources/data/items/item_data.gd`) is referenced far
beyond the inventory UI. Before planning any fix that touches an EquipSlot member (add/remove/
rename), grep `BOOTS\|GLOVES\|EquipSlot` (or whichever member) across the whole repo — it
consistently turns up in:

- `ui/notebook/inventory/equipment_slot.gd` (`_slot_name()` match arm)
- `ui/notebook/inventory/inventory_tab.gd` (`SLOT_NODE_NAMES` dict + slot array)
- `ui/notebook/inventory/inventory_tab.tscn` (one `Slot_<NAME>` child node per member)
- `resources/data/items/inventory.gd` (doc comments, equip/unequip logic)
- `resources/data/player_data_resource.gd` (the starter-save seed item's `equip_slot`, e.g.
  the "Old Boots" sample item)
- `tests/unit/ui/notebook/inventory/test_equipment_slot.gd` and
  `test_inventory_tab_scene.gd` (scene-as-data node-name assertions)
- `tests/integration/foundation/test_foundation_layer.gd` (enum-membership + equip/unequip/
  swap coverage — tends to reuse one slot, historically BOOTS, as "the reliable slot to test
  with" in a dozen+ assertions)
- `tests/integration/notebook/test_inventory_tab_handlers.gd` (same "reliable slot" pattern,
  heaviest single consumer — 15+ references in one file)
- `tests/e2e/notebook/inventory_actions.md` + `tests/e2e/notebook/test_plan.md` (an entire e2e
  scenario built around equipping the seed boots item, with named reference screenshots)
- `docs/features/notebook/design.md` §5.2 (the ASCII silhouette diagram of slot positions)

**Why:** issue #30 (rework equipment slots for the blob-shaped CreamBun redesign, drop
limb-based BOOTS/GLOVES) looked like a small UI tweak but touches ~13 files spanning code,
tests, and docs, because tests lean on one enum member as a stand-in "any equippable item"
fixture rather than a dedicated test-only slot.

**How to apply:** when planning a fix that changes EquipSlot membership, budget for updating
all of the above categories, not just the `.tscn`/`.gd` slot UI. Flag the exact new slot set
as a design assumption if the issue doesn't pin one down — cheaper to confirm during review
than to re-touch 13 files twice. Regenerating e2e reference screenshots (see
`[[project_e2e_screenshot_regen]]` if that memory exists) is likely a required follow-up, not
optional polish.
