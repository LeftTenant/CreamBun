# CreamBun Godot Coder — Agent Memory

- [Inventory.add() leftover return logic](feedback_inventory_return_logic.md) — add() must return count-minus-allowed_to_add, not to_add after the loop
- [GDScript typed arrays of inner enums](feedback_gdscript_typed_arrays.md) — Array[SomeClass.SomeInnerEnum] is not valid; use plain Array with int loop var
- [MCP mouse coords are OS-window space](feedback_mcp_mouse_coordinates.md) — scale logical/viewport coords by the live window/viewport ratio (don't hardcode a multiple; the window is resizable)
- [MCP testing-sandbox stdout is DEVNULL](feedback_mcp_stdout_devnull.md) — print() is invisible; use screenshots + get_node_property for diagnosis instead
- [Always create .uid sidecars](feedback_uid_sidecar_files.md) — every new .gd script needs a matching .uid file; .tres embeds its uid in the header instead
- [Theme .tres serialization](reference_theme_tres_serialization.md) — global color path format, Color() float precision for GUT equality, has_font() fallback gotcha
