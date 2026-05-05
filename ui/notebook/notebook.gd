class_name Notebook
extends CanvasLayer
## Root controller for the in-game notebook UI.
##
## The notebook is the primary pause mechanism in CreamBun — opening it freezes
## world time (get_tree().paused = true) and transitions the game to NOTEBOOK
## state. Closing it restores both. See docs/features/notebook/design.md §6.
##
## This node is instanced once at game startup (hidden) and stays in the tree
## for the session lifetime so tab scroll positions and selections persist across
## opens without any extra bookkeeping.
##
## Design doc: docs/features/notebook/design.md
## Pause / process_mode reference:
##   https://docs.godotengine.org/en/stable/tutorials/scripting/pausing_games.html


## The five sections that exist inside the notebook.
## Integer values are stable contract — they are stored in save data and passed
## over GameEvents signals. Do NOT reorder without a save-migration plan.
enum NotebookTab {
	INVENTORY = 0,
	MAP       = 1,
	QUESTS    = 2,
	SETTINGS  = 3,
	SESSIONS  = 4,
}

## Which tab the notebook is currently showing. Exposed for tests (GDScript does
## not enforce access control, so leading underscore is a convention only).
var _current_tab: int = NotebookTab.INVENTORY

## The most recently active tab. Used so Esc can re-open to the right tab after
## the notebook was closed, even if the player last navigated away from it.
var _last_tab: int = NotebookTab.INVENTORY

## The game state that was active when open() was called. Saved so close() can
## restore it — important for DIALOGUE → notebook → close → resume dialogue flows.
var _previous_state: GameState.State = GameState.State.PLAYING

## One NotebookTab instance per tab, created on first access and reused so each
## tab's internal state (inventory, quest log, etc.) persists across switches.
var _tab_instances: Dictionary = {}

## The tab controller that is currently populating the pages. Tracked so we can
## set its visible flag (which gates its _unhandled_input hotkeys) when switching.
var _active_tab_node: NotebookTab = null

## Page Controls populated by each tab's populate_left / populate_right calls.
## @onready resolves these after _ready() has added the scene children.
## https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html#onready-annotation
@onready var _left_page: Control = $Book/Pages/LeftPage
@onready var _right_page: Control = $Book/Pages/RightPage


# ---------------------------------------------------------------------------
# Built-in overrides
# ---------------------------------------------------------------------------

func _ready() -> void:
	# The notebook must keep processing even when the scene tree is paused,
	# so that the player can still interact with it while the world is frozen.
	# PROCESS_MODE_ALWAYS = 3 as documented in CLAUDE.md.
	# https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-property-process-mode
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Start hidden — the notebook is revealed only when open() is called.
	hide()


func _unhandled_input(event: InputEvent) -> void:
	# Per-tab hotkeys toggle the notebook open (or switch tabs if already open).
	# set_input_as_handled() prevents the event reaching other nodes.
	# https://docs.godotengine.org/en/stable/classes/class_viewport.html#class-viewport-method-set-input-as-handled
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
		# Three cases — see design doc §7.1:
		# 1. Notebook is closed → open to last tab.
		# 2. Notebook is open, no control is active → close.
		# 3. A settings control is in edit mode → that control consumes the
		#    event first, so we never reach this branch. Free behaviour.
		if visible:
			close()
		else:
			open(_last_tab)
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("ui_focus_next"):
		# Tab key: cycle forward through notebook tabs while the notebook is open.
		# We consume Tab here so it does not move UI focus to buttons/sliders.
		_switch_tab((_current_tab + 1) % NotebookTab.size())
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("ui_focus_prev"):
		# Shift+Tab: cycle backward.
		_switch_tab((_current_tab - 1 + NotebookTab.size()) % NotebookTab.size())
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# Public methods
# ---------------------------------------------------------------------------

## Opens the notebook, pauses the world, and transitions to NOTEBOOK state.
## @param initial_tab - which tab to show first (defaults to INVENTORY).
func open(initial_tab: int = NotebookTab.INVENTORY) -> void:
	_previous_state = GameState.current_state
	GameState.change_state(GameState.State.NOTEBOOK)
	get_tree().paused = true
	show()
	_switch_tab(initial_tab)
	GameEvents.notebook_opened.emit(initial_tab)


## Closes the notebook, unpauses the world, and restores the prior game state.
func close() -> void:
	hide()
	get_tree().paused = false
	GameState.change_state(_previous_state)
	GameEvents.notebook_closed.emit()


# ---------------------------------------------------------------------------
# Private methods
# ---------------------------------------------------------------------------

## Switches the active tab: updates state, notifies listeners, and renders
## the new tab's content into the left and right page Controls.
func _switch_tab(tab: int) -> void:
	_current_tab = tab
	_last_tab = tab
	GameEvents.notebook_tab_changed.emit(tab)
	_show_tab(tab)


## Decides whether a hotkey press should open the notebook, switch its tab,
## or close it (toggle). See design doc §7.1 for the full logic.
func _open_or_switch(tab: int) -> void:
	if visible and _current_tab == tab:
		# Same tab pressed again while already open → close (toggle).
		close()
	elif visible:
		# Different tab pressed while notebook is open → switch without closing.
		_switch_tab(tab)
	else:
		# Notebook is closed → open to the requested tab.
		open(tab)


## Clear both pages and populate them with the given tab's content.
## Tab instances are created once and reused so their internal state (inventory,
## quest log, etc.) persists across tab switches within a single session.
func _show_tab(tab: int) -> void:
	if _left_page == null or _right_page == null:
		return

	# Deactivate the previous tab so its _unhandled_input hotkey guard
	# (if not visible: return) prevents it firing while off-screen.
	if _active_tab_node != null:
		_active_tab_node.visible = false

	# Clear previously built page content before rebuilding.
	for child in _left_page.get_children():
		child.free()
	for child in _right_page.get_children():
		child.free()

	# Create the tab controller on first access; reuse it on subsequent visits.
	if not _tab_instances.has(tab):
		var tab_node: NotebookTab = _create_tab(tab)
		if tab_node == null:
			return
		_tab_instances[tab] = tab_node

	_active_tab_node = _tab_instances[tab]
	# Make visible so the tab's own _unhandled_input hotkeys (e.g. E/T/R in
	# InventoryTab) are active while this tab is showing.
	_active_tab_node.visible = true
	_active_tab_node.populate_left(_left_page)
	_active_tab_node.populate_right(_right_page)


## Instantiate the correct NotebookTab subclass for a given tab enum value and
## add it as a hidden child so _ready() runs and its data model initialises.
## The node is invisible because it is a controller — its content lives in the
## LeftPage and RightPage Controls, not inside the tab node itself.
func _create_tab(tab: int) -> NotebookTab:
	var tab_node: NotebookTab = null
	match tab:
		NotebookTab.INVENTORY: tab_node = InventoryTab.new()
		NotebookTab.MAP:       tab_node = MapTab.new()
		NotebookTab.QUESTS:    tab_node = QuestsTab.new()
		NotebookTab.SETTINGS:  tab_node = SettingsTab.new()
		NotebookTab.SESSIONS:  tab_node = SessionsTab.new()
	if tab_node == null:
		return null
	# Add to the tree before returning so _ready() is called and internal
	# state (inventory sample data, quest log, etc.) is initialised.
	# https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-add-child
	tab_node.visible = false
	add_child(tab_node)
	return tab_node
