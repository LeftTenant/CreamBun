---
name: Always create .uid sidecars for new .gd and .tres files
description: Godot 4.4+ requires a .uid sidecar next to every script and resource; create and commit it whenever you add one
metadata:
  type: feedback
---

When adding a new `.gd` or `.tres` file to the project, also create the matching `.uid` sidecar (e.g. `foo.gd` → `foo.gd.uid`) and include it in the commit. The repo's convention is to track `.uid` files — `.gitignore` excludes `.godot/` (the regeneratable cache) but does NOT exclude `.uid`, and 20+ existing `.uid` files are tracked.

**Why:** Godot 4.4+ writes a stable `uid://...` identifier to each `.uid` file. Other resources (autoloads, preloads, scene-script bindings, `load("uid://...")` calls) reference scripts and resources by that UID. If a teammate or CI clones the repo without the `.uid`, Godot regenerates a fresh UID on first load — silently breaking every reference that pointed at the old one. The bug surfaces as missing scripts or "resource not found" errors that look unrelated to the file you actually added.

This was missed in the issue #4 PR for `tests/integration/notebook/test_settings_tab_layout.gd` and required a follow-up commit (`1bab283`) on `main` to repair.

**How to apply:** After adding any new `.gd` or `.tres` file, either (a) open the project in the editor so Godot writes the `.uid`, then `git add` it; or (b) write the `.uid` directly using a fresh `uid://` value of the form `uid://` followed by a 13-char base32 string. Always `git status` before committing to verify the sidecar is staged alongside the source file.
