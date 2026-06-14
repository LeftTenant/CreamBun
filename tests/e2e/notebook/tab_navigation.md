# Scenario: Tab navigation (cycle forward / backward / hotkey switch)

Verifies that while the notebook is open, `PageUp` and `PageDown` cycle through
the five tabs and that pressing a tab hotkey while a *different* tab is open
switches the tab without closing the notebook.

Design doc reference: §7.2 (Tab navigation).

## Setup
- Load scene: `res://world/world.tscn`
- Wait: 10 frames
- Press action: `open_notebook_inventory`
- Wait: 10 frames
- Assert: node property `Notebook._current_tab` == `0` (INVENTORY)

## Steps

### Step 1: PageUp — INVENTORY (0) → MAP (1)
- Press action: `notebook_page_next`
- Wait: 5 frames
- Screenshot → save / compare reference: `tab_navigation_step_01_map.png`
- Assert: node property `Notebook._current_tab` == `1` (MAP)

### Step 2: PageUp — MAP (1) → QUESTS (2)
- Press action: `notebook_page_next`
- Wait: 5 frames
- Screenshot → save / compare reference: `tab_navigation_step_02_quests.png`
- Assert: node property `Notebook._current_tab` == `2` (QUESTS)

### Step 3: PageUp — QUESTS (2) → SETTINGS (3)
- Press action: `notebook_page_next`
- Wait: 5 frames
- Screenshot → save / compare reference: `tab_navigation_step_03_settings.png`
- Assert: node property `Notebook._current_tab` == `3` (SETTINGS)

### Step 4: PageUp — SETTINGS (3) → SESSIONS (4)
- Press action: `notebook_page_next`
- Wait: 5 frames
- Screenshot → save / compare reference: `tab_navigation_step_04_sessions.png`
- Assert: node property `Notebook._current_tab` == `4` (SESSIONS)

### Step 5: PageUp wraps SESSIONS (4) → INVENTORY (0)
- Press action: `notebook_page_next`
- Wait: 5 frames
- Assert: node property `Notebook._current_tab` == `0` (INVENTORY)
- Assert: node property `Notebook.visible` == `true`  (no accidental close)

### Step 6: PageDown wraps backward INVENTORY (0) → SESSIONS (4)
- Press action: `notebook_page_prev`
- Wait: 5 frames
- Assert: node property `Notebook._current_tab` == `4` (SESSIONS)
- Assert: node property `Notebook.visible` == `true`

### Step 7: Hotkey on a different tab switches without closing
- Press action: `open_notebook_quests`
- Wait: 5 frames
- Screenshot → save / compare reference: `tab_navigation_step_07_quests_via_hotkey.png`
- Assert: node property `Notebook._current_tab` == `2` (QUESTS)
- Assert: node property `Notebook.visible` == `true`

### Step 8: Same-tab hotkey toggles closed
- Press action: `open_notebook_quests`
- Wait: 5 frames
- Assert: node property `Notebook.visible` == `false`
- Assert: `GameState.current_state` == `PLAYING`
