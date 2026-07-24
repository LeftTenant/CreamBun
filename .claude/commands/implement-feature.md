---
description: "Drive a CreamBun feature from design doc → slices → tests → code → review, with checkpoints back to the user."
argument-hint: "<design-doc-path> [continue-all]"
---

You are running the `/implement-feature` flow for CreamBun. **You are the executor**: the `feature-orchestrator` agent plans the slices, and you drive the build loop for each slice by spawning specialist agents via the Agent tool. Do not write game code or tests yourself — the specialists own those steps. The single exception: answering questions you can answer from this conversation alone (e.g. "what slices are left?").

**Arguments:** `$ARGUMENTS`

The first argument is the design doc path (e.g. `docs/features/notebook/design.md`).
The optional second argument `continue-all` means: do not pause between slices; only stop at the test-plan checkpoint inside each slice and at stuck conditions. Default behaviour pauses between slices.

## Phase A — Slice breakdown

1. **Validate** that the design doc path was supplied and exists. If not, ask the user for it and stop.
2. **Spawn `feature-orchestrator`** with the design doc path. It reads the design doc and writes the slice breakdown to `docs/features/<feature>/slices.md`, then returns a summary. To revise the breakdown after user feedback, message the *same* orchestrator agent via SendMessage — don't spawn a new one (that loses its context).
3. ⏸ **Checkpoint** — show the user the slice breakdown (point them at `slices.md`) and wait for approval before starting the first slice.

## Phase B — Per-slice build loop

Run these steps for each approved slice, in `slices.md` order. Fill each prompt's placeholders from `slices.md`. Steps marked ⏸ pause for user input.

### B1 — Test plan ⏸
Spawn `godot-testing:godot-test-engineer` with:
> "Write a human-readable test plan ONLY (no GUT code) for **[SLICE NAME]** of the **[FEATURE]** feature.
> Design doc: [design doc path]. Slice description: [paste the slice's goal from slices.md].
> Save the plan to: docs/features/[feature]/[slice-name]-test-plan.md.
> Structure with ### E2E, ### Integration, ### Unit sections. Each item = one line stating what is verified."

After it returns: point the user at the test plan, ask for sign-off. Do NOT proceed to B2 until approved.

### B2 — Generate tests
Spawn `godot-testing:godot-test-engineer` with:
> "Generate GUT tests from the approved test plan at docs/features/[feature]/[slice-name]-test-plan.md.
> Write test files under tests/unit/ and tests/integration/ (mirror source layout). Write e2e scenarios
> to tests/e2e/[feature]/. Run unit+integration tests via the godot mcp server — expect failures
> (no implementation yet). Report pass/fail counts per file."

### B3 — Implement
Spawn `godot-coder` with:
> "Implement **[SLICE NAME]** of the **[FEATURE]** feature.
> Design doc: [path]. Slice: [paste slice goal + files from slices.md].
> Tests to satisfy: [list test file paths from B2].
> Make all tests pass while honoring the design doc's intent, not just the letter of the tests."

### B4 — Run tests
Spawn `godot-testing:godot-test-engineer` (pass `model: haiku` — this step is mechanical) with:
> "Re-run the following test files and report pass/fail counts: [test file paths from B2]."

### B5 — Fix loop
If failures remain after B4: spawn `godot-coder` with the test output to fix, then re-run B4.
**Stuck condition** — stop and report to the user when ANY of:
- 3 consecutive fix iterations without strictly reducing the failing-test count
- Same test fails twice in a row after fixes
- `godot-coder` reports a contradiction between the design doc and the tests

### B6 — Review
Spawn `code-reviewer` with:
> "Review the code written for **[SLICE NAME]** of **[FEATURE]**. Run `git diff main...HEAD` for context.
> Slice description: [paste from slices.md]. Tests: [test file paths]."

If the review surfaces errors or warnings: spawn `godot-coder` to fix, then re-run B4 + B6.
Stuck condition: same class of review issue twice → report to the user.

### B7 — Slice complete ⏸
Report to the user: what was built, files touched, test counts, review notes, next slice name.
Pause for go-ahead before the next slice unless `continue-all` is in effect.

## End of flow

When the final slice is complete, summarise in 2–3 sentences: feature name, slices shipped, test files added (counts only, by category), and any deferred items the user should follow up on. Then stop.
