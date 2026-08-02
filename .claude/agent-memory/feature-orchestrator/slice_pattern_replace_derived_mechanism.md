---
name: slice-pattern-replace-derived-mechanism
description: How to slice a feature that replaces an existing, tested, in-production mechanism with a new one (e.g. world-thresholds replacing world-collision's edge-derived transitions)
metadata:
  type: feedback
---

When a design doc explicitly "supersedes" part of an earlier design and gives a §9-style exhaustive
deletion table against live, tested code (not just a diff), decompose as:

1. **Build the new mechanism's pieces additively**, one vertical slice each, without touching the
   file(s) the old mechanism lives in. This is usually possible even when the new mechanism will
   eventually live in the *same* class, because the new pieces (a new placeable node/scene, a new
   collider, a new signal-driven handler) are structurally independent of the old computed geometry
   until the final switch.
2. **Prove the new mechanism against small test-only fixtures**, not the real production content the
   old mechanism still serves live traffic through. This keeps the old mechanism's existing test
   suite green through every additive slice — nothing about it has changed yet.
3. **One atomic "switchover" slice** does all of: delete the old mechanism per the design doc's own
   deletion table, migrate real content to the new mechanism, and retire/rewrite every test that
   referenced anything on the deletion list. Call out explicitly *why* this can't be split further:
   removing the old mechanism's trigger-building step from a shared class (e.g. collapsing a
   branching wall-builder to unconditional walls) instantly breaks the old mechanism's live content
   the moment it lands, so there is no safe intermediate commit between "old mechanism still
   serves the map" and "new mechanism does."
4. **Flag every test file that references a to-be-deleted static member, enum, or signal** as part
   of the switchover slice's scope explicitly, even ones not obviously about the removed feature
   (e.g. a cross-cutting invariants file that happens to call one soon-to-be-deleted static). A
   stale reference is a parse-time failure for the *whole* suite in GDScript/GUT, not just that one
   test — this is easy to miss when skimming a file for "is this about the old mechanism," since the
   file may be 90% still-valid.
5. **A trailing docs-only slice** (updating a designer-facing reference doc) belongs last, after the
   switchover, since it documents the finished real-content mechanism rather than a proposal.
6. **When the user resolves a flagged ambiguity in a later turn, rewrite that section of
   `slices.md` as a settled decision — don't just append a "resolved:" note on top of the old
   open-question framing.** Replace hedge language ("open question," "recommend," "confirm with the
   human") with the plain statement of what was decided and why, so a specialist agent reading the
   slice later sees a spec, not a negotiation transcript. This kept `slices.md` self-sufficient per
   its own stated goal (a build-loop agent shouldn't have to reconstruct which of several options won
   from conversational back-and-forth).

See [[execution-tools-not-available]] for the broader constraint this pattern operates under (the
orchestrator writes this decomposition into `slices.md`; it does not execute any of it).
