---
name: vocabulary-rename-stragglers
description: The seven places stale prose hides after a CreamBun refactor — a renamed/removed domain term, or an "only/never" scope claim a behavior change just falsified
metadata:
  type: project
---

When a refactor renames or removes a piece of **domain vocabulary** — an `EquipSlot` member,
a `sample_*` item id, a `Slot_*` node name — GDScript and GUT only prove the *code* paths were
updated. The suite goes green with the old term still sitting in five places that no compiler
or test reads.

**Why:** the codebase carries the same vocabulary in prose (README, design docs), in
markdown-driven e2e scenarios, and in binary reference screenshots. None of those are covered
by `godot-testing:run-unit` / `run-integration`, which is what an implementer typically runs
before asking for review.

**How to apply:** grep case-insensitively for **both the old identifier and its English form**
(`BOOTS` *and* "boots") across the whole repo, not just `*.gd`, and check these specifically:

1. **`README.md`** — the root README is CLAUDE.md's stated source of truth for the game design.
   Its feature prose (e.g. the notebook-tab paragraph) enumerates domain vocabulary in plain
   English and goes stale silently, leaving the design doc of record contradicting the code.
2. **`docs/features/<area>/design.md` outside the section being edited** — the §2 folder-tree
   block carries inline `# One slot (backpack, boots, etc.)` comments that a scoped "edit §5.2"
   instruction never reaches.
3. **`.gd` doc-comments in production code** — `equipment_slot.gd` illustrates the pattern:
   the `_slot` field comment got updated while the `@onready` label comment and the
   `_can_drop_data` rationale ("prevents dropping boots onto the gloves slot") did not. Comments
   naming removed enum members are the highest-value straggler because they mislead at the
   point of edit.
4. **`tests/e2e/**/*.md` + their reference screenshots** — see [[testing-conventions]]. These
   are executed by the testing-sandbox MCP server, not GUT, so "full unit+integration suite
   passes" says nothing about them.
5. **`docs/features/*/slice-*-test-plan.md`** — historical slice plans repeat the old ids. Low
   priority (they describe a past slice), but worth naming so the omission is a decision.
6. **Test-file prose: assertion *messages*, local variable names, and arithmetic in comments.**
   The mechanical part of a rename (`EquipSlot.BOOTS` → `EquipSlot.CLOTHING`) leaves the
   surrounding English behind, producing self-contradicting lines like
   `assert_eq(heading.text, "Clothing", "SlotLabel must show the slot name ('Boots')")` and
   fixture vars still called `boots` while holding a CLOTHING item. Two sub-cases are easy to
   miss with a `BOOTS` grep: **files the diff never touched** (a `before_each` doc-comment in a
   *different* suite that recites the starter bag), and **numbers** — if the rename changes an
   item's weight/count, grep the old total too (`2.3`), since a comment like
   `# 3 x 0.5 + 1 x 0.8 = 2.3 kg` stays green when the assertion beneath it is a loose
   `assert_ne(..., "Weight: 0.0 ...")`.

7. **Absolute-scope claims ("only", "never", "unaffected") that a *behavior* change falsified.**
   Not a rename at all, but the same failure mode: when a fix widens what a state variable
   drives, every comment asserting the old narrow scope becomes a lie and no test catches it.
   Grep the touched file for `only`, `never`, `unaffected`, `always` before approving. The
   canonical instance: `_selected` used to drive nothing but `SelectionRect.visible`, so
   `equipment_slot.gd` and `test_equipment_slot.gd` between them carried **six** variants of
   "SelectionRect is the only element driven by selection state" — including one *inside*
   `_update_display()`, a few lines below new code that also drives `ItemNameLabel`'s
   `font_color` off `_selected`. Test *names* count too
   (`test_set_selected_true_reveals_highlight_only`).

## Related

[[game-data-conventions]] — why an enum rename can also be a save-schema change.
[[runtime-theme-override-vs-scene-guard]] — the theme-override change that produced case 7.
[[testing-conventions]] — the e2e-staleness rule this extends.
