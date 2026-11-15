class_name Codex
extends CanvasLayer
## In-game encyclopedia of the real terms the game uses (data/codex.json): J anywhere in the
## designer / launch / cruise (attached by PauseMenu.attach), or CODEX in the ESC menu.
## Terms unlock when something first mentions them (briefing pages, event walkthroughs, the report):
## `Codex.unlock(["dsn", ...])` saves them in user://codex.cfg, marks them NEW and shows a toast.
## Locked terms show as "???" so players see there is more to find.
## Alone the game pauses while it is open; in co-op only this player's input is blocked.

const PATH := "res://data/codex.json"
const SAVE := "user://codex.cfg"
const ACCENT := Color("8cffb0")
const BOX := Rect2(28, 22, 424, 226)
const LIST_W := 140.0
const ROW := 9.0

static var _data := {}
static var _instance: Codex

var _rows: Array = []          # [{cat} | {id}] in display order
var _index := 0                # selected row (always a term row)
var _scroll := 0
var _canvas: Node2D
var _time := 0.0
var _toast := ""
var _toast_left := 0.0
var _paused := false


static func attach(scene: Node) -> Codex:
	var c := Codex.new()
	c.name = "Codex"
	scene.add_child(c)
	return c


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(f.get_as_text()) if f else null
		_data = parsed if parsed is Dictionary else {terms = {}, categories = []}
	return _data


static func term(id: String) -> Dictionary:
	return data().terms.get(id, {})


static func is_unlocked(id: String) -> bool:
	var cfg := ConfigFile.new()
	cfg.load(SAVE)
	return cfg.get_value("unlocked", id, false)


## Unlock terms (unknown ids are ignored); new ones get a NEW marker and a toast.
static func unlock(ids: Array) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE)
	var fresh: Array[String] = []
	for id: String in ids:
		if term(id).is_empty() or cfg.get_value("unlocked", id, false):
			continue
		cfg.set_value("unlocked", id, true)
		cfg.set_value("new", id, true)
		fresh.append(id)
	if fresh.is_empty():
		return
	cfg.save(SAVE)
	if _instance:
		var names := fresh.map(func(id: String) -> String: return str(term(id).name))
		_instance._show_toast("NEW IN CODEX: %s  [J]" % ", ".join(names))


func _ready() -> void:
	layer = 28
	process_mode = Node.PROCESS_MODE_ALWAYS
	_instance = self
	_canvas = Node2D.new()
	_canvas.draw.connect(_draw_codex)
	add_child(_canvas)


func _exit_tree() -> void:
	if _instance == self:
		_instance = null
	if is_open():
		close()


func is_open() -> bool:
	return _rows.size() > 0


func open() -> void:
	if is_open():
		return
	_build_rows()
	# Start on a NEW find, else the first unlocked term, else the top.
	var unlocked := -1
	var fresh := -1
	for i in _rows.size():
		var id := str(_rows[i].get("id", ""))
		if id == "" or not is_unlocked(id):
			continue
		unlocked = i if unlocked < 0 else unlocked
		if fresh < 0 and _is_new(id):
			fresh = i
	_index = fresh if fresh >= 0 else (unlocked if unlocked >= 0 else _first_term(0, 1))
	_scroll = 0
	Tutorial.hold(true)
	if not Network.is_in_room() or Network.players.size() <= 1:
		_paused = not get_tree().paused
		if _paused:
			get_tree().paused = true
			Sfx.pause_loops(true)
	Sfx.play("page")


func close() -> void:
	if not is_open():
		return
	_mark_seen()
	_rows = []
	Tutorial.hold(false)
	if _paused:
		get_tree().paused = false
		Sfx.pause_loops(false)
		_paused = false
	Sfx.play("ui_click")


func _build_rows() -> void:
	_rows = []
	var terms: Dictionary = data().terms
	for cat: String in data().get("categories", []):
		var ids := terms.keys().filter(func(id: String) -> bool: return terms[id].cat == cat)
		if ids.is_empty():
			continue
		_rows.append({cat = cat})
		for id: String in ids:
			_rows.append({id = id})


func _first_term(from: int, step: int) -> int:
	var i := from
	for n in _rows.size():
		if _rows[wrapi(i, 0, _rows.size())].has("id"):
			return wrapi(i, 0, _rows.size())
		i += step
	return 0


static func _is_new(id: String) -> bool:
	var cfg := ConfigFile.new()
	cfg.load(SAVE)
	return cfg.get_value("new", id, false)


func _selected_id() -> String:
	return str(_rows[_index].get("id", "")) if _index < _rows.size() else ""


func _mark_seen() -> void:
	var id := _selected_id()
	if id == "" or not is_unlocked(id):
		return
	var cfg := ConfigFile.new()
	cfg.load(SAVE)
	if cfg.get_value("new", id, false):
		cfg.set_value("new", id, false)
		cfg.save(SAVE)


func _show_toast(text: String) -> void:
	_toast = text
	_toast_left = 3.5
	Sfx.play("select", 1.6)


func _process(delta: float) -> void:
	_time += delta
	_toast_left = maxf(_toast_left - delta, 0.0)
	_canvas.queue_redraw()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if not is_open():
		# J opens it, unless another overlay (tutorial dialog, ESC menu, minigame) has the input.
		if event.physical_keycode == KEY_J and (not Tutorial.is_blocking() or _over_reading_screen()):
			open()
			get_viewport().set_input_as_handled()
		return
	match event.physical_keycode:
		KEY_J, KEY_ESCAPE, KEY_Q:
			close()
		KEY_W, KEY_UP:
			_move(-1)
		KEY_S, KEY_DOWN:
			_move(1)
	get_viewport().set_input_as_handled()


## The briefing / mission report block gameplay input, but the Codex may open over them
## (they list the terms they just unlocked).
func _over_reading_screen() -> bool:
	var b := get_parent().get_node_or_null("Briefing") as MissionBriefing
	var r := get_parent().get_node_or_null("MissionReport") as MissionReport
	return (b != null and b.is_open()) or (r != null and r.visible)


func _move(step: int) -> void:
	_mark_seen()
	_index = _first_term(_index + step, step)
	Sfx.play("ui_hover")


# --- drawing ------------------------------------------------------------------------------

func _draw_codex() -> void:
	var font := UiFont.font()
	if _toast_left > 0.0:
		var a := clampf(_toast_left / 0.5, 0.0, 1.0)
		var w := UiFont.width(_toast, 8)
		var r := Rect2(240 - w / 2.0 - 6, 60, w + 12, 13)   # under the HUD banner + toast rows
		_canvas.draw_rect(r, Color(0.02, 0.06, 0.04, 0.85 * a))
		_canvas.draw_rect(r, Color(ACCENT, a), false, 1.0)
		_canvas.draw_string(font, r.position + Vector2(6, 10), _toast, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(8), Color(ACCENT, a))
	if not is_open():
		return
	var cfg := ConfigFile.new()
	cfg.load(SAVE)
	_canvas.draw_rect(Rect2(0, 0, 480, 270), Color(0.01, 0.02, 0.05, 0.78))
	_canvas.draw_rect(BOX.grow(2), Color(0, 0, 0, 0.6))
	_canvas.draw_rect(BOX, Color("0c1420"))
	_canvas.draw_rect(BOX, ACCENT, false, 1.0)
	_canvas.draw_rect(Rect2(BOX.position, Vector2(BOX.size.x, 15)), Color("12301e"))
	var unlocked := 0
	for id: String in data().terms:
		unlocked += 1 if cfg.get_value("unlocked", id, false) else 0
	_canvas.draw_string(font, BOX.position + Vector2(8, 11), "CODEX - SPACE TERMS", HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(9), ACCENT)
	var count := "%d / %d FOUND" % [unlocked, data().terms.size()]
	_canvas.draw_string(font, Vector2(BOX.end.x - 8 - UiFont.width(count, 7), BOX.position.y + 11), count,
			HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(7), Color("6b9a7a"))
	# List (scrolled so the selection stays visible).
	var top := BOX.position.y + 22.0
	var row_h := maxf(ROW, UiFont.px(8) + 1.0)   # grows with the TEXT SIZE setting
	var visible_rows := int((BOX.size.y - 36.0) / row_h)
	if _index < _scroll:
		_scroll = _index
	elif _index >= _scroll + visible_rows:
		_scroll = _index - visible_rows + 1
	for i in range(_scroll, mini(_scroll + visible_rows, _rows.size())):
		var row: Dictionary = _rows[i]
		var y := top + (i - _scroll) * row_h
		if row.has("cat"):
			_canvas.draw_string(font, Vector2(BOX.position.x + 6, y + 7), str(row.cat), HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(7), Color("6b9a7a"))
			continue
		var id: String = row.id
		var found := bool(cfg.get_value("unlocked", id, false))
		var sel := i == _index
		if sel:
			_canvas.draw_rect(Rect2(BOX.position.x + 4, y - 1, LIST_W - 4, row_h), Color(ACCENT, 0.15))
		var label := str(term(id).name) if found else "???"
		var col := (Color("ffc640") if sel else Color("dfe8e0")) if found else Color("4a5a50")
		var new_x := BOX.position.x + LIST_W - 2 - UiFont.width("NEW", 6)
		_canvas.draw_string(font, Vector2(BOX.position.x + 12, y + 7), label, HORIZONTAL_ALIGNMENT_LEFT, new_x - BOX.position.x - 14, UiFont.px(8), col)
		if found and cfg.get_value("new", id, false):
			_canvas.draw_string(font, Vector2(new_x, y + 7), "NEW", HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(6),
					Color("ff8a5c") if fmod(_time, 0.8) < 0.5 else Color("a05a3c"))
	_canvas.draw_line(Vector2(BOX.position.x + LIST_W + 4, top - 2), Vector2(BOX.position.x + LIST_W + 4, BOX.end.y - 14),
			Color(ACCENT, 0.3))
	# Entry.
	var x := BOX.position.x + LIST_W + 12
	var w := BOX.end.x - x - 8
	var sel_id := _selected_id()
	var t := term(sel_id)
	var y := top + 8
	if sel_id != "" and cfg.get_value("unlocked", sel_id, false):
		_canvas.draw_string(font, Vector2(x, y), str(t.name).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(11), Color.WHITE)
		y += 16
		for line in MissionSelect._wrap(str(t.body), w, 8):
			_canvas.draw_string(font, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(8), Color("e0e8e4"))
			y += 10
		y += 8
		_canvas.draw_string(font, Vector2(x, y), "IN THE GAME", HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(7), ACCENT)
		y += 10
		for line in MissionSelect._wrap(str(t.get("game", "")), w, 8):
			_canvas.draw_string(font, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(8), Color("b8e8c8"))
			y += 10
	else:
		_canvas.draw_string(font, Vector2(x, y), "NOT FOUND YET", HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(11), Color("4a5a50"))
		y += 16
		for line in MissionSelect._wrap("Read mission briefings and survive events to unlock this term.", w, 8):
			_canvas.draw_string(font, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(8), Color("6b7a70"))
			y += 10
	var keys := "W/S browse · J / Q / ESC close"
	_canvas.draw_string(font, Vector2(BOX.end.x - 8 - UiFont.width(keys, 7), BOX.end.y - 5), keys,
			HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(7), Color("6b7390"))
