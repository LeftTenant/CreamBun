# CreamBun Godot Coder — Agent Memory

- [Inventory.add() leftover return logic](feedback_inventory_return_logic.md) — add() must return count-minus-allowed_to_add, not to_add after the loop
- [GDScript typed arrays of inner enums](feedback_gdscript_typed_arrays.md) — Array[SomeClass.SomeInnerEnum] is not valid; use plain Array with int loop var
- [MCP mouse coords must be 2× OS window space](feedback_mcp_mouse_coordinates.md) — viewport is 640×480 but window is 1280×960; multiply logical coords by 2
- [MCP testing-sandbox stdout is DEVNULL](feedback_mcp_stdout_devnull.md) — print() is invisible; use screenshots + get_node_property for diagnosis instead
- [Always create .uid sidecars](feedback_uid_sidecar_files.md) — every new .gd/.tres needs a matching .uid file committed alongside it
