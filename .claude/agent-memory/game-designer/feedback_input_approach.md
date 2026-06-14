---
name: Input design approach
description: How this user thinks about input design — mnemonic keys, surfacing conflicts, and resolving them cleanly
type: feedback
---

**Keyboard shortcuts should be mnemonic.** I=Inventory, M=Map, Q=Quests. The mapping should be obvious enough that a player could guess it without reading the docs.

**Why:** Players shouldn't have to memorise arbitrary bindings.

**How to apply:** Assign hotkeys starting from the first letter of the concept. Only fall back to arbitrary keys if there's a genuine conflict.

---

**Surface input conflicts explicitly as numbered items with named options.** Don't bury them in implementation notes. The user resolves them decisively once they're visible.

**Why:** Hidden conflicts become bugs. Making them visible turns them into decisions.

**How to apply:** Include a dedicated conflicts section in design docs. List each conflict, name the options, and let the user choose. Don't pre-resolve them silently.

---

**Resolve conflicts by removing redundancy, not adding workarounds.** When S conflicted with move_down, the shortcut was dropped. When Tab conflicted with ui_focus_next, Tab was repurposed and the open/close binding was simplified to I only.

**Why:** Workarounds accumulate complexity. A clean input model is worth more than preserving every proposed binding.

**How to apply:** When two bindings conflict, first ask whether one can simply be removed. Only add modifiers or guards if removal isn't viable.

**Update (issue #26):** The Tab-repurposing decision above was reverted. Binding notebook page-cycling to `ui_focus_next`/`ui_focus_prev` (Tab/Shift+Tab) broke once any Control had focus, because the focused Control consumes Tab for focus navigation before the notebook's `_unhandled_input` sees it. Page cycling now uses dedicated `notebook_page_next`/`notebook_page_prev` actions (PageUp/PageDown), and Tab/Shift+Tab are left alone for normal UI focus navigation. Don't re-propose binding page/tab cycling onto `ui_focus_*` — a focused Control will always intercept those first.
