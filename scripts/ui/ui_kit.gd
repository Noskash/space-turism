class_name UiKit
extends RefCounted
## Shared pixel-art UI kit (CLAUDE.md "UI kit"). Immediate-mode helpers: call them from a
## CanvasItem's _draw() with that CanvasItem as `ci`. Everything is in 480x270 units and snapped
## to whole pixels; no gradients, no blur - depth comes from a 1 px ink outline plus a bevel
## (light top/left, dark bottom/right), transparency from 1 px checker dithering.
##
##   panel()    raised block            frame()     big minigame frame (2 px outline, cut corners)
##   seg_bar()  segmented resource bar  keycap()    keyboard key label
##   chip()     small coloured block    icon()      16x16 / 8x8 icon from sprites/ui_icons
##   text*()    UiFont text, TEXT SIZE applied, optional ink outline
##   dither()   50% checker fill        stamp()     "DONE" rubber stamp
##
## `hud` holds the screen rects of the cruise HUD blocks (filled by the HUD every frame) so other
## overlays can sit next to them or keep out of them (station panels, event guide, tutorial).

# --- palette --------------------------------------------------------------------------------
const INK := Color("06070f")        # every outline
const PANEL := Color("171d35")      # block fill
const PANEL_DARK := Color("0d1124")
const WELL := Color("090c18")       # bar troughs, insets
const TEXT := Color("eef1fb")
const DIM := Color("8a93b0")
const FAINT := Color("4a5274")
const GOOD := Color("5cf07a")
const WARN := Color("ffc640")
const BAD := Color("ff5050")
const KEY_TOP := Color("dfe3ee")    # keycaps
const KEY_SIDE := Color("8a93aa")

## One colour per crew role (task rows, name tags, cursors, station rings).
const ROLE_COLORS := {
	"navigator": Color("4fd8ff"),
	"engineer": Color("ff9a3c"),
	"comms": Color("5cf07a"),
	"scientist": Color("b77bff"),
	"team": Color("d8f4ff"),
}
## Station role -> 8x8 icon.
const ROLE_ICONS := {
	"navigator": "nav", "engineer": "pwr", "comms": "com", "scientist": "sci", "team": "team",
}
## One colour per resource (= the role that owns it).
const RESOURCE_COLORS := {
	"power": Color("ff9a3c"), "fuel": Color("4fd8ff"), "data": Color("b77bff"),
	"hull": Color("d8dce8"), "o2": Color("8cf0ff"),
}

const ICON_DIR := "res://sprites/ui_icons/"

## Cruise HUD block rects in screen units: "resources", "progress", "alert", "tasks",
## "action", "you". Empty outside the cruise.
static var hud := {}
## Where the world (ship map) sits on screen: the cruise moves it down to leave a band for the top HUD.
## Screen point = world point + world_offset. Use world_rect() for highlights given in map coordinates.
static var world_offset := Vector2.ZERO
## Other overlays' rects that HUD pieces should stack under (e.g. "guide" = event checklist).
static var overlays := {}

static var _icons := {}
static var _checker: ImageTexture


static func role_color(role: String) -> Color:
	return ROLE_COLORS.get(role.split("+")[0], Color("e8e8e8"))


static func world_rect(r: Rect2) -> Rect2:
	return Rect2(r.position + world_offset, r.size)


static func hud_rect(key: String, fallback := Rect2()) -> Rect2:
	return hud.get(key, fallback)


## True if `r` (screen units) overlaps any HUD block.
static func hits_hud(r: Rect2) -> bool:
	for key: String in hud:
		if (hud[key] as Rect2).intersects(r):
			return true
	return false


# --- blocks ---------------------------------------------------------------------------------

## Raised block: 1 px ink outline with cut corners, fill, bevel. `accent` (if set) lights the
## top edge in a colour (role / alert).
static func panel(ci: CanvasItem, r: Rect2, fill := PANEL, accent := Color(0, 0, 0, 0)) -> void:
	r = _snap(r)
	if r.size.x < 4 or r.size.y < 4:
		return
	_outline(ci, r, INK)
	var inner := r.grow(-1)
	ci.draw_rect(inner, fill)
	var hi := accent if accent.a > 0.0 else fill.lightened(0.22)
	var lo := fill.darkened(0.5)
	ci.draw_rect(Rect2(inner.position, Vector2(inner.size.x, 1)), hi)
	ci.draw_rect(Rect2(inner.position + Vector2(0, 1), Vector2(1, inner.size.y - 1)), fill.lightened(0.12))
	ci.draw_rect(Rect2(inner.position.x, inner.end.y - 1, inner.size.x, 1), lo)
	ci.draw_rect(Rect2(inner.end.x - 1, inner.position.y + 1, 1, inner.size.y - 1), lo)


## Big frame for full-screen panels (minigames, dialogs): 2 px ink, 1 px accent ring,
## corners cut 2 px deep.
static func frame(ci: CanvasItem, r: Rect2, accent: Color, fill := PANEL_DARK) -> void:
	r = _snap(r)
	# 2 px ink with a 2-step corner cut.
	ci.draw_rect(Rect2(r.position.x + 2, r.position.y, r.size.x - 4, r.size.y), INK)
	ci.draw_rect(Rect2(r.position.x, r.position.y + 2, r.size.x, r.size.y - 4), INK)
	ci.draw_rect(Rect2(r.position.x + 1, r.position.y + 1, r.size.x - 2, r.size.y - 2), INK)
	var ring := r.grow(-2)
	_outline(ci, ring, accent)
	var inner := ring.grow(-1)
	ci.draw_rect(inner, fill)
	ci.draw_rect(Rect2(inner.position, Vector2(inner.size.x, 1)), fill.lightened(0.18))
	ci.draw_rect(Rect2(inner.position.x, inner.end.y - 1, inner.size.x, 1), fill.darkened(0.5))


## Small solid block with an ink outline.
static func chip(ci: CanvasItem, r: Rect2, color: Color) -> void:
	r = _snap(r)
	ci.draw_rect(r, INK)
	ci.draw_rect(r.grow(-1), color)
	if r.size.y >= 4:
		ci.draw_rect(Rect2(r.position + Vector2(1, 1), Vector2(r.size.x - 2, 1)), color.lightened(0.35))


## Segmented bar. `value` and `ghost` are 0..1; lit segments = round(value x segments).
## Segments between value and ghost use `ghost_color` (red "lost" on a drop, light on a gain).
## Returns nothing; size the rect with seg_bar_width().
static func seg_bar(ci: CanvasItem, r: Rect2, value: float, color: Color, segments := 10,
		ghost := -1.0, ghost_color := BAD, flash := false) -> void:
	r = _snap(r)
	ci.draw_rect(r, INK)
	var inner := r.grow(-1)
	ci.draw_rect(inner, WELL)
	var seg_w := floorf((inner.size.x - (segments - 1)) / segments)
	var lit := roundi(clampf(value, 0.0, 1.0) * segments)
	var ghost_lit := roundi(clampf(ghost, 0.0, 1.0) * segments) if ghost >= 0.0 else lit
	for i in segments:
		var s := Rect2(inner.position.x + i * (seg_w + 1), inner.position.y, seg_w, inner.size.y)
		var c := color
		if i >= lit:
			if i < ghost_lit:
				c = ghost_color
			else:
				ci.draw_rect(Rect2(s.position.x, s.end.y - 1, s.size.x, 1), FAINT.darkened(0.3))
				continue
		if flash:
			c = Color.WHITE
		ci.draw_rect(s, c)
		ci.draw_rect(Rect2(s.position, Vector2(s.size.x, 1)), c.lightened(0.45))
		if s.size.y > 2:
			ci.draw_rect(Rect2(s.position.x, s.end.y - 1, s.size.x, 1), c.darkened(0.35))


## Width of a seg_bar with `segments` segments of `seg_w` px (incl. the 1 px outline).
static func seg_bar_width(segments: int, seg_w: int) -> int:
	return segments * seg_w + (segments - 1) + 2


## Keyboard key cap with a label (e.g. "SPACE", "Q", "TAB"). `pos` = top-left.
## Returns the cap's rect.
static func keycap(ci: CanvasItem, pos: Vector2, label: String, size := 7, enabled := true) -> Rect2:
	var w := maxf(text_w(label, size) + 4, 8)
	var h := float(UiFont.px(size)) + 3
	var r := _snap(Rect2(pos, Vector2(w, h)))
	var top := KEY_TOP if enabled else FAINT
	var side := KEY_SIDE if enabled else FAINT.darkened(0.4)
	_outline(ci, r, INK)
	var inner := r.grow(-1)
	ci.draw_rect(inner, side)
	ci.draw_rect(Rect2(inner.position, inner.size - Vector2(0, 2)), top)
	text_c(ci, r.get_center().x, r.position.y + h - 3, label, size, INK, 0)
	return r


static func keycap_size(label: String, size := 7) -> Vector2:
	return Vector2(roundf(maxf(text_w(label, size) + 4, 8)), roundf(UiFont.px(size) + 3))


## 50% checker fill (pixel-art transparency). The CanvasItem needs texture_repeat enabled
## (UiKit.setup_canvas does that).
static func dither(ci: CanvasItem, r: Rect2, color: Color) -> void:
	r = _snap(r)
	if _checker == null:
		var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		img.set_pixel(0, 0, Color.WHITE)
		img.set_pixel(1, 1, Color.WHITE)
		_checker = ImageTexture.create_from_image(img)
	ci.draw_texture_rect(_checker, r, true, color)


## Nearest filtering + repeat for a canvas that uses the kit.
static func setup_canvas(ci: CanvasItem) -> void:
	ci.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ci.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED


# --- icons ----------------------------------------------------------------------------------

static func icon_tex(icon_name: String) -> Texture2D:
	if not _icons.has(icon_name):
		var path := ICON_DIR + icon_name + ".png"
		_icons[icon_name] = load(path) if ResourceLoader.exists(path) else null
	return _icons[icon_name]


## Draws an icon at `pos` (top-left), integer `scale`, tinted by `mod` (icons are drawn in white
## and greys with an ink outline, so tinting keeps the outline dark).
static func icon(ci: CanvasItem, icon_name: String, pos: Vector2, scale := 1, mod := Color.WHITE) -> Vector2:
	var tex := icon_tex(icon_name)
	if tex == null:
		var s := Vector2(8, 8) * scale
		ci.draw_rect(Rect2(pos.round(), s), mod)
		return s
	var size := tex.get_size() * scale
	ci.draw_texture_rect(tex, Rect2(pos.round(), size), false, mod)
	return size


# --- text -----------------------------------------------------------------------------------

## Text with the baseline at pos.y. `size` is a base size (TEXT SIZE applies);
## `outline` = ink outline width in screen pixels of the 480 grid (0 = none).
static func text(ci: CanvasItem, pos: Vector2, s: String, size := 8, col := TEXT, outline := 2) -> void:
	var f := UiFont.font()
	var px := UiFont.px(size)
	var p := pos.round()
	if outline > 0:
		ci.draw_string_outline(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, outline, Color(INK, col.a))
	ci.draw_string(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)


static func text_c(ci: CanvasItem, center_x: float, baseline: float, s: String, size := 8, col := TEXT, outline := 2) -> void:
	text(ci, Vector2(roundf(center_x - text_w(s, size) / 2.0), baseline), s, size, col, outline)


static func text_r(ci: CanvasItem, right_x: float, baseline: float, s: String, size := 8, col := TEXT, outline := 2) -> void:
	text(ci, Vector2(roundf(right_x - text_w(s, size)), baseline), s, size, col, outline)


static func text_w(s: String, size := 8) -> float:
	return UiFont.width(s, size)


## Cap height-ish: how far above the baseline the text reaches.
static func ascent(size := 8) -> float:
	return UiFont.font().get_ascent(UiFont.px(size)) * 0.78


static func line_h(size := 8) -> float:
	return roundf(UiFont.px(size) * 1.15)


## Cuts `s` with ".." so it fits `max_w`.
static func fit(s: String, size: int, max_w: float) -> String:
	if text_w(s, size) <= max_w:
		return s
	while s.length() > 1 and text_w(s + "..", size) > max_w:
		s = s.substr(0, s.length() - 1)
	return s.strip_edges() + ".."


## Word wrap at a base size.
static func wrap(s: String, size: int, max_w: float) -> PackedStringArray:
	var lines := PackedStringArray()
	for para in s.split("\n"):
		var line := ""
		for word in para.split(" ", false):
			var test := word if line == "" else line + " " + word
			if text_w(test, size) > max_w and line != "":
				lines.append(line)
				line = word
			else:
				line = test
		lines.append(line)
	return lines


## Readable text colour on top of a fill.
static func ink_on(fill: Color) -> Color:
	return INK if fill.get_luminance() > 0.55 else TEXT


# --- effects --------------------------------------------------------------------------------

## Rubber stamp ("DONE", "FAILED"): slams in at `k` 1 -> 0 (scale 2.5x -> 1x), then sits.
## `k` = 1 - age / slam time, clamped (0 once it has landed).
static func stamp(ci: CanvasItem, center: Vector2, label: String, color: Color, k := 0.0, size := 20) -> void:
	var scale := 1.0 + 1.5 * k * k
	var w := text_w(label, size) + 14
	var h := UiFont.px(size) + 8.0
	ci.draw_set_transform(center.round(), 0.0, Vector2(scale, scale))
	var r := Rect2(Vector2(-w, -h) / 2.0, Vector2(w, h)).abs()
	r = Rect2(r.position.round(), r.size.round())
	var a := clampf(1.4 - k, 0.0, 1.0)
	ci.draw_rect(r, Color(INK, 0.85 * a))
	_outline(ci, r.grow(-1), Color(color, a))
	_outline(ci, r.grow(-3), Color(color, a))
	text_c(ci, 0, r.position.y + h - 5, label, size, Color(color, a), 3)
	ci.draw_set_transform(Vector2.ZERO)


# --- internals ------------------------------------------------------------------------------

## 1 px outline with the four corner pixels left out (pixel-rounded).
static func _outline(ci: CanvasItem, r: Rect2, c: Color) -> void:
	ci.draw_rect(Rect2(r.position.x + 1, r.position.y, r.size.x - 2, 1), c)
	ci.draw_rect(Rect2(r.position.x + 1, r.end.y - 1, r.size.x - 2, 1), c)
	ci.draw_rect(Rect2(r.position.x, r.position.y + 1, 1, r.size.y - 2), c)
	ci.draw_rect(Rect2(r.end.x - 1, r.position.y + 1, 1, r.size.y - 2), c)


static func _snap(r: Rect2) -> Rect2:
	return Rect2(r.position.round(), r.size.round())
