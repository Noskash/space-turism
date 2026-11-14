class_name LevelCard
extends Button
## Карточка уровня: вращающаяся планета, номер, название и описание.
## Экран выбора создаёт карточки сам и вызывает setup() после add_child().

const PLANET_SHADER := preload("res://shaders/planet_preview.gdshader")
const HIGHLIGHT_SCALE := Vector2(1.04, 1.04)

@onready var _planet: ColorRect = %Planet
@onready var _number: Label = %Number
@onready var _title: Label = %Title
@onready var _accent_line: ColorRect = %AccentLine
@onready var _description: Label = %Description

var _highlight_tween: Tween


func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	focus_entered.connect(_set_highlight.bind(true))
	focus_exited.connect(_set_highlight.bind(false))
	resized.connect(_update_pivot)
	_update_pivot()


func setup(data: LevelData, number: int) -> void:
	_number.text = "УРОВЕНЬ %d" % number
	_title.text = data.title
	_description.text = data.description
	_accent_line.color = data.accent_color
	_number.add_theme_color_override("font_color", data.accent_color)

	var planet_material := ShaderMaterial.new()
	planet_material.shader = PLANET_SHADER
	planet_material.set_shader_parameter("color_a", data.planet_color_a)
	planet_material.set_shader_parameter("color_b", data.planet_color_b)
	planet_material.set_shader_parameter("atmosphere_color", data.atmosphere_color)
	planet_material.set_shader_parameter("gas_giant", data.gas_giant)
	planet_material.set_shader_parameter("rings", data.rings)
	planet_material.set_shader_parameter("ring_color", data.planet_color_b.lightened(0.15))
	# С кольцами планета меньше, чтобы кольца поместились в квадрат.
	planet_material.set_shader_parameter("planet_radius", 0.23 if data.rings else 0.34)
	planet_material.set_shader_parameter("highlight", 0.0)
	_planet.material = planet_material

	_apply_accent(data.accent_color)


## Карточка только для показа (в комнате): без нажатий, сразу подсвечена.
func show_as_selected() -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := get_theme_stylebox("focus").duplicate() as StyleBoxFlat
	style.draw_center = true
	style.bg_color = (get_theme_stylebox("normal") as StyleBoxFlat).bg_color
	add_theme_stylebox_override("normal", style)
	if _planet.material:
		(_planet.material as ShaderMaterial).set_shader_parameter("highlight", 1.0)


func _apply_accent(accent: Color) -> void:
	for style_name in ["hover", "focus", "pressed", "hover_pressed"]:
		var style := get_theme_stylebox(style_name).duplicate() as StyleBoxFlat
		style.border_color = Color(accent, style.border_color.a)
		if style_name == "focus":
			style.shadow_color = Color(accent, 0.35)
		add_theme_stylebox_override(style_name, style)


func _on_mouse_entered() -> void:
	# Мышь и клавиатура выделяют одну и ту же карточку.
	if not disabled:
		grab_focus()


func _set_highlight(highlighted: bool) -> void:
	if _highlight_tween:
		_highlight_tween.kill()
	_highlight_tween = create_tween().set_parallel(true)
	_highlight_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_highlight_tween.tween_property(self, "scale", HIGHLIGHT_SCALE if highlighted else Vector2.ONE, 0.2)
	if _planet.material:
		_highlight_tween.tween_property(_planet, "material:shader_parameter/highlight",
				1.0 if highlighted else 0.0, 0.3).set_trans(Tween.TRANS_SINE)


func _update_pivot() -> void:
	pivot_offset = size * 0.5
