# CreamBun Code Reviewer — Agent Memory

- [CreamBun Code Patterns](project_patterns.md) — durable Godot 4 / GDScript / Control / theme conventions; the "this is intentional, don't re-flag it" list
- [Scene Migration Pattern](scene_migration_pattern.md) — notebook-tab `_ensure_pages_built()` page-extraction pattern, orphan trade-off, owner-clear, re-entrancy guards
- [Testing Conventions](testing_conventions.md) — GUT test file conventions: `.uid` companions, mirrored dirs, continuation indent, headless engine facts
- [Game Data Conventions](game_data_conventions.md) — PlayerData/SaveManager persistence: autoload never-null guarantee, ResourceSaver/CACHE_MODE_REPLACE facts, shared-settings-by-reference, hermetic user:// test I/O
- [Perspective Terminology](project_perspective_terminology.md) — three-quarter top-down, never "isometric"; never name the projection in identifiers; square 32×16 grid
- [.tscn Editor Drift](gotcha_tscn_editor_drift.md) — editor writes stray root-node `position` into scene files; audit every .tscn hunk against `main`, revert rather than leave unstaged
- [TileMap Geometry Review](gotcha_tilemap_geometry_review.md) — never renumber `sources/N`; decode `tile_map_data`; halving `tile_size` breaks pixel-authored node positions

Per-developer profile memories live in `.claude/agent-memory-local/code-reviewer/` (gitignored). Check there for any local context before reviewing.
