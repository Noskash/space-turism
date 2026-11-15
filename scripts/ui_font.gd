class_name UiFont
extends RefCounted
## In-game UI font: Share Tech Mono (SIL OFL, ui/fonts/OFL.txt) - a crisp terminal look.
## Gameplay scenes run in canvas_items stretch mode (PixelMode), so text is rasterised at the
## real screen resolution while the pixel art stays on the 480x270 grid.
##
## TEXT SIZE (ESC menu: NORMAL / LARGE / HUGE) scales every size that goes through px().
## Draw text with UiKit.text() (it calls px()), or pass sizes through UiFont.px() yourself.

const PATH := "res://ui/fonts/ShareTechMono-Regular.ttf"
## Default size in 480x270 units (x3 at 1440p, x4 at 4K... it stays sharp).
const SIZE := 8
const SETTINGS := "user://settings.cfg"
const SCALES := [1.0, 1.25, 1.5]
const SIZE_NAMES := ["NORMAL", "LARGE", "HUGE"]

static var _font: Font
static var _level := -1
## Highest TEXT SIZE level the current screen can fit (dense screens lower it, e.g. the designer
## caps at LARGE). Set it in _enter_tree, reset to 2 in _exit_tree.
static var max_level := 2
## Bumps every time the text size changes (for anything that caches sizes).
static var revision := 0


static func font() -> Font:
	if _font == null:
		var file: FontFile = load(PATH) if ResourceLoader.exists(PATH) else null
		if file:
			file.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
			file.hinting = TextServer.HINTING_NONE
			# Text is drawn at 480x270 units and scaled up, so glyph advances are fractional:
			# subpixel positioning keeps the monospace spacing even.
			file.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_ONE_QUARTER
		_font = file if file else ThemeDB.fallback_font
	return _font


## TEXT SIZE setting: 0 NORMAL, 1 LARGE, 2 HUGE (saved in user://settings.cfg).
static func text_size() -> int:
	if _level < 0:
		var cfg := ConfigFile.new()
		cfg.load(SETTINGS)
		_level = clampi(int(cfg.get_value("ui", "text_size", 0)), 0, SCALES.size() - 1)
	return _level


static func set_text_size(level: int) -> void:
	_level = clampi(level, 0, SCALES.size() - 1)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("ui", "text_size", _level)
	cfg.save(SETTINGS)
	revision += 1


## A base size (480x270 units) scaled by the TEXT SIZE setting.
static func px(size: int) -> int:
	return maxi(roundi(size * SCALES[mini(text_size(), max_level)]), 1)


## Width of `text` at an already scaled size (use UiKit.text_w for base sizes).
static func width(text: String, size := SIZE) -> float:
	return font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## A Label already styled for the HUD (size is a base size; TEXT SIZE applies).
static func label(text: String, size := SIZE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font())
	l.add_theme_font_size_override("font_size", px(size))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 2)
	return l
