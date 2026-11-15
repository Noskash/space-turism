class_name LevelCard
extends Button
## Level card: spinning planet, number, name and description.
## The select screen creates the cards and calls setup() after add_child().

const PLANET_SHADER := preload("res://shaders/planet_preview.gdshader")
const HIGHLIGHT_SCALE := Vector2(1.04, 1.04)

@onready var _planet: ColorRect = %Planet
@onready var _number: Label = %Number
@onready var _title: Label = %Title
@onready var _accent_line: ColorRect = %AccentLine
@onready var _description: Label = %Description

var _highlight_tween: Tween
var _locked := false
var _sign: Control        # "UNDER DEVELOPMENT" plate over a level that isn't playable yet
var _t := 0.0


func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	focus_entered.connect(_set_highlight.bind(true))
	focus_exited.connect(_set_highlight.bind(false))
	resized.connect(_update_pivot)
	_update_pivot()


func setup(data: LevelData, number: int) -> void:
	_number.text = "LEVEL %d" % number
	_title.text = data.title
	_description.text = data.description
	# Campaign mission (lobby): "MARS · MISSION 1" on top, the mission name as the title.
	var mission: Dictionary = Missions.mission(data.mission) if data.mission != "" else {}
	if not mission.is_empty():
		_number.text = "MARS · MISSION %d" % int(mission.number)
		_title.text = str(mission.title).capitalize()
	# Long titles wrap and shrink instead of stretching the card past its width.
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if _title.text.length() > 9:
		_title.add_theme_font_size_override("font_size", 26 if _title.text.length() <= 16 else 22)
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
	# With rings the planet is smaller so the rings fit in the square.
	planet_material.set_shader_parameter("planet_radius", 0.23 if data.rings else 0.34)
	planet_material.set_shader_parameter("highlight", 0.0)
	_planet.material = planet_material

	_apply_accent(data.accent_color)
	if not data.available:
		_lock()


## Not playable yet: dimmed card + a hazard-taped "UNDER DEVELOPMENT / NOT AVAILABLE YET" sign.
func is_locked() -> bool:
	return _locked


func _lock() -> void:
	_locked = true
	for n: Control in [_planet, _number, _title, _description, _accent_line]:
		n.modulate = Color(0.55, 0.55, 0.62, 0.8)
	_sign = Control.new()
	_sign.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sign.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sign.draw.connect(_draw_sign)
	add_child(_sign)


func _process(delta: float) -> void:
	if _sign:
		_t += delta
		_sign.queue_redraw()


func _draw_sign() -> void:
	var r := _sign.get_rect()
	var font := get_theme_default_font()
	var w := r.size.x - 16.0
	var h := 62.0
	var box := Rect2(8.0, roundf(r.size.y * 0.42 - h / 2.0), w, h)
	var blink := fmod(_t, 1.2) < 0.9
	_sign.draw_rect(box.grow(3), Color(0.02, 0.02, 0.05, 0.92))
	# Hazard tape top and bottom (pixel steps, no smoothing).
	for edge: float in [box.position.y - 3.0, box.end.y - 3.0]:
		var x := box.position.x - 3.0
		var i := int(_t * 8.0) % 2
		while x < box.end.x + 3.0:
			var sw := minf(8.0, box.end.x + 3.0 - x)
			_sign.draw_rect(Rect2(x, edge, sw, 6), Color("ffc640") if i % 2 == 0 else Color("1a1a22"))
			x += 8.0
			i += 1
	var top := "UNDER DEVELOPMENT"
	var bottom := "NOT AVAILABLE YET"
	var size_a := 24
	var size_b := 16
	while size_a > 8 and font.get_string_size(top, HORIZONTAL_ALIGNMENT_LEFT, -1, size_a).x > w - 8.0:
		size_a -= 1
	var ya := box.position.y + 28.0
	var yb := box.position.y + 50.0
	var col := Color("ffc640") if blink else Color("b88a2a")
	_sign.draw_string_outline(font, Vector2(box.position.x, ya), top, HORIZONTAL_ALIGNMENT_CENTER, w, size_a, 4, Color.BLACK)
	_sign.draw_string(font, Vector2(box.position.x, ya), top, HORIZONTAL_ALIGNMENT_CENTER, w, size_a, col)
	_sign.draw_string(font, Vector2(box.position.x, yb), bottom, HORIZONTAL_ALIGNMENT_CENTER, w, size_b, Color(0.85, 0.87, 0.95))


## Pressed while locked: a short "no" shake.
func shake() -> void:
	var tw := create_tween()
	for k: float in [6.0, -5.0, 3.0, 0.0]:
		tw.tween_property(self, "rotation", deg_to_rad(k * 0.4), 0.05)


## Display-only card (in the room): no presses, highlighted from the start.
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
	# Mouse and keyboard select the same card.
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
