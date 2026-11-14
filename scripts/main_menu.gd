extends Control
## Главное меню: анимированный космос, название игры и кнопки.

## «Создать комнату»: создатель комнаты сначала выбирает уровень.
@export_file("*.tscn") var create_room_scene: String = "res://scenes/level_select.tscn"
## «Присоединиться»: подключение к комнате по IP-адресу.
@export_file("*.tscn") var join_scene: String = "res://scenes/join_room.tscn"
## Экран с описанием персонажей.
@export_file("*.tscn") var characters_scene: String = "res://scenes/characters.tscn"

const HIGHLIGHT_SCALE := Vector2(1.06, 1.06)

## Длинное интро играется один раз за запуск игры,
## при возврате в меню — только короткое затемнение.
static var _intro_played := false
static var _last_focused := 0

@onready var _content: Control = $Content
@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _create_button: Button = %CreateRoomButton
@onready var _join_button: Button = %JoinButton
@onready var _characters_button: Button = %CharactersButton
@onready var _fade: ColorRect = $Fade

var _buttons: Array[Button] = []
var _scale_tweens := {}
var _busy := false


func _ready() -> void:
	# В главном меню игрок точно не в комнате (например, вернулся из уровня).
	Network.leave_room()
	_buttons = [_create_button, _join_button, _characters_button]
	var scenes := [create_room_scene, join_scene, characters_scene]
	for i in _buttons.size():
		var button := _buttons[i]
		button.mouse_entered.connect(_on_button_hovered.bind(button))
		button.focus_entered.connect(_animate_button.bind(button, true))
		button.focus_exited.connect(_animate_button.bind(button, false))
		button.resized.connect(_update_pivot.bind(button))
		button.pressed.connect(_open_scene.bind(scenes[i], i))
		_update_pivot(button)
	_play_intro()


func _play_intro() -> void:
	if _intro_played:
		create_tween().tween_property(_fade, "color:a", 0.0, 0.35)
		_buttons[_last_focused].grab_focus()
		return
	_intro_played = true

	_title.modulate.a = 0.0
	_subtitle.modulate.a = 0.0
	for button in _buttons:
		button.modulate.a = 0.0

	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_fade, "color:a", 0.0, 1.4)
	tween.tween_property(_content, "position:x", 0.0, 1.2).from(-50.0)
	tween.tween_property(_title, "modulate:a", 1.0, 1.0).set_delay(0.3)
	tween.tween_property(_subtitle, "modulate:a", 1.0, 1.0).set_delay(0.55)
	for i in _buttons.size():
		tween.tween_property(_buttons[i], "modulate:a", 1.0, 0.6).set_delay(0.8 + 0.15 * i)
	tween.chain().tween_callback(_create_button.grab_focus)


func _on_button_hovered(button: Button) -> void:
	# Мышь и клавиатура подсвечивают одну и ту же кнопку.
	if not _busy:
		button.grab_focus()


func _animate_button(button: Button, highlighted: bool) -> void:
	if _scale_tweens.has(button):
		(_scale_tweens[button] as Tween).kill()
	var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", HIGHLIGHT_SCALE if highlighted else Vector2.ONE, 0.18)
	_scale_tweens[button] = tween


func _update_pivot(button: Button) -> void:
	# Масштабируем от левого края, чтобы кнопка «выезжала» вправо.
	button.pivot_offset = Vector2(0.0, button.size.y * 0.5)


func _open_scene(path: String, focus_index: int) -> void:
	if _busy:
		return
	_busy = true
	_last_focused = focus_index
	# Пока идёт переход, затемнение перехватывает клики мыши.
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, 0.3)
	await tween.finished
	get_tree().change_scene_to_file(path)
