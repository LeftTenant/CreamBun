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
- **Test plans live in two places depending on the workflow.** Feature slices use
  `docs/features/<area>/<name>-test-plan.md`; the `/fix-issue` flow commits either
  `tests/<suite>/<area>/test_plan_issue_<N>.md` (e.g.
  `tests/integration/notebook/test_plan_issue_26.md`) or, when the fix is unit-only /
  spans no single suite, `docs/features/<area>/issue-<N>-<slug>-test-plan.md` (e.g.
  `docs/features/testing-sandbox/issue-41-mouse-input-test-plan.md`). Both forms are in use
  for issue fixes — don't flag the location, but *do* check the plan file is `git add`ed
  (a plan left untracked is the common miss). All are `- [ ]` / `- [x]` checklists
  grouped by `### E2E` / `### Integration` / `### Unit`. Boxes are ticked once the
  corresponding test exists and passes — an unticked box on a delivered test is stale.
  The issue plans are *authored in the red phase*, so before commit they also need their
  "not edited by this pass" / "flagged, not fixed by this pass" / "Expected: tests above FAIL
  against current code" framing rewritten past-tense. `test_plan_issue_26.md` is the
  correctly-finalised exemplar to diff against. See [[gotcha_gut_helper_silent_passes]] §5
  for the matching pre-fix-tense problem inside the `.gd` test files.
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

- **E2E scenarios are markdown, and they hard-code node paths.** `tests/e2e/**/*.md` steps
  contain literal `get_node_property: World/Player.position`, `World/Boulder.position`,
  `World/Ground` etc., executed by the testing-sandbox MCP server. Any scene restructure
  that moves a node changes those paths and silently breaks the scenarios — GUT will still
  be green. **Grep `tests/e2e/` for the affected node names in every review of a structural
  scene change** and require the paths be updated in the same slice.
  The same applies to **content**, not just node paths: the scenarios name concrete seeded
  items ("`sample_boots` — Old Boots, weight 0.8"), assert specific UI element counts, and
  compare against committed `screenshots/*.png`. Any change to
  `PlayerDataResource._seed_starter_content()` or to how many widgets a page renders
  invalidates both the scenario text and every reference screenshot for it. "Full
  unit+integration suite passes" is not evidence the e2e suite survived — it runs under the
  testing-sandbox MCP server, not GUT. See [[vocabulary-rename-stragglers]].
- **Textual guards read a specific file.** `test_tile_geometry.gd` scans one scene's raw text
  (for a banished placeholder texture name, and to check every `ext_resource` path exists).
  Its subject has already moved once — `world/world.tscn` → `world/areas/meadow.tscn` when the
  TileSet was extracted into the WorldArea. When content moves out of the scanned file, those
  assertions go vacuously green *and* the file they left behind loses its `ext_resource`
  coverage. Check whether a textual guard's subject moved, ask for the guard to follow it, and
  confirm non-vacuity by grepping the new target for the thing being asserted about.

## Two opposing conventions — check a test is in the right file

Most world/player tests follow **"mirror the constant, don't read it"**: the test restates the
expected value so a source change fails loudly (`tests/integration/player/test_player_scene.gd`
is the canonical example — `EXPECTED_CAPSULE_*`, `EXPECTED_COLLIDER_EXTENT`, layer/mask bits).

`tests/integration/world/test_collision_geometry_invariants.gd` deliberately does **the
opposite**, and its header says so at length: it *reads* live scenes and the real constants and
asserts **relationships between independently-authored facts** (art alpha ↔ collider ↔ world
geometry). Mirroring catches values that *changed*; this file catches values that changed to
something *wrong*.

**How to apply:** when a slice adds scene-as-data checks (a node exists, its shape is
`Vector2(x, y)`, its layer bit is N), those belong in the mirroring file for that scene, not in
the invariants file — putting literals there contradicts the host file's stated reason for
existing and reads as two copies of one number. Only the check that *relates* two independently
authored facts (e.g. "the authored rect still contains the measured opaque-pixel union") belongs
in the invariants file, and only because it needs that file's `_drawn_character_extent()` helper.

Also watch for tests whose *name* encodes a one-time event ("…_is_unchanged_by_X",
"…_unperturbed_by_X"). Those read as commit messages; if the assertion is a standing invariant,
name it for the invariant, and if it merely restates coverage another file already has, it is
duplication (see [[no-one-time-op-tests]]).

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
- **An `area_entered` overlap test only exercises ONE side's `collision_mask`.** Detection
  fires when the *detector's* mask intersects the *detectee's* layer. If the detectee's own
  mask is `0` (as `Player/ThresholdBounds` is — it is detected, never detects), the detector's
  `collision_layer` is behaviourally inert: verified that zeroing a `Threshold`'s
  `collision_layer` still emits `area_entered` from the player's bounds. So a physics
  integration test proves the mask pairing and nothing about the layer value; the layer needs
  a separate scene-as-data assertion, and a failure message naming both bits misleads whoever
  debugs it.

## Related

[[game-data-conventions]] — hermetic `user://` I/O for save/load tests.
[[CreamBun Code Patterns]] — general Godot/GDScript conventions.
