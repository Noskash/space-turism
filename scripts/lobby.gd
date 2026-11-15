extends Control
## Экран комнаты (лобби): адрес для друзей, экипаж и старт полёта.
## У создателя комнаты есть кнопка «Начать полёт», остальные ждут старта.

@export_file("*.tscn") var menu_scene: String = "res://scenes/main_menu.tscn"
## Куда попадает игрок, если связь с комнатой пропала.
@export_file("*.tscn") var join_scene: String = "res://scenes/join_room.tscn"

const CARD_SCENE := preload("res://scenes/ui/level_card.tscn")
const HOST_COLOR := Color(1, 0.8, 0.4)
const ME_COLOR := Color(0.55, 0.92, 1)
const OTHER_COLOR := Color(0.82, 0.88, 0.97)
const EMPTY_COLOR := Color(0.6, 0.7, 0.86, 0.35)

@onready var _background: ColorRect = $Background
@onready var _content: Control = $Margin
@onready var _subtitle: Label = %Subtitle
@onready var _leave_button: Button = %LeaveButton
@onready var _card_slot: Control = %CardSlot
@onready var _address_box: Control = %AddressBox
@onready var _address: Label = %Address
@onready var _address_hint: Label = %AddressHint
@onready var _players_caption: Label = %PlayersCaption
@onready var _players_list: VBoxContainer = %PlayersList
@onready var _status: Label = %Status
@onready var _start_button: Button = %StartButton
@onready var _notice: Label = %Notice
@onready var _fade: ColorRect = $Fade

var _card: LevelCard
var _busy := false
var _notice_tween: Tween
## Создатель: «играть через интернет / по локальной сети» (пока в комнате никого нет).
var _mode_button: Button


func _ready() -> void:
	if not Network.is_in_room():
		# Экран открыли без комнаты (например, запуском сцены из редактора).
		get_tree().change_scene_to_file.call_deferred(menu_scene)
		return

	(_background.material as ShaderMaterial).set_shader_parameter("warp", 0.0)
	_notice.modulate.a = 0.0
	Network.room_changed.connect(_refresh)
	Network.room_closed.connect(_on_room_closed)
	Network.game_started.connect(_on_game_started)
	_leave_button.pressed.connect(_leave)
	_start_button.pressed.connect(_on_start_pressed)

	var host := Network.is_host()
	_leave_button.text = "ЗАКРЫТЬ КОМНАТУ" if host else "ВЫЙТИ"
	_address_box.visible = host
	_start_button.visible = host
	if host:
		_mode_button = Button.new()
		_mode_button.focus_mode = Control.FOCUS_ALL
		_mode_button.add_theme_font_size_override("font_size", 15)
		_mode_button.pressed.connect(_toggle_mode)
		_address_box.add_child(_mode_button)
		_address_box.move_child(_mode_button, _address_box.get_child_count() - 2)
		_show_address_info()
	else:
		_subtitle.text = "ТЫ В КОМНАТЕ"
		_status.text = "Ждём, пока создатель комнаты начнёт полёт…"

	_refresh()
	create_tween().tween_property(_fade, "color:a", 0.0, 0.4)
	if host:
		_start_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not _busy and event.is_action_pressed("ui_cancel"):
		_leave()
		get_viewport().set_input_as_handled()


## Создатель: код комнаты (интернет) или IP-адрес (локальная сеть).
func _show_address_info() -> void:
	var caption := _address_box.get_node_or_null("AddressCaption") as Label
	if Network.is_online_room():
		_subtitle.text = "ДРУЗЬЯ ВХОДЯТ ПО КОДУ КОМНАТЫ — ИЗ ЛЮБОЙ ТОЧКИ МИРА"
		_status.text = "Друзья вводят код в «Присоединиться». Комната закроется, если ты выйдешь."
		if caption:
			caption.text = "КОД КОМНАТЫ"
		if Network.room_code == "":
			_address.text = "…"
			_address_hint.text = "Получаем код у сервера…"
		else:
			_address.text = Network.room_code
			_address_hint.text = "Его вводят в «Присоединиться». Игра идёт через интернет."
		_mode_button.text = "ИГРАТЬ ПО ЛОКАЛЬНОЙ СЕТИ (IP)"
	else:
		_subtitle.text = "ДРУЗЬЯ ПОДКЛЮЧАЮТСЯ ПО АДРЕСУ НИЖЕ"
		_status.text = "Друзья не могут войти? Сделай сеть «Частной» и разреши игре доступ в брандмауэре."
		if caption:
			caption.text = "АДРЕС КОМНАТЫ"
		_show_addresses()
		_mode_button.text = "ИГРАТЬ ЧЕРЕЗ ИНТЕРНЕТ (КОД)"
	# Сменить способ можно, только пока в комнате один создатель (иначе все вылетят).
	_mode_button.visible = Network.players.size() <= 1


func _toggle_mode() -> void:
	if _busy or Network.players.size() > 1:
		return
	if Network.set_online(not Network.online) != OK:
		_show_notice("Порт %d занят другой программой — остаёмся в игре через интернет." \
				% Network.DEFAULT_PORT)
	_mode_button.grab_focus()


func _show_addresses() -> void:
	var addresses := Network.get_local_addresses()
	if addresses.is_empty():
		_address.text = "нет сети"
		_address_hint.text = "Компьютер не подключён к сети — друзья не смогут войти."
		return
	_address.text = addresses[0]
	var hint := "Его вводят в «Присоединиться». Порт %d." % Network.DEFAULT_PORT
	if addresses.size() > 1:
		hint += "\nДругие адреса: " + ", ".join(addresses.slice(1))
	_address_hint.text = hint


func _refresh() -> void:
	if not Network.is_in_room():
		return
	if _mode_button:
		_show_address_info()
	if Network.level and _card == null:
		_card = CARD_SCENE.instantiate() as LevelCard
		_card_slot.add_child(_card)
		_card.setup(Network.level, Network.level_number)
		_card.show_as_selected()

	_players_caption.text = "ЭКИПАЖ  %d / %d" % [Network.players.size(), Network.MAX_PLAYERS]
	for child in _players_list.get_children():
		_players_list.remove_child(child)
		child.queue_free()
	var ids := Network.players.keys()
	ids.sort()
	for id: int in ids:
		_players_list.add_child(_make_player_row(id, str(Network.players[id])))
	for i in range(ids.size(), Network.MAX_PLAYERS):
		_players_list.add_child(_make_row("Свободное место", EMPTY_COLOR, EMPTY_COLOR, ""))


func _make_player_row(id: int, player_name: String) -> Control:
	var tags := PackedStringArray()
	var color := OTHER_COLOR
	if id == 1:
		tags.append("создатель")
		color = HOST_COLOR
	if id == Network.my_id():
		tags.append("ты")
		color = ME_COLOR
	return _make_row(player_name, Color.WHITE, color, ", ".join(tags))


func _make_row(text: String, text_color: Color, dot_color: Color, tag: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(10, 10)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var style := StyleBoxFlat.new()
	style.bg_color = dot_color
	style.set_corner_radius_all(5)
	dot.add_theme_stylebox_override("panel", style)
	row.add_child(dot)

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", text_color)
	row.add_child(label)

	if not tag.is_empty():
		var tag_label := Label.new()
		tag_label.text = "· " + tag
		tag_label.add_theme_font_size_override("font_size", 16)
		tag_label.add_theme_color_override("font_color", dot_color)
		row.add_child(tag_label)
	return row


func _on_start_pressed() -> void:
	if not _busy:
		Network.start_game()


func _on_game_started() -> void:
	if _busy:
		return
	_busy = true
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var title := Network.level.title
	var scene := Network.level.scene
	var has_scene := not scene.is_empty() and ResourceLoader.exists(scene)

	# Прыжок в гиперпространство: интерфейс гаснет, звёзды вытягиваются в лучи.
	var jump := create_tween().set_parallel(true)
	jump.tween_property(_content, "modulate:a", 0.0, 0.5)
	jump.tween_property(_background, "material:shader_parameter/warp", 1.0, 1.8) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	if has_scene:
		jump.chain().tween_property(_fade, "color:a", 1.0, 0.5)
		await jump.finished
		get_tree().change_scene_to_file(scene)
		return

	await jump.finished
	push_warning("Lobby: у уровня «%s» не задана сцена — укажи её в поле Scene." % title)
	var back := create_tween().set_parallel(true)
	back.tween_property(_background, "material:shader_parameter/warp", 0.0, 1.0) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	back.tween_property(_content, "modulate:a", 1.0, 0.5).set_delay(0.6)
	await back.finished
	_busy = false
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Network.set_room_open(true)
	if Network.is_host():
		_start_button.grab_focus()
	_show_notice("Сцена уровня «%s» ещё не подключена" % title)


func _on_room_closed(_reason: String) -> void:
	# Причину покажет экран «Присоединиться» (Network.pending_message).
	_busy = false
	_go_to(join_scene)


func _leave() -> void:
	if _busy:
		return
	Network.leave_room()
	_go_to(menu_scene)


func _show_notice(text: String) -> void:
	_notice.text = text
	if _notice_tween:
		_notice_tween.kill()
	_notice_tween = create_tween()
	_notice_tween.tween_property(_notice, "modulate:a", 1.0, 0.25)
	_notice_tween.tween_interval(3.0)
	_notice_tween.tween_property(_notice, "modulate:a", 0.0, 0.6)


func _go_to(path: String) -> void:
	if _busy:
		return
	_busy = true
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, 0.3)
	await tween.finished
	get_tree().change_scene_to_file(path)
