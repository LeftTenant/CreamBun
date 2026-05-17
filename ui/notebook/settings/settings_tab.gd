class_name SettingsTab
extends NotebookTab
## The Settings tab of the in-game notebook.
##
## Phase 1 exposes audio volume sliders (left page) and a window scale
## option button (right page). Settings are held in a fresh GameSettings
## resource each session; Phase 2 will load persisted settings from disk
## via SaveManager before populating the UI.
##
## The two populate methods work by building a VBoxContainer and appending
## it to the provided parent Control. This keeps page layout concerns inside
## notebook.gd while letting each tab decide its own internal structure.
##
## Design doc: docs/features/notebook/design.md §3.2 (Settings)


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Integer multipliers offered in the window-scale OptionButton. The OptionButton
# index for a scale is `scale - 1` (1× → 0, 2× → 1, etc).
const _WINDOW_SCALE_OPTIONS: Array[int] = [1, 2, 3, 4]


# ---------------------------------------------------------------------------
# Private vars — set in _ready() or during populate calls
# ---------------------------------------------------------------------------

# Fresh defaults every session. Phase 2 will replace this with
# SaveManager.load_settings() so values persist across launches.
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


# ---------------------------------------------------------------------------
# Built-in overrides
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Always start from defaults in Phase 1. This gives a predictable baseline
	# and avoids showing stale values if the node is instantiated multiple times.
	_settings = GameSettings.new()


# ---------------------------------------------------------------------------
# Public methods (override NotebookTab)
# ---------------------------------------------------------------------------

## Populate the left page with audio and gameplay sliders.
## Creates a VBoxContainer as the layout host and adds it to parent, then
## appends labelled sliders and a reset button inside it.
##
## @param parent - the Control node that will hold left-page content.
##                 Per NotebookTab contract: guard against null.
func populate_left(parent: Control) -> void:
	if parent == null:
		return

	# VBoxContainer stacks children vertically with automatic spacing.
	# https://docs.godotengine.org/en/stable/classes/class_vboxcontainer.html
	var vbox: VBoxContainer = VBoxContainer.new()
	parent.add_child(vbox)

	# --- Audio section ---
	var audio_label: Label = Label.new()
	audio_label.text = "Audio"
	# Category headers are decorative; they should not receive keyboard focus
	# so the player's Tab key skips straight to the first interactive control.
	# https://docs.godotengine.org/en/stable/classes/class_control.html#enum-control-focusmode
	audio_label.focus_mode = Control.FOCUS_NONE
	vbox.add_child(audio_label)

	_master_slider = _make_volume_slider(
			"Master Volume", _settings.master_volume, vbox)
	# value_changed fires whenever the slider moves, including programmatic
	# changes. We use it to apply the setting immediately (no Apply button).
	# https://docs.godotengine.org/en/stable/classes/class_range.html#signal-value-changed
	_master_slider.value_changed.connect(_on_master_volume_changed)

	_music_slider = _make_volume_slider(
			"Music Volume", _settings.music_volume, vbox)
	_music_slider.value_changed.connect(_on_music_volume_changed)

	_sfx_slider = _make_volume_slider(
			"SFX Volume", _settings.sfx_volume, vbox)
	_sfx_slider.value_changed.connect(_on_sfx_volume_changed)

	# --- Gameplay section ---
	var gameplay_label: Label = Label.new()
	gameplay_label.text = "Gameplay"
	gameplay_label.focus_mode = Control.FOCUS_NONE
	vbox.add_child(gameplay_label)

	_text_speed_slider = _make_slider(
			"Text Speed", 0.0, 200.0, _settings.text_speed * 100.0, vbox)
	_text_speed_slider.value_changed.connect(_on_text_speed_changed)

	# --- Reset button ---
	var reset_btn: Button = Button.new()
	reset_btn.text = "Reset Audio & Gameplay to Defaults"
	vbox.add_child(reset_btn)
	reset_btn.pressed.connect(_on_reset_left_pressed)


## Populate the right page with the display / window scale option button.
## Creates a VBoxContainer and adds the scale selector and a reset button.
##
## @param parent - the Control node that will hold right-page content.
##                 Per NotebookTab contract: guard against null.
func populate_right(parent: Control) -> void:
	if parent == null:
		return

	var vbox: VBoxContainer = VBoxContainer.new()
	parent.add_child(vbox)

	# --- Display section ---
	var display_label: Label = Label.new()
	display_label.text = "Display"
	display_label.focus_mode = Control.FOCUS_NONE
	vbox.add_child(display_label)

	_window_scale_option = OptionButton.new()
	# Labels are generated from the project's base viewport size so changing
	# `display/window/size/viewport_*` in project.godot keeps the displayed
	# resolutions accurate without code edits.
	# https://docs.godotengine.org/en/stable/classes/class_optionbutton.html
	for scale: int in _WINDOW_SCALE_OPTIONS:
		var size: Vector2i = _scaled_window_size(scale)
		_window_scale_option.add_item("%d× (%d×%d)" % [scale, size.x, size.y])
	# _settings.window_scale is 1–4; OptionButton indices are 0–3, so subtract 1.
	_window_scale_option.selected = _settings.window_scale - 1
	vbox.add_child(_window_scale_option)
	# item_selected fires only on player-driven changes (not programmatic select()),
	# which prevents an infinite loop when the reset button calls select() below.
	# https://docs.godotengine.org/en/stable/classes/class_optionbutton.html#signal-item-selected
	_window_scale_option.item_selected.connect(_on_window_scale_changed)

	# --- Reset button ---
	var reset_btn: Button = Button.new()
	reset_btn.text = "Reset Display to Defaults"
	vbox.add_child(reset_btn)
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


## Apply the text speed multiplier. Slider range is 0–200; GameSettings stores
## 0.0–2.0 so dialogue systems can use it as a direct multiplier.
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
		# Index = scale - 1.
		_window_scale_option.selected = _settings.window_scale - 1
	# Apply the change directly since item_selected won't fire for select().
	DisplayServer.window_set_size(_scaled_window_size(_settings.window_scale))


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Build a labelled HSlider for a volume control (range 0–100) and add both
## the label and the slider to vbox. Returns the slider so the caller can
## store a reference and connect signals.
##
## @param label_text - text shown above the slider
## @param current_volume - the 0.0–1.0 GameSettings value; multiplied by 100 for the slider
## @param vbox - the VBoxContainer to append the new nodes to
func _make_volume_slider(label_text: String, current_volume: float,
		vbox: VBoxContainer) -> HSlider:
	return _make_slider(label_text, 0.0, 100.0, current_volume * 100.0, vbox)


## Build a labelled HSlider with arbitrary range and add both to vbox.
## Extracted to avoid duplicating slider construction code for the text-speed
## slider, which uses a different range (0–200).
##
## @param label_text    - text shown above the slider
## @param min_val       - slider minimum value
## @param max_val       - slider maximum value
## @param current_val   - the initial slider value
## @param vbox          - the VBoxContainer to append the new nodes to
func _make_slider(label_text: String, min_val: float, max_val: float,
		current_val: float, vbox: VBoxContainer) -> HSlider:
	var label: Label = Label.new()
	label.text = label_text
	label.focus_mode = Control.FOCUS_NONE
	vbox.add_child(label)

	var slider: HSlider = HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.value = current_val
	# step = 1 gives integer tick marks and prevents floating-point noise from
	# appearing in the value_changed callback.
	slider.step = 1.0
	vbox.add_child(slider)

	return slider


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
