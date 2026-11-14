extends CanvasLayer
## Mission HUD: resource bars along the top hull strip, controls hint along the bottom,
## and a short toast for the last action. Reads only Events.state_changed.

const BARS := [
	["power", "PWR", Color("ff9a3c")],
	["fuel", "FUEL", Color("4fd8ff")],
	["data", "DATA", Color("b77bff")],
]
const FONT_SIZE := 8

var _root: Control
var _day_label: Label
var _bars := {}  # key -> ProgressBar
var _toast: Label
var _toast_tween: Tween
var _last_action := ""


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_root)

	var top := HBoxContainer.new()
	top.position = Vector2(30, 10)
	top.add_theme_constant_override("separation", 10)
	_root.add_child(top)

	_day_label = _label("DAY 0")
	_day_label.custom_minimum_size.x = 46
	top.add_child(_day_label)
	for bar_info in BARS:
		top.add_child(_label(bar_info[1]))
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(48, 6)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.add_theme_stylebox_override("background", _box(Color(0, 0, 0, 0.6)))
		bar.add_theme_stylebox_override("fill", _box(bar_info[2]))
		top.add_child(bar)
		_bars[bar_info[0]] = bar

	var hint := _label("WASD move · SPACE use station · ESC menu")
	hint.position = Vector2(30, 254)
	hint.modulate.a = 0.7
	_root.add_child(hint)

	_toast = _label("")
	_toast.position = Vector2(30, 22)
	_toast.modulate.a = 0.0
	_root.add_child(_toast)

	Events.state_changed.connect(_on_state_changed)


func _on_state_changed(state: Dictionary) -> void:
	_day_label.text = "DAY %d" % int(state.get("day", 0))
	for key: String in _bars:
		_bars[key].value = float(state.get(key, 0))
	var action: String = state.get("last_action", "")
	if action != "" and action != _last_action:
		_show_toast(action)
	_last_action = action


func _show_toast(text: String) -> void:
	_toast.text = text
	if _toast_tween:
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.5)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 2)
	return label


static func _box(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	return box
