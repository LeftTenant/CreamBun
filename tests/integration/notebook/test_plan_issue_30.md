# Test plan — Issue #30: Redesign inventory equipment page (blob character, no limbs)

## Bug
The inventory tab's equipment page (`ui/notebook/inventory/inventory_tab.tscn`)
models the OLD limbed CreamBun via `ItemData.EquipSlot`
(`resources/data/items/item_data.gd`): six slots — BACKPACK, CLOTHING, BOOTS,
GLOVES, GOGGLES, NECKLACE. The current CreamBun is a small round blob with no
limbs, so BOOTS and GLOVES don't make sense, and the six-slot list (each
`EquipmentSlot` node has an 18px min-height) is tall enough to overflow the
equipment page's height budget at the 320×180 target resolution.

## Fix under test
Replace `EquipSlot` with **NONE, BACKPACK, CLOTHING, GOGGLES, BELT** —
BOOTS and GLOVES are removed entirely (not repurposed), and NECKLACE is
renamed to BELT. This shrinks the left equipment page by two slot-heights.
Affected production files (not edited by this pass): `item_data.gd`,
`equipment_slot.gd`, `inventory_tab.gd`, `inventory_tab.tscn`, `inventory.gd`
doc comments, `player_data_resource.gd` (starter item moves off BOOTS).

## Save-compat risk (flagged, not fixed by this pass)
`EquipSlot` is int-backed and both `ItemData.equip_slot` and
`Inventory.equipped` (keyed by the enum) are `@export`ed, so
`ResourceSaver.save()` (see `autoloads/save_manager.gd`) persists these as
raw ints inside `.tres` save files. `PlayerDataResource.rehydrate()` is a
documented no-op and there is no version-keyed migration for `equip_slot`.
Removing BOOTS/GLOVES (which sit before GOGGLES) and renaming NECKLACE→BELT
shifts GOGGLES from 5→3 and repurposes the old NECKLACE slot (6) as unused —
any save file written before this fix that has GOGGLES or NECKLACE equipped
will silently reinterpret as the wrong slot (or a slot that no longer
resolves to a name) on load. No migration exists yet; this plan only adds a
regression test that pins the new int values so a *future* accidental
reorder is caught in CI, and documents the risk here for a follow-up
(save_version bump + migration) rather than solving it in this bugfix.

## E2E (not exercised in this pass)
- [ ] `tests/e2e/notebook/inventory_actions.md` and `tests/e2e/notebook/test_plan.md`
      script equipping "Old Boots" into the BOOTS slot, which no longer
      exists after the fix. These scenario docs (and their reference
      screenshots) need a rewrite/regeneration once the starter item and
      slot rename land — flagged for a follow-up `godot-testing:run-e2e`
      pass, out of scope here.

## Unit

- [ ] `ItemData.EquipSlot` contains exactly NONE, BACKPACK, CLOTHING,
      GOGGLES, BELT — BOOTS, GLOVES, NECKLACE are gone
      (`tests/integration/foundation/test_foundation_layer.gd::test_item_data_has_equip_slot_enum`)
      (FAILS pre-fix: BOOTS/GLOVES/NECKLACE still present, BELT absent.)
- [ ] `EquipSlot`'s int values are pinned (NONE=0, BACKPACK=1, CLOTHING=2,
      GOGGLES=3, BELT=4) so a future reorder is caught in CI — save-compat
      regression guard, see risk note above
      (`tests/integration/foundation/test_foundation_layer.gd::test_item_data_equip_slot_values_are_stable_after_blob_redesign`)
      (FAILS pre-fix: BELT doesn't exist yet; GOGGLES is still 5, not 3.)
- [ ] `EquipmentSlot._slot_name()` returns "Backpack"/"Clothing"/"Goggles"/"Belt"
      for the four retained slots, and the empty/filled/selection/drag-drop
      behaviors from issue #7 still hold when exercised against retained
      slots instead of BOOTS/GLOVES
      (`tests/unit/ui/notebook/inventory/test_equipment_slot.gd`)
      (FAILS pre-fix: BELT label test — BELT doesn't exist yet.)
- [ ] `inventory_tab.tscn` declares exactly 4 equipment slot placeholder
      nodes — Slot_BACKPACK, Slot_CLOTHING, Slot_GOGGLES, Slot_BELT — and no
      longer declares Slot_BOOTS, Slot_GLOVES, or Slot_NECKLACE
      (`tests/unit/ui/notebook/inventory/test_inventory_tab_scene.gd`)
      (FAILS pre-fix: scene still declares the old 6-slot set.)

## Integration

- [ ] `Inventory.equip()`/`unequip()` round-trip correctly on the retained
      CLOTHING and GOGGLES slots (replacing BOOTS/GLOVES-based coverage);
      `unequip()` on an empty BELT slot returns null (replacing the
      NECKLACE-based coverage)
      (`tests/integration/foundation/test_foundation_layer.gd`)
      (FAILS pre-fix: BELT slot reference doesn't resolve to a valid value.)
- [ ] `populate_left()` builds exactly 4 EquipmentSlot nodes, not 6
      (`tests/integration/notebook/test_inventory_tab.gd::test_inventory_tab_populate_left_adds_six_slots`,
      renamed to `..._adds_four_slots`)
      (FAILS pre-fix: still builds 6.)
- [ ] A fresh `reset_to_new_game()` save renders 4 equipment slots on the
      left page and its equippable starter item lands in a valid *retained*
      slot (not BOOTS/GLOVES) on the right page — asserted generically since
      the starter item's exact name/slot is being changed independently
      (`tests/integration/notebook/test_inventory_tab.gd::test_fresh_player_data_renders_starter_bag_and_equipment_silhouette`)
      (FAILS pre-fix: 6 slots rendered; starter item still uses BOOTS.)
- [ ] InventoryTab signal wiring (slot_drop_received → `_on_slot_drop`, slot
      selection → Unequip button relabel, equip/unequip hotkey, mutation of
      `PlayerData.inventory.equipped`) continues to work when exercised
      against a retained slot (CLOTHING) using a locally-seeded fixture item
      instead of depending on the starter bag's (soon-to-change) equipped
      item
      (`tests/integration/notebook/test_inventory_tab_handlers.gd`)
      (FAILS pre-fix: CLOTHING-based assertions pass already since CLOTHING
      is untouched, but the file no longer compiles/passes as a whole once
      any remaining BELT-dependent expectations run — see individual test
      notes in the file.)

## Expected
Unit and integration tests above FAIL against current code (old 6-slot
enum, BOOTS/GLOVES/NECKLACE still present, BELT missing) and are expected to
PASS once the approved fix lands.
