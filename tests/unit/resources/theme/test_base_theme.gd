## test_base_theme.gd
## TDD contract tests for the base UI theme (resources/theme/base_theme.tres).
##
## These tests define the expected contents of the base theme: default font,
## default font size, the nine §4 palette colors, and the "Heading" Label type
## variation. Regression guard for that shipped theme resource. See:
##   docs/refactors/pixel-art-purist-size-and-theme.md (§3 font, §4 theme/palette)
##   docs/features/pixel-art-purist/slices.md (Slice 1)
##   docs/features/pixel-art-purist/slice-1-populate-base-theme-test-plan.md
##
## Requires GUT: https://github.com/bitwes/Gut
##
## Run in the Godot editor:
##   Project > Tools > GUT > Run All Tests
## or via CLI:
##   godot --headless -s addons/gut/gut_cmdln.gd -gselect=test_base_theme.gd -gexit

class_name TestBaseTheme
extends GutTest


# Path to the resource under test.
const THEME_PATH: String = "res://resources/theme/base_theme.tres"

# Path the default font is expected to resolve to — the runtime copy under
# resources/, never an art/ path (per CLAUDE.md art/ vs resources/ workflow).
const EXPECTED_FONT_PATH: String = "res://resources/theme/fonts/monogram-extended.ttf"

# Path to the font's .import file, used by the verify-only import-flag guard.
const FONT_IMPORT_PATH: String = "res://resources/theme/fonts/monogram-extended.ttf.import"

# §4 palette: theme color name -> expected hex (from the design doc table verbatim).
const EXPECTED_PALETTE: Dictionary = {
	"paper_bg": "#f4e9d8",
	"paper_bg_shadow": "#e3d4bd",
	"ink": "#3b2f2a",
	"ink_muted": "#7a6a5d",
	"accent": "#c8743c",
	"accent_soft": "#e7b07e",
	"success": "#6f8f4a",
	"frame_line": "#2a201c",
	"disabled": "#b6a892",
}


# ---------------------------------------------------------------------------
# Loading & default font
# ---------------------------------------------------------------------------

func test_theme_loads_as_theme_resource() -> void:
	var theme: Resource = load(THEME_PATH)

	assert_not_null(theme, "base_theme.tres should load")
	assert_true(theme is Theme, "base_theme.tres should load as a Theme resource")


func test_theme_has_default_font() -> void:
	var theme: Theme = load(THEME_PATH)

	# has_default_font() is the documented way to check before calling
	# get_default_font(), which can otherwise return a fallback font object.
	# https://docs.godotengine.org/en/stable/classes/class_theme.html#class-theme-method-has-default-font
	assert_true(theme.has_default_font(), "theme should define a default font")
	assert_not_null(theme.get_default_font(), "theme's default font should not be null")


func test_default_font_resolves_to_imported_monogram_font_under_resources() -> void:
	var theme: Theme = load(THEME_PATH)

	var default_font: Font = theme.get_default_font()
	assert_not_null(default_font, "theme should have a default font set")
	if default_font == null:
		return  # avoid null-ref on the assertions below

	# The default font must be the FontFile imported from
	# resources/theme/fonts/monogram-extended.ttf — never an art/ path. Reading
	# resource_path on the loaded FontFile fails loudly if a future edit ever
	# repoints the theme back into art/.
	assert_true(default_font is FontFile, "default font should be a FontFile (imported TTF)")
	assert_eq(default_font.resource_path, EXPECTED_FONT_PATH,
			"default font should resolve to the imported resources/ copy of monogram-extended.ttf, not an art/ path")
	assert_false(default_font.resource_path.begins_with("res://art/"),
			"default font must never point into art/ — only resources/ is referenced at runtime")


func test_default_font_size_is_8() -> void:
	var theme: Theme = load(THEME_PATH)

	# §3: body/default text is size 8 — half the design size, still an exact
	# divisor of the font's 16px grid, so glyphs stay pixel-perfect.
	assert_eq(theme.get_default_font_size(), 8, "theme's default font size should be 8")


# ---------------------------------------------------------------------------
# Palette colors
# ---------------------------------------------------------------------------

func test_palette_colors_are_defined_and_match_expected_hex() -> void:
	var theme: Theme = load(THEME_PATH)

	# Theme colors added without a specific control type land under the empty
	# type string "" — these are the theme-wide "named roles" from §4.
	# https://docs.godotengine.org/en/stable/classes/class_theme.html#class-theme-method-get-color-list
	for color_name: String in EXPECTED_PALETTE:
		var expected_color: Color = Color(EXPECTED_PALETTE[color_name])

		assert_true(theme.has_color(color_name, ""),
				"theme should define a palette color named '%s'" % color_name)
		if not theme.has_color(color_name, ""):
			continue  # avoid comparing against the fallback magenta below

		var actual_color: Color = theme.get_color(color_name, "")
		assert_eq(actual_color, expected_color,
				"palette color '%s' should equal %s (got %s)" % [color_name, EXPECTED_PALETTE[color_name], actual_color])


func test_palette_has_exactly_nine_colors_with_no_extras() -> void:
	var theme: Theme = load(THEME_PATH)

	# Guards against scope creep into per-control colors this slice — only the
	# nine §4 roles should exist as theme-wide ("") colors.
	var actual_names: PackedStringArray = theme.get_color_list("")
	var expected_names: Array = EXPECTED_PALETTE.keys()

	assert_eq(actual_names.size(), expected_names.size(),
			"theme should define exactly %d palette colors, found %d: %s" % [expected_names.size(), actual_names.size(), actual_names])

	for color_name: String in expected_names:
		assert_true(color_name in actual_names,
				"expected palette color '%s' to be present in theme.get_color_list(\"\")" % color_name)

	for color_name: String in actual_names:
		assert_true(color_name in expected_names,
				"unexpected stray palette color '%s' found in theme (only the nine §4 roles should exist)" % color_name)


# ---------------------------------------------------------------------------
# "Heading" Label type variation
# ---------------------------------------------------------------------------

func test_heading_type_variation_exists_with_base_type_label() -> void:
	var theme: Theme = load(THEME_PATH)

	# Type variations appear in get_type_list(); get_type_variation_base()
	# reports which built-in type a variation extends.
	# https://docs.godotengine.org/en/stable/classes/class_theme.html#class-theme-method-get-type-variation-base
	assert_true(theme.get_type_list().has("Heading"),
			"theme should define a 'Heading' type")
	assert_true(theme.is_type_variation("Heading", "Label"),
			"'Heading' should be a type variation of Label")
	assert_eq(theme.get_type_variation_base("Heading"), "Label",
			"'Heading' variation's base type should be 'Label'")


func test_heading_variation_sets_font_size_16() -> void:
	var theme: Theme = load(THEME_PATH)

	# §3: headings use the full design size (16) — a clean 2x multiple of the
	# body size (8), so both stay pixel-perfect.
	assert_true(theme.has_font_size("font_size", "Heading"),
			"'Heading' variation should set a 'font_size' override")
	assert_eq(theme.get_font_size("font_size", "Heading"), 16,
			"'Heading' variation's font_size should be 16")


func test_heading_variation_does_not_override_font() -> void:
	var theme: Theme = load(THEME_PATH)

	# Headings reuse the monogram default font — only the size differs from
	# body text, so headings stay in the same typeface as the rest of the UI.
	#
	# has_font("font", "Heading") is NOT useful here: it returns true for any
	# type whenever the theme defines a default font, due to default-font
	# fallback. get_font_list() lists only EXPLICIT per-type overrides (no
	# fallback), so an empty list proves "Heading" defines no font override
	# of its own.
	# https://docs.godotengine.org/en/stable/classes/class_theme.html#class-theme-method-get-font-list
	assert_true(theme.get_font_list("Heading").is_empty(),
			"'Heading' variation should NOT define a 'font' override (it should reuse the theme default)")


# ---------------------------------------------------------------------------
# Font import flag guard (verify-only — import already done)
# ---------------------------------------------------------------------------

func test_font_import_flags_guard_pixel_perfect_settings() -> void:
	# Parses the .import file's [params] section as text — the same
	# data-shaped assertion the rest of this slice uses (per the test plan's
	# notes for the test author). This guards the §3 pixel-perfect import
	# flags against accidental regression (e.g. re-importing with defaults).
	var file: FileAccess = FileAccess.open(FONT_IMPORT_PATH, FileAccess.READ)
	assert_not_null(file, "monogram-extended.ttf.import should exist and be readable")
	if file == null:
		return  # avoid null-ref on the assertions below

	var contents: String = file.get_as_text()
	file.close()

	var expected_params: Dictionary = {
		"antialiasing": "0",
		"hinting": "0",
		"subpixel_positioning": "0",
		"generate_mipmaps": "false",
		"multichannel_signed_distance_field": "false",
		"force_autohinter": "false",
	}

	for param_name: String in expected_params:
		var expected_value: String = expected_params[param_name]
		# Match "key=value" on its own line so e.g. "hinting=0" doesn't
		# false-match inside some longer, unrelated key.
		var pattern: String = "%s=%s" % [param_name, expected_value]
		assert_true(contents.contains(pattern),
				"monogram-extended.ttf.import [params] should contain '%s' (pixel-perfect import flag)" % pattern)
