---
description: Run the project's GUT unit tests headlessly and report a pass/fail summary
argument-hint: "[optional filename filter, e.g. test_inventory_tab.gd]"
---

Run the project's **unit** tests using the `run_gut_tests` tool on the `testing-sandbox` MCP server.

- `directory`: `res://tests/unit/`, with `include_subdirs` = true.
- If an argument is given below, pass it as the `select` filter so only matching files run; if it's empty, run the whole unit suite.

Argument (optional): `$ARGUMENTS`

Then report the run:
- State the `summary_text` (e.g. "24/24 passed, 0 pending, 0 failing").
- If `failures` is non-empty, list each `{script, test, message}` so I can see exactly what broke.
- Point me at the saved `report_path` / `log_path` for full detail — do **not** paste the raw log into the conversation.
- Do **not** write any Bash/python to parse or count output; the tool already returns structured results.
