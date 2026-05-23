---
name: Inventory Design Decisions
description: Key design choices made during Phase 1 Foundation Layer testing that affect the Inventory API
type: project
---

**current_weight() registry pattern chosen (2026-05-02)**

`Inventory.current_weight()` accepts a `Dictionary` parameter (`registry: Dictionary`) mapping `StringName → ItemData`. This lets `ItemStack` stay a lightweight `item_id: StringName` + `count: int` record without needing a global item registry autoload.

**Why:** `ItemStack` stores only `item_id`, not a full `ItemData` reference, so weight lookups need a resolver. A dictionary parameter is the simplest beginner-friendly approach — no new autoload, no circular dependency.

**How to apply:** When implementing `Inventory.current_weight()`, signature is `func current_weight(registry: Dictionary) -> float`. When calling it in UI code, pass a `Dictionary` built from all known `ItemData` resources. Tests build this dictionary inline.

---

**Capacity enforcement rule**

When `capacity()` returns `0.0` (no backpack equipped), `add()` treats it as unlimited — no weight enforcement. Weight enforcement only activates when a backpack is equipped. Specified in the test prompt; confirmed by the design doc's intent (player starts without a backpack and can pick things up).

---

**equip() and stacks interaction**

`equip(item)` is expected to:
1. Remove the item from `stacks` (it came from inventory).
2. Place it in `equipped[item.equip_slot]`.
3. If a previous item was in that slot, add it back to `stacks` and return it.
4. Return `null` if the slot was empty.

`unequip(slot)` is expected to:
1. Remove the item from `equipped`.
2. Add it back to `stacks`.
3. Return the item (or `null` if slot was already empty).
