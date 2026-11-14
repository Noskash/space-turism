extends CanvasLayer
## Mission HUD: resource bars + ticket chips along the top hull strip, DSN / science status
## and controls hint along the bottom, and a short toast for sim messages.
## Reads only Events.state_changed.

const BARS := [
	["power", "PWR", Color("ff9a3c")],
	["fuel", "FUEL", Color("4fd8ff")],
	["data", "DATA", Color("b77bff")],
]
const FONT_SIZE := 8

var _root: Control
var _day_label: Label
var _bars := {}  # key -> ResourceBar
var _first_state := true
var _toast: Label
var _toast_tween: Tween
var _last_seq := -1
var _tickets: TicketStrip
var _status: Label
var _hint: Label


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
		var bar := ResourceBar.new()
		bar.color = bar_info[2]
		bar.custom_minimum_size = Vector2(48, 6)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(bar)
		_bars[bar_info[0]] = bar

	_tickets = TicketStrip.new()
	_tickets.position = Vector2(330, 8)
	_tickets.size = Vector2(120, 12)
	_root.add_child(_tickets)

	_status = _label("")
	_status.position = Vector2(300, 254)
	_status.size = Vector2(150, 10)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_root.add_child(_status)

	_hint = _label("")
	_hint.position = Vector2(30, 254)
	_hint.modulate.a = 0.7
	_root.add_child(_hint)
	show_role("")

	_toast = _label("")
	_toast.position = Vector2(30, 22)
	_toast.modulate.a = 0.0
	_root.add_child(_toast)

	Events.state_changed.connect(_on_state_changed)


func _on_state_changed(state: Dictionary) -> void:
	_day_label.text = "DAY %d" % int(state.get("day", 0))
	for key: String in _bars:
		_bars[key].set_value(float(state.get(key, 0)), _first_state)  # no animation on spawn
	_first_state = false
	_tickets.events = state.get("events", [])

	var dsn: Dictionary = state.get("dsn", {})
	var dsn_text := "DSN --"
	if dsn.get("site", "") != "":
		dsn_text = "DSN %s %ds" % [dsn.site, ceili(dsn.time_left)]
	_status.text = "%s · SENT %d · LOST %d" % [dsn_text, int(state.get("science_sent", 0)),
			int(state.get("science_lost", 0))]

	var seq: int = state.get("action_seq", 0)
	if seq != _last_seq and _last_seq != -1 and state.get("last_action", "") != "":
		_show_toast(state.last_action)
		Sfx.play("toast")
	_last_seq = seq


## Bottom-left hint; `role_text` (e.g. "NAV+PWR") is shown first in co-op.
func show_role(role_text: String) -> void:
	var keys := "WASD move · SHIFT run · SPACE use · K skin · ESC menu"
	_hint.text = keys if role_text == "" else "YOU: %s · %s" % [role_text, keys]


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
