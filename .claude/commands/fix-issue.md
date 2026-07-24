---
description: "Drive a GitHub issue from lookup → branch → plan → tests → fix → review → PR, with checkpoints back to the user."
argument-hint: "<issue-number-or-url>"
---

You are running the `/fix-issue` flow for CreamBun. **You are the executor**: the `github-issue-orchestrator` agent triages the issue and drafts the fix plan, and you drive the fix by spawning specialist agents via the Agent tool. Do not write game code or tests yourself — the specialists own those steps. The single exception: answering questions you can answer from this conversation alone (e.g. "what branch are we on?").

**Arguments:** `$ARGUMENTS`

The argument is either a GitHub issue number (e.g. `42`) or a full issue URL.

## Phase 1–3 — Triage, branch, plan

1. **Validate** that an issue number or URL was supplied. If not, ask the user for one and stop.
2. **Spawn `github-issue-orchestrator`** with the raw issue argument. It fetches the issue, summarizes it, creates a `fix/<number>-<description>` branch from `main`, and drafts a fix plan. It will end its turn whenever it needs user input (issue-summary confirmation, plan approval, dirty working tree) — surface its question, wait for the user, then resume the *same* agent via SendMessage. Don't spawn a new one (that loses its context).
3. ⏸ **Checkpoint** — when the orchestrator returns the approved plan (issue summary, branch, root cause, files, test strategy), confirm with the user before starting Step 4a.

## Phase 4 — Fix loop

Fill each prompt's placeholders from the orchestrator's plan.

### Step 4a — Test plan + test creation
Spawn `godot-testing:godot-test-engineer` with:
> "Write a test plan and tests that reproduce issue #[number]: [title].
> Issue summary: [one paragraph]. Affected files: [list]. Fix plan: [summary].
> First write a test plan (markdown checklist), then implement GUT tests that should FAIL
> against the current code (they prove the bug exists). Run them to confirm failure."

### Step 4b — Implementation
After confirming tests exist and fail, spawn `godot-coder` with:
> "Fix issue #[number]: [title].
> Root cause: [hypothesis]. Fix plan: [detailed plan].
> Tests that must pass: [test file paths].
> Project conventions: see CLAUDE.md. Keep it simple."

### Step 4c — Test execution
Spawn `godot-testing:godot-test-engineer` (pass `model: haiku` — this step is mechanical) with:
> "Re-run the tests at [test file paths]. Report pass/fail counts."

If tests FAIL: spawn `godot-coder` again with the failure output (up to 3 times). If still failing after 3 attempts, stop and report to the user.

### Step 4d — Code review
Spawn `code-reviewer` with:
> "Review the fix for issue #[number]. Run `git diff main...HEAD` for the diff.
> Issue context: [summary]. Fix plan: [plan]. Tests: [test file paths]."

If the reviewer finds issues: spawn `godot-coder` to address them, then re-run 4c + 4d. If the same review issue recurs twice, stop and report to the user.

### Step 4e — Commit & PR
Once tests pass and review is approved:

```bash
git add -A
git commit -m "Fix #<number>: <short summary>

<paragraph explaining root cause and fix>

Tests:
- <test descriptions>

Closes #<number>"
git push -u origin fix/<number>-<description>
```

Then create the PR (via `gh pr create` or `mcp__github__create_pull_request`):
- Title: `Fix #<number>: <short summary>`
- Body: root cause, fix approach, tests added, `Closes #<number>`
- Base: `main`

## End of flow

When the PR is open, surface the PR URL and summarize in 2–3 sentences: issue number/title, branch name, files changed (counts only), and tests added. Then stop.
