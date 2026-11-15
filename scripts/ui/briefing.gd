class_name MissionBriefing
extends CanvasLayer
## Mission briefing (data/missions.json "briefing"): a few pages before the designer - the real NASA
## mission, your goals, what will go wrong, crew jobs, design tips. Each page unlocks its Codex terms
## (listed at the bottom: J opens the Codex). Shown automatically the first time a mission is
## flown (campaign.cfg [briefed]); MISSION BRIEFING in the ESC menu reopens it.
## Every co-op player reads it on their own screen; gameplay input is blocked meanwhile.
## Keys: SPACE / D next · A back · ESC close. Mouse works on the buttons.

signal closed

const BOX := Rect2(40, 24, 400, 222)

var _mission := {}
var _pages: Array = []
var _index := -1
var _canvas: Node2D
var _time := 0.0
var _buttons := {}
var _hover := ""
var _paused := false        # this briefing paused the tree (solo)


static func attach(scene: Node) -> MissionBriefing:
	var b := MissionBriefing.new()
	b.name = "Briefing"
	scene.add_child(b)
	return b


static func was_shown(id: String) -> bool:
	var cfg := ConfigFile.new()
	cfg.load(Missions.SAVE)
	return cfg.get_value("briefed", id, false)


func _ready() -> void:
	layer = 21
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Node2D.new()
	_canvas.draw.connect(_draw_briefing)
	add_child(_canvas)
	visible = false


func is_open() -> bool:
	return _index >= 0


func open() -> void:
	_mission = Missions.current()
	_pages = _mission.get("briefing", [])
	if is_open() or _pages.is_empty():
		return
	_index = 0
	visible = true
	Tutorial.hold(true)
	# Alone, reading pauses everything (like the Codex): the sim must not run on while you read.
	if not Network.is_in_room() or Network.players.size() <= 1:
		_paused = not get_tree().paused
		if _paused:
			get_tree().paused = true
			Sfx.pause_loops(true)
	_page_opened()


func _exit_tree() -> void:
	if is_open():   # scene changed under us (room closed...): never leave input blocked
		_release()


func _release() -> void:
	Tutorial.hold(false)
	if _paused:
		get_tree().paused = false
		Sfx.pause_loops(false)
		_paused = false


func _close() -> void:
	if not is_open():
		return
	var cfg := ConfigFile.new()
	cfg.load(Missions.SAVE)
	cfg.set_value("briefed", Missions.current_id(), true)
	cfg.save(Missions.SAVE)
	_index = -1
	visible = false
	_release()
	Sfx.play("ui_click")
	closed.emit()


func _page_opened() -> void:
	Sfx.play("page")
	Codex.unlock(_pages[_index].get("terms", []))


func _go(step: int) -> void:
	if step > 0 and _index >= _pages.size() - 1:
		_close()
		return
	var to := clampi(_index + step, 0, _pages.size() - 1)
	if to != _index:
		_index = to
		_page_opened()


func _process(delta: float) -> void:
	_time += delta
	if is_open():
		_canvas.queue_redraw()


func _input(event: InputEvent) -> void:
	if not is_open():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_D, KEY_RIGHT:
				_go(1)
			KEY_A, KEY_LEFT:
				_go(-1)
			KEY_ESCAPE, KEY_Q:
				_close()
			KEY_J:
				return   # let the Codex open over the briefing
	elif event is InputEventMouseMotion:
		_hover = _button_at(_canvas.get_local_mouse_position())
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		match _button_at(_canvas.get_local_mouse_position()):
			"next":
				_go(1)
			"back":
				_go(-1)
	if event is InputEventKey or event is InputEventMouseButton:
		get_viewport().set_input_as_handled()


func _button_at(p: Vector2) -> String:
	for id: String in _buttons:
		if (_buttons[id] as Rect2).has_point(p):
			return id
	return ""


# --- drawing ------------------------------------------------------------------------------

func _draw_briefing() -> void:
	if not is_open():
		return
	var c := _canvas
	var font := UiFont.font()
	var accent := Color(str(_mission.get("accent", "4fd8ff")))
	var page: Dictionary = _pages[_index]
	c.draw_rect(Rect2(0, 0, 480, 270), Color(0.01, 0.02, 0.05, 0.82))
	c.draw_rect(BOX.grow(2), Color(0, 0, 0, 0.6))
	c.draw_rect(BOX, Color("0e1224"))
	c.draw_rect(BOX, accent, false, 1.0)
	# Header: mission number, NASA mission, title.
	c.draw_rect(Rect2(BOX.position, Vector2(BOX.size.x, 30)), Color(accent, 0.14))
	var x := BOX.position.x + 10
	c.draw_string(font, Vector2(x, BOX.position.y + 11), "MISSION %d BRIEFING  ·  BASED ON NASA'S %s (%d)" % [
			int(_mission.number), str(_mission.nasa).to_upper(), int(_mission.year)], HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(7), Color(accent, 0.9))
	c.draw_string(font, Vector2(x, roundf(BOX.position.y + 14 + UiFont.px(14) * 0.8)), str(_mission.title), HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(14), Color.WHITE)
	var pg := "%d/%d" % [_index + 1, _pages.size()]
	c.draw_string(font, Vector2(BOX.end.x - 10 - UiFont.width(pg, 8), BOX.position.y + 25), pg, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(8), Color("6b7390"))
	# Page title + small Mars.
	var y := BOX.position.y + 46
	c.draw_string(font, Vector2(x, y), str(page.title).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(10), accent)
	var mars := Vector2(BOX.end.x - 34, BOX.position.y + 58)
	c.draw_circle(mars, 16, Color("8c3a1c"))
	c.draw_circle(mars + Vector2(-3, -3), 12, Color("c8602e"))
	c.draw_circle(mars + Vector2(4, 5), 3, Color("8c3a1c"))
	var a := _time * 0.8
	c.draw_rect(Rect2((mars + Vector2(cos(a) * 24, sin(a) * 8)).round(), Vector2(2, 2)), Color.WHITE)
	y += 16
	var w := BOX.size.x - 70.0
	if str(page.body) == "GOALS":
		for g: Dictionary in _mission.get("goals", []):
			c.draw_rect(Rect2(x + 2, y - 6, 6, 6), accent, false, 1.0)
			for line in MissionSelect._wrap(Missions.goal_text(g), w - 14, 9):
				c.draw_string(font, Vector2(x + 14, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(9), Color.WHITE)
				y += 11
			y += 4
		y += 4
		for line in MissionSelect._wrap("Each goal met = 1 star. The goals stay at the top of the screen during the flight. The mission ends when you brake into Mars orbit (or miss it).", w, 8):
			c.draw_string(font, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(8), Color("aab4cc"))
			y += 10
		y += 6
		for line in MissionSelect._wrap("LESSON: " + str(_mission.lesson), w, 8):
			c.draw_string(font, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(8), accent)
			y += 10
	else:
		for line in MissionSelect._wrap(str(page.body), w, 8):
			c.draw_string(font, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(8), Color("e8ecf8"))
			y += 10
	# Terms this page unlocked.
	var terms: Array = page.get("terms", [])
	if not terms.is_empty():
		var names := terms.map(func(id: String) -> String: return str(Codex.term(id).get("name", id)))
		var text := "TERMS: " + ", ".join(names) + "   (J: CODEX)"
		c.draw_string(font, Vector2(x, BOX.end.y - 26), text, HORIZONTAL_ALIGNMENT_LEFT, BOX.size.x - 20, UiFont.px(7), Color("8cffb0"))
	# Buttons.
	var by := BOX.end.y - 17
	var next_text := ("TO THE DESIGNER" if _index == _pages.size() - 1 else "NEXT >") + " [SPACE]"
	var back_text := "< BACK [A]"
	_buttons = {
		next = Rect2(BOX.end.x - 10 - UiFont.width(next_text, 8) - 8, by, UiFont.width(next_text, 8) + 8, 12),
	}
	if _index > 0:
		_buttons.back = Rect2(x - 2, by, UiFont.width(back_text, 8) + 8, 12)
	_button("next", next_text, Color("ffc640"))
	if _index > 0:
		_button("back", back_text, Color("9aa4b8"))


func _button(id: String, text: String, color: Color) -> void:
	var r: Rect2 = _buttons[id]
	var hot := _hover == id or (id == "next" and fmod(_time, 1.2) < 0.8)
	_canvas.draw_rect(r, Color(color, 0.18 if hot else 0.08))
	_canvas.draw_rect(r, Color(color, 0.9 if hot else 0.5), false, 1.0)
	_canvas.draw_string(UiFont.font(), r.position + Vector2(4, 9), text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(8), color)
