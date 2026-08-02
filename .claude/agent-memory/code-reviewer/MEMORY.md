# CreamBun Code Reviewer — Agent Memory

- [CreamBun Code Patterns](project_patterns.md) — durable Godot 4 / GDScript / Control / theme conventions; the "this is intentional, don't re-flag it" list
- [Scene Migration Pattern](scene_migration_pattern.md) — notebook-tab `_ensure_pages_built()` page-extraction pattern, orphan trade-off, owner-clear, re-entrancy guards
- [Testing Conventions](testing_conventions.md) — GUT conventions: `.uid`/`.import` companions, mirrored dirs, mirror-vs-relate file split, movement-test corridor rule, headless facts
- [Game Data Conventions](game_data_conventions.md) — PlayerData/SaveManager persistence: autoload never-null guarantee, ResourceSaver/CACHE_MODE_REPLACE facts, shared-settings-by-reference, hermetic user:// test I/O
- [Perspective Terminology](project_perspective_terminology.md) — three-quarter top-down, never "isometric"; never name the projection in identifiers; square 32×16 grid
- [.tscn Editor Drift](gotcha_tscn_editor_drift.md) — editor writes stray root-node `position` into scene files; `;` comments are dropped on re-save; audit every .tscn hunk against `main`
- [TileMap Geometry Review](gotcha_tilemap_geometry_review.md) — never renumber `sources/N`; decode `tile_map_data`; tile collision is per-alternative; round-trip hand-spliced .tscn
- [.tscn Default-Valued Props](gotcha_tscn_default_valued_props.md) — Godot drops props equal to the class default on save (`collision_mask = 1` vanishes); they can't document intent
- [@tool _ready writes get serialized](gotcha_tool_ready_writes_serialize.md) — editor-run `_ready()` bakes instance-ROOT props into the placing .tscn; child writes never stored
- [Vacuous "blocked" movement tests](gotcha_vacuous_blocked_movement_assertions.md) — upper-bound-only assertions pass when the probe never moves; GUT `simulate()` no-ops on scriptless bodies
- [find_child owned flag](gotcha_find_child_owned_flag.md) — `owned=true` prunes whole subtrees under script-instanced (owner-less) nodes; reparent preserves owner
- [GUT helper silent passes](gotcha_gut_helper_silent_passes.md) — `return node as T` swallows a failed cast; `%` binds tighter than `+`; sentinel returns; a parse error drops a script yet still reports "All tests passed!"
- [Player Sprite Geometry](reference_player_sprite_geometry.md) — measured opaque union is 26×27 at x[-13,13] y[-31,-4]; the "5px padding on every side / 22×22" claim is false
- [Camera edge lock vs tall sprite](gotcha_camera_edge_lock_vs_tall_sprite.md) — fixed by insetting the north wall 32px; only 5px of slack, redo the math if any constant moves
- [Corner-gap wall test is inert](gotcha_perimeter_corner_gap_test_inert.md) — widened-span checks can't detect a missing corner extension on a wall ring; mutate the source to prove a test's catch
- [get_bounds_px() coordinate space](gotcha_worldarea_bounds_coordinate_space.md) — Ground-local rect consumed as both WorldArea-local (walls) and global (camera limits)
- [Open-edge trigger corner gaps](gotcha_open_edge_trigger_corner_gaps.md) — linked edge = stub/trigger/stub; a vertical edge's north stub is 64px on purpose (headroom inset), measured NE band ≈33px
- [World-area authoring facts](reference_world_area_authoring_facts.md) — TileSets are per-scene embedded sub-resources; min area is 10×**12** tiles; bounds are a bounding box
- [Destroy-before-acquire soft-lock](gotcha_destroy_before_acquire_soft_lock.md) — validate the replacement scene BEFORE reparent/remove_child/queue_free; a late null-guard fires into an empty tree
- [Sub-resource mutation leaks](gotcha_test_subresource_mutation_leak.md) — instantiate() shares [sub_resource]s process-wide; tests must assign not mutate, template scenes need resource_local_to_scene

Per-developer profile memories live in `.claude/agent-memory-local/code-reviewer/` (gitignored). Check there for any local context before reviewing.
