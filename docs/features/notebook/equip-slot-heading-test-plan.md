# Equip Slot Heading & Selection (Issue #7) — Test Plan

### Integration
- [x] Selecting a filled equipment slot relabels the right-page Equip button to "Unequip (E)"
- [x] Invoking the equip-action (button press) with a slot selected calls `Inventory.unequip()`, returns the item to `PlayerData.inventory.stacks`, and emits `item_unequipped` + `inventory_changed`
- [x] Invoking the equip-action via the `notebook_equip` hotkey (E) with a slot selected performs the same unequip
- [x] The slot's heading Label remains visible (not hidden) after the item is unequipped and the slot becomes empty again
- [x] Selecting a bag row clears the active equipment-slot selection and restores the Equip button label to "Equip"

### Unit
- [x] equipment_slot.tscn declares an always-visible heading Label (separate from the icon)
- [x] equipment_slot.tscn declares a framed IconRect that sits beside the heading, not replacing it
- [x] equipment_slot.tscn declares a selection-only item-name Label
- [x] equipment_slot.tscn declares a selection highlight rect
- [x] `setup()` with an equipped item keeps the heading Label visible and populates the framed icon
- [x] `setup()` with no item (empty slot) shows the heading and hides the icon, item-name label, and highlight
- [x] `set_selected(true)` on a filled slot reveals the item-name label and the selection highlight
- [x] `set_selected(false)` hides the item-name label and the selection highlight again
- [x] Clicking a filled slot emits `selected` and shows the selection state
- [x] Clicking an empty slot does NOT emit `selected` and the slot remains unselected
