# Notebook — Design Document

The notebook  is the primary out-of-world UI in CreamBun. It is presented in-fiction as a physical book Cream Bun carries: when the player opens it, a leather-bound notebook fills the screen and the world fades behind it. Inside are five tabbed sections covering inventory, maps, quests, settings, and Story (save session) management.

This document describes how the notebook is structured, what data it consumes, and how it integrates with the existing autoloads (`GameEvents`, `GameState`, `SaveManager`).

---

## 1. Player Experience (in one paragraph)

Pressing **I**, **Tab**, or the gamepad menu button slows the world to a stop and a cozy notebook flips open in the centre of the screen. The pages have soft paper textures and hand-drawn tab markers along the right edge. The player can browse with the mouse, click tabs, drag items between slots — or use arrow keys, **E/T/R** shortcuts, and a gamepad. Closing the notebook (same button, or **Esc**) tucks it away with a gentle paper sound and gameplay resumes. There is no failure here: the notebook is a calm, low-pressure screen the player can dwell in.

---

## 2. Scene & Folder Structure

All notebook scenes and scripts live under `ui/notebook/`, following the project's co-location pattern. Each tab is its own self-contained scene — the root notebook scene swaps between them.

```
ui/
  notebook/
    notebook.tscn                  # Root CanvasLayer; owns the book frame and tab strip
    notebook.gd                    # Open/close, tab switching, input routing

    shared/
      notebook_tab.gd              # Base class all tab scripts extend
      page_panel.tscn              # A single "page" Panel with paper background
      page_panel.gd

    inventory/
      inventory_tab.tscn           # Equipment (left page) + item list (right page)
      inventory_tab.gd
      equipment_slot.tscn          # One slot (backpack, boots, etc.)
      equipment_slot.gd
      inventory_row.tscn           # One item row in the right-page list
      inventory_row.gd
      drag_preview.tscn            # Floating sprite shown while dragging

    map/
      map_tab.tscn                 # Global map (left) + local map (right)
      map_tab.gd
      global_map.gd
      local_map.gd                 # Renders fog-of-war over a TileMapLayer snapshot

    quests/
      quests_tab.tscn              # Quest list (left) + quest detail (right)
      quests_tab.gd
      quest_row.tscn
      quest_row.gd

    settings/
      settings_tab.tscn
      settings_tab.gd

    sessions/
      sessions_tab.tscn            # Story switching / new Story
      sessions_tab.gd
      story_card.tscn              # One card per existing Story save
      story_card.gd
```

The `notebook.tscn` is a `CanvasLayer` so it overlays the world. All `CanvasLayer` nodes in this feature must use `process_mode = 3` (`PROCESS_MODE_ALWAYS`) so the UI keeps responding while the game tree is paused — see `CLAUDE.md`.

The notebook scene is **instanced once at game startup** by `world.tscn` (or a dedicated `ui_root.tscn` if we add one later) and stays in the tree, hidden until opened. This avoids re-instantiating on every open.

---

## 3. Data Models

All custom data classes live as `.gd` files with a `class_name`, with their `.tres` instances under `resources/data/<category>/`.

### 3.1 New resource classes

#### `ItemData` — `resources/data/items/item_data.gd`

Already referenced in `CLAUDE.md`; the notebook is the first feature to consume it.

| Property            | Type           | Purpose                                                       |
|---------------------|----------------|---------------------------------------------------------------|
| `id`                | `StringName`   | Stable lookup key (e.g. `&"horsenut_leaf"`).                  |
| `display_name`      | `String`       | Shown in inventory rows and tooltips.                         |
| `icon`              | `Texture2D`    | The "photo" on each row.                                      |
| `weight`            | `float`        | In abstract units; sum must be ≤ backpack capacity.           |
| `description`       | `String`       | Long-form blurb for the right-page detail panel (Phase 2).    |
| `equip_slot`        | `EquipSlot`    | Enum below; `NONE` for non-equippable.                        |
| `is_recyclable`     | `bool`         | Gates the **R** action.                                       |
| `recycle_yield`     | `Array[ItemStack]` | What pops out when recycled. Empty = consumed without output. |
| `stackable`         | `bool`         | If true, multiple of this item collapse into one row with a count. |
| `max_stack`         | `int`          | Cap when `stackable`. Default 99.                             |

`EquipSlot` enum (defined inside `item_data.gd`):

```gdscript
enum EquipSlot {
    NONE,
    BACKPACK,
    CLOTHING,
    BOOTS,
    GLOVES,
    GOGGLES,
    NECKLACE,
}
```

Equipment-only items also need backpack capacity. Phase 1 keeps it simple by adding a single optional field on `ItemData`:

| Property              | Type    | Purpose                                       |
|-----------------------|---------|-----------------------------------------------|
| `backpack_capacity`   | `float` | Only read when `equip_slot == BACKPACK`. 0 otherwise. |

#### `ItemStack` — `resources/data/items/item_stack.gd`

A small resource binding an `ItemData` to a count. Used inside the inventory and inside `recycle_yield`. Keeping it as a resource (instead of a `Dictionary`) makes it inspectable in the Godot editor, which is helpful for a beginner project.

| Property    | Type         |
|-------------|--------------|
| `item_id`   | `StringName` |
| `count`     | `int`        |

#### `Inventory` — `resources/data/items/inventory.gd`

Runtime resource (not loaded from disk; created at session start, persisted by `SaveManager`). Owns the player's bag contents and equipped items. Always `duplicate()`d per Story.

| Property             | Type                                | Purpose                                |
|----------------------|-------------------------------------|----------------------------------------|
| `stacks`             | `Array[ItemStack]`                  | The unequipped contents.               |
| `equipped`           | `Dictionary[EquipSlot, ItemData]`   | Currently worn items.                  |

Methods (sketch):

```gdscript
func add(item: ItemData, count: int = 1) -> int       # returns leftover count
func remove(item: ItemData, count: int = 1) -> bool
func equip(item: ItemData) -> ItemData                # returns the item unequipped, if any
func unequip(slot: EquipSlot) -> ItemData
func capacity() -> float                              # from equipped backpack
func current_weight() -> float                        # sum of stacks[i].item.weight * count
```

#### `QuestData` — `resources/data/quests/quest_data.gd`

| Property           | Type             | Purpose                                                     |
|--------------------|------------------|-------------------------------------------------------------|
| `id`               | `StringName`     | Stable id for save data.                                    |
| `title`            | `String`         | Shown in the list.                                          |
| `description`      | `String`         | Shown in the right-page detail.                             |
| `objectives`       | `Array[String]`  | Phase 1: simple text bullets.                               |
| `is_main`          | `bool`           | Decorative pin/icon in the list.                            |

A separate **runtime** resource `QuestLog` tracks state across the play session:

```gdscript
# resources/data/quests/quest_log.gd
class_name QuestLog
extends Resource

# id -> { "status": int, "completed_objectives": Array[int] }
@export var states: Dictionary = {}

enum Status { ACTIVE, COMPLETED, HIDDEN }
```

Quest definitions are static (`.tres` on disk); their state lives in `QuestLog` which is part of the saved Story.

#### `MapDestination` — `resources/data/map/map_destination.gd`

| Property         | Type        | Purpose                                                  |
|------------------|-------------|----------------------------------------------------------|
| `id`             | `StringName`| Stable id (e.g. `&"hopster_forest"`).                    |
| `display_name`   | `String`    | Label shown after first visit.                           |
| `world_position` | `Vector2`   | Pin location on the global map texture.                  |
| `local_scene`    | `PackedScene` | The local-map scene to load on fast travel.            |
| `pin_icon`       | `Texture2D` | Optional decorative pin sprite.                          |

A `MapState` runtime resource tracks visits and fog of war:

```gdscript
# resources/data/map/map_state.gd
class_name MapState
extends Resource

@export var visited_destinations: Array[StringName] = []
# Per-destination explored cells; key: destination id, value: PackedByteArray bitmask
@export var fog_data: Dictionary = {}
```

Storing fog as a `PackedByteArray` keyed by destination keeps saves compact and is straightforward to write/read in GDScript.

#### `StorySlot` — `resources/data/sessions/story_slot.gd`

Metadata about one save session ("Story"). The `SaveManager` serializes one of these per slot.

| Property        | Type        | Purpose                                                 |
|-----------------|-------------|---------------------------------------------------------|
| `slot_id`       | `String`    | Filename-safe id, e.g. `story_a3f1`.                    |
| `display_name`  | `String`    | Player-entered name (default: their character name).    |
| `cover_color`   | `Color`     | Drives the notebook cover tint.                         |
| `cover_pattern` | `int`       | Index into a small set of pattern textures.             |
| `created_at`    | `int`       | `Time.get_unix_time_from_system()`.                     |
| `last_played`   | `int`       | Used for sorting on the sessions tab.                   |
| `play_seconds`  | `int`       | Cumulative playtime; nice flavour text on the card.     |

The cover color/pattern are randomised at Story creation — that randomisation is what makes each notebook visually distinct (per the README's "slightly different notebook depiction").

### 3.2 Settings

Phase 1 keeps settings in a tiny resource that mirrors what the UI exposes:

```gdscript
# resources/data/settings/game_settings.gd
class_name GameSettings
extends Resource

@export var master_volume: float = 1.0   # 0.0..1.0
@export var music_volume: float = 1.0
@export var sfx_volume: float = 1.0
@export var window_scale: int = 4        # integer multiplier for the 320x180 viewport
@export var text_speed: float = 1.0      # multiplier for typewriter dialogue
```

Settings are global to the install (not per-Story) and are persisted by `SaveManager` to a separate file (`user://settings.tres`).

---

## 4. New `GameEvents` Signals

Add the following to `autoloads/game_events.gd`. Group them with comment headers for clarity.

```gdscript
# Notebook lifecycle
signal notebook_opened(tab: int)            # tab is NotebookTab enum below
signal notebook_closed()
signal notebook_tab_changed(tab: int)

# Inventory
signal inventory_changed()                  # any add/remove/equip/unequip
signal item_equipped(item: ItemData, slot: int)
signal item_unequipped(item: ItemData, slot: int)
signal item_dropped(item: ItemData, count: int)
signal item_recycled(item: ItemData, yield_stacks: Array)
signal inventory_full(item: ItemData)       # UI flashes a gentle "no room" hint

# Map / fast travel
signal destination_visited(id: StringName)
signal fast_travel_requested(id: StringName)

# Quests
signal quest_added(id: StringName)
signal quest_updated(id: StringName)
signal quest_completed(id: StringName)

# Sessions / Stories
signal story_created(slot: StorySlot)
signal story_loaded(slot: StorySlot)
signal story_switch_requested(slot_id: String)
```

`NotebookTab` is a small enum that lives on `notebook.gd`:

```gdscript
enum NotebookTab { INVENTORY, MAP, QUESTS, SETTINGS, SESSIONS }
```

The signal bus only carries the *integer* (`int`) so we don't have to forward-declare the enum across scripts.

> **Pattern note**: Per `CLAUDE.md`, only signals that legitimately cross system boundaries belong on `GameEvents`. Signals strictly between, say, an `EquipmentSlot` and the `InventoryTab` (its parent) should remain local — wire those with direct `$Node` references.

---

## 5. UI Layout

### 5.1 Book frame

The notebook scene (`notebook.tscn`) is structured like:

```
Notebook (CanvasLayer, process_mode=ALWAYS)
  Dimmer (ColorRect)              # semi-transparent black, fades in/out
  BookFrame (TextureRect)         # the leather book art, two-page spread
    LeftPage (PagePanel)
      <swappable left content>
    RightPage (PagePanel)
      <swappable right content>
    TabStrip (VBoxContainer)      # five tab buttons running down the right edge
      InventoryTab (TextureButton)
      MapTab (TextureButton)
      QuestsTab (TextureButton)
      SettingsTab (TextureButton)
      SessionsTab (TextureButton)
    CloseHint (Label)             # "I to open/close  •  Esc to close or cancel"
```

When a tab is clicked or its hotkey is pressed, `notebook.gd` removes whatever is currently parented under `LeftPage` and `RightPage` and instances the appropriate tab scene in their place. Tab scenes expose `populate_left(parent: Control)` and `populate_right(parent: Control)` via the `notebook_tab.gd` base class.

### 5.2 Inventory tab

**Left page — Equipment**

A pixel-art silhouette of Cream Bun in the centre, surrounded by six `EquipmentSlot` nodes positioned over their corresponding body region:

```
  GOGGLES (head)
  NECKLACE (collar)
BACKPACK (back)   CLOTHING (torso)
GLOVES (paws)
  BOOTS (feet)
```

Each `EquipmentSlot` is a `Control` with:

- A square frame drawn behind the icon
- An item icon (or a faint silhouette of the slot type when empty)
- A focus ring (visible when arrow-key navigation lands on it)
- Mouse drop target behaviour (accepts an `ItemData` drag payload of matching `equip_slot`)
- `slot_clicked(slot: EquipSlot)` signal handled directly by the parent `inventory_tab.gd`

**Right page — Inventory list**

Top-of-page header: `Weight: 12.4 / 30.0` driven by `Inventory.current_weight()` and `Inventory.capacity()`.

Body: a `ScrollContainer` containing a `VBoxContainer` of `inventory_row.tscn` instances. Each row shows: icon (32×32), name, count (if stack > 1), and weight. The currently selected row gets a tinted background.

Footer: three buttons in a row: **Equip (E)**, **Throw out (T)**, **Recycle (R)**. Buttons are also **drop targets**: dragging a row onto a button performs the action without needing a prior selection.

#### Selection model (Phase 1)

There is **one selection cursor** for the inventory tab, which can be:

- An `EquipmentSlot` (left page), or
- An `InventoryRow` (right page).

Arrow keys move the cursor:

- Left/Right cross between pages.
- Up/Down move within the page (across slots on the left, scroll the list on the right).

This keeps keyboard nav simple and predictable. Phase 2 may add separate cursors per page.

#### Action verbs

| Verb     | Mouse                                  | Keyboard                               | Result                                    |
|----------|----------------------------------------|----------------------------------------|-------------------------------------------|
| Select   | Click slot/row                         | Arrow keys                             | Highlights the item.                      |
| Equip    | Drag row → equipment slot, or → Equip button | **E** with row selected         | Calls `Inventory.equip()`. Old item, if any, returns to the list. |
| Drop     | Drag row → Throw out button, or click Throw out | **T** with row selected         | Calls `Inventory.remove()`; emits `item_dropped`. |
| Recycle  | Drag row → Recycle button, or click Recycle      | **R** with row selected         | Replaces the item with `recycle_yield`. Disabled when `is_recyclable` is false; the button greys out. |
| Unequip  | Drag equipment slot → list                       | **E** with slot selected        | Calls `Inventory.unequip()`.              |

**Throw out** has no confirmation in Phase 1 — the cozy tone tolerates the occasional misclick. Phase 2 can add an undo banner.

### 5.3 Map tab

**Left page — Global map.** A `TextureRect` of a hand-drawn world map. `MapDestination` resources are positioned via `world_position` as child `TextureButton`s. Unvisited destinations show a faint `?` instead of the label. Clicking a destination shows a tooltip with its name and a **Travel here** button. Confirming emits `fast_travel_requested(id)` and closes the notebook. The player's current destination is indicated by a small Cream Bun sprite placed beside that destination's pin — not replacing it, so the pin art and the character sprite are both visible side by side.

**Right page — Local area.** A scrollable view of the current location rendered as a simplified map showing only **terrain and significant landmarks** (buildings, bridges, major trees, bodies of water) — not item-level detail such as which foraging spots currently have items available. This scope decision means the map never needs to update when the world mutates (picked plants, moved items), so a static `Texture2D` snapshot rendered to a `SubViewport` at scene load is sufficient. Fog-of-war (`Image`/`ImageTexture` bitmask overlay, one bit per explored chunk of e.g. 8×8 tiles) is applied on top. Cream Bun's current position is drawn as a small pin sprite.

### 5.4 Quests tab

**Left page.** A `VBoxContainer` of `quest_row.tscn` nodes inside a `ScrollContainer`. Active quests are listed first (sorted by recency); a horizontal divider separates them from completed quests, which are dimmed.

**Right page.** Detail for the selected quest:

- Title (large)
- Description paragraph
- Objectives as bullet checkboxes (`[x]` if completed)
- A small "rewards" footer (Phase 2)

If no quest is selected, the right page shows a friendly placeholder ("Select a quest to see details.").

### 5.5 Settings tab

Settings are split across both pages, one category group per page. Each page is a vertical list of labelled controls. Non-selectable category headers separate the groups within a page.

**Left page — Audio & Gameplay**

| # | Label | Control | Values |
|---|-------|---------|--------|
| — | **Audio** | *(header)* | |
| 1 | Master volume | `HSlider` | 0–100% |
| 2 | Music volume | `HSlider` | 0–100% |
| 3 | SFX volume | `HSlider` | 0–100% |
| — | **Gameplay** | *(header)* | |
| 4 | Text speed | `HSlider` | Slow / Normal / Fast (0–2) |

**Right page — Display**

| # | Label | Control | Values |
|---|-------|---------|--------|
| — | **Display** | *(header)* | |
| 1 | Window scale | `OptionButton` | 1×, 2×, 3×, 4× |
| 2 | Fullscreen | `OptionButton` | Windowed, Fullscreen, Borderless |
| — | **Accessibility** | *(header)* | |
| 3 | *(reserved for Phase 2)* | | |

A **Reset to defaults** button sits at the bottom of each page, affecting only the settings on that page.

#### Keyboard navigation

- **Left / Right** move focus between the left page and the right page.
- **Up / Down** move focus between selectable rows within the focused page. Category headers are skipped.
- **Enter / ui_accept** activates the focused control:
  - On an `HSlider`: the slider enters *edit mode*. Left / Right now nudge the value. **Enter** confirms and exits edit mode; **Esc / ui_cancel** reverts to the value before activation and exits edit mode.
  - On an `OptionButton`: the dropdown opens. Up / Down move between options; **Enter** selects; **Esc / ui_cancel** closes without changing.

Mouse interaction follows Godot's standard `Control` behaviour — click to focus, drag sliders, click options.

#### Applying changes

Settings are applied **immediately** where the engine allows it (volume via `AudioServer`, text speed via the dialogue system). Settings that require an engine restart — currently only **Fullscreen** mode changes on some platforms — prompt the player with a small modal:

> *"This change will take effect after restarting. Restart now?"*
> **Restart** / **Later**

Choosing **Later** keeps the new value stored in `GameSettings` so it is applied on the next launch, but reverts the live display to the old value until then. The control also shows a small line beneath the current value — e.g. *"On restart: Fullscreen"* — so the player can see what is pending without opening a separate menu.

### 5.6 Sessions tab

**Left page.** A list of existing Stories as `story_card.tscn` nodes. Each card shows:

- The notebook's cover (rendered with the slot's `cover_color`/`cover_pattern`)
- The Story's display name
- "Last played: 3 days ago"
- A small **Switch to this Story** button

A **+ New Story** card sits at the top.

**Right page.** Detail for the selected Story: bigger cover preview, total playtime, character name, and a **Delete Story** button (with a confirmation modal — destructive, so this one *does* confirm).

#### The cover-swap transition

When the player chooses to switch:

1. Notebook closes with its current cover (page-flip + cover-close animation).
2. `GameEvents.story_switch_requested` fires.
3. `SaveManager` flushes the current Story (it should already be on disk thanks to autosave), then loads the new slot.
4. `GameState.change_state(LOADING)` while assets swap.
5. Notebook re-opens already on the Sessions tab, but now drawn with the *new* slot's cover_color/pattern. The transition reads as the same notebook becoming a different one.

Creating a new Story works the same way, with an intro sequence (per the README) preceding the re-open.

---

## 6. State Integration

Opening the notebook transitions to `GameState.State.NOTEBOOK`. This requires renaming the existing `INVENTORY` state in `autoloads/game_state.gd` to `NOTEBOOK`, and updating any code that references `State.INVENTORY`. The rename is intentional: the notebook is the container — the inventory tab is just one page inside it — and naming the state after the whole UI avoids confusion when future features check game state.

```gdscript
# autoloads/game_state.gd — rename INVENTORY → NOTEBOOK, remove PAUSED
enum State {
    MAIN_MENU,
    PLAYING,
    DIALOGUE,
    NOTEBOOK,   # was INVENTORY
    COMBAT,
    LOADING,
}
```

The `PAUSED` state is removed entirely. Opening the notebook is the intended way to pause the game — a dedicated pause state is redundant and would require every system that checks game state to handle an extra case. Any code that previously referenced `State.PAUSED` should be removed or replaced with a check for `State.NOTEBOOK`.

```gdscript
# notebook.gd (sketch)

var _previous_state: GameState.State

func open(initial_tab: int = NotebookTab.INVENTORY) -> void:
    _previous_state = GameState.current_state
    GameState.change_state(GameState.State.NOTEBOOK)
    get_tree().paused = true
    show()
    _switch_tab(initial_tab)
    GameEvents.notebook_opened.emit(initial_tab)

func close() -> void:
    hide()
    get_tree().paused = false
    GameState.change_state(_previous_state)
    GameEvents.notebook_closed.emit()
```

Pause-game-tree behaviour: with `get_tree().paused = true`, only nodes whose `process_mode` is `ALWAYS` or `WHEN_PAUSED` keep ticking. The notebook's `CanvasLayer` and all its descendants must be `ALWAYS` (already required by `CLAUDE.md`). The world stays frozen.

The settings tab needs `get_tree().paused = false` exempt for any audio bus changes, but those happen via `AudioServer` which is not affected by tree pause — no special handling needed.

---

## 7. Input Handling

### 7.1 Open / close

Each tab has a dedicated hotkey that opens the notebook directly to that tab. `notebook.gd` tracks `_last_tab` so Esc can reopen to whichever tab was last active.

| Action | Key | Opens to |
|---|---|---|
| `open_notebook_inventory` | I | Inventory tab |
| `open_notebook_map` | M | Map tab |
| `open_notebook_quests` | Q | Quests tab |
| `ui_cancel` (built-in) | Esc | Last-opened tab, or closes if already open |

Pressing a tab hotkey when the notebook is already open on that tab closes the notebook (toggle). Pressing a tab hotkey when the notebook is open on a *different* tab switches to that tab without closing.

```gdscript
# notebook.gd (sketch)

var _last_tab: int = NotebookTab.INVENTORY
var _current_tab: int = NotebookTab.INVENTORY

func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("open_notebook_inventory"):
        _open_or_switch(NotebookTab.INVENTORY)
        get_viewport().set_input_as_handled()
    elif event.is_action_pressed("open_notebook_map"):
        _open_or_switch(NotebookTab.MAP)
        get_viewport().set_input_as_handled()
    elif event.is_action_pressed("open_notebook_quests"):
        _open_or_switch(NotebookTab.QUESTS)
        get_viewport().set_input_as_handled()
    elif event.is_action_pressed("ui_cancel"):
        if visible:
            close()
        else:
            open(_last_tab)
        get_viewport().set_input_as_handled()

func _open_or_switch(tab: int) -> void:
    if visible and _current_tab == tab:
        close()
    elif visible:
        _switch_tab(tab)
    else:
        open(tab)

func _switch_tab(tab: int) -> void:
    _current_tab = tab
    _last_tab = tab
    # ... swap page content
```

**Esc behaviour has three cases, handled naturally by Godot's event propagation:**

1. **Notebook is closed** — `ui_cancel` reaches `_unhandled_input`; the notebook opens to `_last_tab`.
2. **Notebook is open, no control is active** — `ui_cancel` reaches `_unhandled_input`; the notebook closes.
3. **A settings control (slider or dropdown) is in edit mode** — the focused `Control` node consumes `ui_cancel` first, cancelling the edit and returning the control to its resting state. The event never reaches `_unhandled_input`, so the notebook stays open.

Case 3 is free: active controls already handle `ui_cancel` via Godot's built-in `Control` behaviour with no extra code required.

The existing `open_inventory` action in `project.godot` should be **removed** and replaced with the four per-tab actions above. The existing `pause` action should also be **removed** — Esc is handled via `ui_cancel` and there is no longer a separate pause state. A gamepad button binding should be added to each tab action, or mapped to a single button that opens to `_last_tab` (proposal: `JOY_BUTTON_START`).

### 7.2 Tab navigation

Inside the notebook:

- Mouse: click a `TabStrip` button.
- Keyboard: **PageUp** cycles forward through tabs; **PageDown** cycles backward. Arrow keys are reserved for in-tab selection and are not used here. **Tab**/**Shift+Tab** are reserved for normal in-page focus navigation (e.g. moving between Settings sliders) and do not cycle tabs.
- Gamepad: shoulder buttons (`L1`/`R1`).

`notebook.gd` manages this via `_unhandled_input` and dispatches to `_switch_tab(NotebookTab)`.

> **Note:** PageUp/PageDown are dedicated `notebook_page_next`/`notebook_page_prev` actions in `project.godot`, so they keep cycling tabs even while a Control has focus — unlike `ui_focus_next`/`ui_focus_prev` (Tab/Shift+Tab), which a focused Control consumes first. This resolves the focus-conflict issue described in the open questions (issue #26). On macOS laptops without dedicated PageUp/PageDown keys, use fn+up/down arrow.

### 7.3 Within-tab input

Each tab script handles its own input through `_unhandled_input`. The notebook always processes input before the tab, and tabs do not call `set_input_as_handled()` for navigation keys they don't consume — letting unused keys fall through is fine.

For the inventory tab specifically:

```gdscript
# inventory_tab.gd (sketch)

func _unhandled_input(event: InputEvent) -> void:
    if not visible:
        return
    if event.is_action_pressed("ui_up"):    _move_cursor(Vector2i.UP)
    elif event.is_action_pressed("ui_down"):  _move_cursor(Vector2i.DOWN)
    elif event.is_action_pressed("ui_left"):  _move_cursor(Vector2i.LEFT)
    elif event.is_action_pressed("ui_right"): _move_cursor(Vector2i.RIGHT)
    elif event.is_action_pressed("notebook_equip"):    _do_equip()
    elif event.is_action_pressed("notebook_throw"):    _do_throw()
    elif event.is_action_pressed("notebook_recycle"):  _do_recycle()
```

We add three new input actions to `project.godot`:

| Action              | Default key | Notes                              |
|---------------------|-------------|------------------------------------|
| `notebook_equip`    | E           | Same physical key as `interact`. Only consumed when the notebook is open, so they don't conflict. |
| `notebook_throw`    | T           |                                    |
| `notebook_recycle`  | R           |                                    |

These can be bound on gamepad to face buttons (e.g. A/B/X) when we wire that up.

### 7.4 Drag-and-drop

Godot 4 has built-in drag-and-drop on `Control` nodes via `_get_drag_data`, `_can_drop_data`, `_drop_data`. We use this verbatim. Documentation: <https://docs.godotengine.org/en/stable/tutorials/ui/gui_drag_and_drop.html>.

- `inventory_row.gd` overrides `_get_drag_data` to return a `Dictionary` like `{ "kind": "item", "stack": ItemStack }`.
- `equipment_slot.gd` overrides `_can_drop_data` to accept only matching `equip_slot`s, and `_drop_data` to call `Inventory.equip`.
- The action buttons (Equip / Throw / Recycle) likewise accept drops.

The drag preview is set with `set_drag_preview(preview_node)` inside `_get_drag_data` — a lightweight `TextureRect` showing the icon.

---

## 8. Session (Story) Management Flow

The notebook embodies the Story metaphor: each save slot is "a notebook". The cover art's color and pattern are picked at Story creation and shown:

1. On the spine in the Sessions tab list.
2. As the visible cover during the open/close animation.

### 8.1 Files on disk

`SaveManager` (currently a stub) gains:

```
user://stories/                       # created on first run
  story_a3f1.tres                     # full Story save (Inventory, QuestLog, MapState, position, etc.)
  story_a3f1.meta.tres                # StorySlot metadata (cover, name, last_played)
  ...
user://settings.tres                  # global settings
user://current_story.txt              # plain-text id of the most recently played slot
```

The split between `.tres` (full save) and `.meta.tres` is so the Sessions tab can list slots without paying the cost of deserialising every full save.

### 8.2 Creating a new Story

1. Sessions tab → **+ New Story** card.
2. Modal: name field + a "randomise cover" button (preview shows the result).
3. On confirm:
   - `SaveManager.create_story(name, cover_color, cover_pattern) -> StorySlot`
   - The player is equipped with a starter backpack (empty; capacity defined by `backpack_capacity` on the starter `ItemData`). Backpack capacity balancing is deferred — for now the starter backpack uses a placeholder capacity value.
   - The notebook closes with the new cover.
   - `GameEvents.story_created` fires.
   - The intro sequence (Doug's bookshop, per README) plays as a **dedicated intro scene** — not the notebook UI. When the intro completes, its events are recorded as a pre-completed quest ("The Foraging Book") in `QuestLog` so the player can review what they learned from the Quests tab at any time.
   - First autosave writes the new slot's full save file.

### 8.3 Switching Stories

1. Sessions tab → click a Story card → confirm.
2. Notebook closes with the *current* cover.
3. `GameEvents.story_switch_requested(slot_id)` → `SaveManager.load_story(slot_id)`.
4. `GameState` goes to `LOADING` while the world reloads.
5. Notebook reopens on the Sessions tab with the new cover. From the player's view, the same notebook has "become" a different one.

### 8.4 Autosave

Out of scope for this design doc, but the notebook hooks into existing autosave triggers — opening the notebook is itself a "significant state change" (per README), so the act of opening can opportunistically trigger an autosave if one hasn't happened in N seconds. This is a one-line addition once `SaveManager` is implemented.

---

## 9. Implementation Notes (Godot 4.4)

- **Pause vs not-pause.** Use `get_tree().paused = true` while the notebook is open. All notebook nodes need `process_mode = PROCESS_MODE_ALWAYS` (`3`). See <https://docs.godotengine.org/en/stable/tutorials/scripting/pausing_games.html>.
- **Single instance.** Instantiate `notebook.tscn` once at startup, hidden, rather than instancing/freeing on each open. Keeping it in the tree means tab state (last-selected item, scroll position) persists across opens for free.
- **Resource duplication.** Per `CLAUDE.md`, anything that can be shared as a `.tres` (item definitions, quest definitions, destinations) is **read-only data** and should never be mutated at runtime. Runtime state goes in `Inventory`, `QuestLog`, `MapState` resources, all of which are `.duplicate(true)`d on Story creation.
- **Drag-and-drop coordinate spaces.** When using `set_drag_preview`, the preview is a separate `Control` parented to the viewport — its mouse follow is automatic, no manual `_process` needed.
- **Theme.** Define a single `Theme` resource at `resources/data/notebook_theme.tres` and apply it on the root `BookFrame`. This keeps fonts/colours consistent across tabs.
- **Pixel-perfect.** The project uses a 320×180 viewport with stretch=`viewport`. The notebook should be designed at that resolution (the book art around 280×140 leaves margins). Avoid sub-pixel positioning of `Control` nodes.
- **Beginner-friendliness.** Each tab scene is self-contained. A new contributor can open `quests_tab.tscn` in the editor, see exactly which nodes drive what, and modify it without touching the other tabs.

---

## 10. Phasing

**Phase 1 (minimum viable notebook)**

- Scene structure, open/close, tab switching with PageUp/PageDown.
- Inventory tab with mouse + keyboard, drag-and-drop, equip/throw/recycle.
- Map tab: static terrain/landmark texture left page, static local-map placeholder right page (no fog of war yet).
- Quests tab: list + detail, no objective tracking logic (reads `QuestLog` directly). Includes the pre-completed "The Foraging Book" intro quest.
- Settings tab: volumes + window scale only.
- Sessions tab: stub showing a single "Default Story" card. No multi-Story logic yet.

**Phase 2**

- Fog of war on the local map; fast travel.
- Multi-Story creation, switching, deletion, cover-swap transition.
- Recycling animation; recycling yield preview tooltip.
- Settings persistence, controls remapping.
- Quest objective tracking with auto-advance.
- TBD: Gamepad button mapping (locked in after a play test).
- TBD: Revisit per-tab vs. shared selection cursor in the inventory tab if two-page navigation feels awkward.

**Phase 3**

- Tooltip on inventory hover.
- Filtering / sorting on the inventory list.
- A "favourites" pin per item.

---

## 11. Design Decisions

Decisions made during design review, recorded here for reference.

1. **Notebook scene tree placement** — Parented to `world.tscn` for simplicity. Refactor to a dedicated `ui_root.tscn` later if the world scene becomes too crowded.
2. **Intro sequence** — A dedicated intro scene (not the notebook UI). When it completes, its content is recorded as a pre-completed quest ("The Foraging Book") in `QuestLog` so the player can review it from the Quests tab at any time.
3. **Starter backpack** — Every new Story begins with the player already equipped with an empty starter backpack. Capacity value is a placeholder to be balanced later; upgrading to a bigger backpack is a natural early progression goal.
4. **Recycling yield preview** — Not shown in Phase 1. The player presses R and the item is recycled immediately. A yield preview tooltip is a Phase 2 addition.
5. **Gamepad mapping** — Deferred to Phase 2; locked in after a play test.
6. **Inventory tab selection cursor** — Phase 1 uses one cursor per tab. Revisit in Phase 2 if two-page navigation feels awkward.
7. **Local map scope** — The local map renders only terrain and significant landmarks, not item-level detail. This means the map never needs to react to world mutations (picked plants, etc.), so a static snapshot is sufficient.
