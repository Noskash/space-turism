class_name UiFont
extends RefCounted
## In-game UI font: Share Tech Mono (SIL OFL, ui/fonts/OFL.txt) - a crisp terminal look.
## Gameplay scenes run in canvas_items stretch mode (PixelMode), so text is rasterised at the
## real screen resolution while the pixel art stays on the 480x270 grid.

const PATH := "res://ui/fonts/ShareTechMono-Regular.ttf"
## Default size in 480x270 units (x3 at 1440p, x4 at 4K... it stays sharp).
const SIZE := 8

## TEXT SIZE setting (ESC menu, user://settings.cfg [ui] text): every draw_string size goes through
## px(), width() measures with the same scale, so centring / wrapping / boxes sized from width() follow.
const SCALES := [1.0, 1.15, 1.3]
const SCALE_NAMES := ["NORMAL", "LARGE", "HUGE"]
const SETTINGS := "user://settings.cfg"
const LABEL_GROUP := "ui_font_label"

static var scale := -1.0     # loaded lazily from the settings
static var _font: Font


## A font size in 480x270 units, scaled by the TEXT SIZE setting.
static func px(size: int) -> int:
	if scale < 0.0:
		var cfg := ConfigFile.new()
		cfg.load(SETTINGS)
		scale = SCALES[clampi(int(cfg.get_value("ui", "text", 0)), 0, SCALES.size() - 1)]
	return roundi(size * scale)


static func level() -> int:
	px(1)
	return maxi(SCALES.find(scale), 0)


## Changes + saves the setting; labels made by label() are resized on the spot.
static func set_level(index: int, tree: SceneTree) -> void:
	index = wrapi(index, 0, SCALES.size())
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("ui", "text", index)
	cfg.save(SETTINGS)
	scale = SCALES[index]
	for l in tree.get_nodes_in_group(LABEL_GROUP):
		(l as Label).add_theme_font_size_override("font_size", px(int(l.get_meta("base_size", SIZE))))


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


static func width(text: String, size := SIZE) -> float:
	return font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px(size)).x


## A Label already styled for the HUD.
static func label(text: String, size := SIZE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font())
	l.add_theme_font_size_override("font_size", px(size))
	l.set_meta("base_size", size)
	l.add_to_group(LABEL_GROUP)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 2)
	return l
