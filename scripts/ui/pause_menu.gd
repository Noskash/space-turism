class_name PauseMenu
extends CanvasLayer
## ESC menu for gameplay screens (designer, launch, cruise): RESUME · HOW TO PLAY · SOUND ·
## FULLSCREEN · LEAVE · QUIT. Alone (offline, or the only player in a room) the whole game pauses:
## tree, sounds, music. With 2+ players the game only pauses once EVERY player has the menu open
## (the host counts who is paused and tells everyone); until then it keeps running and only this
## player's input is blocked.
## Leave / quit ask for a second press. Settings live in user://settings.cfg.

const SETTINGS := "user://settings.cfg"
const MENU_SCENE := "res://scenes/main_menu.tscn"
const VOLUMES := [0.0, -6.0, -14.0, -80.0]           # dB on the Master bus
const VOLUME_NAMES := ["100%", "70%", "40%", "OFF"]
const ACCENT := Color("4fd8ff")
const W := 190.0

var leave_label := "LEAVE TO MAIN MENU"
var _items: Array[String] = []
var _index := 0
var _confirm := ""        # item waiting for its second press
var _canvas: Node2D
var _time := 0.0
var _rows := {}           # item -> Rect2, for the mouse
var _paused_tree := false
var _paused_peers := {}   # host: peer id -> menu open
var _pause_count := Vector2i.ZERO   # (paused, players) as last told by the host


static func attach(scene: Node, leave_text := "LEAVE TO MAIN MENU") -> PauseMenu:
	var m := PauseMenu.new()
	m.name = "PauseMenu"
	m.leave_label = leave_text
	scene.add_child(m)
	Codex.attach(scene)   # J / CODEX item: the encyclopedia is on every gameplay screen
	return m


## Applies saved volume / fullscreen; called once from the main menu or any screen.
static func apply_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	_set_volume(int(cfg.get_value("audio", "volume", 0)))


static func _set_volume(level: int) -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, VOLUMES[level])
	AudioServer.set_bus_mute(bus, level == VOLUMES.size() - 1)


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Node2D.new()
	_canvas.draw.connect(_draw_menu)
	add_child(_canvas)
	visible = false
	apply_settings()
	if Network.is_in_room() and Network.is_host():
		Network.room_changed.connect(_host_recount)


func _exit_tree() -> void:
	if visible:
		_close()


func is_open() -> bool:
	return visible


func open() -> void:
	if visible:
		return
	_items = ["resume", "briefing", "codex", "help", "sound", "music", "text", "fullscreen", "leave", "quit"]
	if get_parent().get_node_or_null("Tutorial") == null:
		_items.erase("help")
	if Missions.current().is_empty():
		_items.erase("briefing")
	_index = 0
	_confirm = ""
	visible = true
	Tutorial.hold(true)
	_want_pause(true)
	Sfx.play("page")


func _close() -> void:
	visible = false
	Tutorial.hold(false)
	_want_pause(false)


# --- pausing (alone: right away; co-op: when everyone has the menu open) -------------------------

func _solo() -> bool:
	return not Network.is_in_room() or Network.players.size() <= 1


func _want_pause(on: bool) -> void:
	if _solo():
		_set_tree_paused(on)
	elif Network.is_host():
		_host_set(1, on)
	else:
		_report_pause.rpc_id(1, on)


@rpc("any_peer", "call_remote", "reliable")
func _report_pause(on: bool) -> void:
	if Network.is_host():
		_host_set(multiplayer.get_remote_sender_id(), on)


func _host_set(peer: int, on: bool) -> void:
	_paused_peers[peer] = on
	_host_recount()


func _host_recount() -> void:
	if not Network.is_in_room() or not Network.is_host():
		return
	var count := 0
	for id in Network.players:
		if _paused_peers.get(id, false):
			count += 1
	var total: int = Network.players.size()
	var all := count >= total and total > 0
	_apply_pause.rpc(all, count, total)
	_apply_pause(all, count, total)


@rpc("authority", "call_remote", "reliable")
func _apply_pause(on: bool, count: int, total: int) -> void:
	_pause_count = Vector2i(count, total)
	_set_tree_paused(on)


func _set_tree_paused(on: bool) -> void:
	if on == _paused_tree:
		return
	_paused_tree = on
	get_tree().paused = on
	Sfx.pause_loops(on)


func _process(delta: float) -> void:
	_time += delta
	if visible:
		_canvas.queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible:
		var report := get_parent().get_node_or_null("MissionReport") as CanvasLayer
		if event.is_action_pressed("ui_cancel") and not Tutorial.any_open() and not (report and report.visible):
			open()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE, KEY_Q:
				_close()
				Sfx.play("ui_click")
			KEY_W, KEY_UP:
				_move(-1)
			KEY_S, KEY_DOWN:
				_move(1)
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_E:
				_activate(_items[_index])
			KEY_A, KEY_LEFT:
				_side(-1)
			KEY_D, KEY_RIGHT:
				_side(1)
	elif event is InputEventMouseMotion:
		var hit := _row_at(_canvas.get_local_mouse_position())
		if hit != "" and _items[_index] != hit:
			_index = _items.find(hit)
			Sfx.play("ui_hover")
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var hit := _row_at(_canvas.get_local_mouse_position())
		if hit != "":
			_activate(hit)
	get_viewport().set_input_as_handled()


func _move(step: int) -> void:
	_index = wrapi(_index + step, 0, _items.size())
	_confirm = ""
	Sfx.play("ui_hover")


## ←/→ on a setting changes it too.
func _side(step: int) -> void:
	match _items[_index]:
		"sound":
			_cycle_volume(step)
		"music":
			_cycle_music(step)
		"text":
			_cycle_text(step)
		"fullscreen":
			_activate("fullscreen")


func _activate(item: String) -> void:
	match item:
		"resume":
			_close()
			Sfx.play("ui_click")
		"help":
			_close()
			var t: Tutorial = get_parent().get_node_or_null("Tutorial")
			if t:
				t.open()
		"briefing":
			_close()
			var b: MissionBriefing = get_parent().get_node_or_null("Briefing")
			if b == null:
				b = MissionBriefing.attach(get_parent())
			b.open()
		"codex":
			_close()
			var c: Codex = get_parent().get_node_or_null("Codex")
			if c:
				c.open()
		"sound":
			_cycle_volume(1)
		"music":
			_cycle_music(1)
		"text":
			_cycle_text(1)
		"fullscreen":
			var full := DisplayServer.window_get_mode() >= DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
			Sfx.play("toggle")
		"leave", "quit":
			if _confirm != item:
				_confirm = item
				Sfx.play("denied")
				return
			_close()
			if item == "quit":
				get_tree().quit()
				return
			if Network.is_in_room():
				Network.leave_room()  # the host leaving closes the room for everyone
			get_tree().change_scene_to_file(MENU_SCENE)


func _cycle_volume(step: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	var level := wrapi(int(cfg.get_value("audio", "volume", 0)) + step, 0, VOLUMES.size())
	cfg.set_value("audio", "volume", level)
	cfg.save(SETTINGS)
	_set_volume(level)
	Sfx.play("toggle")


func _cycle_music(step: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	var level := wrapi(int(cfg.get_value("audio", "music", 0)) + step, 0, Radio.LEVELS_DB.size())
	cfg.set_value("audio", "music", level)
	cfg.save(SETTINGS)
	Radio.apply_volume(level)
	Sfx.play("toggle")


func _cycle_text(step: int) -> void:
	UiFont.set_level(UiFont.level() + step, get_tree())
	Sfx.play("toggle")


func _label(item: String) -> String:
	match item:
		"resume":
			return "RESUME"
		"help":
			return "HOW TO PLAY"
		"briefing":
			return "MISSION BRIEFING"
		"codex":
			return "CODEX (J)"
		"sound":
			var cfg := ConfigFile.new()
			cfg.load(SETTINGS)
			return "SOUND   < %s >" % VOLUME_NAMES[int(cfg.get_value("audio", "volume", 0))]
		"music":
			var cfg := ConfigFile.new()
			cfg.load(SETTINGS)
			return "MUSIC   < %s >" % Radio.LEVEL_NAMES[int(cfg.get_value("audio", "music", 0))]
		"text":
			return "TEXT SIZE   < %s >" % UiFont.SCALE_NAMES[UiFont.level()]
		"fullscreen":
			var full := DisplayServer.window_get_mode() >= DisplayServer.WINDOW_MODE_FULLSCREEN
			return "FULLSCREEN   < %s >" % ("ON" if full else "OFF")
		"leave":
			return "PRESS AGAIN TO LEAVE" if _confirm == "leave" else leave_label
		"quit":
			return "PRESS AGAIN TO QUIT" if _confirm == "quit" else "QUIT GAME"
	return item


func _row_at(p: Vector2) -> String:
	for item: String in _rows:
		if (_rows[item] as Rect2).has_point(p):
			return item
	return ""


func _draw_menu() -> void:
	var font := UiFont.font()
	_canvas.draw_rect(Rect2(0, 0, 480, 270), Color(0.01, 0.02, 0.06, 0.72))
	var h := 44.0 + _items.size() * 16.0 + 20.0
	var box := Rect2((480.0 - W) / 2.0, (270.0 - h) / 2.0, W, h)
	_canvas.draw_rect(box.grow(2), Color(0, 0, 0, 0.6))
	_canvas.draw_rect(box, Color("10142a"))
	_canvas.draw_rect(box, ACCENT, false, 1.0)
	var title := "PAUSED" if _paused_tree else "MENU"
	_canvas.draw_string(font, Vector2(240 - UiFont.width(title, 14) / 2.0, box.position.y + 20), title,
			HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(14), ACCENT)
	if not _solo():
		var note := "ALL %d PLAYERS PAUSED" % _pause_count.y if _paused_tree \
				else "MISSION RUNNING - PAUSED %d/%d (ALL MUST PAUSE)" % [_pause_count.x, maxi(_pause_count.y, Network.players.size())]
		_canvas.draw_string(font, Vector2(240 - UiFont.width(note, 6) / 2.0, box.position.y + 31), note,
				HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(6), Color("ff8a5c"))
	_rows.clear()
	var y := box.position.y + 42.0
	for i in _items.size():
		var item := _items[i]
		var row := Rect2(box.position.x + 10, y, W - 20, 14)
		_rows[item] = row
		var selected := i == _index
		var col := Color("ffc640") if selected else Color("c8d0e0")
		if item == _confirm:
			col = Color("ff5050")
		if selected:
			_canvas.draw_rect(row, Color(col, 0.14))
			_canvas.draw_rect(row, Color(col, 0.7), false, 1.0)
		var text := _label(item)
		_canvas.draw_string(font, Vector2(240 - UiFont.width(text, 9) / 2.0, y + 10), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(9), col)
		y += 16.0
	var keys := "W/S choose · SPACE select · Q / ESC back"
	_canvas.draw_string(font, Vector2(240 - UiFont.width(keys, 6) / 2.0, box.end.y - 7), keys,
			HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(6), Color("6b7390"))
