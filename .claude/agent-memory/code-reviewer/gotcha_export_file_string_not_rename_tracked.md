---
name: gotcha-export-file-string-not-rename-tracked
description: "@export_file paths stored as String are invisible to Godot's dependency updater — moving/renaming the target .tscn silently breaks them, unlike ext_resource/uid references"
metadata:
  type: project
---

`@export_file("*.tscn") var destination: String` (Threshold, `world/thresholds/threshold.gd`)
gives an Inspector file-picker, but the value is stored in the `.tscn` as a **plain string
property**, not an `[ext_resource]` with a `uid://`.

**Why it matters:** Godot's FileSystem dock rewrites dependencies on move/rename by walking
`ext_resource` entries and UIDs. A String property is not a dependency, so it is never rewritten.
Rename `orchard.tscn` in the dock and every `Threshold.destination` pointing at it keeps the old
path — with no editor error, no import warning, and no red X. The break only surfaces at crossing
time as `world.gd`'s `push_error(... did not load/instantiate as a WorldArea ...)`.

The String type is itself deliberate and must not be "fixed" to `PackedScene`: two area scenes
holding live `PackedScene` refs to each other deadlock Godot's loader at parse time (confirmed
empirically, world-collision design §12.2). The `neighbour_*` exports it replaced used a String
for exactly this reason. So the rename hazard is the accepted cost, which makes *documenting* it
the only available mitigation.

**How to apply:**
- When reviewing area/threshold authoring docs, check that the rename hazard is called out —
  a designer guide that omits it is incomplete.
- When reviewing a PR that moves or renames an area `.tscn`, grep every `.tscn` for the old path
  string; do not trust that the editor fixed it.
- Same trap applies to any future `@export_file` / `@export_dir` String the project adds.

## Related

[[reference-threshold-arrival-placement]] — the placed mechanism these exports drive.
