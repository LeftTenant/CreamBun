---
name: Always create .uid sidecars for new .gd files (not .tres)
description: Godot 4.4+ requires a .uid sidecar next to every script; .tres resources embed their uid in the header instead
metadata:
  type: feedback
---

When adding a new `.gd` script to the project, also create the matching `.uid` sidecar (e.g. `foo.gd` → `foo.gd.uid`) and include it in the commit. The repo's convention is to track `.uid` files — `.gitignore` excludes `.godot/` (the regeneratable cache) but does NOT exclude `.uid`, and 20+ existing `.uid` files are tracked.

**`.tres` files do NOT get a `.uid` sidecar.** A hand-written or editor-saved `.tres` carries its UID inline in the resource header: `[gd_resource type="..." ... uid="uid://..."]`. Verified: zero `*.tres.uid` files exist anywhere under `resources/`. Imported binary assets (`.ttf`, `.png`, etc.) get a `.import` file with the UID instead — also no separate `.uid` sidecar. Only `.gd` scripts use the `.uid` sidecar form.

**Why:** Godot 4.4+ writes a stable `uid://...` identifier so other resources (autoloads, preloads, scene-script bindings, `load("uid://...")` calls) can reference scripts/resources by UID even if the path moves. For scripts this lives in `foo.gd.uid`; if missing, Godot regenerates a fresh UID on first load — silently breaking every reference that pointed at the old one. For `.tres`/imported assets the UID is embedded directly, so as long as you preserve the existing `uid="..."` in the header (or `.import` file) when editing, no extra file is needed.

A missing `.uid` on a new `.gd` script has previously slipped through a PR and needed a follow-up repair commit — so treat it as part of adding any script, not an afterthought.

**How to apply:** After adding any new `.gd` script, either (a) open the project in the editor so Godot writes the `.uid`, then `git add` it; or (b) write the `.uid` directly using a fresh `uid://` value of the form `uid://` followed by a 13-char base32 string. For `.tres` edits, just preserve the existing `uid="..."` in the `[gd_resource ...]` header line — do not create a `.uid` sidecar for it. Always `git status` before committing to verify staged files match expectations.
