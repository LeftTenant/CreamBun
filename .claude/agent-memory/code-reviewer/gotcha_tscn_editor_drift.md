---
name: gotcha-tscn-editor-drift
description: Godot editor writes stray transform props (esp. root-node position) into .tscn files — check every .tscn hunk in a diff for unintended editor state
metadata:
  type: project
---

Treat every `.tscn` hunk in a review diff as suspect until confirmed intentional. The
Godot editor persists incidental manipulation into the scene file — most commonly a
`position = Vector2(...)` appearing on the **root** node after someone drags it in the
2D viewport while panning.

**Why:** `world/world.tscn` has picked up exactly this (`position` on the `World` root,
not present in `main`). A root-node offset silently translates every child — TileMapLayer,
Player, everything — so it is a real behavioural change disguised as noise, and it rides
along into any `git commit -a`.

**How to apply:**
- When a diff touches a `.tscn`, ask which hunks the change actually required. Transform
  props on nodes the task never mentioned are almost always accidental.
- Compare against `main` (`git show main:path/to.tscn`) rather than assuming the working
  tree is the baseline — the drift often predates the branch.
- Recommend `git checkout -- <file>` (revert), not merely "leave it unstaged". Unstaged
  drift survives and re-appears in the next branch's diff.
- Node **local** `position` assertions in tests are immune to a root-node offset, so a
  green suite does not clear this class of drift.

## Related

[[testing-conventions]] — scene-instantiation tests under GUT.
[[CreamBun Code Patterns]] — general `.tscn` review notes.
