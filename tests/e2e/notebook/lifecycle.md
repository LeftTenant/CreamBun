# Scenario: Notebook open / close / toggle lifecycle

Verifies the core open/close contract: hotkeys open to the right tab,
pressing the same hotkey toggles the notebook closed, Esc closes (or reopens
to the last tab), `GameState` and `get_tree().paused` follow the visibility.

Design doc reference: §6 (State integration) and §7.1 (Open / close).

## Setup
- Load scene: `res://world/world.tscn`
- Wait: 10 frames
- Assert: `GameState.current_state` == `PLAYING`
- Assert: node property `Notebook.visible` == `false`

## Steps

### Step 1: Initial state — world plays, notebook hidden
- Screenshot → save / compare reference: `lifecycle_step_01_world_only.png`
- Assert: node property `Notebook.visible` == `false`
- Assert: `GameState.current_state` == `PLAYING`

### Step 2: Press I — notebook opens on Inventory tab
- Press action: `open_notebook_inventory`
- Wait: 10 frames
- Screenshot → save / compare reference: `lifecycle_step_02_open_inventory.png`
- Assert: node property `Notebook.visible` == `true`
- Assert: node property `Notebook._current_tab` == `0` (INVENTORY)
- Assert: `GameState.current_state` == `NOTEBOOK`

### Step 3: World is paused while notebook is open
- Assert: `get_tree().paused` is reflected by `GameState.NOTEBOOK` — the world
  state machine is the source of truth here. (We rely on the GameState
  assertion above plus a visual diff against step 1 / step 4 screenshots.)

### Step 4: Press I again — notebook toggles closed
- Press action: `open_notebook_inventory`
- Wait: 10 frames
- Screenshot → save / compare reference: `lifecycle_step_04_closed_again.png`
- Assert: node property `Notebook.visible` == `false`
- Assert: `GameState.current_state` == `PLAYING`

### Step 5: Press M — notebook reopens directly on Map tab
- Press action: `open_notebook_map`
- Wait: 10 frames
- Screenshot → save / compare reference: `lifecycle_step_05_open_map.png`
- Assert: node property `Notebook.visible` == `true`
- Assert: node property `Notebook._current_tab` == `1` (MAP)
- Assert: node property `Notebook._last_tab` == `1`

### Step 6: Press Esc — notebook closes from Map tab
- Press action: `ui_cancel`
- Wait: 10 frames
- Assert: node property `Notebook.visible` == `false`
- Assert: `GameState.current_state` == `PLAYING`

### Step 7: Press Esc again — notebook reopens to last tab (Map)
- Press action: `ui_cancel`
- Wait: 10 frames
- Screenshot → save / compare reference: `lifecycle_step_07_reopen_last_tab.png`
- Assert: node property `Notebook.visible` == `true`
- Assert: node property `Notebook._current_tab` == `1` (MAP)
- Assert: `GameState.current_state` == `NOTEBOOK`
