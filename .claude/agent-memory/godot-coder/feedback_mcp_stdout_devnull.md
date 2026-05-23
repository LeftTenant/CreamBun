---
name: testing-sandbox-stdout-devnull
description: Godot stdout is DEVNULL in testing-sandbox; print() diagnostics are invisible via MCP
metadata:
  type: feedback
---

The testing-sandbox MCP server launches Godot with `stdout=subprocess.DEVNULL` (see `plugins/godot-testing/server/mcp_server.py` line ~159). GDScript `print()` calls produce no output observable through any MCP tool.

**Why:** Affects diagnostic strategies — adding print() statements and checking logs via `get_debug_output` does not work. The `mcp__godot__get_debug_output` tool belongs to a separate godot MCP plugin that has no active process when the testing-sandbox is running.

**How to apply:** When diagnosing bugs via the testing-sandbox, use visual verification (screenshots before/after), `get_node_property` to inspect live scene state, and static code analysis. Do not add print() calls expecting to read them through MCP. If logs are truly needed, write to a file via `FileAccess` and read it back, or use `get_node_property` on a custom debug property.

See also: [[mcp-mouse-coordinates-2x]]
