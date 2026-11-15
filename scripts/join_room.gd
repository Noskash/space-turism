extends Control
## Экран «Присоединиться»: подключение к комнате друга по коду (интернет) или IP-адресу.
## Drawn on the UI kit (UiKit + MenuKit) at 480x270 (PixelMode): one kit frame with the input well,
## live ONLINE CODE / LOCAL IP chips, status line, chunky JOIN / BACK buttons, keycap hints.
## Only the LineEdit is a real Control (typing, IME, the web virtual keyboard); the rest is _draw().

## Сцена, в которую возвращает кнопка «Назад».
@export_file("*.tscn") var menu_scene: String = "res://scenes/main_menu.tscn"
## Экран комнаты, куда попадаем после подключения.
@export_file("*.tscn") var lobby_scene: String = "res://scenes/lobby.tscn"

const ACCENT := Color("4fd8ff")
const STATUS_INFO := UiKit.DIM
const STATUS_ERROR := UiKit.BAD
const FRAME := Rect2(100, 56, 280, 140)
const WELL := Rect2(116, 86, 248, 32)
const JOIN_RECT := Rect2(170, 166, 140, 22)
const BACK_RECT := Rect2(418, 8, 54, 20)

## Последний введённый адрес — подставляется при следующем открытии экрана.
static var _last_address := ""

@onready var _address_input: LineEdit = %AddressInput
@onready var _fade: ColorRect = $Fade

var _busy := false
var _connecting := false
var _status_text := ""
var _status_color := STATUS_INFO
var _time := 0.0
var _stars: Array = []
var _juice := UiJuice.new()
var _hot := ""          # "join" / "back" under the mouse
var _saved_window := {}


func _enter_tree() -> void:
	_saved_window = PixelMode.enter(get_window())
	UiFont.max_level = 1   # dense screen: TEXT SIZE stops at LARGE


func _exit_tree() -> void:
	PixelMode.exit(get_window(), _saved_window)
	UiFont.max_level = 2


func _ready() -> void:
	UiKit.setup_canvas(self)
	_stars = MenuKit.make_stars(50, 21)
	_style_input()
	_address_input.text_submitted.connect(func(_text: String) -> void: _try_join())
	_address_input.text_changed.connect(_on_address_changed)
	Network.joined_room.connect(_on_joined_room)
	Network.join_failed.connect(_on_join_failed)

	_address_input.text = _last_address
	_on_address_changed(_address_input.text)
	if Network.pending_message.is_empty():
		_set_status("The 4-letter code (or the address) is on the host's room screen.", STATUS_INFO)
	else:
		_set_status(NetText.message(Network.pending_message), STATUS_ERROR)
		Network.pending_message = ""

	create_tween().tween_property(_fade, "color:a", 0.0, 0.4)
	_focus_input()


func _style_input() -> void:
	var e := _address_input
	e.position = WELL.position + Vector2(4, 3)
	e.size = WELL.size - Vector2(8, 6)
	e.add_theme_font_override("font", UiFont.font())
	e.add_theme_font_size_override("font_size", UiFont.px(16))
	e.add_theme_color_override("font_color", UiKit.TEXT)
	e.add_theme_color_override("font_uneditable_color", UiKit.DIM)
	e.add_theme_color_override("font_placeholder_color", UiKit.FAINT)
	e.add_theme_color_override("caret_color", UiKit.GOOD)
	e.add_theme_color_override("selection_color", Color(ACCENT, 0.35))
	e.add_theme_constant_override("caret_width", 2)
	for style in ["normal", "focus", "read_only"]:
		e.add_theme_stylebox_override(style, StyleBoxEmpty.new())
	e.mouse_default_cursor_shape = Control.CURSOR_IBEAM


func _process(delta: float) -> void:
	_time += delta
	_juice.step(delta)
	queue_redraw()


func _input(event: InputEvent) -> void:
	# Esc возвращает в меню, даже когда курсор в поле ввода.
	if not _busy and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_go_back()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var hot := _button_at(get_local_mouse_position())
		if hot != _hot and hot != "":
			Sfx.play("ui_hover")
		_hot = hot
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		match _button_at(get_local_mouse_position()):
			"join":
				_juice.kick("press_join", 0.15)
				_try_join()
			"back":
				_juice.kick("press_back", 0.15)
				_go_back()
			_:
				if WELL.has_point(get_local_mouse_position()):
					_focus_input()


func _button_at(p: Vector2) -> String:
	if JOIN_RECT.has_point(p):
		return "join"
	if BACK_RECT.has_point(p):
		return "back"
	return ""


func _on_address_changed(_text: String) -> void:
	_juice.kick("typed", 0.12)


func _can_join() -> bool:
	return not _connecting and not _address_input.text.strip_edges().is_empty()


func _try_join() -> void:
	if _busy or _connecting:
		return
	var address := _address_input.text.strip_edges()
	if address.is_empty():
		_set_status("Type the room code or address first.", STATUS_ERROR)
		return
	if RelayPeer.looks_like_code(address):
		address = address.to_upper()
		_address_input.text = address
	_last_address = address
	if Network.join_room(address) != OK:
		_set_status("That is not a code or an address. Example: KRMX, 192.168.1.5 or 192.168.1.5:7777", STATUS_ERROR)
		return
	Sfx.play("ui_click")
	_set_connecting(true)
	if RelayPeer.looks_like_code(address):
		_set_status("Looking for room %s online" % address, STATUS_INFO)
	else:
		_set_status("Connecting to %s" % address, STATUS_INFO)


func _on_joined_room() -> void:
	_set_status("Connected! Entering the room", UiKit.GOOD)
	_juice.kick("ok", 0.4)
	_go_to(lobby_scene)


func _on_join_failed(reason: String) -> void:
	_set_connecting(false)
	_set_status(NetText.message(reason), STATUS_ERROR)
	_focus_input()


## Ставит курсор в конец поля адреса, чтобы можно было сразу печатать.
func _focus_input() -> void:
	_address_input.grab_focus()
	_address_input.edit()
	_address_input.caret_column = _address_input.text.length()


func _set_connecting(value: bool) -> void:
	_connecting = value
	_address_input.editable = not value


func _set_status(text: String, color: Color) -> void:
	_status_text = text
	_status_color = color
	if color == STATUS_ERROR:
		_juice.kick("error", 0.35)
		Sfx.play("denied")


func _go_back() -> void:
	if _connecting:
		Network.leave_room()
	_go_to(menu_scene)


func _go_to(path: String) -> void:
	if _busy:
		return
	_busy = true
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, 0.3)
	await tween.finished
	get_tree().change_scene_to_file(path)


# --- drawing ----------------------------------------------------------------------------

func _draw() -> void:
	MenuKit.backdrop(self, "low_left")
	MenuKit.stars(self, _stars, _time)
	MenuKit.title(self, Vector2(8, 6), "JOIN A ROOM", "ENTER A FRIEND'S ROOM", ACCENT, "downlink")
	MenuKit.button(self, BACK_RECT, "BACK", UiKit.DIM.lightened(0.3), _hot == "back", true, 8, "",
			_juice.k("press_back"))

	var shake := _juice.shake("error")
	var f := Rect2(FRAME.position + shake, FRAME.size)
	UiKit.frame(self, f, ACCENT)
	UiKit.text_c(self, f.get_center().x, f.position.y + 14, "ROOM CODE OR ADDRESS", 7, ACCENT, 0)
	# Input well: inset trough with an ink outline; the LineEdit sits inside.
	var well := Rect2(WELL.position + shake, WELL.size)
	var focused := _address_input.has_focus() and not _connecting
	draw_rect(well, UiKit.INK)
	draw_rect(well.grow(-1), UiKit.WELL)
	draw_rect(Rect2(well.position + Vector2(1, 1), Vector2(well.size.x - 2, 1)), Color.BLACK)
	var edge := (ACCENT if fmod(_time, 1.0) < 0.6 or _juice.active("typed") else ACCENT.darkened(0.3)) if focused else UiKit.FAINT
	if _juice.active("error"):
		edge = UiKit.BAD
	draw_rect(Rect2(well.position.x + 1, well.end.y - 2, well.size.x - 2, 1), edge)
	_address_input.position = well.position + Vector2(4, 3)

	# What the text looks like: an online code (4 letters) or a LAN address.
	var text := _address_input.text.strip_edges()
	var is_code := RelayPeer.looks_like_code(text)
	var is_ip := text != "" and not is_code and not Network.parse_address(text).is_empty() \
			and text.substr(0, 1).is_valid_int()
	var c1 := "ONLINE CODE"
	var c2 := "LOCAL IP"
	var w := MenuKit.tag_w(c1, "earth") + 4 + MenuKit.tag_w(c2, "dsn")
	var x := roundf(f.get_center().x - w / 2.0)
	var cy := well.end.y + 5
	var r1 := MenuKit.tag(self, Vector2(x, cy - (1 if is_code else 0)), c1, ACCENT if is_code else UiKit.FAINT.lightened(0.15), "earth", 6, is_code)
	MenuKit.tag(self, Vector2(r1.end.x + 4, cy - (1 if is_ip else 0)), c2, Color("ff9a3c") if is_ip else UiKit.FAINT.lightened(0.15), "dsn", 6, is_ip)

	# Status: icon + wrapped text (animated dots while connecting).
	var status := _status_text
	if _connecting:
		status += ".".repeat(1 + int(_time * 3.0) % 3)
	var lines := UiKit.wrap(status, 6, f.size.x - 40)
	var sy := cy + 21
	var icon_name := "alert" if _status_color == STATUS_ERROR else ("check" if _status_color == UiKit.GOOD else "dsn")
	var icon_y := sy - 7
	if icon_name == "alert":
		UiKit.icon(self, "alert", Vector2(f.position.x + 10, icon_y - 2), 1, UiKit.BAD)
	else:
		UiKit.icon(self, icon_name, Vector2(f.position.x + 14, icon_y), 1, _status_color if _status_color != STATUS_INFO else ACCENT)
	for line in lines.slice(0, 3):
		UiKit.text(self, Vector2(f.position.x + 30, sy), line, 6, _status_color if _status_color != STATUS_INFO else UiKit.TEXT.darkened(0.15), 0)
		sy += UiKit.line_h(6)

	var label := "CONNECTING" + ".".repeat(1 + int(_time * 3.0) % 3) if _connecting else "JOIN"
	var join_col := UiKit.GOOD if not _connecting else UiKit.WARN
	var join_hot := (_hot == "join" or (_can_join() and focused)) and _can_join()
	MenuKit.button(self, Rect2(JOIN_RECT.position + shake, JOIN_RECT.size), label, join_col,
			join_hot or _connecting, _can_join() or _connecting, 9, "fly" if not _connecting else "", _juice.k("press_join"))

	MenuKit.key_hints(self, 240, 246, [["ENTER", "JOIN"], ["ESC", "BACK"]], 6)
	UiKit.text_c(self, 240, 238, "4 LETTERS = ONLINE ROOM  ·  IP (+ :PORT) = SAME NETWORK", 5, UiKit.FAINT.lightened(0.2), 0)
