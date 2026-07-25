# CreamBun Godot Coder — Agent Memory

- [Inventory.add() leftover return logic](feedback_inventory_return_logic.md) — add() must return count-minus-allowed_to_add, not to_add after the loop
- [GDScript typed arrays of inner enums](feedback_gdscript_typed_arrays.md) — Array[SomeClass.SomeInnerEnum] is not valid; use plain Array with int loop var
- [MCP mouse coords are OS-window space](feedback_mcp_mouse_coordinates.md) — scale logical/viewport coords by the live window/viewport ratio (don't hardcode a multiple; the window is resizable)
- [MCP testing-sandbox stdout is DEVNULL](feedback_mcp_stdout_devnull.md) — print() is invisible; use screenshots + get_node_property for diagnosis instead
- [Always create .uid sidecars](feedback_uid_sidecar_files.md) — every new .gd script needs a matching .uid file; .tres embeds its uid in the header instead
- [Theme .tres serialization](reference_theme_tres_serialization.md) — global color path format, Color() float precision for GUT equality, has_font() fallback gotcha
- [GUT Image.load() import warning](reference_gut_image_load_warning.md) — Image.load() on an imported texture path warns and GUT counts it as a failure even if the real assert passed
- [TileSet source_id renumbering trap](reference_tileset_source_id_renumbering.md) — deleting a TileSetAtlasSource must not renumber remaining sources/N keys; tile_map_data references source_id by value
- [Pixel art resize needs nearest-neighbor](reference_pixel_art_resize_nearest.md) — `sips -z` blurs pixel art (no nearest option); use PIL Image.NEAREST and sanity-check with a unique-color count
- [Collision layer/mask explicit defaults](reference_collision_layer_mask_explicit_defaults.md) — engine default mask=1 coincidentally matches "world" bit; explicit .tscn value gets stripped on re-save, so tests are the real source of truth
- [TileSet physics layer serialization](reference_tileset_physics_layer_serialization.md) — exact .tscn key format for physics layers/TileData collision polygons; probe via headless script + ResourceSaver rather than guessing; use an alternative tile id to avoid retroactively blocking existing painted cells
