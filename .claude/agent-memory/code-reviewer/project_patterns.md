---
name: CreamBun Code Patterns
description: Recurring patterns, architectural decisions, and gotchas found during Phase 1 Foundation Layer review
type: project
---

## Established Patterns

**current_weight() takes a registry**: The implementation of `Inventory.current_weight(registry: Dictionary)` accepts an external item registry (StringName → ItemData), deviating from the design doc which shows no parameter. The rationale is documented in inventory.gd: add() uses a separate `_inline_weight()` that relies on ItemStack.item (set at add() time) because the registry isn't available there. The test was written to match the implementation, not the spec. This is an intentional design decision made during implementation.

**Signal types on GameEvents autoload**: `game_events.gd` uses typed signal parameters referencing class_name types (`ItemData`, `StorySlot`). This is safe in Godot 4.4 because the project scanner registers all global class_names before autoloads are initialized.

**Autoloads have no class_name**: `game_state.gd` and `game_events.gd` intentionally omit `class_name` — they are accessed as singleton names only. Inner enums on autoloads (e.g. `GameState.State`) are accessible via the singleton name in Godot 4.

**E key intentional conflict**: `notebook_equip` and `interact` both bind to physical_keycode 69 (E). This is intentional per design doc — the notebook script consumes input first when open, preventing conflict.

## Notebook Shell Patterns (Phase 1 Sub-feature 2)

**GameState.State type hint on autoload inner enum**: `_previous_state: GameState.State` is valid — Godot 4 exposes inner enums on autoload singletons via `AutoloadName.EnumName` syntax even without a class_name.

**GDScript enum as Dictionary**: Inner enums in GDScript are dictionaries. `SomeEnum.size()` returns the count of entries and `SomeEnum.has("KEY")` checks string keys. Both are valid. The codebase uses `NotebookTab.size()` for tab cycling modulo — works but a named constant would be more readable.

**CanvasLayer visible property**: Godot 4.4 CanvasLayer exposes `visible` — setting it in a .tscn is valid and functional.

**ColorRect under CanvasLayer needs explicit anchors**: CanvasLayer does not propagate rect to its children. Any ColorRect meant to fill the viewport must set `anchor_right = 1.0` and `anchor_bottom = 1.0` explicitly (or `anchors_preset = 15`). The Dimmer in notebook.tscn is missing this.

**Redundant minimum size in .tscn + _ready()**: PagePanel sets `custom_minimum_size` in both the .tscn and `_ready()`. The _ready() value wins; having both causes confusion when editing one without the other.

## Known Logic Gaps (not tested, not critical for Phase 1)

**remove() single-stack assumption**: `Inventory.remove()` only finds the first stack matching an item_id and checks if that one stack has enough. If a stackable item spans multiple stacks (only possible when max_stack is exceeded), remove() may incorrectly return false even when the total count is sufficient. No Phase 1 test exercises multi-stack removal (all tests use max_stack=99).

**equip() allows NONE slot (now fixed)**: `Inventory.equip()` previously lacked a guard for `equip_slot == NONE`. The Phase 1 Inventory Tab implementation adds that guard at the call site (`_do_equip()` checks `item.equip_slot == ItemData.EquipSlot.NONE` before calling equip), and `Inventory.equip()` itself also pushes a warning and returns null for NONE-slot items.

**current_weight() vs design doc**: Design doc line 137 shows `func current_weight() -> float` with no parameter. Implementation adds `registry: Dictionary`. The test matches the implementation. If the design doc is later treated as the authoritative spec for other tabs, this discrepancy needs resolving.

## Inventory Tab Patterns (Phase 1 Sub-feature 7)

**_find_by_class uses Script.get_global_name()**: The test helper uses `child.get_script().get_global_name()` to match nodes by `class_name`. `Script.get_global_name()` was added in Godot 4.3 and is available in 4.4. The recursion correctly walks the full subtree (not just direct children), so grandchildren like EquipmentSlots inside a VBoxContainer are found.

**set_drag_preview() outside drag context**: Calling `_get_drag_data()` directly in a GUT test triggers `set_drag_preview()` outside an active drag. Godot 4 handles this with a WARN_PRINT (not push_error), so GUT does not record it as a test failure. The return value of `_get_drag_data()` is still correct, and test 7 passes despite the warning.

**Tab builds UI in _ready(), not populate_left/right**: InventoryTab builds sample item data in `_ready()` (runs on add_child_autofree) and builds the rendered UI only when `populate_left/right()` are called. Tests that need rows must call populate_right() explicitly after add_child_autofree.

**_do_equip() / _do_throw() read stack BEFORE free**: Both action methods capture `stack` as a local variable before setting `_selected_row = null` and calling `_refresh_both_pages()`. The refresh calls `child.free()` on old row nodes. The local `stack` variable holds a reference to the stack Resource (not the row node itself), so there is no use-after-free. The freed InventoryRow node is never accessed again after the action completes.

**Plain Array for EquipSlot iteration**: `populate_left()` uses `var slots: Array = [...]` instead of `Array[ItemData.EquipSlot]` because GDScript 4 does not support typed arrays of inner enum types. The iteration variable is typed `slot_enum: int`. This is the established pattern for this codebase.
