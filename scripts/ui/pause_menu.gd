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
## Controls of the screen behind the menu (shown in the footer; "" = none).
var controls := ""
var _items: Array[String] = []
var _index := 0
var _confirm := ""        # item waiting for its second press
var _canvas: Node2D
var _time := 0.0
var _rows := {}           # item -> Rect2, for the mouse
var _paused_tree := false


static func attach(scene: Node, leave_text := "LEAVE TO MAIN MENU", controls_text := "") -> PauseMenu:
	var m := PauseMenu.new()
	m.name = "PauseMenu"
	m.leave_label = leave_text
	m.controls = controls_text
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
	UiKit.setup_canvas(_canvas)
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
	_items = ["resume", "help", "sound", "music", "text", "fullscreen", "leave", "quit"]
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


## TEXT SIZE: NORMAL / LARGE / HUGE for every text drawn through UiFont.px (UiKit).
func _cycle_text(step: int) -> void:
	UiFont.set_text_size(wrapi(UiFont.text_size() + step, 0, UiFont.SCALES.size()))
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
		"text":
			return "TEXT SIZE   < %s >" % UiFont.SIZE_NAMES[UiFont.text_size()]
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
	var c := _canvas
	c.draw_rect(Rect2(0, 0, 480, 270), Color(0.01, 0.02, 0.06, 0.72))
	var w := minf(W * UiFont.SCALES[UiFont.text_size()], 300.0)
	var row_h := maxf(16.0, UiKit.line_h(9) + 5)
	var title_h := UiKit.line_h(14) + 10
	var note_h := UiKit.line_h(6) + 2 if Network.is_in_room() else 0.0
	var foot := PackedStringArray(["W/S CHOOSE · A/D CHANGE · SPACE SELECT · ESC BACK"])
	if controls != "":
		foot.append_array(UiKit.wrap("IN GAME: " + controls, 6, w - 20))
	var foot_lines := foot.size()
	var h := title_h + note_h + 4 + _items.size() * (row_h + 2) + 6 + foot_lines * UiKit.line_h(6) + 8
	var box := Rect2(roundf((480.0 - w) / 2.0), roundf((270.0 - h) / 2.0), roundf(w), roundf(h))
	UiKit.frame(c, box, ACCENT)
	var title := "PAUSED" if _paused_tree else "MENU"
	UiKit.text_c(c, 240, box.position.y + title_h - 4, title, 14, ACCENT, 3)
	var y := box.position.y + title_h
	if Network.is_in_room():
		UiKit.text_c(c, 240, y + note_h - 2, "CO-OP: THE MISSION KEEPS RUNNING", 6, Color("ff8a5c"), 0)
		y += note_h
	y += 4
	_rows.clear()
	for i in _items.size():
		var item := _items[i]
		var row := Rect2(box.position.x + 10, y, box.size.x - 20, row_h)
		_rows[item] = row
		var selected := i == _index
		var col := UiKit.WARN if selected else Color("c8d0e0")
		if item == _confirm:
			col = UiKit.BAD
		if selected:
			UiKit.panel(c, row, UiKit.PANEL, col)
			# Little arrow marker that nudges right and back.
			var nx := row.position.x + 4 + (1.0 if fmod(_time, 0.5) < 0.25 else 0.0)
			var cy := roundf(row.get_center().y)
			c.draw_colored_polygon(PackedVector2Array([Vector2(nx, cy - 3), Vector2(nx + 4, cy), Vector2(nx, cy + 3)]), col)
		UiKit.text_c(c, 240, row.end.y - 5, _label(item), 9, col, 0 if not selected else 2)
		y += row_h + 2
	y += 6
	for i in foot.size():
		y += UiKit.line_h(6)
		UiKit.text_c(c, 240, y - 2, foot[i], 6, UiKit.DIM if i == 0 else UiKit.FAINT.lightened(0.3), 0)
