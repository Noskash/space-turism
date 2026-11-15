class_name MissionSelect
extends Node2D
## Mars campaign picker (after the Mars card in the level select): three short missions based on
## real NASA missions, all open, numbered in the suggested order, best stars shown.
## Picking one creates the room with a copy of the Mars LevelData whose `mission` is set, so every
## co-op peer gets the mission id with the room info. A/D (or mouse) choose · SPACE fly · ESC back.
## Drawn on the UI kit (UiKit + MenuKit): chunky cards, goal / threat chips, keycap hints.

const SCENE := "res://scenes/mission_select.tscn"
const LOBBY_SCENE := "res://scenes/lobby.tscn"
const BACK_SCENE := "res://scenes/level_select.tscn"
const PANEL_W := 110.0
const PANEL_Y := 50.0
const PANEL_H := 158.0
const ACCENT := Color("ff8a4c")
# The 4th card: SANDBOX (missions.json "sandbox"). W/S pick a row, SPACE flips a hazard or flies.
const SANDBOX_KEYS := ["storms", "debris", "hull", "conjunction"]
const SANDBOX_NAMES := {storms = "STORMS", debris = "DEBRIS", hull = "HULL+O2", conjunction = "CONJUNCTION"}
const SANDBOX_ICONS := {storms = "power", debris = "debris", hull = "hull", conjunction = "dsn"}
const SANDBOX_HINTS := {
	storms = "Radiation storms: shields or safe mode",
	debris = "Comet debris: radar + dodge",
	hull = "Breaches vent air: patch them",
	conjunction = "Sun blocks the radio for a while",
}
const SANDBOX_ROW_Y := 66.0      # first toggle row, from the panel top
const SANDBOX_ROW_H := 16.0
const BACK_RECT := Rect2(418, 8, 54, 20)
# Goal kinds -> chip text + icon; threats from the mission's sim flags.
const THREATS := [["storms", "STORMS", "power"], ["debris", "DEBRIS", "debris"], ["hull", "HULL", "hull"]]

static var level: LevelData          # the Mars card's data (set by the level select)
static var level_number := 1
static var _last := 0

var _ids: Array = []
var _index := 0
var _time := 0.0
var _stars: Array = []
var _saved_window := {}
var _message := ""
var _message_t := 0.0
var _busy := false
var _row := SANDBOX_KEYS.size()   # sandbox card: 0..3 = hazard switches, 4 = FLY
var _juice := UiJuice.new()
var _back_hot := false


func _enter_tree() -> void:
	_saved_window = PixelMode.enter(get_window())
	UiFont.max_level = 1   # dense screen: TEXT SIZE stops at LARGE


func _exit_tree() -> void:
	PixelMode.exit(get_window(), _saved_window)
	UiFont.max_level = 2


func _ready() -> void:
	UiKit.setup_canvas(self)
	_ids = Missions.order().duplicate()
	_ids.append(Missions.SANDBOX)
	_index = clampi(_last, 0, maxi(_ids.size() - 1, 0))
	_stars = MenuKit.make_stars(60)
	PauseMenu.apply_settings()
	_juice.kick("sel", 0.35)


func _process(delta: float) -> void:
	_time += delta
	_juice.step(delta)
	if _message_t > 0.0:
		_message_t -= delta
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_A, KEY_LEFT:
				_move(-1)
			KEY_D, KEY_RIGHT:
				_move(1)
			KEY_W, KEY_UP:
				if _on_sandbox():
					_set_row(wrapi(_row - 1, 0, SANDBOX_KEYS.size() + 1))
			KEY_S, KEY_DOWN:
				if _on_sandbox():
					_set_row(wrapi(_row + 1, 0, SANDBOX_KEYS.size() + 1))
			KEY_SPACE:
				if _on_sandbox() and _row < SANDBOX_KEYS.size():
					_toggle(SANDBOX_KEYS[_row])
				else:
					_pick()
			KEY_ENTER, KEY_KP_ENTER:
				_pick()
			KEY_ESCAPE:
				_back()
	elif event is InputEventMouseMotion:
		var mouse := get_local_mouse_position()
		_back_hot = BACK_RECT.has_point(mouse)
		var hit := _panel_at(mouse)
		if hit >= 0 and hit != _index:
			_select(hit)
		if hit >= 0 and _on_sandbox():
			var row := _sandbox_row_at(mouse)
			if row >= 0 and row != _row:
				_set_row(row)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse := get_local_mouse_position()
		if BACK_RECT.has_point(mouse):
			_back()
			return
		var hit := _panel_at(mouse)
		if hit >= 0:
			if hit != _index:
				_select(hit)
			var row := _sandbox_row_at(mouse) if _on_sandbox() else -1
			if row >= 0 and row < SANDBOX_KEYS.size():
				_row = row
				_toggle(SANDBOX_KEYS[row])
			else:
				_pick()


func _move(step: int) -> void:
	_select(wrapi(_index + step, 0, _ids.size()))


func _select(i: int) -> void:
	_index = i
	_juice.kick("sel", 0.3)
	Sfx.play("ui_hover")


func _set_row(row: int) -> void:
	_row = row
	_juice.kick("row", 0.2)
	Sfx.play("ui_hover")


func _back() -> void:
	_busy = true
	Sfx.play("ui_click")
	get_tree().change_scene_to_file(BACK_SCENE)


func _on_sandbox() -> bool:
	return not _ids.is_empty() and _ids[_index] == Missions.SANDBOX


func _toggle(key: String) -> void:
	Missions.offline_options[key] = not bool(Missions.offline_options.get(key, key != "hull"))
	_juice.kick("tog_" + key, 0.3)
	Sfx.play("toggle")


func _sandbox_row_rect(i: int) -> Rect2:
	var r := _panel_rect(_ids.find(Missions.SANDBOX))
	if i == SANDBOX_KEYS.size():   # FLY button
		return Rect2(r.position.x + 6, r.end.y - 25, r.size.x - 12, 19)
	return Rect2(r.position.x + 4, r.position.y + SANDBOX_ROW_Y + i * SANDBOX_ROW_H, r.size.x - 8, SANDBOX_ROW_H - 2)


func _sandbox_row_at(p: Vector2) -> int:
	for i in SANDBOX_KEYS.size() + 1:
		if _sandbox_row_rect(i).has_point(p):
			return i
	return -1


func _pick() -> void:
	if _ids.is_empty():
		return
	var id: String = _ids[_index]
	var m := Missions.mission(id)
	_last = _index
	Missions.offline_id = id
	var data: LevelData = level.duplicate() if level else LevelData.new()
	data.mission = id
	data.options = Missions.offline_options.duplicate() if id == Missions.SANDBOX else {}
	data.title = str(m.title).capitalize()   # the card shows "MARS · MISSION n" above it
	data.description = str(m.tagline)
	if data.scene == "":
		data.scene = "res://scenes/design/hangar.tscn"
	var error := Network.create_room(data, level_number)
	if error != OK:
		_message = "Could not create the room: port %d is busy." % Network.DEFAULT_PORT
		_message_t = 4.0
		_juice.kick("deny", 0.3)
		Sfx.play("denied")
		return
	Sfx.play("ui_click")
	_busy = true
	get_tree().change_scene_to_file(LOBBY_SCENE)


func _panel_rect(i: int) -> Rect2:
	var n := maxf(float(_ids.size()), 1.0)
	var gap := floorf((480.0 - PANEL_W * n) / (n + 1.0))
	var x0 := floorf((480.0 - (PANEL_W * n + gap * (n - 1.0))) / 2.0)
	return Rect2(x0 + i * (PANEL_W + gap), PANEL_Y, PANEL_W, PANEL_H)


func _panel_at(p: Vector2) -> int:
	for i in _ids.size():
		if _panel_rect(i).grow(2).has_point(p):
			return i
	return -1


func _accent(id: String) -> Color:
	return Color(str(Missions.mission(id).get("accent", "4fd8ff")))


# --- drawing ----------------------------------------------------------------------------

func _draw() -> void:
	MenuKit.backdrop(self, "low_right")
	MenuKit.stars(self, _stars, _time)
	MenuKit.title(self, Vector2(8, 6), "MARS CAMPAIGN", "3 REAL NASA MISSIONS FLOWN BY YOUR CREW - OR A SANDBOX", ACCENT, "fly")
	MenuKit.button(self, BACK_RECT, "BACK", UiKit.DIM.lightened(0.3), _back_hot, true, 8)
	for i in _ids.size():
		if i == _index:
			continue
		_draw_card(i)
	_draw_card(_index)   # selected last: its frame and arrow sit on top
	_draw_info()
	var keys := [["A/D", "CHOOSE"], ["SPACE", "FLY THIS MISSION"], ["ESC", "BACK"]]
	if _on_sandbox():
		keys = [["A/D", "CHOOSE"], ["W/S", "HAZARD"], ["SPACE", "SWITCH"], ["ENTER", "FLY"], ["ESC", "BACK"]]
	MenuKit.key_hints(self, 240, 252, keys, 6)
	if _message != "" and _message_t > 0.0:
		MenuKit.toast(self, 240 + _juice.shake("deny").x, 246, _message, UiKit.BAD, clampf(_message_t * 4.0, 0.0, 1.0))


func _draw_card(i: int) -> void:
	var id: String = _ids[i]
	var sel := i == _index
	var r := _panel_rect(i)
	var accent := _accent(id)
	if sel:
		r.position.y += -3.0 + _juice.bounce("sel", 3.0)
		UiKit.frame(self, r.grow(2), accent, UiKit.PANEL)
		MenuKit.arrow_down(self, Vector2(r.get_center().x, r.position.y - 3), accent, _time)
	else:
		UiKit.panel(self, r, UiKit.PANEL_DARK, accent.darkened(0.35))
	if id == Missions.SANDBOX:
		_draw_sandbox(r, accent, sel)
	else:
		_draw_mission(r, id, accent, sel, i)


## Header strip: label chip left, `right` text right.
func _header(r: Rect2, label: String, right: String, accent: Color, sel: bool) -> void:
	var strip := Rect2(r.position.x + 3, r.position.y + 3, r.size.x - 6, 13)
	draw_rect(strip, accent.darkened(0.55 if sel else 0.72))
	draw_rect(Rect2(strip.position.x, strip.end.y, strip.size.x, 1), UiKit.INK)
	UiKit.text(self, Vector2(strip.position.x + 3, strip.end.y - 3), label, 7, accent if sel else accent.darkened(0.2), 0)
	if right != "":
		UiKit.text_r(self, strip.end.x - 3, strip.end.y - 3, right, 7, UiKit.TEXT if sel else UiKit.DIM, 0)


func _draw_mission(r: Rect2, id: String, accent: Color, sel: bool, i: int) -> void:
	var m := Missions.mission(id)
	_header(r, "MISSION %d" % int(m.number), str(int(m.year)), accent, sel)
	# Little pixel Mars with the mission's spacecraft on a dotted orbit (back half behind it).
	var c := Vector2(roundf(r.get_center().x), r.position.y + 31)
	var a := _time * (1.3 if sel else 0.4) + i * 2.0
	_orbit(c, accent, a, false, sel)
	var tex := MenuKit.mars_tex(10)
	draw_texture(tex, c - Vector2(10, 10))
	_orbit(c, accent, a, true, sel)
	var y := r.position.y + 54
	var title := str(m.title)
	var title_size := 10
	while title_size > 7 and UiKit.text_w(title, title_size) > r.size.x - 8:
		title_size -= 1
	UiKit.text_c(self, r.get_center().x, y, title, title_size, UiKit.TEXT if sel else UiKit.TEXT.darkened(0.15), 2)
	y += 8
	var nasa := "NASA: " + str(m.nasa)
	var nasa_size := 6
	while nasa_size > 5 and UiKit.text_w(nasa, nasa_size) > r.size.x - 6:
		nasa_size -= 1
	UiKit.text_c(self, r.get_center().x, y, UiKit.fit(nasa, nasa_size, r.size.x - 6), nasa_size, accent, 0)
	var lines := UiKit.wrap(str(m.tagline), 6, r.size.x - 12)
	for line in lines.slice(0, 4):
		y += UiKit.line_h(6)
		UiKit.text(self, Vector2(r.position.x + 6, y), line, 6, Color("d8deee") if sel else UiKit.DIM, 0)
	# Goals + threats as chips.
	y = maxf(r.position.y + 99, y + 4)
	UiKit.text(self, Vector2(r.position.x + 6, y + 4), "GOALS", 5, UiKit.FAINT.lightened(0.25), 0)
	var chips: Array = []
	for g: Dictionary in m.get("goals", []):
		chips.append(_goal_chip(g))
	y = _chip_flow(r, y + 6, chips, UiKit.GOOD if sel else UiKit.GOOD.darkened(0.3)) + 1
	var sim: Dictionary = m.get("sim", {})
	var threats: Array = []
	for t: Array in THREATS:
		if bool(sim.get(t[0], false)):
			threats.append(["", t[2]])
	if float(sim.get("conjunction_at", -1)) >= 0.0:
		threats.append(["", "dsn"])
	if float(sim.get("big_storm_at", -1)) >= 0.0:
		threats.append(["BIG", "power"])
	var label_w := UiKit.text_w("THREATS", 5) + 4
	UiKit.text(self, Vector2(r.position.x + 6, y + 7), "THREATS", 5, UiKit.FAINT.lightened(0.25), 0)
	var tx := r.position.x + 6 + label_w
	for t: Array in threats:
		var tr := MenuKit.tag(self, Vector2(tx, y), t[0], UiKit.WARN if sel else UiKit.WARN.darkened(0.3), t[1], 5)
		tx = tr.end.x + 2
	# Best result: three pixel stars + points.
	var best := Missions.best_stars(id)
	var sy := r.end.y - 9
	for k in 3:
		MenuKit.pixel_star(self, Vector2(r.position.x + 11 + k * 11, sy), k < best, accent.darkened(0.3))
	var points := Missions.best_score(id)
	if points > 0:
		var pts := "%d PTS" % points
		MenuKit.tag(self, Vector2(r.end.x - 5 - MenuKit.tag_w(pts, "", 5), sy - 5), pts, Color("ffd34a"), "", 5)


func _goal_chip(g: Dictionary) -> Array:
	var target := int(g.get("target", 0))
	match str(g.get("kind", "")):
		"storms_recorded":
			return ["STORM x%d" % target, "power"]
		"science_sent":
			return ["SEND %d" % target, "sent"]
		"science_lost_max":
			return ["LOSE <%d" % target, "lost"]
		"orbit":
			return ["ORBIT", "mars"]
	return [str(g.get("kind", "?")).to_upper(), ""]


## Lays chips out left to right, wrapping inside the card. Returns the y under the last row.
func _chip_flow(r: Rect2, y: float, chips: Array, col: Color) -> float:
	var x := r.position.x + 5
	var h := 10.0
	for chip: Array in chips:
		var w := MenuKit.tag_w(chip[0], chip[1], 5)
		if x + w > r.end.x - 5 and x > r.position.x + 5:
			x = r.position.x + 5
			y += h + 1
		MenuKit.tag(self, Vector2(x, y), chip[0], col, chip[1], 5)
		x += w + 2
	return y + h + 1


## Half of a dotted orbit ellipse (front = lower half, drawn over the planet) + the ship on it.
func _orbit(c: Vector2, accent: Color, a: float, front: bool, sel: bool) -> void:
	var rx := 21.0
	var ry := 7.0
	for k in 28:
		var t := k * TAU / 28.0
		if (sin(t) > 0.0) != front:
			continue
		draw_rect(Rect2((c + Vector2(cos(t) * rx, sin(t) * ry)).round(), Vector2(1, 1)), Color(accent, 0.55 if sel else 0.3))
	if (sin(a) > 0.0) == front:
		var p := (c + Vector2(cos(a) * rx, sin(a) * ry)).round()
		draw_rect(Rect2(p - Vector2(2, 2), Vector2(5, 5)), UiKit.INK)
		draw_rect(Rect2(p - Vector2(1, 1), Vector2(3, 3)), Color.WHITE)
		draw_rect(Rect2(p + Vector2(-5, 0), Vector2(3, 1)), accent)
		draw_rect(Rect2(p + Vector2(3, 0), Vector2(3, 1)), accent)


## The SANDBOX card: double budget, no goals; four hazard switches (W/S + SPACE or click) and FLY.
## The switches live in Missions.offline_options and go to every peer with the room (LevelData.options).
func _draw_sandbox(r: Rect2, accent: Color, sel: bool) -> void:
	var m := Missions.mission(Missions.SANDBOX)
	_header(r, "FREE PLAY", "", accent, sel)
	var lift := r.position.y - PANEL_Y   # rows follow the card's lift
	UiKit.text_c(self, r.get_center().x, r.position.y + 30, str(m.title), 10, UiKit.TEXT, 2)
	var t1 := "BUDGET x%d" % int(m.get("budget_mult", 1))
	var t2 := "NO GOALS"
	var tw := MenuKit.tag_w(t1, "", 5) + 2 + MenuKit.tag_w(t2, "", 5)
	var tx := roundf(r.get_center().x - tw / 2.0)
	MenuKit.tag(self, Vector2(tx, r.position.y + 35), t1, Color("ffd34a"), "", 5)
	MenuKit.tag(self, Vector2(tx + MenuKit.tag_w(t1, "", 5) + 2, r.position.y + 35), t2, accent, "", 5)
	var y := r.position.y + 51
	for line in UiKit.wrap("Flip hazards on and off: what does each design survive?", 5, r.size.x - 12).slice(0, 2):
		UiKit.text(self, Vector2(r.position.x + 6, y), line, 5, Color("d8deee") if sel else UiKit.DIM, 0)
		y += UiKit.line_h(5)
	var opts := Missions.offline_options
	for row in SANDBOX_KEYS.size():
		var rr := _sandbox_row_rect(row)
		rr.position.y += lift
		var key: String = SANDBOX_KEYS[row]
		var on := bool(opts.get(key, key != "hull"))
		var hot := sel and row == _row
		var dx := _juice.shake("tog_" + key).x
		rr.position.x += dx
		if hot:
			UiKit.panel(self, rr, UiKit.PANEL.lightened(0.06), accent)
		else:
			draw_rect(rr.grow(-1), Color(UiKit.WELL, 0.6))
		var col := UiKit.TEXT if on else UiKit.FAINT.lightened(0.2)
		UiKit.icon(self, SANDBOX_ICONS[key], Vector2(rr.position.x + 3, roundf(rr.get_center().y - 4)), 1, accent if on else UiKit.FAINT)
		UiKit.text(self, Vector2(rr.position.x + 14, rr.end.y - 4), SANDBOX_NAMES[key], 6, col, 0)
		MenuKit.toggle(self, Vector2(rr.end.x - 20, roundf(rr.get_center().y - 4)), on, accent)
	var fly := _sandbox_row_rect(SANDBOX_KEYS.size())
	fly.position.y += lift
	MenuKit.button(self, fly, "FLY SANDBOX", accent, sel and _row == SANDBOX_KEYS.size(), true, 7, "", 0.0)
	var points := Missions.best_score(Missions.SANDBOX)
	if points > 0:
		var pts := "BEST %d PTS" % points
		MenuKit.tag(self, Vector2(roundf(r.get_center().x - MenuKit.tag_w(pts, "", 5) / 2.0), fly.position.y - 12), pts, Color("ffd34a"), "", 5)


## Strip under the cards: the selected mission's lesson (or what the hot sandbox switch does).
func _draw_info() -> void:
	var id: String = _ids[_index]
	var m := Missions.mission(id)
	var accent := _accent(id)
	var r := Rect2(8, 214, 464, 26)
	UiKit.panel(self, r, UiKit.PANEL_DARK, accent)
	var label := "LESSON"
	var body := str(m.get("lesson", ""))
	if id == Missions.SANDBOX and _row < SANDBOX_KEYS.size():
		label = SANDBOX_NAMES[SANDBOX_KEYS[_row]]
		body = str(SANDBOX_HINTS[SANDBOX_KEYS[_row]]) + ". " + str(m.get("lesson", ""))
	elif id == Missions.SANDBOX:
		label = "FLY"
		body = "ENTER (or click FLY) creates the room with these hazards. " + str(m.get("lesson", ""))
	var chip := MenuKit.tag(self, Vector2(r.position.x + 5, r.position.y + 5), label, accent, "", 6, true)
	var x := chip.end.x + 6
	var lines := UiKit.wrap(body, 6, r.end.x - 6 - x)
	var y := r.position.y + 4 + UiKit.ascent(6) + 2
	if lines.size() == 1:
		y += 5
	for line in lines.slice(0, 2):
		UiKit.text(self, Vector2(x, y), line, 6, UiKit.TEXT, 0)
		y += UiKit.line_h(6) + 1


## Word wrap at a base size (used by the briefing, codex, launch + mission reports).
static func _wrap(text: String, max_w: float, size: int) -> PackedStringArray:
	var out := PackedStringArray()
	for paragraph in text.split("
"):
		var line := ""
		for word in paragraph.split(" "):
			var test := word if line == "" else line + " " + word
			if UiFont.width(test, size) > max_w and line != "":
				out.append(line)
				line = word
			else:
				line = test
		out.append(line)
	return out
