extends SceneTree
## Generates the UI kit icons (our own designs): 8x8 and 16x16 PNGs + @4x copies in this folder.
## Run from the project folder:
##   Godot_console.exe --headless --path . -s res://sprites/ui_icons/draw_icons.gd [-- <preview.png>]
## then open the editor (or run --headless --import) so Godot imports the new PNGs.
##
## Icons are FILL maps: the script adds a 1 px ink outline around every shape and a darker shade on
## the bottom/right edge, so designs only say where the shape is.
##   .  empty      w  white      l  light grey    m  mid grey     d  dark grey    k  ink (explicit)
##   colours for icons that keep their own colours (planets): b B g G (Earth) r R D (Mars) y o c
## White/grey icons are tinted in game (UiKit.icon(..., mod)); the ink outline stays dark.

const PALETTE := {
	"w": Color("ffffff"), "l": Color("c9cfdd"), "m": Color("8d96ad"), "d": Color("4d5573"),
	"k": Color("06070f"),
	"b": Color("2c64c8"), "B": Color("5d9cf5"), "g": Color("49b85a"), "G": Color("2c8240"),
	"r": Color("c4532f"), "R": Color("e8834f"), "D": Color("86331e"),
	"y": Color("ffd84a"), "o": Color("ff8a2a"), "c": Color("4fd8ff"),
}
const INK := Color("06070f")

const ICONS_8 := {
	"power": [
		"........",
		"....ww..",
		"...ww...",
		"..wwwww.",
		".wwwww..",
		"...ww...",
		"..ww....",
		"........"],
	"fuel": [
		"........",
		"...ww...",
		"...ww...",
		"..wwwl..",
		".wwwwll.",
		".wwwllm.",
		"..lmmm..",
		"........"],
	"data": [
		"........",
		".wwwwww.",
		".llllll.",
		".kkkkkk.",
		".wwwwww.",
		".llllll.",
		".mmmmmm.",
		"........"],
	"earth": [
		"........",
		"..bBgb..",
		".bBggbb.",
		".bggbbg.",
		".bbgGbb.",
		".gbbbgb.",
		"..bbgb..",
		"........"],
	"mars": [
		"........",
		"..RRrr..",
		".RRrrDr.",
		".RrrrrD.",
		".rDDrrr.",
		".rrrDrr.",
		"..DrrD..",
		"........"],
	"ship": [
		"........",
		".w......",
		".mww....",
		".mwwwww.",
		".mwwwww.",
		".mww....",
		".w......",
		"........"],
	"dsn": [
		"........",
		".w....w.",
		".lw..w..",
		"..lww...",
		"...lw...",
		"...m....",
		"..mmm...",
		"........"],
	"sent": [
		"........",
		"...ww...",
		"..wwww..",
		".wwwwww.",
		"...ww...",
		"........",
		".wwwwww.",
		"........"],
	"lost": [
		"........",
		".ww..ww.",
		"..wwww..",
		"...ww...",
		"..wwww..",
		".ww..ww.",
		"........",
		"........"],
	"check": [
		"........",
		"........",
		".....ww.",
		".w..ww..",
		".wwww...",
		"..ww....",
		"........",
		"........"],
	"nav": [
		"........",
		"...ww...",
		"..wwww..",
		".ww..ww.",
		".ww..ww.",
		"..wwww..",
		"...ww...",
		"........"],
	"pwr": [
		"........",
		"....ww..",
		"...ww...",
		"..wwwww.",
		".wwwww..",
		"...ww...",
		"..ww....",
		"........"],
	"com": [
		"........",
		"......w.",
		"......w.",
		"....w.w.",
		"....w.w.",
		"..w.w.w.",
		"..w.w.w.",
		"........"],
	"sci": [
		"........",
		"...ww...",
		"...ww...",
		"..wwll..",
		".wwwwll.",
		".mmmmmm.",
		"..mmmm..",
		"........"],
	"team": [
		"........",
		"...ww...",
		"..wllw..",
		"...ww...",
		"........",
		".wwwwww.",
		"..llll..",
		"........"],
	"wrench": [
		"........",
		".....w..",
		"....ww.w",
		"....wwww",
		"...www..",
		"..www...",
		".ww.....",
		"........"],
	"debris": [
		"........",
		".ww.....",
		".wlm..w.",
		"..m..wl.",
		"......m.",
		".ww.....",
		".lm.....",
		"........"],
	"note": [
		"........",
		"....ww..",
		"....w.w.",
		"....w...",
		"..www...",
		".wwww...",
		"..ww....",
		"........"],
	"hull": [
		"........",
		".wwwwww.",
		".wmwwmw.",
		".wwwwww.",
		".llllll.",
		".lmllml.",
		".llllll.",
		"........"],
	"o2": [
		"........",
		"...www..",
		"..wwlww.",
		"..wwwww.",
		"...www..",
		".ww.....",
		".wl.....",
		"........"],
	"fire": [   # keeps its own colours (not tinted)
		"........",
		"...y....",
		"...yo...",
		"..yyo.y.",
		".yywyoo.",
		".ywwwyo.",
		"..ywyo..",
		"........"],
	"extinguisher": [
		"........",
		"..ww....",
		".w.ww...",
		"...ll...",
		"..wwww..",
		"..wwwl..",
		"..wwll..",
		"........"],
	"ping": [
		"........",
		".wwwwww.",
		".wwkkww.",
		".wwkkww.",
		".wwwwww.",
		".wwkkww.",
		"..w.....",
		"........"],
}

const ICONS_16 := {
	"dock": [
		"................",
		"................",
		"............ww..",
		"......w.....ww..",
		"......ww....ww..",
		"......www...ww..",
		".wwwwwwwww..ww..",
		".wwwwwwwwww.ww..",
		".llllllllll.ll..",
		".lllllllll..ll..",
		"......lll...ll..",
		"......ll....ll..",
		"......l.....ll..",
		"............ll..",
		"................",
		"................"],
	"work": [
		"................",
		"......wwww......",
		"..ww..wwww..ww..",
		"..wwwwwwwwwwww..",
		"...wwwwwwwwww...",
		"...wwww..wwww...",
		".wwwww....wwwww.",
		".wwww......wwww.",
		".llll......llll.",
		".lllll....lllll.",
		"...llll..llll...",
		"...llllllllll...",
		"..llllllllllll..",
		"..ll..llll..ll..",
		"......llll......",
		"................"],
	"repair": [
		"................",
		"...........ww...",
		"..........ww..w.",
		"..........ww.ww.",
		"..........wwwww.",
		".........wwwww..",
		"........www.....",
		".......www......",
		"......www.......",
		".....lll........",
		"....lll.........",
		"...lll..........",
		"..lll...........",
		".ll.............",
		"................",
		"................"],
	"shield": [
		"................",
		"................",
		"..wwwwwwllllll..",
		"..wwwwwwllllll..",
		"..wwwwwwllllll..",
		"..wwwwwwllllll..",
		"..wwwwwwllllll..",
		"..wwwwwwllllll..",
		"...wwwwwlllll...",
		"...wwwwwlllll...",
		"....wwwwllll....",
		".....wwwlll.....",
		"......wwll......",
		".......wl.......",
		"................",
		"................"],
	"safe": [
		"................",
		".......ww.......",
		".......ww.......",
		"...ww..ww..ww...",
		"..ww...ww...ww..",
		".ww....ww....ww.",
		".ww....ww....ww.",
		".ww..........ww.",
		".ll..........ll.",
		".ll..........ll.",
		"..ll........ll..",
		"...ll......ll...",
		"....llllllll....",
		"................",
		"................",
		"................"],
	"fly": [
		"................",
		"................",
		"...w............",
		"...www..........",
		"...wwwww........",
		"..mwwwwwww......",
		".mmwwwwwwwwww...",
		".mmwwwwwwllwwww.",
		".mmllllllllllll.",
		".mmllllllllll...",
		"..mllllllll.....",
		"...lllll........",
		"...lll..........",
		"...l............",
		"................",
		"................"],
	"burn": [
		"................",
		"........w.......",
		".......ww.......",
		"......www..w....",
		"......wwww.ww...",
		".....wwlwwwww...",
		"....wwllwwwww...",
		"....wwllllwww...",
		"...wwllmmllwww..",
		"...wllmmmmllww..",
		"...wllmmmmmllw..",
		"...wllmmmmmllw..",
		"....wllmmmllw...",
		".....wlllllw....",
		"......wwwww.....",
		"................"],
	"switch": [
		"................",
		"..........w.....",
		".........www....",
		"........www.....",
		".......ww.......",
		"......ww........",
		".....ww.........",
		"....ww..........",
		"..wwwwwwwwwwww..",
		"..lddddddddddl..",
		"..lddddddddddl..",
		"..lddddddddddl..",
		"..llllllllllll..",
		"................",
		"................",
		"................"],
	"downlink": [
		"................",
		".............w..",
		"...........w..w.",
		"............w.w.",
		"..ww.........w..",
		"..wlw...........",
		"...wlw....w.....",
		"...wllw..w......",
		"....wllww.......",
		".....wllw.......",
		"......wlw.......",
		".......ww.......",
		"......mm........",
		".....mmmm.......",
		"....mmmmmm......",
		"................"],
	"observe": [
		"................",
		"................",
		"................",
		"................",
		".....wwwwww.....",
		"...wwwwwwwwww...",
		"..wwwwkkkkwwww..",
		".wwwwkkwwkkwwww.",
		".llllkkkkkkllll.",
		"..llllkkkkllll..",
		"...llllllllll...",
		".....llllll.....",
		"................",
		"................",
		"................",
		"................"],
	"radio": [
		"................",
		"......wwwwwwww..",
		"......wwwwwwww..",
		"......ww....ww..",
		"......ww....ww..",
		"......ww....ww..",
		"......ww....ww..",
		"......ww....ww..",
		"......ww....ww..",
		"......ww.lllll..",
		"...lllll.lllll..",
		"..llllll.lllll..",
		"..llllll..lll...",
		"...llll.........",
		"................",
		"................"],
	"alert": [
		"................",
		".......ww.......",
		"......wwww......",
		"......wkkw......",
		".....wwkkww.....",
		".....wwkkww.....",
		"....wwwkkwww....",
		"....wwwkkwww....",
		"...wwwwkkwwww...",
		"...wwwwwwwwww...",
		"..lllllkklllll..",
		"..lllllkklllll..",
		".llllllllllllll.",
		"................",
		"................",
		"................"],
	"blackout": [
		"................",
		".kk......wwww...",
		".kkk....wwww....",
		"..kkk..wwww.....",
		"...kkkwwww......",
		".....kkkwwwww...",
		"....wwkkkwww....",
		"........kkk.....",
		".......wwkkk....",
		"......www.kkk...",
		".....ww....kkk..",
		"....ww......kkk.",
		"..............kk",
		"................",
		"................",
		"................"],
	"use": [
		"................",
		"......ww........",
		".....wwww.......",
		".....wwww.......",
		".....wwww.......",
		".....wwwwww.....",
		".....wwwwwwwww..",
		"..ww.wwwwwwwwww.",
		"..wwwwwwwwwwwww.",
		"..lllllllllllll.",
		"...llllllllllll.",
		"....llllllllll..",
		".....llllllll...",
		".....llllllll...",
		"................",
		"................"],
}


func _initialize() -> void:
	var dir := ProjectSettings.globalize_path("res://sprites/ui_icons/")
	var made: Array[Image] = []
	var names: Array[String] = []
	for n: String in ICONS_8:
		made.append(_save(dir, n, _from_map(ICONS_8[n])))
		names.append(n)
	for n: String in ICONS_16:
		made.append(_save(dir, n, _from_map(ICONS_16[n])))
		names.append(n)
	made.append(_save(dir, "radiation", _radiation()))
	names.append("radiation")
	made.append(_save(dir, "debris_big", _debris_big()))
	names.append("debris_big")
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_preview(made, args[0])
	print("ui icons: %d written to %s" % [made.size(), dir])
	quit()


func _from_map(rows: Array) -> Image:
	var h := rows.size()
	var w: int = (rows[0] as String).length()
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in h:
		var row: String = rows[y]
		assert(row.length() == w, "icon row %d is %d wide, expected %d" % [y, row.length(), w])
		for x in w:
			var ch := row[x]
			if PALETTE.has(ch):
				img.set_pixel(x, y, PALETTE[ch])
	return _finish(img)


## Ink outline around every filled pixel (8 neighbours), then a darker shade on fills that
## touch the outline below or to the right.
func _finish(img: Image) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var out := img.duplicate() as Image
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > 0.0:
				continue
			var near := false
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var nx: int = x + dx
					var ny: int = y + dy
					if nx >= 0 and ny >= 0 and nx < w and ny < h and img.get_pixel(nx, ny).a > 0.0 \
							and img.get_pixel(nx, ny) != INK:
						near = true
			if near:
				out.set_pixel(x, y, INK)
	var shaded := out.duplicate() as Image
	for y in h:
		for x in w:
			var c := out.get_pixel(x, y)
			if c.a == 0.0 or c == INK:
				continue
			var below := out.get_pixel(x, y + 1) if y + 1 < h else INK
			var right := out.get_pixel(x + 1, y) if x + 1 < w else INK
			if below == INK or right == INK:
				shaded.set_pixel(x, y, c.darkened(0.18))
	return shaded


## Radiation trefoil: centre dot + three blades (up-left, up-right, down), 16x16.
func _radiation() -> Image:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(7.5, 7.5)
	for y in 16:
		for x in 16:
			var p := Vector2(x, y) - c
			var r := p.length()
			var ok := r <= 1.6
			if r >= 3.0 and r <= 6.8:
				for a_deg in [-150.0, -30.0, 90.0]:
					var diff := absf(wrapf(rad_to_deg(p.angle()) - a_deg, -180.0, 180.0))
					if diff <= 31.0:
						ok = true
			if ok:
				img.set_pixel(x, y, PALETTE.w if y < 9 else PALETTE.l)
	return _finish(img)


## Three tumbling rocks, 16x16.
func _debris_big() -> Image:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for rock in [[Vector2(4.5, 4.5), 3.2], [Vector2(11.5, 6.0), 2.4], [Vector2(6.5, 11.5), 2.2]]:
		var at: Vector2 = rock[0]
		var rad: float = rock[1]
		for y in 16:
			for x in 16:
				var p := Vector2(x, y) - at
				# Lumpy edge: radius wobbles with the angle.
				if p.length() <= rad * (0.85 + 0.15 * sin(p.angle() * 3.0 + rad)):
					var lit := p.x + p.y < 0.0
					img.set_pixel(x, y, PALETTE.w if lit else PALETTE.m)
	return _finish(img)


func _save(dir: String, icon_name: String, img: Image) -> Image:
	img.save_png(dir + icon_name + ".png")
	var big := img.duplicate() as Image
	big.resize(img.get_width() * 4, img.get_height() * 4, Image.INTERPOLATE_NEAREST)
	big.save_png(dir + icon_name + "@4x.png")
	return img


## Contact sheet at 8x on a dark panel, white icons tinted with role colours.
func _preview(images: Array[Image], path: String) -> void:
	var tints := [Color("4fd8ff"), Color("ff9a3c"), Color("5cf07a"), Color("b77bff"), Color("ffc640")]
	var cell := 144
	var cols := 10
	var rows := ceili(images.size() / float(cols))
	var sheet := Image.create(cols * cell, rows * cell * 2, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("171d35"))
	for t in 2:
		for i in images.size():
			var img: Image = images[i].duplicate()
			if t == 1:
				var tint: Color = tints[i % tints.size()]
				for y in img.get_height():
					for x in img.get_width():
						var c := img.get_pixel(x, y)
						if c.a > 0.0 and c != INK:
							img.set_pixel(x, y, c * tint)
			img.resize(img.get_width() * 8, img.get_height() * 8, Image.INTERPOLATE_NEAREST)
			var at := Vector2i((i % cols) * cell + 8, (t * rows + i / cols) * cell + 8)
			sheet.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), at)
	sheet.save_png(path)
