---
description: Run the full suite — GUT unit + integration, then e2e scenarios — and give a combined summary
---

Run the project's complete test suite in two phases, reporting between them.

**Phase 1 — GUT (unit + integration):**
- Call `run_gut_tests` with `directory` = `res://tests/` and `include_subdirs` = true. This runs every `test_*.gd` under `tests/` (unit and integration); the e2e `.md` scenarios are ignored by GUT.
- Report the `summary_text` and, if `failures` is non-empty, each `{script, test, message}`.
- If Phase 1 has failures, mention them but still proceed to Phase 2 unless I tell you to stop.

**Phase 2 — e2e scenarios:**
- Run the e2e scenarios exactly as `/godot-testing:run-e2e` does (drive each via the testing-sandbox tools, compare to committed baselines, write transient frames to `.godot-test-reports/e2e/`).

**Final report:**
- A combined summary: GUT counts (passing/failing/pending) + e2e per-scenario pass/fail.
- Point me at the saved GUT `report_path` / `log_path`.
- Do **not** write Bash/python to parse output — use the structured fields the tool returns.
