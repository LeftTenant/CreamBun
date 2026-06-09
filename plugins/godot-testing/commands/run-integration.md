---
description: Run the project's GUT integration tests headlessly and report a pass/fail summary
argument-hint: "[optional filename filter, e.g. test_quests_tab.gd]"
---

Run the project's **integration** tests using the `run_gut_tests` tool on the `testing-sandbox` MCP server.

- `directory`: `res://tests/integration/`, with `include_subdirs` = true.
- If an argument is given below, pass it as the `select` filter so only matching files run; if it's empty, run the whole integration suite.

Argument (optional): `$ARGUMENTS`

Then report the run:
- State the `summary_text`.
- If `failures` is non-empty, list each `{script, test, message}`.
- Point me at the saved `report_path` / `log_path` for full detail — do **not** paste the raw log.
- Do **not** write any Bash/python to parse output; the tool returns structured results.
