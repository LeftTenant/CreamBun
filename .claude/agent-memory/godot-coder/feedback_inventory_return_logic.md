---
name: Inventory.add() leftover return value
description: The add() method must return count-minus-allowed, not zero after the stack loop exits
type: feedback
---

When `add()` enforces a capacity limit, it reduces `to_add` before entering the stack-manipulation block. After that block runs, `to_add` is 0 (all allowed items were placed). The leftover is NOT `to_add` at the end — it's `count - allowed_to_add` where `allowed_to_add` is the capacity-clamped value captured before the stackable/non-stackable branch.

**Why:** On first implementation the return was `count - (count - to_add) if to_add > 0 else 0`, which always returned 0 after a successful (but capacity-limited) add. The test expects `2` when only 2 of 4 items fit.

**How to apply:** Always capture `allowed_to_add = to_add` after the capacity check and before the stack mutation block. Return `count - allowed_to_add` unconditionally.
