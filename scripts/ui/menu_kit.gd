class_name MenuKit
extends RefCounted
## Menu screens on the UI kit (mission select, join, lobby): the pieces they share, drawn from a
## CanvasItem's _draw() in 480x270 units like UiKit. Pixel rules as UiKit: whole pixels, ink
## outlines, no gradients (banded + Bayer-dithered textures instead).
##
##   backdrop()   space + dithered nebula + a big banded Mars (cached 480x270 texture) + live stars
##   planet_tex() small banded pixel planet (cached)
##   button()     chunky Soul Knight button: face over a darker lip, lifts when hot
##   key_hints()  row of keycaps + labels, centred
##   title()      screen title plate (icon, title, subtitle)
##   tag()        tiny label chip (icon + text)
##   toggle()     ON/OFF pixel switch
##   pixel_star() 9x9 score star
## Screens keep their own state; MenuKit holds only cached textures.

const SPACE := Color("070914")
const NEBULA_A := Color("150f33")
const NEBULA_B := Color("0b1f2e")
const MARS_LIGHT := Color("e8834a")
const MARS_MID := Color("b8532a")
const MARS_DARK := Color("6e2a16")
const MARS_SHADE := Color("2a0f0c")
const STAR := Color("cfd8ff")

const BAYER4 := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

static var _backdrops := {}
static var _planets := {}


# --- backdrop -------------------------------------------------------------------------------

## Whole-screen backdrop. `variant` picks where the big planet sits:
## "low_right" (mission select), "low_left" (join), "high_right" (lobby).
static func backdrop(ci: CanvasItem, variant := "low_right") -> void:
	ci.draw_texture(backdrop_tex(variant), Vector2.ZERO)


static func backdrop_tex(variant: String) -> Texture2D:
	if _backdrops.has(variant):
		return _backdrops[variant]
	var img := Image.create(480, 270, false, Image.FORMAT_RGBA8)
	img.fill(SPACE)
	var noise := FastNoiseLite.new()
	noise.seed = 11 + variant.length()
	noise.frequency = 0.007
	noise.fractal_octaves = 3
	var noise2 := FastNoiseLite.new()
	noise2.seed = 91
	noise2.frequency = 0.011
	for y in 270:
		for x in 480:
			var b: int = BAYER4[(y % 4) * 4 + (x % 4)]
			var n := noise.get_noise_2d(x, y * 1.6)
			var n2 := noise2.get_noise_2d(x + 300, y * 1.3)
			# Two nebula bands, each fading out through a dither ramp.
			if n > 0.18 + b * 0.012:
				img.set_pixel(x, y, NEBULA_A if n < 0.42 + b * 0.01 else NEBULA_A.lightened(0.07))
			elif n2 > 0.28 + b * 0.012:
				img.set_pixel(x, y, NEBULA_B)
	# Dim fixed stars baked in (the bright ones twinkle live).
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 160:
		var sx := rng.randi_range(0, 479)
		var sy := rng.randi_range(0, 269)
		img.set_pixel(sx, sy, img.get_pixel(sx, sy).blend(Color(STAR, rng.randf_range(0.15, 0.4))))
	var center := Vector2(400, 300)
	var radius := 96
	match variant:
		"low_left":
			center = Vector2(60, 312)
			radius = 110
		"high_right":
			center = Vector2(470, -40)
			radius = 84
	_paint_planet(img, center, radius, [MARS_LIGHT.darkened(0.3), MARS_MID.darkened(0.35), MARS_DARK.darkened(0.35), MARS_SHADE],
			Vector3(-0.55, -0.6, 0.58), 5, false)
	var tex := ImageTexture.create_from_image(img)
	_backdrops[variant] = tex
	return tex


## Twinkling bright stars. `stars` = Array of Vector3(x, y, phase). `warp` 0..1 stretches them into
## horizontal streaks flying left (the hyperspace jump out of the lobby).
static func stars(ci: CanvasItem, list: Array, t: float, warp := 0.0) -> void:
	for s: Vector3 in list:
		var depth := 0.4 + fmod(s.z, 1.0) * 0.6
		var a := 0.35 + 0.45 * (0.5 + 0.5 * sin(t * 1.7 + s.z * 6.0))
		if warp <= 0.0:
			ci.draw_rect(Rect2(s.x, s.y, 1, 1), Color(STAR, a))
			if fmod(s.z, 1.0) > 0.85:   # a few big ones get a 1 px cross
				ci.draw_rect(Rect2(s.x - 1, s.y, 3, 1), Color(STAR, a * 0.5))
				ci.draw_rect(Rect2(s.x, s.y - 1, 1, 3), Color(STAR, a * 0.5))
			continue
		var speed := warp * warp * 900.0 * depth
		var x := fposmod(s.x - t * speed, 520.0) - 20.0
		var length := roundf(1.0 + warp * 70.0 * depth)
		ci.draw_rect(Rect2(roundf(x), s.y, length, 1), Color(STAR, minf(1.0, a + warp)))


static func make_stars(count: int, seed_value := 7) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out := []
	for i in count:
		out.append(Vector3(rng.randi_range(0, 479), rng.randi_range(0, 269), rng.randf() * 7.0))
	return out


# --- planets --------------------------------------------------------------------------------

## Small banded planet, lit from the upper left. colors = [light, mid, dark, shade].
static func planet_tex(radius: int, colors: Array, seed_value := 1, cap := false) -> Texture2D:
	var key := "%d|%s|%d|%s" % [radius, str(colors), seed_value, cap]
	if _planets.has(key):
		return _planets[key]
	var size := radius * 2 + 1
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_paint_planet(img, Vector2(radius, radius), radius, colors, Vector3(-0.6, -0.55, 0.58), seed_value, cap)
	var tex := ImageTexture.create_from_image(img)
	_planets[key] = tex
	return tex


static func mars_tex(radius: int) -> Texture2D:
	return planet_tex(radius, [MARS_LIGHT, MARS_MID, MARS_DARK, MARS_SHADE], 5, false)


## Paints a dithered, 4-band planet into `img` (clipped to the image).
static func _paint_planet(img: Image, c: Vector2, r: int, colors: Array, light: Vector3, seed_value: int, cap: bool) -> void:
	var l := light.normalized()
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 2.2 / maxf(r, 1.0)
	var w := img.get_width()
	var h := img.get_height()
	for py in range(maxi(0, int(c.y) - r), mini(h, int(c.y) + r + 1)):
		for px in range(maxi(0, int(c.x) - r), mini(w, int(c.x) + r + 1)):
			var dx := (px - c.x) / r
			var dy := (py - c.y) / r
			var d2 := dx * dx + dy * dy
			if d2 > 1.0:
				continue
			var nz := sqrt(1.0 - d2)
			var lit := Vector3(dx, dy, nz).dot(l)
			var b: float = (BAYER4[(py % 4) * 4 + (px % 4)] / 16.0 - 0.5) * 0.18
			var v := lit + b
			# Surface: dark patches (maria / craters) step the band down by one.
			var patch := noise.get_noise_2d(px, py) > 0.22
			var band := 0 if v > 0.62 else (1 if v > 0.28 else (2 if v > 0.0 else 3))
			if patch and band < 3:
				band += 1
			var col: Color = colors[band]
			if cap and dy < -0.82 + b and band < 3:
				col = Color("f1e6dc") if band < 2 else Color("b9a89c")
			img.set_pixel(px, py, col)


# --- widgets --------------------------------------------------------------------------------

## Chunky button: face over a 2 px darker lip; hot = lifted, bright fill, ink text.
## `press` 0..1 (UiJuice k) pushes the face down onto the lip. Returns the face rect.
static func button(ci: CanvasItem, r: Rect2, label: String, color: Color, hot := false, enabled := true,
		size := 9, icon_name := "", press := 0.0) -> Rect2:
	r = Rect2(r.position.round(), r.size.round())
	var lip := 3.0
	var drop := 0.0 if hot and enabled else 1.0
	if press > 0.0:
		drop = 2.0
	var fill := color if hot and enabled else UiKit.PANEL
	if not enabled:
		fill = UiKit.PANEL_DARK
	var lip_col := (color.darkened(0.55) if enabled else UiKit.WELL)
	# Lip (the button's "side"), then the face.
	ci.draw_rect(Rect2(r.position.x + 1, r.position.y + lip, r.size.x - 2, r.size.y - lip), UiKit.INK)
	ci.draw_rect(Rect2(r.position.x + 2, r.end.y - lip - 1, r.size.x - 4, lip), lip_col)
	var face := Rect2(r.position.x, r.position.y + drop, r.size.x, r.size.y - lip)
	UiKit.panel(ci, face, fill, color if enabled and not hot else Color(0, 0, 0, 0))
	var text_col := UiKit.ink_on(fill) if hot and enabled else (color if enabled else UiKit.FAINT)
	var tw := UiKit.text_w(label, size)
	var iw := 0.0
	if icon_name != "":
		var tex := UiKit.icon_tex(icon_name)
		iw = (float(tex.get_width()) if tex else 8.0) + 3.0
	var x := roundf(face.get_center().x - (tw + iw) / 2.0)
	if icon_name != "":
		var tex := UiKit.icon_tex(icon_name)
		var ih: float = tex.get_height() if tex else 8.0
		UiKit.icon(ci, icon_name, Vector2(x, roundf(face.get_center().y - ih / 2.0)), 1, text_col)
		x += iw
	var base := roundf(face.get_center().y + UiKit.ascent(size) / 2.0)
	UiKit.text(ci, Vector2(x, base), label, size, text_col, 0 if hot and enabled else 2)
	return face


## Row of keycaps with labels, centred on `center_x`, caps' top at `y`.
## items = [["A/D", "CHOOSE"], ["SPACE", "FLY"]]; "A/D" draws two caps.
static func key_hints(ci: CanvasItem, center_x: float, y: float, items: Array, size := 6, col := UiKit.DIM) -> void:
	var total := 0.0
	for pair: Array in items:
		total += _hint_w(pair, size) + 8.0
	total -= 8.0
	var x := roundf(center_x - total / 2.0)
	for pair: Array in items:
		var caps := str(pair[0]).split("/")
		var cap := Rect2(x, y, 0, 0)
		for k in caps.size():
			cap = UiKit.keycap(ci, Vector2(x, y), caps[k], size)
			x = cap.end.x + 1.0
		x += 2.0
		UiKit.text(ci, Vector2(x, cap.end.y - 2), str(pair[1]), size, col, 2)
		x += UiKit.text_w(str(pair[1]), size) + 8.0


static func _hint_w(pair: Array, size: int) -> float:
	var w := 0.0
	for k in str(pair[0]).split("/"):
		w += UiKit.keycap_size(k, size).x + 1.0
	return w + 2.0 + UiKit.text_w(str(pair[1]), size)


## Screen title plate at the top left: icon + big title, subtitle under it. Returns its rect.
static func title(ci: CanvasItem, pos: Vector2, text: String, sub: String, accent: Color, icon_name := "") -> Rect2:
	var tw := UiKit.text_w(text, 14)
	var sw := UiKit.text_w(sub, 6) if sub != "" else 0.0
	var w := maxf(tw + (20.0 if icon_name != "" else 0.0), sw) + 14.0
	var h := 22.0 + (9.0 if sub != "" else 0.0)
	var r := Rect2(pos, Vector2(roundf(w), h))
	UiKit.panel(ci, r, UiKit.PANEL_DARK, accent)
	var x := r.position.x + 6
	if icon_name != "":
		var tex := UiKit.icon_tex(icon_name)
		var isz := tex.get_size() if tex else Vector2(8, 8)
		var scale := 2 if isz.x <= 8 else 1
		UiKit.icon(ci, icon_name, Vector2(x, r.position.y + roundf((22.0 - isz.y * scale) / 2.0)), scale, accent)
		x += isz.x * scale + 4
	UiKit.text(ci, Vector2(x, r.position.y + 17), text, 14, accent, 3)
	if sub != "":
		UiKit.text(ci, Vector2(r.position.x + 7, r.end.y - 4), sub, 6, UiKit.DIM, 0)
	return r


## Tiny label chip: optional 8x8 icon + text, `color` = text/icon, darker fill. Returns its rect.
static func tag(ci: CanvasItem, pos: Vector2, text: String, color: Color, icon_name := "", size := 6, solid := false) -> Rect2:
	var iw := 9.0 if icon_name != "" else 0.0
	var w := tag_w(text, icon_name, size)
	var h := roundf(maxf(UiFont.px(size) + 3.0, 10.0 if icon_name != "" else 0.0))
	var r := Rect2(pos.round(), Vector2(w, h))
	var fill := color if solid else color.darkened(0.72)
	UiKit.chip(ci, r, fill)
	var text_col := UiKit.ink_on(fill) if solid else color
	if icon_name != "":
		UiKit.icon(ci, icon_name, Vector2(r.position.x + 2, roundf(r.get_center().y - 4)), 1, Color.WHITE if solid else text_col)
	UiKit.text(ci, Vector2(r.position.x + 2 + iw, r.end.y - 3), text, size, text_col, 0)
	return r


static func tag_w(text: String, icon_name := "", size := 6) -> float:
	if text == "":
		return 12.0
	return roundf(UiKit.text_w(text, size) + (9.0 if icon_name != "" else 0.0) + 5.0)


## ON/OFF pixel switch (16x8): a knob that sits right + lit when on.
static func toggle(ci: CanvasItem, pos: Vector2, on: bool, color: Color) -> Rect2:
	var r := Rect2(pos.round(), Vector2(17, 9))
	UiKit.chip(ci, r, color.darkened(0.25) if on else UiKit.WELL)
	var knob := Rect2(r.position + Vector2(9 if on else 1, 1), Vector2(7, 7))
	ci.draw_rect(knob, UiKit.INK)
	ci.draw_rect(knob.grow(-1), UiKit.KEY_TOP if on else UiKit.FAINT)
	ci.draw_rect(Rect2(knob.position + Vector2(1, 1), Vector2(5, 1)), Color.WHITE if on else UiKit.DIM)
	return r


## 9x9 pixel star (score). Empty = outline only.
static func pixel_star(ci: CanvasItem, center: Vector2, full: bool, empty_col := UiKit.FAINT) -> void:
	const ROWS := ["....#....", "...###...", "...###...", "#########", ".#######.", "..#####..", ".###.###.", ".##...##.", "##.....##"]
	var o := center.round() - Vector2(4, 4)
	var gold := Color("ffd34a")
	for y in ROWS.size():
		var row: String = ROWS[y]
		for x in row.length():
			if row[x] != "#":
				continue
			var edge := y == 0 or x == 0 or x == row.length() - 1 or y == ROWS.size() - 1 \
					or row[x - 1] != "#" or row[x + 1] != "#" or (ROWS[y - 1] as String)[x] != "#" \
					or (y + 1 < ROWS.size() and (ROWS[y + 1] as String)[x] != "#")
			var c := (gold.darkened(0.35) if edge else (gold.lightened(0.3) if y < 4 else gold)) if full \
					else (empty_col if edge else Color(0, 0, 0, 0))
			if c.a > 0.0:
				ci.draw_rect(Rect2(o + Vector2(x, y), Vector2(1, 1)), c)


## Arrow marker pointing down (above the selected card), nudging on a beat.
static func arrow_down(ci: CanvasItem, tip: Vector2, color: Color, t: float) -> void:
	var p := tip.round() + Vector2(0, -1 if fmod(t, 0.5) < 0.25 else 0)
	for i in 4:
		ci.draw_rect(Rect2(p.x - 3 + i, p.y - 4 + i, 7 - i * 2, 1), UiKit.INK if i == 0 else color)
	ci.draw_rect(Rect2(p.x - 4, p.y - 5, 9, 1), UiKit.INK)


## Bottom toast: kit panel with a coloured accent, text centred. `k` 0..1 = how far in it is.
static func toast(ci: CanvasItem, center_x: float, bottom: float, text: String, color: Color, k := 1.0) -> void:
	if k <= 0.0 or text == "":
		return
	var lines := UiKit.wrap(text, 7, 300.0)
	var w := 0.0
	for line in lines:
		w = maxf(w, UiKit.text_w(line, 7))
	var h := lines.size() * UiKit.line_h(7) + 8.0
	var y := bottom - h + roundf((1.0 - k) * (h + 12.0))
	var r := Rect2(roundf(center_x - (w + 28.0) / 2.0), y, roundf(w + 28.0), roundf(h))
	UiKit.panel(ci, r, UiKit.PANEL_DARK, color)
	ci.draw_rect(Rect2(r.position.x + 5, r.position.y + 4, 3, h - 8), color)
	var by := r.position.y + 4 + UiKit.ascent(7) + 1
	for line in lines:
		UiKit.text_c(ci, r.get_center().x + 4, by, line, 7, UiKit.TEXT, 2)
		by += UiKit.line_h(7)


## Little crewmate (Among Us-ish spacesuit), 12x14 px x `scale`: body in `body`, backpack in `pack`,
## visor glints. `pos` = top-left. Bobs by `bob` whole pixels.
static func crewmate(ci: CanvasItem, pos: Vector2, body: Color, pack: Color, scale := 2, bob := 0) -> void:
	const ROWS := [
		"....####....",
		"...#bbbb#...",
		"..#bbbbbb#..",
		".##bbvvvvv#.",
		"#p#bvwwvvv#.",
		"#p#bvvvvvv#.",
		"#p#bbvvvvb#.",
		"#p#bbbbbbb#.",
		"#p#bbbbbbb#.",
		".##bbbbbbd#.",
		"..#bbbbbdd#.",
		"..#bb##bdd#.",
		"..#bb#.#dd#.",
		"..####.####.",
	]
	var o := pos.round() + Vector2(0, bob)
	var cols := {
		"#": UiKit.INK, "b": body, "d": body.darkened(0.35), "p": pack,
		"v": Color("6fc3df"), "w": Color("e8fbff"),
	}
	for y in ROWS.size():
		var row: String = ROWS[y]
		for x in row.length():
			var ch := row[x]
			if ch == ".":
				continue
			ci.draw_rect(Rect2(o + Vector2(x, y) * scale, Vector2(scale, scale)), cols[ch])
