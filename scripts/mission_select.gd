class_name MissionSelect
extends Node2D
## Mars campaign picker (after the Mars card in the level select): three short missions based on
## real NASA missions, all open, numbered in the suggested order, best stars shown.
## Picking one creates the room with a copy of the Mars LevelData whose `mission` is set, so every
## co-op peer gets the mission id with the room info. A/D (or mouse) choose · SPACE fly · ESC back.

const SCENE := "res://scenes/mission_select.tscn"
const LOBBY_SCENE := "res://scenes/lobby.tscn"
const BACK_SCENE := "res://scenes/level_select.tscn"
const PANEL_W := 110.0
const PANEL_Y := 44.0
const PANEL_H := 196.0
# The 4th card: SANDBOX (missions.json "sandbox"). W/S pick a row, SPACE flips a hazard or flies.
const SANDBOX_KEYS := ["storms", "debris", "hull", "conjunction"]
const SANDBOX_NAMES := {storms = "STORMS", debris = "DEBRIS", hull = "HULL+O2", conjunction = "CONJUNCTION"}
const SANDBOX_HINTS := {
	storms = "Radiation storms: shields or safe mode",
	debris = "Comet debris: radar + dodge",
	hull = "Breaches vent air: patch them",
	conjunction = "Sun blocks the radio for a while",
}
const SANDBOX_ROW_Y := 92.0      # first toggle row, from the panel top
const SANDBOX_ROW_H := 17.0

static var level: LevelData          # the Mars card's data (set by the level select)
static var level_number := 1
static var _last := 0

var _ids: Array = []
var _index := 0
var _time := 0.0
var _stars: Array[Vector3] = []
var _saved_window := {}
var _message := ""
var _busy := false
var _row := SANDBOX_KEYS.size()   # sandbox card: 0..3 = hazard switches, 4 = FLY


func _enter_tree() -> void:
	_saved_window = PixelMode.enter(get_window())


func _exit_tree() -> void:
	PixelMode.exit(get_window(), _saved_window)


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ids = Missions.order().duplicate()
	_ids.append(Missions.SANDBOX)
	_index = clampi(_last, 0, maxi(_ids.size() - 1, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 70:
		_stars.append(Vector3(rng.randi_range(0, 479), rng.randi_range(0, 269), rng.randf() * TAU))
	PauseMenu.apply_settings()


func _process(delta: float) -> void:
	_time += delta
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
					_row = wrapi(_row - 1, 0, SANDBOX_KEYS.size() + 1)
					Sfx.play("ui_hover")
			KEY_S, KEY_DOWN:
				if _on_sandbox():
					_row = wrapi(_row + 1, 0, SANDBOX_KEYS.size() + 1)
					Sfx.play("ui_hover")
			KEY_SPACE:
				if _on_sandbox() and _row < SANDBOX_KEYS.size():
					_toggle(SANDBOX_KEYS[_row])
				else:
					_pick()
			KEY_ENTER, KEY_KP_ENTER:
				_pick()
			KEY_ESCAPE:
				_busy = true
				get_tree().change_scene_to_file(BACK_SCENE)
	elif event is InputEventMouseMotion:
		var hit := _panel_at(get_local_mouse_position())
		if hit >= 0 and hit != _index:
			_index = hit
			Sfx.play("ui_hover")
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse := get_local_mouse_position()
		var hit := _panel_at(mouse)
		if hit >= 0:
			_index = hit
			var row := _sandbox_row_at(mouse) if _on_sandbox() else -1
			if row >= 0 and row < SANDBOX_KEYS.size():
				_row = row
				_toggle(SANDBOX_KEYS[row])
			else:
				_pick()


func _move(step: int) -> void:
	_index = wrapi(_index + step, 0, _ids.size())
	Sfx.play("ui_hover")


func _on_sandbox() -> bool:
	return not _ids.is_empty() and _ids[_index] == Missions.SANDBOX


func _toggle(key: String) -> void:
	Missions.offline_options[key] = not bool(Missions.offline_options.get(key, key != "hull"))
	Sfx.play("toggle")


func _sandbox_row_rect(i: int) -> Rect2:
	var r := _panel_rect(_ids.find(Missions.SANDBOX))
	return Rect2(r.position.x + 4, r.position.y + SANDBOX_ROW_Y + i * SANDBOX_ROW_H - 9, r.size.x - 8, SANDBOX_ROW_H - 1)


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
	data.title = str(m.title).capitalize()   # the card shows "МАРС · МИССИЯ n" above it
	data.description = str(m.tagline)
	if data.scene == "":
		data.scene = "res://scenes/design/hangar.tscn"
	var error := Network.create_room(data, level_number)
	if error != OK:
		_message = "Could not create the room: port %d is busy." % Network.DEFAULT_PORT
		Sfx.play("denied")
		return
	Sfx.play("ui_click")
	_busy = true
	get_tree().change_scene_to_file(LOBBY_SCENE)


func _panel_rect(i: int) -> Rect2:
	var n := maxf(float(_ids.size()), 1.0)
	var gap := (480.0 - PANEL_W * n) / (n + 1.0)
	return Rect2(gap + i * (PANEL_W + gap), PANEL_Y, PANEL_W, PANEL_H)


func _panel_at(p: Vector2) -> int:
	for i in _ids.size():
		if _panel_rect(i).has_point(p):
			return i
	return -1


# --- drawing ----------------------------------------------------------------------------

func _draw() -> void:
	var font := UiFont.font()
	draw_rect(Rect2(0, 0, 480, 270), Color("070914"))
	for s in _stars:
		draw_rect(Rect2(s.x, s.y, 1, 1), Color(0.8, 0.85, 1.0, 0.25 + 0.35 * (0.5 + 0.5 * sin(_time * 1.5 + s.z))))
	_centered("MARS CAMPAIGN", 20, 16, Color("ff8a4c"))
	_centered("Three real NASA missions flown by your crew - or a sandbox to experiment.", 34, 8, Color("9aa4c0"))
	for i in _ids.size():
		if _ids[i] == Missions.SANDBOX:
			_draw_sandbox(i)
		else:
			_draw_panel(i)
	var keys := "A/D choose · SPACE fly this mission · ESC back"
	if _on_sandbox():
		keys = "A/D choose · W/S + SPACE switch hazards · ENTER fly · ESC back"
	_centered(keys, 252, 8, Color("ffc640") if fmod(_time, 1.2) < 0.85 else Color("9a8040"))
	if _message != "":
		_centered(_message, 242, 8, Color("ff5050"))


func _draw_panel(i: int) -> void:
	var font := UiFont.font()
	var id: String = _ids[i]
	var m := Missions.mission(id)
	var r := _panel_rect(i)
	var accent := Color(str(m.get("accent", "4fd8ff")))
	var sel := i == _index
	if sel:
		r = r.grow(2)
		draw_rect(r.grow(2), Color(accent, 0.15 + 0.1 * sin(_time * 4.0)))
	draw_rect(r, Color("10142a"))
	draw_rect(r, accent if sel else Color(accent, 0.45), false, 1.0)
	draw_rect(Rect2(r.position, Vector2(r.size.x, 14)), Color(accent, 0.25 if sel else 0.12))
	var x := r.position.x + 7
	draw_string(font, Vector2(x, r.position.y + 10), "MISSION %d" % int(m.number), HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(8), accent)
	var year := str(int(m.year))
	draw_string(font, Vector2(r.end.x - 7 - UiFont.width(year, 8), r.position.y + 10), year, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(8), Color("c8d0e0"))
	# Little Mars with the mission's spacecraft orbiting it.
	var c := Vector2(r.get_center().x, r.position.y + 36)
	draw_circle(c, 14, Color("8c3a1c"))
	draw_circle(c + Vector2(-2, -2), 11, Color("c8602e"))
	draw_circle(c + Vector2(4, 3), 3, Color("8c3a1c"))
	draw_circle(c + Vector2(-6, 5), 2, Color("a84a22"))
	var a := _time * (1.4 if sel else 0.5) + i * 2.0
	var ship := c + Vector2(cos(a) * 22.0, sin(a) * 8.0)
	draw_arc(c, 22.0, 0, TAU, 32, Color(accent, 0.15), 1.0)   # (circle; the ellipse is implied)
	draw_rect(Rect2(ship.round() - Vector2(1, 1), Vector2(3, 3)), Color.WHITE)
	draw_rect(Rect2(ship.round() + Vector2(-4, 0), Vector2(2, 1)), accent)
	draw_rect(Rect2(ship.round() + Vector2(3, 0), Vector2(2, 1)), accent)
	var y := r.position.y + 66
	var title := str(m.title)
	var title_size := 11
	while title_size > 7 and UiFont.width(title, title_size) > r.size.x - 6:
		title_size -= 1
	_center_in(r, title, y, title_size, Color.WHITE)
	y += 11
	var nasa := "NASA: " + str(m.nasa)
	var nasa_size := 7
	while nasa_size > 5 and UiFont.width(nasa, nasa_size) > r.size.x - 6:
		nasa_size -= 1   # long names (Mars Reconnaissance Orbiter) at big TEXT SIZE
	_center_in(r, nasa, y, nasa_size, Color(accent, 0.9))
	y += 13
	for line in _wrap(str(m.tagline), r.size.x - 14, 8):
		draw_string(font, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(8), Color("e8ecf8"))
		y += 9
	y += 4
	draw_string(font, Vector2(x, y), "LESSON", HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(7), Color("6b7390"))
	y += 9
	for line in _wrap(str(m.lesson), r.size.x - 14, 7):
		draw_string(font, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(7), Color("aab4cc"))
		y += 8
	# Best result.
	var best := Missions.best_stars(id)
	for k in 3:
		_star(Vector2(r.get_center().x - 14 + k * 14, r.end.y - 12), k < best, accent)
	var points := Missions.best_score(id)
	if points > 0:
		var pts := "%d PTS" % points
		draw_string(font, Vector2(r.end.x - 6 - UiFont.width(pts, 6), r.end.y - 3), pts, HORIZONTAL_ALIGNMENT_LEFT, -1,
				UiFont.px(6), Color("ffd34a"))


## The SANDBOX card: double budget, no goals; four hazard switches (W/S + SPACE or click) and FLY.
## The switches live in Missions.offline_options and go to every peer with the room (LevelData.options).
func _draw_sandbox(i: int) -> void:
	var font := UiFont.font()
	var m := Missions.mission(Missions.SANDBOX)
	var r := _panel_rect(i)
	var accent := Color(str(m.get("accent", "8cffb0")))
	var sel := i == _index
	if sel:
		r = r.grow(2)
		draw_rect(r.grow(2), Color(accent, 0.15 + 0.1 * sin(_time * 4.0)))
	draw_rect(r, Color("10142a"))
	draw_rect(r, accent if sel else Color(accent, 0.45), false, 1.0)
	draw_rect(Rect2(r.position, Vector2(r.size.x, 14)), Color(accent, 0.25 if sel else 0.12))
	var x := r.position.x + 6
	draw_string(font, Vector2(x, r.position.y + 10), "FREE PLAY", HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(8), accent)
	_center_in(r, str(m.title), r.position.y + 30, 11, Color.WHITE)
	_center_in(r, "BUDGET x%d · NO GOALS" % int(m.get("budget_mult", 1)), r.position.y + 41, 7, Color(accent, 0.9))
	var y := r.position.y + 54
	for line in _wrap(str(m.tagline), r.size.x - 12, 7):
		draw_string(font, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(7), Color("e8ecf8"))
		y += 8
	var opts := Missions.offline_options
	for row in SANDBOX_KEYS.size() + 1:
		var rr := Rect2(r.position.x + 4, r.position.y + SANDBOX_ROW_Y + row * SANDBOX_ROW_H - 9, r.size.x - 8, SANDBOX_ROW_H - 1)
		var hot := sel and row == _row
		if hot:
			draw_rect(rr, Color(accent, 0.18))
			draw_rect(rr, Color(accent, 0.8), false, 1.0)
		if row == SANDBOX_KEYS.size():
			var fly := "FLY SANDBOX >"
			_center_in(rr, fly, rr.position.y + 11, 9, accent if hot else Color(accent, 0.7))
			continue
		var key: String = SANDBOX_KEYS[row]
		var on := bool(opts.get(key, key != "hull"))
		var box := Rect2(rr.position.x + 3, rr.position.y + 4, 6, 6)
		if on:
			draw_rect(box, accent)
		else:
			draw_rect(box, Color(accent, 0.6), false, 1.0)
		draw_string(font, Vector2(rr.position.x + 13, rr.position.y + 10), str(SANDBOX_NAMES[key]), HORIZONTAL_ALIGNMENT_LEFT, -1,
				UiFont.px(8), Color.WHITE if on else Color("6b7390"))
		var state := "ON" if on else "OFF"
		draw_string(font, Vector2(rr.end.x - 3 - UiFont.width(state, 7), rr.position.y + 10), state, HORIZONTAL_ALIGNMENT_LEFT, -1,
				UiFont.px(7), accent if on else Color("6b7390"))
	# What the highlighted switch does, under the rows.
	var hint := "Then ENTER (or FLY) to create the room."
	if sel and _row < SANDBOX_KEYS.size():
		hint = str(SANDBOX_HINTS[SANDBOX_KEYS[_row]])
	y = r.position.y + SANDBOX_ROW_Y + (SANDBOX_KEYS.size() + 1) * SANDBOX_ROW_H + 2
	for line in _wrap(hint, r.size.x - 12, 6):
		draw_string(font, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(6), Color("9aa4c0"))
		y += 7
	var points := Missions.best_score(Missions.SANDBOX)
	if points > 0:
		var pts := "BEST %d PTS" % points
		draw_string(font, Vector2(r.end.x - 6 - UiFont.width(pts, 6), r.end.y - 3), pts, HORIZONTAL_ALIGNMENT_LEFT, -1,
				UiFont.px(6), Color("ffd34a"))


func _star(c: Vector2, full: bool, accent: Color) -> void:
	var pts := PackedVector2Array()
	for k in 10:
		var rr := 5.0 if k % 2 == 0 else 2.2
		var ang := -PI / 2 + k * PI / 5
		pts.append(c + Vector2(cos(ang), sin(ang)) * rr)
	if full:
		draw_colored_polygon(pts, Color("ffd34a"))
	pts.append(pts[0])
	draw_polyline(pts, Color("ffd34a") if full else Color(accent, 0.35), 1.0)


func _centered(text: String, y: float, size: int, col: Color) -> void:
	draw_string(UiFont.font(), Vector2(roundf(240 - UiFont.width(text, size) / 2.0), y), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(size), col)


func _center_in(r: Rect2, text: String, y: float, size: int, col: Color) -> void:
	draw_string(UiFont.font(), Vector2(roundf(r.get_center().x - UiFont.width(text, size) / 2.0), y), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(size), col)


static func _wrap(text: String, max_w: float, size: int) -> PackedStringArray:
	var out := PackedStringArray()
	for paragraph in text.split("\n"):
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
