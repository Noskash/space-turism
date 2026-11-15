class_name UiFont
extends RefCounted
## In-game UI font: Share Tech Mono (SIL OFL, ui/fonts/OFL.txt) - a crisp terminal look.
## Gameplay scenes run in canvas_items stretch mode (PixelMode), so text is rasterised at the
## real screen resolution while the pixel art stays on the 480x270 grid.

const PATH := "res://ui/fonts/ShareTechMono-Regular.ttf"
## Default size in 480x270 units (x3 at 1440p, x4 at 4K... it stays sharp).
const SIZE := 8

static var _font: Font


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
	return font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## A Label already styled for the HUD.
static func label(text: String, size := SIZE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 2)
	return l
