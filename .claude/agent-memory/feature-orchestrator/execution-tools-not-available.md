---
name: execution-tools-not-available
description: This orchestrator role cannot spawn sub-agents or run godot MCP tests; it is a planner whose output is executed by the parent (FleetView)
metadata:
  type: feedback
---

The feature-orchestrator cannot execute the per-slice B-loop itself. It has NO `Agent`/`Task` tool to spawn godot-coder / godot-test-engineer / code-reviewer, NO godot or testing-sandbox MCP tools to run tests, and is forbidden from editing game code/tests/reviews directly.

**Why:** the architecture is planner/executor split — the orchestrator's output IS its product; the parent agent (FleetView) reads it and does the spawning and test runs.

**How to apply:** when a task (even a "resume, just run the loop" task) says "have godot-coder do X" or "run tests via the godot mcp server", do NOT attempt to call those tools or edit files — they will not exist. Instead produce a fully pre-filled, ready-to-execute handoff (B2–B6 prompts with all placeholders resolved, grounded in actual repo state) and hand control back to the parent. Do not thrash searching for tools that are absent; verify once via ToolSearch, then deliver the package.
