# Migration plan: Godot 4.4 → 4.6

Status: completed.
Today's date: 2026-05-17. Godot 4.6 stable shipped Jan 2026; 4.6.1 is the current maintenance release.

## Why this is low-risk for CreamBun

Godot 4.5 and 4.6 each introduced few breaking changes, and almost none of them touch the surface area this project uses. CreamBun is 2D-only, no 3D physics, no Jolt, no GLSL shaders, no networking, no OpenXR, no AnimationPlayer, no FileDialog, no post-process glow/volumetric fog. The cross-cutting changes that *could* have bitten us — `Resource.duplicate()` no longer deep-duplicating external refs (4.5), TileMapLayer physics chunking (4.5), `Node.set_name()` taking StringName (4.5), AnimationPlayer String→StringName props (4.6) — either don't appear in our code or are inert for our use.

The two real unknowns are third-party: the **GUT 9.3.1** addon and our in-tree **godot-testing** plugin.

## Step-by-step plan

### 1. Branch and snapshot
- Create a branch: `migration/godot-4.6`.
- Commit a clean baseline so rollback is one revert.

### 2. Install Godot 4.6.1
- Download Godot 4.6.1 stable (standard, not .NET — we use GDScript).
- Keep the 4.4 binary around until step 7 passes.

### 3. Update `project.godot`
- Change `config/features=PackedStringArray("4.4", "Mobile")` → `PackedStringArray("4.6", "Mobile")`.
- Open the project in 4.6 once; let the editor re-save `.godot/` cache.
- Do NOT yet let the editor re-save every `.tscn` (4.6 may bump scene format with new unique node IDs / dropped `load_steps`); we want to see scenes load cleanly *before* the format gets rewritten.

### 4. Smoke-test the editor and runtime
- Open `world/world.tscn`, `player/player.tscn`, every notebook scene. Watch the Output panel for parse errors and "unknown property" warnings.
- Run the project (F5). Verify:
  - Player moves with WASD/arrows.
  - I / M / Q open the notebook to the right tab.
  - Esc opens & closes the notebook.
  - Tab cycles tabs while the notebook is open.
  - Notebook freezes the world (player input ignored) and unfreezes on close.
- Verify the `TileMapLayer` in `world/world.tscn` renders identically (Y-sort, tile placement).

### 5. Verify GUT (`addons/gut` 9.3.1)
- Run the GUT panel. If the plugin fails to enable or tests fail to discover, upgrade GUT to its latest 4.6-compatible release (check the GUT repo's CHANGELOG / `plugin.cfg` for the supported engine range).
- Run the existing test suite:
  - `tests/unit/ui/notebook/**`
  - `tests/integration/foundation/`
  - `tests/integration/notebook/`
- All should pass without code changes. If any fail, expect the cause to be in GUT itself or a Godot API rename, not in our test logic.
- Upgrade to GUT 9.6.0 if necessary to maintain compatibility

### 6. Verify `plugins/godot-testing`
- The `TestingServer` autoload at `plugins/godot-testing/godot/testing_server.gd` exposes the MCP testing-sandbox surface (input injection, screenshots, scene loading). Launch a sandbox session and run one e2e scenario from `plugins/godot-testing/skills/` (or any existing e2e scenario) to confirm:
  - `launch_game` / `load_scene` work.
  - `screenshot` returns a frame.
  - `press_key` / `mouse_move` deliver events that the game observes.
- If the plugin breaks, it likely needs a small patch — most plausible causes are a renamed input-event property or a new optional parameter on `Viewport`/`DisplayServer` methods.

### 7. Re-save scenes (intentionally)
After steps 4–6 are green, open and re-save each `.tscn` in the 4.6 editor so they adopt the new format (unique node IDs, no `load_steps`). Do this as a separate commit so the diff is reviewable on its own and the "code still works" commit stays clean.

Files to re-save:
- `world/world.tscn`
- `player/player.tscn`
- `ui/notebook/notebook.tscn`
- all `ui/notebook/**/*.tscn`

### 8. Update documentation
- `CLAUDE.md` line 3: "Godot **4.4**" → "Godot **4.6**".
- `MEMORY.md` / `memory/` entries that reference 4.4 specifically.
- This file: mark Status as "complete" with the date.

### 9. Merge
- Squash-merge `migration/godot-4.6` into `main` once steps 4–7 are all green.

## Rollback

If something blocks the migration:
1. Revert `project.godot` (the `4.4 → 4.6` line).
2. Re-open in Godot 4.4. Scene files re-saved in step 7 will still load (format is forward-compatible).
3. Drop the branch.

## Things explicitly *not* changing in this migration

- No renderer switch (stay on **Mobile**).
- No GUT major-version jump unless 9.3.1 is incompatible.
- No scene refactors. We migrate by changing the engine, not the code.
- No new 4.6 features adopted in this PR — keep the diff to "make it boot on 4.6".

## Reference

- [Upgrading from Godot 4.5 to Godot 4.6](https://docs.godotengine.org/en/4.6/tutorials/migrating/upgrading_to_godot_4.6.html)
- [Upgrading from Godot 4.4 to Godot 4.5](https://docs.godotengine.org/en/4.5/tutorials/migrating/upgrading_to_godot_4.5.html)
- [Maintenance release: Godot 4.6.1](https://godotengine.org/article/maintenance-release-godot-4-6-1/)
