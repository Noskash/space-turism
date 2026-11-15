extends Control
## Экран «Присоединиться»: подключение к комнате друга по IP-адресу.

## Сцена, в которую возвращает кнопка «Назад».
@export_file("*.tscn") var menu_scene: String = "res://scenes/main_menu.tscn"
## Экран комнаты, куда попадаем после подключения.
@export_file("*.tscn") var lobby_scene: String = "res://scenes/lobby.tscn"

const STATUS_INFO := Color(0.6, 0.7, 0.86, 0.85)
const STATUS_ERROR := Color(1, 0.55, 0.45)

## Последний введённый адрес — подставляется при следующем открытии экрана.
static var _last_address := ""

@onready var _address_input: LineEdit = %AddressInput
@onready var _join_button: Button = %JoinButton
@onready var _back_button: Button = %BackButton
@onready var _status: Label = %Status
@onready var _fade: ColorRect = $Fade

var _busy := false
var _connecting := false


func _ready() -> void:
	_back_button.pressed.connect(_go_back)
	_join_button.pressed.connect(_try_join)
	_address_input.text_submitted.connect(func(_text: String) -> void: _try_join())
	_address_input.text_changed.connect(_on_address_changed)
	Network.joined_room.connect(_on_joined_room)
	Network.join_failed.connect(_on_join_failed)

	_address_input.text = _last_address
	_on_address_changed(_address_input.text)
	if Network.pending_message.is_empty():
		_set_status("Код (4 буквы) или адрес показан на экране комнаты у её создателя.", STATUS_INFO)
	else:
		_set_status(Network.pending_message, STATUS_ERROR)
		Network.pending_message = ""

	create_tween().tween_property(_fade, "color:a", 0.0, 0.4)
	_focus_input()


func _input(event: InputEvent) -> void:
	# Esc возвращает в меню, даже когда курсор в поле ввода.
	if not _busy and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_go_back()


func _on_address_changed(text: String) -> void:
	_join_button.disabled = _connecting or text.strip_edges().is_empty()


func _try_join() -> void:
	if _busy or _connecting:
		return
	var address := _address_input.text.strip_edges()
	if address.is_empty():
		_set_status("Сначала введи код или адрес комнаты.", STATUS_ERROR)
		return
	if RelayPeer.looks_like_code(address):
		address = address.to_upper()
		_address_input.text = address
	_last_address = address
	if Network.join_room(address) != OK:
		_set_status("Не похоже на код или адрес. Пример: KRMX, 192.168.1.5 или 192.168.1.5:7777", STATUS_ERROR)
		return
	_set_connecting(true)
	if RelayPeer.looks_like_code(address):
		_set_status("Ищем комнату %s через интернет…" % address, STATUS_INFO)
	else:
		_set_status("Подключение к %s…" % address, STATUS_INFO)


func _on_joined_room() -> void:
	_set_status("Подключились! Входим в комнату…", STATUS_INFO)
	_go_to(lobby_scene)


func _on_join_failed(reason: String) -> void:
	_set_connecting(false)
	_set_status(reason, STATUS_ERROR)
	_focus_input()


## Ставит курсор в конец поля адреса, чтобы можно было сразу печатать.
func _focus_input() -> void:
	_address_input.grab_focus()
	_address_input.edit()
	_address_input.caret_column = _address_input.text.length()


func _set_connecting(value: bool) -> void:
	_connecting = value
	_address_input.editable = not value
	_join_button.text = "ПОДКЛЮЧЕНИЕ…" if value else "ПОДКЛЮЧИТЬСЯ"
	_on_address_changed(_address_input.text)


func _set_status(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)


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
