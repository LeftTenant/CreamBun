---
name: game-data-conventions
description: Durable PlayerData / SaveManager persistence conventions and Godot resource-caching facts — the "do not flag / this is intentional" list
metadata:
  type: project
---

Conventions for the game-data layer (`PlayerData` autoload, `PlayerDataResource`,
`SaveManager`, `GameSettings`). Treat these as intentional in reviews.

## Autoload order & the "never null" guarantee

`SaveManager` is declared before `PlayerData` in `project.godot`, so `SaveManager._ready()`
runs first and may call `PlayerData._load_resource()`. This is safe because
`PlayerData._resource` is initialized by an **inline field default**
(`var _resource := PlayerDataResource.new()`), which runs at construction, not in `_ready()`.
The `PlayerData` object therefore always has a non-null resource by the time any other
autoload's `_ready()` touches it. Don't flag this ordering as a bug — it's the documented
never-null guarantee.

`SaveManager._ready()` currently doubles as the launch hook (load settings + seed a slot).
This is an approved interim placement (to move to a main-menu New/Continue flow later); don't
flag it as a layering violation.

## Enums reachable from `PlayerDataResource` are a save schema

Anything `@export`ed on `PlayerDataResource` or its sub-resources is written to
`user://slots/slot_*.tres` by `ResourceSaver`, and **enums serialize as raw ints**. Two live
examples in `Inventory`: `equipped: Dictionary` is *keyed* by `ItemData.EquipSlot`, and each
stored `ItemData.equip_slot` is itself an int. So **reordering or removing a member of any
enum used as an exported value or a Dictionary key is a save-schema change**, even though
nothing in the source looks like a file format.

Failure mode when the numbering shifts: old keys silently re-alias (an item saved under the
old slot 3 renders in whatever slot is 3 now), and keys past the new maximum become orphans —
`inventory_tab.gd`'s `SLOT_NODE_NAMES` never resolves them, so the item is invisible in the
notebook and can never be unequipped. `equipment_slot.gd::_slot_name()` degrades to `"—"`
rather than erroring, so nothing fails loudly.

The migration hooks are `PlayerDataResource.CURRENT_VERSION` (+ the `save_version` stamp) and
`rehydrate()`, which is still a documented no-op. **How to apply:** on any enum change under
`resources/data/`, ask whether `CURRENT_VERSION` should be bumped — leaving it means pre- and
post-change files are indistinguishable forever, foreclosing a future migration. Slot 1
(`BACKPACK`) is load-bearing for `Inventory.capacity()`; keep it at 1.

## Resource caching / persistence facts

- **`ResourceSaver.save(res, path)` mutates `res.resource_path = path`** as a side effect. Since
  `PlayerData.to_resource()` returns the *live* shared instance (not a copy), saving it stamps
  that path onto the live object. Saving the same live resource to two different paths in
  sequence leaves `resource_path` pointing at whichever was saved last — watch for this in any
  multi-slot save/switch work.
- **Loading a just-saved slot needs `CACHE_MODE_REPLACE`.** After a save stamps the live
  instance into Godot's resource cache under `path`, a plain `ResourceLoader.load(path)` returns
  that same cached live instance — so in-memory edits made after the save would "win" on the
  next load (backwards from "switch story"). Use
  `ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)` to force a genuine fresh
  deserialization. The save→mutate→switch round-trip is the authoritative test for this; if it's
  ever removed or weakened, flag it.

## Shared-by-reference settings (exception to the `.duplicate()` rule)

`SettingsTab._settings = SaveManager.settings` is assigned **by reference, no `.duplicate()`** —
intentional, because `GameSettings` is per-device/shared-singleton data, not per-character
stats. The correct test is `assert_same()` (reference identity). Don't flag the missing
`.duplicate()` here; it's the deliberate exception to the general "always duplicate `.tres` data"
rule.

`notebook.gd close()` is the single shared close-persistence hook — `SaveManager.save_settings()`
runs on every close regardless of active tab. Future close-time persistence should extend this
method, not add a second `notebook_closed` listener.

## Test conventions

- **Seeding:** `PlayerDataResource.new()` → optionally `reset_to_new_game()` (for the starter
  bag / seeded quest) → `PlayerData._load_resource(data)` in `before_each()`. Tests that check
  pure scene structure seed a bare (empty) `PlayerDataResource.new()` instead.
- **Hermetic `user://` file I/O:** any test that triggers a real save/load or `close()` backs up
  the pre-existing bytes of `user://slots/slot_default.tres` / `user://settings.tres` in
  `before_each()` and restores or deletes them in `after_each()`.

## Related

[[project_patterns]], [[scene-migration-pattern]]
