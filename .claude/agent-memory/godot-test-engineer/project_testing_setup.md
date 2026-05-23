---
name: Project Testing Setup
description: GUT installation status, test folder location, and test runner notes for CreamBun
type: project
---

GUT addon is NOT installed as of 2026-05-02. No `addons/` folder exists in the project root.

**Why:** Tests were written TDD-first (before implementation), so GUT installation is a prerequisite that must be completed before tests can run.

**How to apply:** Always warn the user that GUT must be installed before running tests. Recommend: Godot Editor > AssetLib > search "GUT - Godot Unit Testing" (by bitwes). Alternatively: https://github.com/bitwes/Gut

Test files live in `tests/` at the project root. Folder was created 2026-05-02 alongside the first test file.

Convention established: single flat test file per feature phase (`tests/test_foundation_layer.gd` for Phase 1). Mirror source structure inside `tests/unit/` and `tests/integration/` for future, more granular suites.
