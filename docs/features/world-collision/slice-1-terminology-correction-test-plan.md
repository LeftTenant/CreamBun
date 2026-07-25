# Slice 1 — Terminology Correction (docs only) — Test Plan

This slice is a prose-only edit (design §3.2): replace every "isometric" reference in
`CLAUDE.md` and `README.md` with the correct "top-down" / "three-quarter top-down" wording.
No game code, scene, or resource changes are in scope, so there is no automatable behavior for
GUT or the testing sandbox to exercise. The GUT (unit/integration) and e2e sections below are
intentionally empty — inventing tests for static text would not catch any real regression a
future code change could introduce.

### E2E
- (none — no runtime behavior changes; nothing renders or runs differently after this slice)

### Integration
- (none — no cross-system flow is touched)

### Unit
- (none — no isolated logic is touched)

### Read-through / grep verification

Manual checks confirming the doc text matches design §3.2 exactly:

- [ ] `CLAUDE.md` line ~5 reads "cozy top-down RPG" (not "cozy isometric RPG").
- [ ] `CLAUDE.md` line ~89 heading reads "### Depth sorting" (not "### Isometric depth sorting").
- [ ] `README.md` line ~3 reads "A cozy top-down RPG about foraging" (not "A cozy isometric RPG
      about foraging").
- [ ] `README.md` line ~41 reads "The game uses a three-quarter top-down perspective — a square
      grid viewed at an angle, with front-facing sprites and foreshortened ground. The Stardew
      Valley look. The aesthetic is soft and cute pixel art." (replacing the old "top-down
      isometric perspective" sentence verbatim, per design §3.2).
- [ ] `grep -rin "isometric" CLAUDE.md README.md` returns no matches anywhere in either file
      (catches any other stray occurrence beyond the four cited locations).
- [ ] No other file changed — `git diff --stat` shows only `CLAUDE.md` and `README.md`.
