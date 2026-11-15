extends Control
## Экран «Новая комната»: создатель комнаты выбирает уровень,
## после чего комната создаётся и открывается её экран (лобби).

## Уровни на экране. Сцену каждого уровня укажи в его поле Scene.
@export var levels: Array[LevelData] = []
## Экран комнаты, куда переходим после создания.
@export_file("*.tscn") var lobby_scene: String = "res://scenes/lobby.tscn"
## Сцена, в которую возвращает кнопка «Назад».
@export_file("*.tscn") var menu_scene: String = "res://scenes/main_menu.tscn"

const CARD_SCENE := preload("res://scenes/ui/level_card.tscn")

## Какая карточка была выбрана последней — при возврате фокус встанет на неё.
static var _last_selected := 0

@onready var _cards_box: HBoxContainer = %Cards
@onready var _back_button: Button = %BackButton
@onready var _notice: Label = %Notice
@onready var _fade: ColorRect = $Fade

var _cards: Array[LevelCard] = []
var _busy := false
var _notice_tween: Tween


func _ready() -> void:
	_notice.modulate.a = 0.0
	_back_button.pressed.connect(_go_to.bind(menu_scene))
	_build_cards()
	create_tween().tween_property(_fade, "color:a", 0.0, 0.4)
	if not _cards.is_empty():
		_cards[clampi(_last_selected, 0, _cards.size() - 1)].grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not _busy and event.is_action_pressed("ui_cancel"):
		_go_to(menu_scene)
		get_viewport().set_input_as_handled()


func _build_cards() -> void:
	for i in levels.size():
		var data := levels[i]
		if data == null:
			continue
		var card := CARD_SCENE.instantiate() as LevelCard
		_cards_box.add_child(card)
		card.setup(data, i + 1)
		card.pressed.connect(_create_room.bind(data, i + 1, card))
		_cards.append(card)

	# Стрелки влево/вправо листают карточки по кругу.
	for i in _cards.size():
		var card := _cards[i]
		var previous := _cards[wrapi(i - 1, 0, _cards.size())]
		var next := _cards[wrapi(i + 1, 0, _cards.size())]
		card.focus_neighbor_left = card.get_path_to(previous)
		card.focus_neighbor_right = card.get_path_to(next)
		card.focus_previous = card.focus_neighbor_left
		card.focus_next = card.focus_neighbor_right


func _create_room(data: LevelData, number: int, card: LevelCard) -> void:
	if _busy:
		return
	_last_selected = _cards.find(card)
	if data.has_missions:   # Mars: pick one of the campaign missions first (it creates the room)
		MissionSelect.level = data
		MissionSelect.level_number = number
		_go_to(MissionSelect.SCENE)
		return
	var error := Network.create_room(data, number)
	if error != OK:
		_show_notice("Не удалось создать комнату: порт %d уже занят другой программой." \
				% Network.DEFAULT_PORT)
		return
	_go_to(lobby_scene)


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
	# Пока идёт переход, затемнение перехватывает клики мыши.
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, 0.3)
	await tween.finished
	get_tree().change_scene_to_file(path)
