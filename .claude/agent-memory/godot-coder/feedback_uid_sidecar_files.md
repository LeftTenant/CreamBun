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

**Headless generation that reliably works:** the `mcp__godot__update_project_uids` tool (runs a `resave_resources` operation) has been observed to report "Found 0 scenes"/"Found 0 scripts" and do nothing — it mishandles an absolute `projectPath`, producing a malformed `res:///Users/...` search root. Don't rely on it. Instead run Godot headless in editor mode against the project, which forces a full filesystem scan + global class registration and writes any missing `.uid` files as a side effect:
```
/Applications/Godot.app/Contents/MacOS/Godot --headless --editor --path <project_root> --quit
```
(Plain `--headless --quit` without `--editor` does NOT trigger this — it just runs the game's main loop and exits without a uid-generation pass.) Verify with `ls <script>.uid` afterward.

**That headless pass adds a `uid=` to the `.gd.uid` file itself, but NOT to any `.tscn`'s `ext_resource` line referencing that script.** Confirmed: after generating a fresh `.gd.uid`, the referencing scene's `[ext_resource type="Script" path="..."]` line was untouched. Hand-edit the `ext_resource` line to add `uid="uid://..."` (copy the exact value from the new `.uid` file), matching the format seen on existing scenes, e.g. `[ext_resource type="Script" uid="uid://b2wakewrrrqh5" path="..." id="1"]` (uid attribute comes before path).

**Don't trust a stated "N missing .gd.uid files" / "only file X is missing one" claim at face value — re-verify with `git ls-files` before acting.** A plain `find . -name "*.gd" | wc -l` over the whole working tree includes gitignored `addons/gut/` (which has its own internal gd/uid count mismatch, irrelevant to this repo's tracked convention) and any other untracked scratch `.gd` files, so its counts won't match a claim based on tracked files only. Also, running the headless editor pass to fix one known gap can surface a *second*, pre-existing, unrelated gap as a side effect (a tracked `.gd` file with no tracked `.gd.uid`, sitting in the working tree as a new untracked file after the pass) — check `comm -23 <(git ls-files '*.gd' | sed 's/\.gd$//' | sort) <(git ls-files '*.gd.uid' | sed 's/\.gd\.uid$//' | sort)` on the base commit to see the real tracked gap set before assuming a single-file fix is complete. Don't fold an unrelated pre-existing gap into an unrelated fix's commit — flag it to the user instead.
