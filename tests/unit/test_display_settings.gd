## test_display_settings.gd
## TDD contract tests for the [display] and [rendering] blocks in project.godot.
##
## Slice 3 established the 320×180 viewport dimensions and the Nearest-filter
## setting. Slice 4 replaces the three guard-rail assertions (which expected
## Slice 4 keys to be absent) with the actual target-state assertions:
##   - stretch/mode = "canvas_items"
##   - stretch/aspect = "keep"   (engine default — asserted via ProjectSettings, not file text)
##   - stretch/scale_mode = "integer"
##   - rendering/2d/snap/snap_2d_transforms_to_pixel = true   ([rendering] section)
##   - rendering/2d/snap/snap_2d_vertices_to_pixel = true     ([rendering] section)
##   - allow_hidpi = false   (non-default — persists in file; keeps window sizes in logical points)
##
## Regression guard for those five shipped project.godot values.
##
## Design reference:
##   docs/refactors/pixel-art-purist-size-and-theme.md §2 and §7 Step 5
##   docs/features/pixel-art-purist/slice-4-pixel-perfect-stretch-snap-test-plan.md
##
## Requires GUT: https://github.com/bitwes/Gut
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd -gselect=test_display_settings.gd -gexit

class_name TestDisplaySettings
extends GutTest


# Path to the project configuration file — parsed as raw text because the
# unit tests must verify the on-disk values, not Godot's in-memory cache.
# FileAccess.open() on a res:// path reads the actual file from disk.
# https://docs.godotengine.org/en/stable/classes/class_fileaccess.html
const PROJECT_GODOT_PATH: String = "res://project.godot"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Return the full text of project.godot, or fail the test and return "".
func _read_project_godot() -> String:
	var file: FileAccess = FileAccess.open(PROJECT_GODOT_PATH, FileAccess.READ)
	assert_not_null(file, "project.godot should exist and be readable at res://project.godot")
	if file == null:
		return ""
	var contents: String = file.get_as_text()
	file.close()
	return contents


## Assert that a key=value pair appears anywhere in project.godot.
##
## The name "_assert_project_key" reflects that this helper is used for keys
## across all sections of project.godot — not just [display] — including the
## [rendering] snap and filter keys added in Slice 4.
##
## We match the literal string "key=value" because project.godot stores
## integers bare (no quotes) and strings quoted, e.g.:
##   window/size/viewport_width=320
##   window/stretch/mode="canvas_items"
## Checking for the exact token on its own line prevents false positives where
## a shorter key name is a prefix of a longer one.
func _assert_project_key(contents: String, key: String, value: String) -> void:
	var pattern: String = "%s=%s\n" % [key, value]
	assert_true(
		contents.contains(pattern),
		"project.godot should contain '%s'" % pattern
	)


# ---------------------------------------------------------------------------
# Slice 3 dimension checks (must remain passing, no changes)
# ---------------------------------------------------------------------------

func test_viewport_width_is_320() -> void:
	# Slice 3 halves the render canvas from 640 to 320 pixels wide. At 2× pixel
	# scale a 640-pixel launch window still fits exactly two viewport columns.
	var contents: String = _read_project_godot()
	if contents.is_empty():
		return
	_assert_project_key(contents, "window/size/viewport_width", "320")


func test_viewport_height_is_180() -> void:
	# Slice 3 halves the render canvas from 360 to 180 pixels tall. At 2× scale
	# a 360-pixel launch window fits exactly two viewport rows.
	var contents: String = _read_project_godot()
	if contents.is_empty():
		return
	_assert_project_key(contents, "window/size/viewport_height", "180")


func test_window_width_override_is_1280() -> void:
	# The launch window is 1280 pixels wide — exactly 4× the 320-pixel viewport,
	# giving a clean integer pixel-art scale at the default 4× window scale.
	# (Changed from 640/2× to 1280/4× as part of the window-scale rework that
	# raised the default from 2× to 4×.)
	var contents: String = _read_project_godot()
	if contents.is_empty():
		return
	_assert_project_key(contents, "window/size/window_width_override", "1280")


func test_window_height_override_is_720() -> void:
	# The launch window is 720 pixels tall — exactly 4× the 180-pixel viewport,
	# giving a clean integer pixel-art scale at the default 4× window scale.
	# (Changed from 360/2× to 720/4× as part of the window-scale rework that
	# raised the default from 2× to 4×.)
	var contents: String = _read_project_godot()
	if contents.is_empty():
		return
	_assert_project_key(contents, "window/size/window_height_override", "720")


# ---------------------------------------------------------------------------
# Slice 3 Nearest-filter check (must remain passing, no changes)
# ---------------------------------------------------------------------------

func test_default_texture_filter_is_nearest() -> void:
	# Nearest-neighbour filtering keeps pixel art crisp — no bilinear blur.
	# Value 0 = CanvasItem.TEXTURE_FILTER_NEAREST in Godot's project setting.
	# Set before Slice 1 and must remain untouched through all pixel-art-purist
	# slices.
	#
	# NOTE: project.godot stores this key in the [rendering] section using the
	# short form (without the "rendering/" prefix), so the literal text on disk
	# is:  textures/canvas_textures/default_texture_filter=0
	# The helper searches the full file text, so we match the short form.
	var contents: String = _read_project_godot()
	if contents.is_empty():
		return
	_assert_project_key(
		contents,
		"textures/canvas_textures/default_texture_filter",
		"0"
	)


# ---------------------------------------------------------------------------
# Slice 4: stretch mode — replaces test_stretch_mode_is_still_viewport()
# ---------------------------------------------------------------------------

func test_stretch_mode_is_canvas_items() -> void:
	# "canvas_items" mode renders UI at the physical window resolution using
	# the 320×180 viewport as a layout reference. This is why glyphs are sharp
	# at any window size — fonts rasterize at actual pixels, not at 320×180
	# then scaled up. Replaces the Slice 3 guard that asserted "viewport".
	#
	# Fails until project.godot [display] block has:
	#   window/stretch/mode="canvas_items"
	var contents: String = _read_project_godot()
	if contents.is_empty():
		return
	_assert_project_key(contents, "window/stretch/mode", "\"canvas_items\"")


# ---------------------------------------------------------------------------
# Slice 4: stretch aspect — replaces test_stretch_aspect_key_is_absent()
# ---------------------------------------------------------------------------

func test_stretch_aspect_is_keep() -> void:
	# "keep" aspect preserves the 16:9 ratio and letterboxes on non-16:9
	# displays. This pairs with "integer" scale mode to guarantee clean pixel
	# grid alignment. Replaces the Slice 3 guard that asserted this key was
	# absent (a deliberate slice-boundary guard now superseded).
	#
	# WHY ProjectSettings instead of file-text: "keep" is the engine default for
	# display/window/stretch/aspect. When Godot re-saves project.godot it strips
	# any key whose value matches the engine default, so the key is absent from
	# the file even though the setting is correctly "keep". Asserting the raw
	# file text would give a false negative. Instead we read the effective
	# runtime value — if the key is absent the engine returns the default ("keep")
	# and the assertion still passes.
	#
	# https://docs.godotengine.org/en/stable/classes/class_projectsettings.html#class-projectsettings-method-get-setting
	assert_eq(
		ProjectSettings.get_setting("display/window/stretch/aspect", "keep"),
		"keep",
		"stretch/aspect effective setting should be 'keep'"
	)


# ---------------------------------------------------------------------------
# Slice 4: scale mode — replaces test_stretch_scale_mode_key_is_absent()
# ---------------------------------------------------------------------------

func test_stretch_scale_mode_is_integer() -> void:
	# "integer" scale mode forces the engine to scale only at whole-number
	# multiples of the base viewport (1×, 2×, 3×, …). This eliminates
	# sub-pixel offsets that cause shimmer and color fringing on pixel art.
	# Replaces the Slice 3 guard that asserted this key was absent.
	#
	# Fails until project.godot [display] block has:
	#   window/stretch/scale_mode="integer"
	var contents: String = _read_project_godot()
	if contents.is_empty():
		return
	_assert_project_key(contents, "window/stretch/scale_mode", "\"integer\"")


# ---------------------------------------------------------------------------
# Slice 4: pixel snap flags — live in the [rendering] section of project.godot
# ---------------------------------------------------------------------------

func test_snap_2d_transforms_to_pixel_is_true() -> void:
	# Snapping 2D transforms to the nearest pixel prevents world-node positions
	# from landing on fractional coordinates, which is the primary cause of
	# sprite shimmer during camera movement. This key lives in the [rendering]
	# section of project.godot, not [display].
	#
	# Fails until project.godot [rendering] block has:
	#   rendering/2d/snap/snap_2d_transforms_to_pixel=true
	var contents: String = _read_project_godot()
	if contents.is_empty():
		return
	_assert_project_key(
		contents,
		"rendering/2d/snap/snap_2d_transforms_to_pixel",
		"true"
	)


func test_snap_2d_vertices_to_pixel_is_true() -> void:
	# Snapping 2D vertices to the nearest pixel eliminates sub-pixel vertex
	# drift when sprites are drawn, complementing the transform snap above.
	# Like the transform snap, this key lives in the [rendering] section of
	# project.godot, not [display].
	#
	# Fails until project.godot [rendering] block has:
	#   rendering/2d/snap/snap_2d_vertices_to_pixel=true
	var contents: String = _read_project_godot()
	if contents.is_empty():
		return
	_assert_project_key(
		contents,
		"rendering/2d/snap/snap_2d_vertices_to_pixel",
		"true"
	)


# ---------------------------------------------------------------------------
# HiDPI — keeps window sizes in logical points on macOS Retina/HiDPI displays
# ---------------------------------------------------------------------------

func test_allow_hidpi_is_false() -> void:
	# WHY this setting exists: on macOS in "scaled" display modes Godot cannot
	# reliably detect the display scale factor. When allow_hidpi=true (the
	# default) the OS may report a window in physical pixels, making a 1280-wide
	# logical window appear as a 2560-wide physical window — causing the
	# window-scale labels in Settings (2×/4×/6×/8×) to no longer match what the
	# player actually sees on screen. Setting allow_hidpi=false forces Godot to
	# measure all window sizes in logical points, so the labels match on every
	# macOS Retina configuration.
	#
	# "false" is the non-default value, so Godot keeps the key in project.godot
	# and the file-text assertion is correct here (unlike stretch/aspect which IS
	# the default and gets stripped). See test_stretch_aspect_is_keep() for why
	# we use ProjectSettings for that key instead.
	#
	# Fails until project.godot [display] block has:
	#   window/dpi/allow_hidpi=false
	var contents: String = _read_project_godot()
	if contents.is_empty():
		return
	_assert_project_key(contents, "window/dpi/allow_hidpi", "false")
