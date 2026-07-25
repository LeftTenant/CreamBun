---
name: perspective-terminology
description: CreamBun's perspective is three-quarter top-down (Stardew look), never "isometric" — and the projection is never named in identifiers
metadata:
  type: project
---

CreamBun is **three-quarter top-down**, not isometric: a square grid viewed at an angle, 2:1
foreshortened ground, front-facing sprites — "the Stardew Valley look". The canonical wording is
fixed by `docs/features/world-collision/design.md` §3.1:

| Context | Use |
| --- | --- |
| Casual mention | "top-down" |
| The one canonical description (README) | "three-quarter top-down perspective" + the Stardew reference |
| Depth-sorting docs | no adjective at all — it is about Y-sort, projection is irrelevant |
| Identifiers (class/folder/constant names) | **never** name the projection |

**Why:** the word "isometric" sends contributors *and* agents reading `CLAUDE.md` toward diamond
grids, rotated axes, and basis-vector maths this project will never use. The grid is a plain
rectangular lattice — screen position is just `tile_coords * TILE_SIZE`, with
`TileSet.tile_shape` left at `SQUARE`. `TILE_SIZE` is `Vector2i(32, 16)`.

**How to apply:** flag any new "isometric" in prose, comments, or names (`IsoProp`, `IsoMap`,
`isometric_*`). Prefer no adjective at all in depth-sorting/Y-sort contexts. Grid concepts
(`footprint`, `TILE_SIZE`, collision layers) are square-grid concepts and should not carry a
projection word. Stale "isometric" copies survive outside the root docs — `.claude/agents/*.md`
prompts and `tests/e2e/pixel-art-purist/world_frames_at_320x180.md` — so verify before assuming
the codebase is clean. See [[creambun-code-patterns]].
