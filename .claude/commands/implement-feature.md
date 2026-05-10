---
description: "Drive a CreamBun feature from design doc → slices → tests → code → review via the feature-orchestrator agent, with checkpoints back to the user."
argument-hint: "<design-doc-path> [continue-all]"
---

You are running the `/implement-feature` flow for CreamBun.

**Arguments:** `$ARGUMENTS`

The first argument is the design doc path (e.g. `docs/features/notebook/design.md`).
The optional second argument `continue-all` means: do not pause between slices; the orchestrator should run all slices back-to-back, only stopping at the test-plan checkpoint inside each slice and at hard guardrails. Default behaviour pauses between slices.

## What you (the main thread) do

1. **Validate** that the design doc path was supplied and exists. If not, ask the user for it and stop — do not launch the orchestrator with a bad path.
2. **Launch the `feature-orchestrator` subagent** (`subagent_type: feature-orchestrator`) with a self-contained prompt that includes:
   - The absolute design-doc path.
   - Whether `continue-all` is in effect.
   - The instruction: "Begin Phase A — read the doc, propose a vertical slice breakdown, write it to `docs/features/<feature>/slices.md`, then end your turn with a summary so the user can approve or edit the breakdown."
3. **Relay checkpoints**: the orchestrator will end its turn whenever it needs user input. Each time it returns:
   - Surface its `Need from you:` line and the artifact path it produced (e.g. `slices.md`, a test plan).
   - Wait for the user to respond.
   - Resume the orchestrator with `SendMessage` to its agent ID, passing the user's reply verbatim plus any clarifying context. Do **not** spawn a new orchestrator — that loses all context. If you accidentally lose the agent ID, tell the user and ask whether to start over from the current slice.
4. **Handle STUCK reports**: if the orchestrator returns a STUCK report (3 fix iterations without progress, same failure twice, same review issue twice, or a design/test contradiction), present its question clearly to the user and wait. Do not try to unstick it yourself by editing code — your job here is the relay, not the fix.
5. **Stay out of the work**: do not read game code, run tests, or make edits in this flow except to verify the design doc path. The specialist agents own those steps. The single exception: if the user asks a question you can answer from this conversation alone (e.g. "what slices are left?"), answer directly.

## End of flow

When the orchestrator reports the final slice complete, summarise in 2–3 sentences: feature name, slices shipped, test files added (counts only, by category), and any deferred items the user should follow up on. Then stop.
