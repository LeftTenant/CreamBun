---
name: General design approach
description: How this user thinks about game design — naming, fiction-first philosophy, phasing, and decision-making style
type: feedback
---

**Name things after what they are, not what's convenient to reuse.** When "INVENTORY" was proposed as the game state for the entire notebook UI, it was immediately rejected — the notebook contains inventory, maps, quests, and settings, so the state is called NOTEBOOK.

**Why:** Reusing an existing name implies the concepts are the same. They're not, and the mismatch causes confusion in the code and for future contributors.

**How to apply:** Before reusing an existing term for a new concept, ask whether the name accurately describes the new thing. If not, coin the right name even if it means a small refactor.

---

**Fiction first — mechanics should reflect the game world.** Removing PAUSED from GameState wasn't just a simplification; it was because the notebook IS the pause mechanism in the fiction. The code should express that directly.

**Why:** Consistency between the game world and the system model makes the game more coherent and the code easier to reason about.

**How to apply:** When proposing game states, input actions, or system names, ask whether they match the player's in-fiction experience. Prefer names and structures a player would recognise.

---

**Simplicity first; defer complexity to explicitly named phases.** Consistently chose the simpler option (world.tscn parent, single selection cursor, placeholder backpack capacity) and committed those deferrals to Phase 2 TBD items, not vague "future work."

**Why:** Premature complexity slows early development and often gets replaced anyway. Named phases make the scope commitment real.

**How to apply:** Phase 1 should be the minimum that can be played and tested. Phase 2+ items should be named specifically, not just listed as "future work."

---

**Lead with a recommendation; make it easy to redirect.** All 7 open design questions were resolved in a single message. When a mistake was made (S key mapping), it was caught and corrected in one sentence without ceremony.

**Why:** Design sessions are more productive when proposals are concrete and corrections are fast.

**How to apply:** Always present a clear recommendation rather than equally-weighted options. When the user redirects, pivot cleanly and update the doc — don't re-argue the point.
