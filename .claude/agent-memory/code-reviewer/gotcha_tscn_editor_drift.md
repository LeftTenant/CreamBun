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

**The mirror-image case: a hand-authored `.tscn` that is missing editor-generated
metadata.** Every `.tscn` in this repo carries `uid="uid://…"` in its `[gd_scene]` header
and `uid=` on its `ext_resource` lines (the sole exception is the hand-written
`ui/notebook/notebook.tscn`). A newly hand-authored scene typically has neither, because a
bare `godot -s` resave strips uids unless paired with `--editor`. Flag it: the first editor
save fills them in, producing a churn diff, and until then every reference to the file is
path-only (renames break silently). Same applies to Godot 4.6's per-node `unique_id=`
attributes.

**`;` comments in a `.tscn` do not survive a re-save.** Verified in Godot 4.6.2: round-tripping a
scene through `ResourceLoader.load` → `ResourceSaver.save` (what the editor does on Ctrl+S) keeps
every real property — including `resource_local_to_scene = true` on a `[sub_resource]` — but
**silently drops every `;` comment line**. So a rationale comment written into a `.tscn` has a
lifetime of "until a designer next opens the scene", and template scenes designers are explicitly
meant to open are the worst place to keep one. Flag it: rationale for a non-obvious `.tscn`
property belongs in the attached script's docblock (durable, and where a reader looks anyway),
with at most a pointer left in the scene.

## Related

[[testing-conventions]] — scene-instantiation tests under GUT.
[[gotcha-test-subresource-mutation-leak]] — the `resource_local_to_scene` flag whose rationale
this affects.
[[CreamBun Code Patterns]] — general `.tscn` review notes.
