class_name CharacterSelect
extends Node2D
## Suit-up locker overlay in the hangar (Soul Knight style character select). Opened with SPACE at the
## crew locker (HangarDecor "locker"); full screen on a CanvasLayer 15 like the RocketBoard.
##
## What you pick is your LOOK = a crew skin (sprites/crew_skins; "" = the classic role-coloured flight
## suit), shown big on its own backdrop (drawn here in code: Earth from orbit, the launch pad at night,
## a blue Mars sunset). WHO you are (name + backstory) comes from your crew role
## (Astronauts.id_for_role, data/astronauts.json), the same astronaut the cruise dose bars and the report
## use - so the bio is shown, but not chosen. Look texts + backdrops: data/characters.json.
##
## A / D (or arrows, or click the side arrows) browse, SPACE (or click the character) = wear it and close,
## Q closes. The hangar sets `_local.skin` on `picked`; the skin rides in the crew snapshot, so every peer
## sees it. The pick is remembered in user://character.cfg (saved_skin()).
## Walking is blocked while open via Tutorial.hold() (like the minigames).

signal picked(skin: String)
signal close_requested

const DATA_PATH := "res://data/characters.json"
const SKINS_PATH := "res://sprites/crew_skins/skins.json"
const CFG := "user://character.cfg"
const STAGE := Rect2(12, 30, 228, 200)      # backdrop window, character stands in it
const BAR := Rect2(12, 233, 228, 29)        # browse strip under the stage
const SIDE := Rect2(246, 30, 222, 232)      # look + astronaut card
const SCALE := 8                            # 16 px sprite -> 128 px
const ARM_TIME := 0.15                      # ignore the SPACE that opened the locker
const TURN := ["down", "down", "left", "down", "down", "right"]   # idle turntable, one step per TURN_TIME
const TURN_TIME := 1.1

var role := "all"            # local crew role (picks the astronaut + accent colour)
var worn := ""               # skin the local player wears now
var crew_root: Node          # hangar crew layer: other players' looks for "ALSO WORN BY"

var _looks: Array = []       # [{skin, title, tagline, backdrop, caption, height}]
var _index := 0
var _t := 0.0
var _change_t := 9.0         # time since the last browse (slide-in)
var _change_dir := 0
var _stars: Array[Vector3] = []
var _hit: Array = []         # [key, Rect2] click / tap targets: "prev", "next", "wear", "close", "stage"


## The look this player picked last time (null = never picked).
static func saved_skin() -> Variant:
	var cfg := ConfigFile.new()
	if cfg.load(CFG) != OK or not cfg.has_section_key("player", "skin"):
		return null
	return str(cfg.get_value("player", "skin", ""))


static func save_skin(skin: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	cfg.set_value("player", "skin", skin)
	cfg.save(CFG)


## Skins a player can wear, in locker order ("" = classic flight suit).
static func looks() -> Array:
	var data := _json(DATA_PATH)
	var heights: Dictionary = _json(SKINS_PATH).get("skins", {})
	var info: Dictionary = data.get("looks", {})
	var out: Array = []
	for skin: String in data.get("order", [""]):
		if skin != "" and not CrewSprite.has_skin(skin):
			continue
		var l: Dictionary = info.get(skin, {})
		out.append({skin = skin, title = str(l.get("title", skin.capitalize())), tagline = str(l.get("tagline", "")),
				backdrop = str(l.get("backdrop", "earth")), caption = str(l.get("caption", "")),
				height = int(heights.get(skin, {}).get("height_cm", 0))})
	return out


func _enter_tree() -> void:
	UiFont.max_level = 1   # dense screen: TEXT SIZE stops at LARGE (like the rocket board)


func _exit_tree() -> void:
	UiFont.max_level = 2
	Tutorial.hold(false)


func _ready() -> void:
	UiKit.setup_canvas(self)
	Tutorial.hold(true)    # crew + hangar input off while the locker is open
	_looks = looks()
	for i in _looks.size():
		if _looks[i].skin == worn:
			_index = i
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	for i in 70:
		_stars.append(Vector3(rng.randi_range(0, int(STAGE.size.x) - 1), rng.randi_range(0, int(STAGE.size.y) - 1), rng.randf() * TAU))
	Sfx.play("page")


# --- input -------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	_change_t += delta
	if _t > ARM_TIME and not _blocked():
		if _pressed("leave"):
			close_requested.emit()
			return
		if _pressed("left"):
			_browse(-1)
		elif _pressed("right"):
			_browse(1)
		elif _pressed("interact"):
			_wear()
	queue_redraw()


func _input(event: InputEvent) -> void:
	if _t <= ARM_TIME or _blocked():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var p := get_local_mouse_position()
		for h: Array in _hit:
			if (h[1] as Rect2).has_point(p):
				get_viewport().set_input_as_handled()
				match str(h[0]):
					"prev": _browse(-1)
					"next": _browse(1)
					"wear", "stage": _wear()
					"close": close_requested.emit()
				return


func _pressed(verb: String) -> bool:
	return Input.is_action_just_pressed(Controls.action("p1", verb))


## A real tutorial dialog or the ESC menu on top: leave the keys to them.
func _blocked() -> bool:
	if Tutorial.any_open():
		return true
	var scene := get_tree().current_scene
	if scene:
		for n in scene.get_children():
			if n is PauseMenu and n.is_open():
				return true
	return false


func _browse(step: int) -> void:
	if _looks.size() < 2:
		return
	_index = posmod(_index + step, _looks.size())
	_change_t = 0.0
	_change_dir = step
	Sfx.play("ui_hover")


func _wear() -> void:
	if _looks.is_empty():
		return
	var skin := str(_looks[_index].skin)
	save_skin(skin)
	Sfx.play("toggle" if skin != worn else "ui_click")
	worn = skin
	picked.emit(skin)
	close_requested.emit()


## Names of the other players wearing `skin` right now.
func _worn_by(skin: String) -> PackedStringArray:
	var out := PackedStringArray()
	if crew_root == null:
		return out
	for m in crew_root.get_children():
		if m is CrewMember and m.remote and m.skin == skin:
			out.append(m.display_name.to_upper() if m.display_name != "" else "CREW")
	return out


# --- drawing -----------------------------------------------------------------------------

func _draw() -> void:
	_hit = []
	if _looks.is_empty():
		return
	var look: Dictionary = _looks[_index]
	var accent := CrewRoles.color(role)
	draw_rect(Rect2(-8, -8, 496, 286), Color(0.01, 0.015, 0.04, 0.9))
	UiKit.frame(self, Rect2(4, 4, 472, 262), accent)
	_draw_title(accent)
	_draw_stage(look, accent)
	_draw_bar(accent)
	_draw_side(look, accent)


func _draw_title(accent: Color) -> void:
	var bar := Rect2(7, 7, 466, 20)
	draw_rect(bar, UiKit.PANEL)
	draw_rect(Rect2(bar.position.x, bar.end.y, bar.size.x, 1), UiKit.INK)
	UiKit.icon(self, "team", bar.position + Vector2(3, 2), 1, accent)
	var cap := UiKit.keycap_size("Q", 7)
	var close_w := cap.x + 3 + UiKit.text_w("CLOSE", 6)
	UiKit.text(self, Vector2(bar.position.x + 23, bar.end.y - 5),
			UiKit.fit("SUIT-UP LOCKER  -  CHOOSE YOUR LOOK", 10, bar.size.x - 40 - close_w), 10, accent)
	var kx := bar.end.x - 4 - close_w
	var kr := UiKit.keycap(self, Vector2(kx, bar.position.y + roundf((bar.size.y - cap.y) / 2.0)), "Q", 7)
	UiKit.text(self, Vector2(kx + cap.x + 3, bar.end.y - 6), "CLOSE", 6, UiKit.DIM, 0)
	_hit.append(["close", Rect2(kr.position, Vector2(close_w, kr.size.y)).grow(3)])


func _draw_stage(look: Dictionary, accent: Color) -> void:
	var s := STAGE
	match str(look.backdrop):
		"mars": _bg_mars(s)
		"pad": _bg_pad(s)
		_: _bg_earth(s)
	# The character: integer scale, feet on the floor line, slides in after a browse.
	var feet_y := s.end.y - 16.0
	var k := clampf(_change_t / 0.18, 0.0, 1.0)
	var slide := roundf((1.0 - k) * (1.0 - k) * 26.0 * _change_dir)
	var hop := -roundf(sin(k * PI) * 6.0) if k < 1.0 else 0.0
	var skin := str(look.skin)
	var cx := s.get_center().x + slide + (18.0 if skin == "friend_1" else -6.0)
	if skin == "friend_1":   # his companion walks with him in the cruise: stands beside him here
		_shadow(Vector2(cx - 62, feet_y + 2), 18)
		_draw_skin("friend_1_girl", Vector2(cx - 62, feet_y + 2 + hop), 5, "down")
	_shadow(Vector2(cx, feet_y), 28)
	var facing: String = TURN[int(_t / TURN_TIME) % TURN.size()]
	if skin == "":
		_draw_classic(Vector2(cx, feet_y + hop), SCALE, facing, CrewRoles.color(role))
	else:
		_draw_skin(skin, Vector2(cx, feet_y + hop), SCALE, facing)
	# caption strip (real place + fact) along the top of the window
	var lines := UiKit.wrap(str(look.caption), 6, s.size.x - 10)
	var lh := UiKit.line_h(6)
	var strip := Rect2(s.position, Vector2(s.size.x, lh * lines.size() + 5))
	draw_rect(strip, Color(UiKit.INK, 0.72))
	for i in lines.size():
		UiKit.text(self, Vector2(s.position.x + 5, s.position.y + 2 + lh * (i + 1)), lines[i], 6, Color(accent, 0.95), 0)
	# side arrows (click / tap targets)
	var bob := roundf(sin(_t * 4.0) * 1.5)
	_hit.append(["prev", _arrow(Vector2(s.position.x + 6, s.get_center().y - 8), -1, bob, accent)])
	_hit.append(["next", _arrow(Vector2(s.end.x - 18, s.get_center().y - 8), 1, -bob, accent)])
	_hit.append(["stage", Rect2(s.get_center().x - 44, s.position.y + 30, 88, s.size.y - 30)])
	if skin == worn:
		UiKit.stamp(self, Vector2(s.end.x - 30, s.end.y - 10), "WEARING", UiKit.GOOD, 0.0, 6)
	draw_rect(s, UiKit.INK, false, 1.0)


## Chunky pixel chevron in a dark box; returns its rect.
func _arrow(pos: Vector2, dir: int, bob: float, col: Color) -> Rect2:
	var r := Rect2(pos + Vector2(bob, 0), Vector2(12, 16))
	UiKit.panel(self, r, UiKit.PANEL_DARK)
	for i in 4:
		var x := r.position.x + (4 + i if dir > 0 else 7 - i)
		draw_rect(Rect2(x, r.position.y + 4 + i, 1, 8 - i * 2), col)
	return r.grow(4)


func _draw_bar(accent: Color) -> void:
	UiKit.panel(self, BAR, UiKit.PANEL_DARK)
	var y := BAR.position.y + 6
	var a := UiKit.keycap(self, Vector2(BAR.position.x + 6, y), "A", 7)
	var d_size := UiKit.keycap_size("D", 7)
	var d := UiKit.keycap(self, Vector2(BAR.end.x - 6 - d_size.x, y), "D", 7)
	_hit.append(["prev", a.grow(3)])
	_hit.append(["next", d.grow(3)])
	UiKit.text(self, Vector2(a.end.x + 3, a.end.y - 3), "PREV", 6, UiKit.DIM, 0)
	UiKit.text_r(self, d.position.x - 3, d.end.y - 3, "NEXT", 6, UiKit.DIM, 0)
	# one pip per look; the shown one is lit, the worn one has a tick under it
	var n := _looks.size()
	var x0 := roundf(BAR.get_center().x - (n * 10 - 4) / 2.0)
	for i in n:
		var r := Rect2(x0 + i * 10, y + 2, 6, 6)
		UiKit.chip(self, r, accent if i == _index else UiKit.FAINT)
		if _looks[i].skin == worn:
			draw_rect(Rect2(r.position.x + 1, r.end.y + 2, 4, 1), UiKit.GOOD)
	UiKit.text_c(self, BAR.get_center().x, BAR.end.y - 3, "%d / %d" % [_index + 1, n], 6, UiKit.DIM, 0)


func _draw_side(look: Dictionary, accent: Color) -> void:
	UiKit.panel(self, SIDE, UiKit.PANEL, accent)
	var x := SIDE.position.x + 8
	var w := SIDE.size.x - 16
	var y := SIDE.position.y + 13
	UiKit.text(self, Vector2(x, y), "LOOK", 6, UiKit.DIM, 0)
	if int(look.height) > 0:
		UiKit.text_r(self, x + w, y, "HEIGHT %d CM" % int(look.height), 6, UiKit.DIM, 0)
	y += UiKit.line_h(12) + 1
	UiKit.text(self, Vector2(x, y), UiKit.fit(str(look.title).to_upper(), 12, w), 12, Color.WHITE)
	y += 3
	for line in UiKit.wrap(str(look.tagline), 7, w).slice(0, 3):
		y += UiKit.line_h(7)
		UiKit.text(self, Vector2(x, y), line, 7, UiKit.TEXT, 0)
	y += 7
	UiKit.dither(self, Rect2(x, y, w, 1), Color(accent, 0.7))
	# who you are: the astronaut your crew role flies as (fixed by the role, shown for the story)
	var id := Astronauts.id_for_role(role)
	var astro := Astronauts.info(id)
	y += 11
	UiKit.text(self, Vector2(x, y), "YOU FLY AS", 6, UiKit.DIM, 0)
	var tag := CrewRoles.tag(role) if role != "all" else "ALL"
	var tw := UiKit.text_w(tag, 6) + 6
	var chip := Rect2(x + w - tw, y - UiKit.line_h(6) + 1, tw, UiKit.line_h(6) + 1)
	UiKit.chip(self, chip, accent)
	UiKit.text_c(self, chip.get_center().x, chip.end.y - 2, tag, 6, UiKit.ink_on(accent), 0)
	y += UiKit.line_h(10) + 1
	UiKit.text(self, Vector2(x, y), UiKit.fit(str(astro.get("name", "")).to_upper(), 10, w), 10, accent)
	y += UiKit.line_h(6)
	UiKit.text(self, Vector2(x, y), str(astro.get("role", "")).to_upper(), 6, UiKit.DIM, 0)
	y += 2
	for line in UiKit.wrap(str(astro.get("bio", "")), 7, w).slice(0, 4):
		y += UiKit.line_h(7)
		UiKit.text(self, Vector2(x, y), line, 7, UiKit.TEXT, 0)
	# bottom: what SPACE does + who else wears it
	var others := _worn_by(str(look.skin))
	var by := SIDE.end.y - 8
	var notes := PackedStringArray()
	if not others.is_empty():
		notes.append("ALSO WORN BY " + ", ".join(others))
	var hint := UiKit.wrap("Your crew role decides who you are (dose bars, report). The locker only changes your look.", 6, w)
	var ny := by - UiKit.line_h(9) - 8 - UiKit.line_h(6) * (hint.size() + notes.size())
	if ny > y + 4:
		for line in hint:
			ny += UiKit.line_h(6)
			UiKit.text(self, Vector2(x, ny), line, 6, UiKit.FAINT.lightened(0.25), 0)
	for line in notes:
		ny += UiKit.line_h(6)
		UiKit.text(self, Vector2(x, ny), UiKit.fit(line, 6, w), 6, UiKit.WARN, 0)
	var wearing := str(look.skin) == worn
	var cap := UiKit.keycap_size("SPACE", 7)
	var verb := "KEEP THIS LOOK" if wearing else "WEAR THIS LOOK"
	var bw := cap.x + 6 + UiKit.text_w(verb, 9) + 10
	var btn := Rect2(x, by - cap.y - 4, bw, cap.y + 6)
	var pulse := 0.5 + 0.5 * sin(_t * 5.0)
	UiKit.panel(self, btn, UiKit.PANEL_DARK, UiKit.GOOD if wearing else Color(accent, 0.6 + 0.4 * pulse))
	UiKit.keycap(self, btn.position + Vector2(4, 3), "SPACE", 7)
	UiKit.text(self, Vector2(btn.position.x + cap.x + 10, btn.end.y - 4), verb, 9, UiKit.GOOD if wearing else Color.WHITE)
	_hit.append(["wear", btn])


# --- characters --------------------------------------------------------------------------

## A crew skin's idle frame, integer-scaled, feet (sheet anchor 8,15) at `feet`.
func _draw_skin(skin: String, feet: Vector2, scale: int, facing: String) -> void:
	var frames := CrewSprite.frames_for(skin)
	if frames == null:
		return
	var anim := "idle_" + facing
	if not frames.has_animation(anim):
		anim = "idle_down"
	var n := frames.get_frame_count(anim)
	var tex := frames.get_frame_texture(anim, int(_t * 3.0) % maxi(n, 1))
	var pos := (feet - Vector2(8, 15) * scale).round()
	draw_texture_rect(tex, Rect2(pos, Vector2(16, 16) * scale), false)


## The classic placeholder astronaut (CrewMember draws it at 1x when skin == ""), big: same silhouette
## (suit in the role colour + white helmet), with a few extra sprite-pixels so it reads as a suit at this size.
func _draw_classic(feet: Vector2, scale: int, facing: String, suit: Color) -> void:
	var o := feet.round()
	var px := func(x: int, y: int, w: int, h: int, c: Color) -> void:
		draw_rect(Rect2(o + Vector2(x, y) * scale, Vector2(w, h) * scale), c)
	for r: Rect2 in [Rect2(-3, -11, 6, 9), Rect2(-3, -15, 6, 5)]:   # ink outline
		draw_rect(Rect2(o + r.position * scale - Vector2(2, 2), r.size * scale + Vector2(4, 4)), UiKit.INK)
	var shade := suit.darkened(0.22)
	px.call(-3, -11, 6, 9, suit)
	px.call(-3, -11, 6, 1, suit.lightened(0.25))
	px.call(-3, -9, 1, 4, shade)                     # arms
	px.call(2, -11, 1, 9, shade)
	px.call(-3, -6, 6, 1, suit.darkened(0.4))        # belt
	px.call(-1, -4, 1, 2, suit.darkened(0.45))       # leg gap
	px.call(-3, -3, 6, 1, Color("3a4258"))           # boots
	var badge := Color("4fd8ff") if suit.get_luminance() > 0.7 else Color("f0f0f0")
	px.call(-2, -9, 1, 1, badge)                     # mission patch
	px.call(-3, -15, 6, 5, Color("f0f0f0"))          # helmet
	px.call(-3, -15, 6, 1, Color.WHITE)
	px.call(2, -15, 1, 5, Color("c8ccd8"))
	px.call(-3, -11, 6, 1, Color("8a93b0"))          # neck ring
	var f := Vector2(0, 1)
	match facing:
		"up": f = Vector2(0, -1)
		"left": f = Vector2(-1, 0)
		"right": f = Vector2(1, 0)
	if f.y >= 0:
		var v := Vector2i(-2 + int(f.x), -14 + int(maxf(f.y, 0)))
		px.call(v.x, v.y, 4, 2, Color("1b2a4a"))      # visor shows facing
		px.call(v.x + 1, v.y, 1, 1, Color("6a8ab8"))  # glint
	else:
		px.call(-2, -13, 4, 2, Color("c8ccd8"))       # back of the helmet / life support


## Dithered oval shadow under the feet.
func _shadow(feet: Vector2, half_w: float) -> void:
	for row in 5:
		var k := 1.0 - absf(row - 2.0) / 3.0
		var hw := roundf(half_w * sqrt(k))
		UiKit.dither(self, Rect2(feet.x - hw, feet.y - 2 + row, hw * 2, 1), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(feet.x - roundf(half_w * 0.6), feet.y, roundf(half_w * 1.2), 1), Color(0, 0, 0, 0.35))


# --- backdrops (hard bands + 50% dither between them, whole pixels) ----------------------

## Rect clipped to the stage.
func _r(r: Rect2, c: Color) -> void:
	var cut := r.intersection(STAGE)
	if cut.has_area():
		draw_rect(cut, c)


func _d(r: Rect2, c: Color) -> void:
	var cut := r.intersection(STAGE)
	if cut.has_area():
		UiKit.dither(self, cut, c)


## Horizontal bands from y0: colours + heights; a 2 px dither seam softens each step.
func _bands(y0: float, cols: Array, heights: Array) -> float:
	var y := y0
	for i in cols.size():
		_r(Rect2(STAGE.position.x, y, STAGE.size.x, heights[i]), cols[i])
		if i > 0:
			_d(Rect2(STAGE.position.x, y - 2, STAGE.size.x, 2), cols[i])
		y += float(heights[i])
	return y


## Filled pixel disc (row spans), optionally dithered.
func _disc(c: Vector2, radius: float, col: Color, dith := false) -> void:
	for dy in range(-int(radius), int(radius) + 1):
		var hw := floorf(sqrt(maxf(radius * radius - dy * dy, 0.0)))
		var r := Rect2(c.x - hw, c.y + dy, hw * 2 + 1, 1)
		if dith:
			_d(r, col)
		else:
			_r(r, col)


## Filled pixel ellipse (row spans), optionally dithered.
func _ellipse(c: Vector2, rx: float, ry: float, col: Color, dith := false) -> void:
	c = c.round()
	for dy in range(-int(ry), int(ry) + 1):
		var hw := floorf(rx * sqrt(maxf(1.0 - float(dy * dy) / maxf(ry * ry, 1.0), 0.0)))
		var r := Rect2(c.x - hw, c.y + dy, hw * 2 + 1, 1)
		if dith:
			_d(r, col)
		else:
			_r(r, col)


func _starfield(max_y: float, twinkle := true) -> void:
	for st in _stars:
		var p := STAGE.position + Vector2(st.x, st.y)
		if p.y > max_y:
			continue
		var a := 0.45 + 0.55 * (0.5 + 0.5 * sin(_t * 1.6 + st.z)) if twinkle else 0.8
		_r(Rect2(p, Vector2.ONE), Color(0.9, 0.93, 1.0, a))
		if int(st.z * 10.0) % 9 == 0:   # a few bright ones get a plus shape
			_r(Rect2(p - Vector2(1, 0), Vector2(3, 1)), Color(0.9, 0.93, 1.0, a * 0.5))
			_r(Rect2(p - Vector2(0, 1), Vector2(1, 3)), Color(0.9, 0.93, 1.0, a * 0.5))


## Gale crater at dusk: butterscotch dust sky, but the sky around the Sun turns blue (real: fine dust
## scatters blue light forward; Curiosity photographed it in 2015). Layered ridges, rust ground.
func _bg_mars(s: Rect2) -> void:
	var horizon := s.position.y + 128.0
	_bands(s.position.y, [Color("0b0c1c"), Color("171731"), Color("2c2340"), Color("4a3043"), Color("6e4040"), Color("94573f"), Color("b07448")],
			[30, 24, 20, 18, 14, 12, 10])
	_starfield(s.position.y + 60.0)
	_r(Rect2(s.position.x + 40, s.position.y + 40, 2, 2), Color("c8b8a8"))   # Phobos
	_r(Rect2(s.position.x + 88, s.position.y + 26, 1, 1), Color("d8ccc0"))   # Deimos
	var sun := Vector2(s.position.x + 166, horizon - 9)
	var glow := 0.85 + 0.15 * sin(_t * 0.8)
	_disc(sun, 30, Color("4c6a9a", 0.8 * glow), true)
	_disc(sun, 21, Color("587ab0", glow))
	_disc(sun, 13, Color("86a8d4"))
	_disc(sun, 7, Color("c0d8f0"))
	_disc(sun, 3, Color("f4f8ff"))
	# far ridge (crater rim) then a nearer one, then the plain
	for x in int(s.size.x):
		var fx := s.position.x + x
		var far := horizon - 12.0 - roundf(6.0 * sin(x * 0.045) + 3.0 * sin(x * 0.13 + 1.0))
		_r(Rect2(fx, far, 1, horizon - far), Color("5a2c2c"))
		var near := horizon - roundf(4.0 + 4.0 * sin(x * 0.03 + 2.0) + 1.5 * sin(x * 0.21))
		_r(Rect2(fx, near, 1, horizon - near + 2), Color("743426"))
	_bands(horizon + 2, [Color("7a3622"), Color("8c4026"), Color("9c4a2a"), Color("a8552e")], [10, 14, 22, s.end.y - horizon])
	for rock: Vector3 in [Vector3(26, 168, 4), Vector3(196, 176, 5), Vector3(62, 150, 2), Vector3(150, 146, 2), Vector3(210, 156, 3)]:
		var p := s.position + Vector2(rock.x, rock.y)
		_r(Rect2(p.x - rock.z, p.y - rock.z + 1, rock.z * 2, rock.z), Color("5e2a1c"))
		_r(Rect2(p.x - rock.z + 1, p.y - rock.z, rock.z * 2 - 2, 1), Color("c0704a"))
	_d(Rect2(s.position.x, horizon + 2, s.size.x, 2), Color("c88a5a", 0.6))   # dust haze on the horizon


## Launch pad at night: floodlit rocket on its pad by the service tower, beams in the haze.
func _bg_pad(s: Rect2) -> void:
	var ground := s.position.y + 150.0
	_bands(s.position.y, [Color("04060e"), Color("080c1c"), Color("0e142c"), Color("161e40"), Color("1e2a52")], [40, 34, 32, 26, 18])
	_starfield(s.position.y + 90.0)
	# distant shoreline lights
	for i in 18:
		var lx := s.position.x + 6 + i * 13 + (i * 7) % 5
		_r(Rect2(lx, ground - 3, 1, 1), Color("ffc640") if i % 3 else Color("ff9a3c"))
	# floodlight beams (dithered wedges) from two masts
	for mast: Vector2 in [Vector2(22, 70), Vector2(220, 60)]:
		var top := s.position + mast
		_r(Rect2(top.x, top.y, 2, ground - top.y), Color("2a3044"))
		_r(Rect2(top.x - 3, top.y - 2, 8, 3), Color("ffe8b0"))
		for row in int(ground - top.y):
			var hw := 2.0 + row * 0.35
			var dir := 1.0 if mast.x < 100 else -1.0
			var cx := top.x + dir * row * 0.55
			if row % 2 == 0:
				_d(Rect2(cx - hw, top.y + row, hw * 2, 1), Color(1.0, 0.92, 0.7, 0.10))
	# service tower (lattice) + rocket
	var tx := s.position.x + 190.0
	var ty := s.position.y + 44.0
	_r(Rect2(tx, ty, 18, ground - ty), Color("1a2034"))
	for yy in range(int(ty), int(ground), 8):
		_r(Rect2(tx, yy, 18, 1), Color("3c4664"))
		for k in 8:
			_r(Rect2(tx + 1 + k * 2, yy + k, 1, 1), Color("2e3854"))
	_r(Rect2(tx, ty, 1, ground - ty), Color("3c4664"))
	_r(Rect2(tx + 17, ty, 1, ground - ty), Color("3c4664"))
	_r(Rect2(tx - 2, ty - 4, 22, 4), Color("2a3248"))
	_r(Rect2(tx + 8, ty - 10, 1, 6), Color("3c4664"))
	_r(Rect2(tx + 8, ty - 11, 1, 1), Color("ff5050") if fmod(_t, 1.2) < 0.6 else Color("5a2020"))   # aircraft warning lamp
	var rx := tx - 18.0
	var rtop := s.position.y + 52.0
	_r(Rect2(rx + 2, rtop - 10, 8, 4), Color("dfe3ee"))   # nose cone, stepped
	_r(Rect2(rx + 3, rtop - 14, 6, 4), Color("dfe3ee"))
	_r(Rect2(rx + 4, rtop - 17, 4, 3), Color("dfe3ee"))
	_r(Rect2(rx + 5, rtop - 19, 2, 2), Color("dfe3ee"))
	_r(Rect2(rx, rtop - 6, 12, ground - rtop + 6), Color("dfe3ee"))
	_r(Rect2(rx + 8, rtop - 17, 4, ground - rtop + 17), Color("9aa2b8"))   # shade side
	_r(Rect2(rx, rtop + 20, 12, 3), Color("1a2034"))       # interstage band
	_r(Rect2(rx, rtop + 70, 12, 2), Color("c89a4a"))       # stripe
	_r(Rect2(rx + 12, rtop + 10, 6, 2), Color("3c4664"))   # swing arm to the tower
	# pad deck
	_bands(ground, [Color("2a2e3c"), Color("343a4a"), Color("3c4252")], [6, 20, s.end.y - ground - 26])
	for i in range(0, int(s.size.x), 12):   # hazard stripes on the pad edge
		_r(Rect2(s.position.x + i, ground + 6, 6, 2), Color("ffc640"))
		_r(Rect2(s.position.x + i + 6, ground + 6, 6, 2), Color("0d1124"))
	_d(Rect2(s.position.x + 20, ground + 10, s.size.x - 40, 14), Color(1.0, 0.92, 0.7, 0.12))   # light pool


## Earth from orbit: black sky, the curved limb with its thin blue atmosphere, clouds; a station truss to stand on.
func _bg_earth(s: Rect2) -> void:
	_r(s, Color("03040a"))
	_starfield(s.end.y)
	# Sun with a pixel cross flare
	var sun := s.position + Vector2(196, 50)
	_disc(sun, 9, Color("fff4d0", 0.35), true)
	_disc(sun, 4, Color("fff8e8"))
	_r(Rect2(sun.x - 16, sun.y, 33, 1), Color(1, 0.97, 0.85, 0.6))
	_r(Rect2(sun.x, sun.y - 12, 1, 25), Color(1, 0.97, 0.85, 0.6))
	# Earth: huge disc below the window -> an arc
	var c := s.position + Vector2(70, 380)
	var radius := 262.0
	_disc(c, radius + 5, Color("4fd8ff", 0.5), true)
	_disc(c, radius + 2, Color("8ae8ff"))
	_disc(c, radius, Color("1b4f94"))
	_disc(c, radius - 6, Color("17457f"))
	_disc(c, radius - 26, Color("123a6c"))
	for blob: Vector3 in [Vector3(30, 150, 16), Vector3(64, 160, 10), Vector3(120, 138, 12), Vector3(176, 160, 20), Vector3(210, 132, 8)]:
		var p := s.position + Vector2(blob.x, blob.y)
		if p.distance_to(c) < radius - 4:
			_ellipse(p, blob.z, blob.z * 0.55, Color("3a7a4a"))                       # land: lumpy, squashed by the curve
			_ellipse(p + Vector2(blob.z * 0.6, blob.z * 0.3), blob.z * 0.6, blob.z * 0.4, Color("3a7a4a"))
			_ellipse(p + Vector2(-2, -1), blob.z * 0.45, blob.z * 0.25, Color("7a8a4a"))
	var drift := fmod(_t * 3.0, 40.0)
	for cloud: Vector3 in [Vector3(10, 132, 9), Vector3(90, 142, 7), Vector3(150, 126, 6), Vector3(196, 150, 10), Vector3(48, 170, 8)]:
		var p := s.position + Vector2(cloud.x + drift, cloud.y)
		if p.distance_to(c) < radius - 3:
			_ellipse(p, cloud.z * 1.6, cloud.z * 0.45, Color("e8f0ff", 0.9), true)     # cloud streaks
			_ellipse(p + Vector2(cloud.z * 0.5, 0), cloud.z * 0.8, cloud.z * 0.25, Color("f4f8ff"))
	# station truss + a solar wing to stand on
	var deck := s.end.y - 16.0
	_r(Rect2(s.position.x, deck, s.size.x, 4), Color("8a93b0"))
	_r(Rect2(s.position.x, deck, s.size.x, 1), Color("c8d0e0"))
	_r(Rect2(s.position.x, deck + 4, s.size.x, 12), Color("2a3044"))
	for i in range(0, int(s.size.x), 10):
		_r(Rect2(s.position.x + i, deck + 4, 1, 12), Color("5a6480"))
		for k in 10:
			_r(Rect2(s.position.x + i + k, deck + 4 + k, 1, 1), Color("4a5470"))
	var wing := Rect2(s.position.x + 8, s.position.y + 30, 44, 26)
	_r(wing.grow(1), Color("2a3044"))
	_r(wing, Color("223a7a"))
	for gx in range(0, int(wing.size.x), 6):
		_r(Rect2(wing.position.x + gx, wing.position.y, 1, wing.size.y), Color("101c40"))
	for gy in range(0, int(wing.size.y), 6):
		_r(Rect2(wing.position.x, wing.position.y + gy, wing.size.x, 1), Color("101c40"))
	_r(Rect2(wing.position.x, wing.position.y, wing.size.x, 1), Color("4a6ab8"))
	_r(Rect2(wing.end.x, wing.get_center().y, 20, 2), Color("5a6480"))   # mast


static func _json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text()) if f else null
	return parsed if parsed is Dictionary else {}
