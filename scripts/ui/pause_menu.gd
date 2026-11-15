class_name PauseMenu
extends CanvasLayer
## ESC menu for gameplay screens (designer, launch, cruise): RESUME · HOW TO PLAY · SOUND ·
## FULLSCREEN · LEAVE · QUIT. Offline the game pauses (get_tree().paused); in co-op it keeps
## running for everyone else and only this player's input is blocked.
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


static func attach(scene: Node, leave_text := "LEAVE TO MAIN MENU") -> PauseMenu:
	var m := PauseMenu.new()
	m.name = "PauseMenu"
	m.leave_label = leave_text
	scene.add_child(m)
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


func _exit_tree() -> void:
	if visible:
		_close()


func is_open() -> bool:
	return visible


func open() -> void:
	if visible:
		return
	_items = ["resume", "help", "sound", "music", "fullscreen", "leave", "quit"]
	if get_parent().get_node_or_null("Tutorial") == null:
		_items.erase("help")
	_index = 0
	_confirm = ""
	visible = true
	Tutorial.hold(true)
	if not Network.is_in_room():
		_paused_tree = true
		get_tree().paused = true
	Sfx.play("page")


func _close() -> void:
	visible = false
	Tutorial.hold(false)
	if _paused_tree:
		_paused_tree = false
		get_tree().paused = false


func _process(delta: float) -> void:
	_time += delta
	if visible:
		_canvas.queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible:
		if event.is_action_pressed("ui_cancel") and not Tutorial.any_open():
			open()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE:
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
		"sound":
			_cycle_volume(1)
		"music":
			_cycle_music(1)
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


func _label(item: String) -> String:
	match item:
		"resume":
			return "RESUME"
		"help":
			return "HOW TO PLAY"
		"sound":
			var cfg := ConfigFile.new()
			cfg.load(SETTINGS)
			return "SOUND   < %s >" % VOLUME_NAMES[int(cfg.get_value("audio", "volume", 0))]
		"music":
			var cfg := ConfigFile.new()
			cfg.load(SETTINGS)
			return "MUSIC   < %s >" % Radio.LEVEL_NAMES[int(cfg.get_value("audio", "music", 0))]
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
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ACCENT)
	if Network.is_in_room():
		var note := "CO-OP: THE MISSION KEEPS RUNNING"
		_canvas.draw_string(font, Vector2(240 - UiFont.width(note, 6) / 2.0, box.position.y + 31), note,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color("ff8a5c"))
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
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, col)
		y += 16.0
	var keys := "W/S choose · SPACE select · ESC back"
	_canvas.draw_string(font, Vector2(240 - UiFont.width(keys, 6) / 2.0, box.end.y - 7), keys,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color("6b7390"))
