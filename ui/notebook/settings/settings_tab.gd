class_name SettingsTab
extends NotebookTab
## The Settings tab of the in-game notebook.
##
## Phase 1 exposes audio volume sliders (left page) and a window scale
## option button (right page). Settings are sourced from SaveManager.settings —
## the shared, per-device GameSettings instance loaded by SaveManager.load_settings()
## at launch (design §11 Step 4) — rather than a fresh GameSettings per session.
## Slider and option-button edits mutate that shared instance directly (by
## reference, no duplicate()), so SaveManager.save_settings() on notebook close
## persists exactly what the player sees.
##
## The two populate methods instantiate settings_tab.tscn, extract the
## LeftPage or RightPage VBoxContainer from that scene, and reparent it
## into the page Control provided by notebook.gd. Static layout (labels,
## sliders, buttons) lives in the .tscn; GDScript is left with data
## binding, signal wiring, and initial-value logic only.
##
## Design doc: docs/features/game-data/design.md §11 Step 4 (per-device settings)
## Design doc: docs/features/notebook/design.md §3.2 (Settings)
## Refactor:   docs/refactors/notebook-ui-scene-migration.md


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# The scene that holds the complete static layout for this tab.
# Loaded once at class parse time; Godot caches PackedScene objects so
# multiple instantiate() calls are cheap.
# https://docs.godotengine.org/en/stable/classes/class_packedscene.html
const TAB_SCENE: PackedScene = preload("res://ui/notebook/settings/settings_tab.tscn")

# Integer multipliers offered in the window-scale OptionButton. The OptionButton
# index for a scale is `scale - 1` (1× → 0, 2× → 1, etc).
const WINDOW_SCALE_OPTIONS: Array[int] = [1, 2, 3, 4]


# ---------------------------------------------------------------------------
# Private vars — set during populate calls
# ---------------------------------------------------------------------------

# The shared, per-device settings instance — SaveManager.settings, by
# reference (not a duplicate). Assigned in _ready(). SaveManager.load_settings()
# (run at launch, see save_manager.gd._ready()) guarantees this is non-null and
# populated before any notebook tab can open.
var _settings: GameSettings

# Slider refs kept so the reset buttons can programmatically restore defaults
# without rebuilding the entire UI. All four are null until populate_left() runs.
var _master_slider: HSlider
var _music_slider: HSlider
var _sfx_slider: HSlider
var _text_speed_slider: HSlider

# OptionButton ref so _on_reset_right_pressed() can call select() on it.
# Null until populate_right() runs.
var _window_scale_option: OptionButton

# Cached page VBoxContainers extracted from a single TAB_SCENE instance.
# Populated on the first populate_left() or populate_right() call and reused
# for the second call, so we only pay the instantiation cost once per tab
# controller lifetime.
var _left_page: VBoxContainer
var _right_page: VBoxContainer


# ---------------------------------------------------------------------------
# Built-in overrides
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Source _settings from the shared SaveManager.settings instance (by
	# reference, not GameSettings.new()) so slider/option edits mutate the
	# same per-device settings object that SaveManager.save_settings() writes
	# to user://settings.tres on notebook close. SaveManager.load_settings()
	# runs at launch (see save_manager.gd._ready()), so SaveManager.settings is
	# already populated by the time this tab is created.
	_settings = SaveManager.settings


# ---------------------------------------------------------------------------
# Public methods (override NotebookTab)
# ---------------------------------------------------------------------------

## Populate the left page with audio and gameplay sliders.
## Instantiates settings_tab.tscn, extracts the LeftPage VBoxContainer,
## reparents it into parent, then resolves named-node references and
## wires signals.
##
## @param parent - the Control node that will hold left-page content.
##                 Per NotebookTab contract: guard against null.
func populate_left(parent: Control) -> void:
	if parent == null:
		return

	_ensure_pages_built()

	# Add the LeftPage VBox into the real page Control provided by notebook.gd.
	# _ensure_pages_built() already detached it from the temporary scene instance.
	# Guard against re-entry: if _left_page already has a parent (because
	# populate_left() was called twice on the same SettingsTab instance), detach
	# it first so add_child does not fail.
	# https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-add-child
	if _left_page.get_parent() != null:
		_left_page.get_parent().remove_child(_left_page)
	parent.add_child(_left_page)

	# Anchor the VBox to fill the parent page so children (sliders) get a real
	# width to expand into; without this the VBox shrinks to its minimum size
	# and HSliders overflow horizontally. Negative right/bottom offsets pull
	# the edges inward when anchors are 1.0, giving a 10px margin on all sides.
	# https://docs.godotengine.org/en/stable/classes/class_control.html#class-control-method-set-anchors-and-offsets-preset
	_left_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_left_page.offset_left = 10
	_left_page.offset_top = 10
	_left_page.offset_right = -10
	_left_page.offset_bottom = -10

	# Resolve named-node references. Nodes live inside _left_page, so the path
	# is relative to it. Using get_node() rather than @onready because the tree
	# shape is established here (inside populate_left) rather than at _ready time.
	_master_slider = _left_page.get_node("MasterSlider") as HSlider
	_music_slider = _left_page.get_node("MusicSlider") as HSlider
	_sfx_slider = _left_page.get_node("SfxSlider") as HSlider
	_text_speed_slider = _left_page.get_node("TextSpeedSlider") as HSlider

	# Set initial values from _settings (created fresh in _ready, or pre-set
	# by a caller before populate_left). The sliders' max_value/step are already
	# set as editor properties in settings_tab.tscn.
	_master_slider.value = _settings.master_volume * 100.0
	_music_slider.value = _settings.music_volume * 100.0
	_sfx_slider.value = _settings.sfx_volume * 100.0
	_text_speed_slider.value = _settings.text_speed * 100.0

	# Wire signals. value_changed fires whenever the slider moves, including
	# programmatic changes; _on_*_changed applies the setting immediately so
	# there is no separate "Apply" step.
	# Guard each connection with is_connected() so calling populate_left() a
	# second time on the same SettingsTab instance does not register duplicates.
	# https://docs.godotengine.org/en/stable/classes/class_range.html#signal-value-changed
	if not _master_slider.value_changed.is_connected(_on_master_volume_changed):
		_master_slider.value_changed.connect(_on_master_volume_changed)
	if not _music_slider.value_changed.is_connected(_on_music_volume_changed):
		_music_slider.value_changed.connect(_on_music_volume_changed)
	if not _sfx_slider.value_changed.is_connected(_on_sfx_volume_changed):
		_sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	if not _text_speed_slider.value_changed.is_connected(_on_text_speed_changed):
		_text_speed_slider.value_changed.connect(_on_text_speed_changed)

	# Wire the left reset button. The button is named in the scene so we can
	# find it reliably without walking the tree by index.
	var reset_btn: Button = _left_page.get_node("ResetLeftButton") as Button
	if not reset_btn.pressed.is_connected(_on_reset_left_pressed):
		reset_btn.pressed.connect(_on_reset_left_pressed)


## Populate the right page with the display / window scale option button.
## Extracts the RightPage VBoxContainer from settings_tab.tscn, reparents
## it into parent, adds the window-scale items, and wires signals.
##
## @param parent - the Control node that will hold right-page content.
##                 Per NotebookTab contract: guard against null.
func populate_right(parent: Control) -> void:
	if parent == null:
		return

	_ensure_pages_built()

	# Add the RightPage VBox into the notebook's right page Control.
	# _ensure_pages_built() already detached it from the temporary scene instance.
	# Same anchoring + margin scheme as populate_left() so the right-page VBox
	# fills its parent and keeps a consistent 10px breathing room from the seam
	# and outer notebook edge. See populate_left() for the rationale.
	# Guard against re-entry: if _right_page already has a parent, detach it first.
	# https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-remove-child
	if _right_page.get_parent() != null:
		_right_page.get_parent().remove_child(_right_page)
	parent.add_child(_right_page)
	_right_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_right_page.offset_left = 10
	_right_page.offset_top = 10
	_right_page.offset_right = -10
	_right_page.offset_bottom = -10

	# Resolve the OptionButton and reset button references.
	_window_scale_option = _right_page.get_node("WindowScaleOption") as OptionButton

	# Populate the window-scale OptionButton items at runtime. Item labels are
	# derived from the project viewport size so changing viewport_width/height
	# in project.godot keeps the displayed resolutions accurate without code edits.
	# Items are added here (not in the .tscn) because their labels include live
	# project settings values that cannot be baked into a static scene file.
	# Guard with get_item_count() so re-entrant calls do not double the list.
	# https://docs.godotengine.org/en/stable/classes/class_optionbutton.html
	if _window_scale_option.get_item_count() == 0:
		for scale: int in WINDOW_SCALE_OPTIONS:
			var size: Vector2i = _scaled_window_size(scale)
			_window_scale_option.add_item("%d× (%d×%d)" % [scale, size.x, size.y])

	# _settings.window_scale is 1–4; OptionButton indices are 0–3, so subtract 1.
	_window_scale_option.selected = _settings.window_scale - 1

	# item_selected fires only on player-driven changes (not programmatic select()),
	# which prevents an infinite loop when the reset button calls select() below.
	# Guard with is_connected() for the same re-entry reason as populate_left().
	# https://docs.godotengine.org/en/stable/classes/class_optionbutton.html#signal-item-selected
	if not _window_scale_option.item_selected.is_connected(_on_window_scale_changed):
		_window_scale_option.item_selected.connect(_on_window_scale_changed)

	var reset_btn: Button = _right_page.get_node("ResetRightButton") as Button
	if not reset_btn.pressed.is_connected(_on_reset_right_pressed):
		reset_btn.pressed.connect(_on_reset_right_pressed)


# ---------------------------------------------------------------------------
# Private methods — signal handlers
# ---------------------------------------------------------------------------

## Apply the new master volume to both _settings and the AudioServer.
## The slider uses a 0–100 range; the audio bus API expects a dB value.
## We store the 0.0–1.0 linear form in _settings for serialisation clarity.
##
## AudioServer.set_bus_volume_db docs:
## https://docs.godotengine.org/en/stable/classes/class_audioserver.html#class-audioserver-method-set-bus-volume-db
func _on_master_volume_changed(value: float) -> void:
	_settings.master_volume = value / 100.0
	# Bus index 0 is always the Master bus in Godot.
	# linear_to_db converts the 0.0–1.0 linear ratio to decibels.
	AudioServer.set_bus_volume_db(0, linear_to_db(_settings.master_volume))


## Apply the new music bus volume. Bus 1 is the Music bus by convention;
## we guard with get_bus_count() because Phase 1 may not have extra buses set up.
func _on_music_volume_changed(value: float) -> void:
	_settings.music_volume = value / 100.0
	if AudioServer.get_bus_count() > 1:
		AudioServer.set_bus_volume_db(1, linear_to_db(_settings.music_volume))


## Apply the new SFX bus volume. Bus 2 is the SFX bus by convention;
## guarded for the same reason as music.
func _on_sfx_volume_changed(value: float) -> void:
	_settings.sfx_volume = value / 100.0
	if AudioServer.get_bus_count() > 2:
		AudioServer.set_bus_volume_db(2, linear_to_db(_settings.sfx_volume))


## Apply the text speed multiplier. Slider range is 0–100; GameSettings stores
## 0.0–1.0 so dialogue systems can use it as a direct multiplier.
func _on_text_speed_changed(value: float) -> void:
	_settings.text_speed = value / 100.0


## Apply the new window scale. OptionButton indices are 0-based; scale is 1-based.
## DisplayServer.window_set_size immediately resizes the OS window.
##
## https://docs.godotengine.org/en/stable/classes/class_displayserver.html#class-displayserver-method-window-set-size
func _on_window_scale_changed(index: int) -> void:
	_settings.window_scale = index + 1
	DisplayServer.window_set_size(_scaled_window_size(_settings.window_scale))


## Reset all audio and gameplay settings to their default values and sync
## the slider widgets. Slider refs are guaranteed non-null by populate_left()
## having run — guards below are for symmetry with _on_reset_right_pressed().
func _on_reset_left_pressed() -> void:
	_settings.master_volume = 1.0
	_settings.music_volume = 1.0
	_settings.sfx_volume = 1.0
	_settings.text_speed = 1.0

	# Update sliders to reflect the reset values.
	# Setting .value triggers value_changed, so the AudioServer is updated too.
	if _master_slider != null:
		_master_slider.value = 100.0
	if _music_slider != null:
		_music_slider.value = 100.0
	if _sfx_slider != null:
		_sfx_slider.value = 100.0
	if _text_speed_slider != null:
		_text_speed_slider.value = 100.0


## Reset the window scale to the default (2×) and sync the OptionButton.
## item_selected is NOT emitted by select(), so we manually apply the scale.
func _on_reset_right_pressed() -> void:
	_settings.window_scale = 2
	if _window_scale_option != null:
		# Index = scale - 1. Assigning .selected directly (not calling select())
		# so that item_selected is not emitted — the resize is applied below instead.
		_window_scale_option.selected = _settings.window_scale - 1
	# Apply the change directly since item_selected won't fire for select().
	DisplayServer.window_set_size(_scaled_window_size(_settings.window_scale))


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Instantiate TAB_SCENE once per SettingsTab lifetime, extract both page
## VBoxContainers, and discard the scene shell. Called at the start of each
## populate_* method so either method can be called first without ordering
## constraints.
##
## We detach the pages from the scene instance rather than reparenting the
## whole instance, because the notebook only needs the page subtrees and the
## bare SettingsTab root Control from the .tscn has no purpose at runtime.
func _ensure_pages_built() -> void:
	if _left_page != null:
		# Already extracted on a previous call; nothing to do.
		return

	# Instantiate the scene to get a fully-formed node tree with editor
	# properties (labels, slider ranges, size flags) already applied.
	# https://docs.godotengine.org/en/stable/classes/class_packedscene.html#class-packedscene-method-instantiate
	var instance: Control = TAB_SCENE.instantiate() as Control

	# Grab references before detaching. The nodes are still children of instance
	# at this point, so get_node paths are relative to instance.
	_left_page = instance.get_node("LeftPage") as VBoxContainer
	_right_page = instance.get_node("RightPage") as VBoxContainer

	# Detach both pages so they survive when the shell is freed.
	# remove_child does not free the node — it simply unparents it.
	# https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-remove-child
	instance.remove_child(_left_page)
	instance.remove_child(_right_page)

	# Clear the owner on both detached pages. After remove_child the nodes still
	# retain their .owner (the TAB_SCENE root, "SettingsTab"). When add_child'd
	# into a different scene tree — the notebook page in production, or a bare
	# Control in tests — Godot emits an owner-inconsistency warning that GUT
	# counts as a test failure. Setting owner to null severs that link and
	# makes the nodes truly parentless/ownerless, ready for adoption by any tree.
	# https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-property-owner
	_left_page.owner = null
	_right_page.owner = null

	# The bare SettingsTab Control shell from the .tscn is no longer needed.
	# queue_free() defers the actual deletion to the end of the current frame,
	# which is safe because we have already removed all the nodes we care about.
	# https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-method-queue-free
	instance.queue_free()


## Return the window pixel size for the given integer scale factor, derived
## from the project's base viewport dimensions. project.godot is the single
## source of truth so the labels and resize math stay in sync when the
## viewport size changes.
## https://docs.godotengine.org/en/stable/classes/class_projectsettings.html#class-projectsettings-method-get-setting
func _scaled_window_size(scale: int) -> Vector2i:
	var width: int = ProjectSettings.get_setting(
			"display/window/size/viewport_width", 640)
	var height: int = ProjectSettings.get_setting(
			"display/window/size/viewport_height", 360)
	return Vector2i(width * scale, height * scale)
