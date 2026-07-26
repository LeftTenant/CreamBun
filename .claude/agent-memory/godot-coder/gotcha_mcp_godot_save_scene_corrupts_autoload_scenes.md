---
name: gotcha-mcp-godot-save-scene-corrupts-autoload-scenes
description: mcp__godot__save_scene silently corrupts any scene whose scripts reference autoload globals (GameState, GameEvents, PlayerData) — back up the .tscn before ever calling it
type: reference
---

`mcp__godot__save_scene` (the `@coding-solo/godot-mcp` package's tool) drives its own
minimal `godot_operations.gd` script that `load()`s the target scene's script
dependencies **without booting the project's autoload graph**. Any script that
references an autoload identifier at parse/reload time (e.g. `GameState.current_state`,
`GameEvents.something`) fails to compile with `Identifier not found: GameState`.

**Verified** (Godot 4.6, `world/world.tscn` — references `player/player.gd` and
`ui/notebook/notebook.gd`, both of which touch `GameState`). Calling
`mcp__godot__save_scene` on it:
- printed a wall of `SCRIPT ERROR: Compile Error: Identifier not found: GameState`
  and `Failed to load script ... Compilation failed` — looks like a hard failure.
- **but still wrote the .tscn back to disk**, corrupted: downgraded
  `[gd_scene format=4 uid="..."]` to `format=3` (dropping the scene's own uid
  entirely), stripped every `ext_resource uid=` attribute, and — worst of all —
  silently baked in wrong per-instance overrides on the nodes whose scripts
  failed to load (`type="CharacterBody2D"` on a `PackedScene` instance node,
  spurious `collision_layer = 2`, `process_mode = 3`, `layer = 128` — values that
  don't match the actual scene at all, apparently a fallback since the real
  script/inherited defaults couldn't be resolved).
- Exit was not a clean error the caller could trust: the tool returned an error
  string, but the damage was already on disk. Only a `git diff` against a
  pre-call backup revealed it.

**How to apply:**
- Any CreamBun scene is a candidate for this failure — `GameEvents`/`GameState`/
  `PlayerData` autoload references are pervasive per project convention.
- Before calling `mcp__godot__save_scene` (or `mcp__godot__add_node` /
  `create_scene`, which likely share the same script-loading codepath) on ANY
  scene that isn't a trivial leaf with no autoload-touching scripts, `cp` the
  `.tscn` to a scratch backup first. Diff after the call even if it reports
  success.
- If corrupted, restore from the backup — do NOT `git checkout` blindly if the
  file had uncommitted changes before the call (checkout would also discard
  those); restore from your own pre-call copy instead.
- For scene edits that need the real editor save codepath (e.g. stamping
  `unique_id=` onto nodes — see [[scene-uid-generation]]), prefer the documented
  headless `--editor` + delayed `EditorInterface` `SceneTree` script approach,
  or fall back to asking the user to do a manual editor save — both are safer
  than this MCP tool for any non-trivial scene.

## Related

[[scene-uid-generation]] — the safer (but fiddlier) headless approach for the
same class of "stamp editor-only scene metadata" problem.
