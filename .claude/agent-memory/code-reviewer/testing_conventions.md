---
name: testing-conventions
description: GUT test conventions in CreamBun — .uid companions, mirrored dirs, class_name, continuation indent, world.tscn headless instantiation
metadata:
  type: project
---

Durable conventions for tests under `tests/` (GUT). Treat as the "do not re-flag /
do check for" list when reviewing new or modified test files.

**Why:** these are enforced by repo-wide consistency rather than by CLAUDE.md, so
they only surface by comparing against sibling test files.

**How to apply:** check each new test file against the points below before passing a review.

## File-level conventions

- **Every tracked `tests/**/*.gd` has a committed `.gd.uid` companion.** `.uid` is not
  gitignored. A new test script added without one produces a spurious diff the next time
  anyone opens the Godot editor. Ask the author to open the editor (or run a headless
  import) and commit the generated `.uid` alongside the script.
- **Test dirs mirror source dirs** — `world/` → `tests/integration/world/`,
  `player/` → `tests/integration/player/`. `.gutconfig.json` scans `res://tests/`
  recursively with prefix `test_` / suffix `.gd`, so no registration step is needed.
- **`class_name TestXxx` on every test file** (e.g. `TestWorldScene`, `TestPlayerScene`).
  Universal in this repo, including for files with no external callers.
- **Long header docstring** is the norm: what/why, the issue or slice reference, the GUT
  link, and both editor and `-gselect=` CLI run instructions.
- **Test plans live at `docs/features/<area>/<name>-test-plan.md`** as `- [ ]` / `- [x]`
  checklists grouped by `### E2E` / `### Integration` / `### Unit`. Boxes are ticked once
  the corresponding test exists and passes — an unticked box on a delivered test is stale.
- **"RED STATE, EXPECTED" header sections go stale.** The TDD workflow here writes the test
  first, so new test files often carry a header paragraph saying the implementation "does not
  exist yet / this script will not parse". Once the implementation lands that paragraph is
  false and actively misleads the next reader. Check for it in every review of a
  test-first slice and ask for it to be rewritten (or deleted) before commit.
- **Every committed `tests/e2e/**/screenshots/*.png` has a committed `*.png.import`
  sibling.** `.gitignore` only ignores `art/**/*.import`, so screenshot `.import` files are
  tracked. A `.png` committed without one shows up as an untracked `.import` the next time
  anyone imports the project. To confirm such a stray file is a benign reimport artifact and
  not a content change: check the `.png` blob hash still matches `HEAD`, and diff the
  `.import`'s `[params]` against a committed sibling — only `uid=`, `path=`, `source_file=`,
  and `dest_files=` should differ.

## Style

- **Multi-line call continuation uses TWO indent levels (two tabs)**, matching the GDScript
  style guide and the rest of `tests/`:
  ```gdscript
  assert_not_null(option,
          "message")
  ```
  A single-tab continuation is a deviation, not the house style.

## Map-driven movement tests: validate the whole travel window, not just the approach

Tests that pick a target cell out of `TileMapLayer.get_used_cells()` and then drive the
player at it are silently **order-dependent**: `get_used_cells()` order is the tile-paint
order, so "the first cell that matches" can change when anyone repaints the map, and a test
can pass (or fail) for a reason that has nothing to do with the tile it named.

The mitigation is a "clear corridor" predicate that rejects a candidate whose path is
contaminated by an unrelated collidable cell. **The corridor must span the entire simulated
run, not just the approach offset.** A blocked-case test only travels `start → target`, so
checking that span is enough; an *unblocked*-case test travels the full
`speed * ticks * delta` (200px at the current `Player.speed = 200`, 60 ticks, 60Hz) — i.e.
~150px *past* the target — and a Solids tile in that tail stops the player just as
effectively, with a failure message that blames collision instead of candidate selection.

**How to review:** for each movement test, compute the actual end position
(`target - approach_offset + speed * ticks * delta`) and confirm the clearance predicate's
`corridor_max_x` reaches it. Then prove the gap or its absence empirically rather than by
eye — drop a throwaway `tests/**/test_zzz_probe_tmp.gd` that forces a specific candidate
cell through the same GUT helpers, run it with `-gselect=`, and delete it.

## Engine / harness facts

- **`world.tscn` instantiates fine headlessly under GUT.** The header of
  `tests/unit/test_minimum_window_size.gd` historically claimed the opposite ("physics,
  TileMapLayer, and CharacterBody2D dependencies … fragile under headless GUT"); that
  rationale is wrong — `tests/integration/world/test_world_scene.gd` loads and adds the
  real scene. The two files' header comments are a linked pair: if you touch either,
  reconcile both. Don't cite "headless fragility" as a reason to avoid a scene test.
- **`add_child()` runs `_ready()` synchronously** when the parent is already in the tree,
  so a GUT test may assert on post-`_ready()` state immediately — no `await
  get_tree().process_frame` needed just for `_ready`.
- **Instantiating `world.tscn` in a test runs `World._set_minimum_window_size()`**, which
  mutates the shared `get_window().min_size` for the rest of the suite. Harmless today
  (headless DisplayServer is a no-op stub and the settings tests skip window readback),
  but it is real cross-test global state — keep it in mind if window-size assertions are
  ever added.
- **`DisplayServer.window_get_size()` returns `(0, 0)` in headless mode.** Tests that need
  a real window readback call `pending()` when `DisplayServer.get_name() == "headless"`.

## Related

[[game-data-conventions]] — hermetic `user://` I/O for save/load tests.
[[CreamBun Code Patterns]] — general Godot/GDScript conventions.
