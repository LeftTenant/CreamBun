---
description: "Drive a GitHub issue from lookup → branch → plan → tests → fix → review → PR via the github-issue-orchestrator agent, with checkpoints back to the user."
argument-hint: "<issue-number-or-url>"
---

You are running the `/fix-issue` flow for CreamBun.

**Arguments:** `$ARGUMENTS`

The argument is either a GitHub issue number (e.g. `42`) or a full issue URL (e.g. `https://github.com/<owner>/<repo>/issues/42`).

## What you (the main thread) do

1. **Validate** that an issue number or URL was supplied. If not, ask the user for one and stop — do not launch the orchestrator with no target.
2. **Launch the `github-issue-orchestrator` subagent** (`subagent_type: github-issue-orchestrator`) with a self-contained prompt that includes:
   - The raw issue argument (number or URL) exactly as supplied.
   - The instruction: "Begin Phase 1 — fetch the issue with `gh`, summarize it back to the user in plain language, and confirm your understanding before creating a branch."
3. **Relay checkpoints**: the orchestrator will end its turn whenever it needs user input (issue summary confirmation, plan approval, dirty working tree, repeated test failures, reviewer disagreements). Each time it returns:
   - Surface its question and any artifact paths it produced (branch name, plan, test files).
   - Wait for the user to respond.
   - Resume the orchestrator with `SendMessage` to its agent ID, passing the user's reply verbatim plus any clarifying context. Do **not** spawn a new orchestrator — that loses all context. If you accidentally lose the agent ID, tell the user and ask whether to start over.
4. **Handle stuck reports**: if the orchestrator reports repeated test failures (>3 iterations), a reviewer rejecting the same point twice, or any other guardrail trip, present its question clearly to the user and wait. Do not try to unstick it yourself by editing code — your job here is the relay, not the fix.
5. **Stay out of the work**: do not read game code, run tests, or make edits in this flow. The specialist agents own those steps. The single exception: if the user asks a question you can answer from this conversation alone (e.g. "what branch are we on?"), answer directly.

## End of flow

When the orchestrator reports the PR is open, surface the PR URL and summarize in 2–3 sentences: issue number/title, branch name, files changed (counts only), and tests added. Then stop.
