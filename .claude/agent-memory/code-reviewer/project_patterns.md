---
name: CreamBun Code Patterns
description: Durable, recurring Godot 4 / GDScript patterns and conventions — the "do not flag this" list for reviews
type: project
---

Conventions and engine facts that recur across reviews. Treat these as intentional
(don't re-flag them) unless a change actually breaks the stated rationale.

## Autoloads & signals

- **Autoloads omit `class_name`** (`game_state.gd`, `game_events.gd`, `save_manager.gd`,
  `player_data.gd`). They are reached by singleton name only. Design-doc pseudocode that
  shows `class_name X` is aspirational — codebase convention wins.
- **Inner enums on autoloads** are reachable as `AutoloadName.EnumName` (e.g.
  `GameState.State`) even without a `class_name`, and are valid as type hints
  (`var _s: GameState.State`).
- **Typed signal params referencing `class_name` types** (`ItemData`, `StorySlot`, …) on
  `game_events.gd` are safe: the project scanner registers all global class names before
  autoloads initialize.

## GDScript facts

- **No typed arrays of inner enum types** — `Array[ItemData.EquipSlot]` is a parse error.
  Use a plain `Array` and type the loop variable `: int` (enums are int at runtime).
- **Inner enums are Dictionaries** — `SomeEnum.size()` (entry count) and
  `SomeEnum.has("KEY")` are valid.
- **`Color(r,g,b)` == `Color(r,g,b,1)`** — alpha defaults to 1.0, so 3- and 4-component
  forms compare equal. `.tscn` stores 4-component; test constants often use 3-component.
- **`Script.get_global_name()`** (Godot 4.3+) is how test helpers match nodes by
  `class_name`; recursive walks find grandchildren, not just direct children.

## Control / scene facts

- **`CanvasLayer` does not propagate a rect to children.** A `ColorRect`/`Control` meant to
  fill the viewport under a `CanvasLayer` must set full-rect anchors explicitly
  (`anchor_right/bottom = 1.0` or `anchors_preset = 15`); it won't inherit one.
- **`CanvasLayer.visible`** exists (Godot 4) and is valid to set in a `.tscn`.
- **Avoid setting `custom_minimum_size` in both `.tscn` and `_ready()`** — the `_ready()`
  value wins, and the duplication misleads whoever edits only one.
- **`set_drag_preview()` called outside an active drag** (e.g. invoking `_get_drag_data()`
  directly in a GUT test) emits a `WARN_PRINT`, not an error — GUT does not fail on it and
  the return value is still valid.

## `@tool` scripts and generated sub-resources

- **A resource embedded in a `.tscn` as a `[sub_resource]` is SHARED by every
  instantiation of that scene** unless `resource_local_to_scene = true`. So a base class
  that *generates* its collider shape (`RectangleShape2D.new()` in `_ready()`) is correct as
  written — the fresh allocation per instance is what keeps two placed props from stomping
  each other's shape. Do not "optimize" such code into mutating the existing
  `_collision.shape` in place; that reintroduces the shared-instance bug the same way a
  non-`duplicate()`d `.tres` does.
- **`@tool` + writing node properties in `_ready()` has editor-side consequences**: `_ready()`
  runs when the scene is opened in the editor, so the generated value is written into the
  edited scene and serialized on the next save (a fresh `[sub_resource]` id each time → `.tscn`
  churn), and any inspector-authored value for that same property is silently overwritten on
  reload. Flag it when a property a designer might reasonably want to override is assigned
  unconditionally in a `@tool` `_ready()`.

## Theme / project.godot facts

- **`get_theme_color_override(name)` does NOT exist** in Godot 4. To read a per-node color
  override, use `control.get("theme_override_colors/<name>")`. (`has_theme_color_override` /
  `has_theme_font_size_override` DO exist.) See also the coder note
  `reference_theme_tres_serialization.md`.
- **2D snap keys serialize with the full `rendering/` prefix** inside `[rendering]`
  (`rendering/2d/snap/snap_2d_transforms_to_pixel`), even though design INI excerpts abbreviate
  them. Some keys in the same section (e.g. `textures/canvas_textures/default_texture_filter`)
  use the short form — match whatever Godot actually writes to disk, not the doc excerpt.
- **Godot strips default-valued keys from `project.godot` on save** (e.g.
  `window/stretch/aspect="keep"`, since `keep` is the default), so they vanish from the file
  even when correctly configured. Assert such settings via `ProjectSettings.get_setting()`,
  not raw file-text search; assert non-default keys (which persist) via file text.

## Related

[[scene-migration-pattern]] — notebook tab scene-migration pattern and conventions.
[[game-data-conventions]] — PlayerData / SaveManager persistence conventions.
