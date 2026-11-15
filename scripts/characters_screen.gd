extends Control
## CREW screen: crew cards you can flip through.

## Characters on the screen. Add new ones in the inspector:
## Characters → Add Element → New CharacterData.
@export var characters: Array[CharacterData] = []
## Scene the BACK button returns to.
@export_file("*.tscn") var menu_scene: String = "res://scenes/main_menu.tscn"

const DEFAULT_ACCENT := Color(0.35, 0.85, 1.0)

@onready var _card: PanelContainer = %Card
@onready var _portrait: Panel = %Portrait
@onready var _ring: Panel = %Ring
@onready var _initials: Label = %Initials
@onready var _image: TextureRect = %Image
@onready var _role: Label = %Role
@onready var _name: Label = %Name
@onready var _accent_line: ColorRect = %AccentLine
@onready var _description: Label = %Description
@onready var _dots: HBoxContainer = %Dots
@onready var _prev_button: Button = %PrevButton
@onready var _next_button: Button = %NextButton
@onready var _back_button: Button = %BackButton
@onready var _fade: ColorRect = $Fade

var _index := 0
var _busy := false
var _switch_tween: Tween
var _card_style: StyleBoxFlat
var _portrait_style: StyleBoxFlat
var _ring_style: StyleBoxFlat


func _ready() -> void:
	# Mars mission crew roster: the astronauts from data/astronauts.json replace the old tourism cards.
	var crew := Astronauts.data().get("astronauts", {}) as Dictionary
	if not crew.is_empty():
		characters = []
		for id: String in ["navigator", "engineer", "comms", "scientist", "commander"]:
			if not crew.has(id):
				continue
			var c := CharacterData.new()
			c.display_name = str(crew[id].name)
			c.role = str(crew[id].role)
			c.description = str(crew[id].bio)
			c.accent_color = Color(str(crew[id].color))
			characters.append(c)
	# Base styles come from the theme; each character recolours copies of them.
	_card_style = _card.get_theme_stylebox("panel") as StyleBoxFlat
	_portrait_style = _portrait.get_theme_stylebox("panel") as StyleBoxFlat
	_ring_style = _ring.get_theme_stylebox("panel") as StyleBoxFlat

	_back_button.pressed.connect(_go_back)
	_prev_button.pressed.connect(_show_relative.bind(-1))
	_next_button.pressed.connect(_show_relative.bind(1))

	var can_switch := characters.size() > 1
	for button: Button in [_prev_button, _next_button]:
		button.disabled = not can_switch
		button.modulate.a = 1.0 if can_switch else 0.0

	_build_dots()
	_show_character(0)
	create_tween().tween_property(_fade, "color:a", 0.0, 0.4)


func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	if event.is_action_pressed("ui_left"):
		_show_relative(-1)
	elif event.is_action_pressed("ui_right"):
		_show_relative(1)
	elif event.is_action_pressed("ui_cancel"):
		_go_back()
	else:
		return
	get_viewport().set_input_as_handled()


func _show_relative(step: int) -> void:
	if _busy or characters.size() < 2:
		return
	_index = wrapi(_index + step, 0, characters.size())
	if _switch_tween:
		_switch_tween.kill()
	_switch_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_switch_tween.tween_property(_card, "modulate:a", 0.0, 0.12)
	_switch_tween.tween_callback(_show_character.bind(_index))
	_switch_tween.tween_property(_card, "modulate:a", 1.0, 0.25)


func _show_character(index: int) -> void:
	var data: CharacterData = characters[index] if index < characters.size() else null
	if data == null:
		_role.text = ""
		_name.text = "No crew yet"
		_description.text = "Add characters to the Characters property in the inspector."
		_initials.text = "?"
		_initials.visible = true
		_image.texture = null
		_apply_accent(DEFAULT_ACCENT)
		return

	_role.text = data.role.to_upper()
	_name.text = data.display_name
	_description.text = data.description
	_image.texture = data.portrait
	_initials.text = _make_initials(data.display_name)
	_initials.visible = data.portrait == null
	_apply_accent(data.accent_color)
	_update_dots()


func _apply_accent(accent: Color) -> void:
	_role.add_theme_color_override("font_color", accent)
	_accent_line.color = accent
	_initials.add_theme_color_override("font_color", accent.lightened(0.35))

	var card := _card_style.duplicate() as StyleBoxFlat
	card.border_color = Color(accent, 0.5)
	card.shadow_color = Color(accent, 0.15)
	_card.add_theme_stylebox_override("panel", card)

	var portrait := _portrait_style.duplicate() as StyleBoxFlat
	portrait.bg_color = accent.darkened(0.7)
	_portrait.add_theme_stylebox_override("panel", portrait)

	var ring := _ring_style.duplicate() as StyleBoxFlat
	ring.border_color = accent
	_ring.add_theme_stylebox_override("panel", ring)


func _build_dots() -> void:
	for child in _dots.get_children():
		child.queue_free()
	if characters.size() < 2:
		return
	for i in characters.size():
		var dot := Panel.new()
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_dots.add_child(dot)


func _update_dots() -> void:
	for i in _dots.get_child_count():
		var dot := _dots.get_child(i) as Panel
		var active := i == _index
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(4)
		style.bg_color = _accent_of(i) if active else Color(1, 1, 1, 0.22)
		dot.add_theme_stylebox_override("panel", style)
		dot.custom_minimum_size = Vector2(30.0 if active else 8.0, 8.0)


func _accent_of(index: int) -> Color:
	var data := characters[index]
	return data.accent_color if data else DEFAULT_ACCENT


func _go_back() -> void:
	if _busy:
		return
	_busy = true
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, 0.3)
	await tween.finished
	get_tree().change_scene_to_file(menu_scene)


static func _make_initials(full_name: String) -> String:
	var result := ""
	for part in full_name.split(" ", false):
		result += part.left(1).to_upper()
		if result.length() >= 2:
			break
	return result if not result.is_empty() else "?"
