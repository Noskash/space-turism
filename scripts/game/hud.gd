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
var _banner: Label
var _banner_text := ""       # format string with %d for the local countdown
var _banner_left := 0.0
var _banner_color := Color.WHITE
var _time := 0.0
var radio_label: Label       # set by Radio


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
	_day_label.custom_minimum_size.x = 92
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

	_banner = UiFont.label("", 11)
	_banner.position = Vector2(0, 30)
	_banner.size = Vector2(480, 14)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_banner)

	radio_label = _label("")
	radio_label.position = Vector2(30, 243)
	radio_label.modulate = Color(1, 0.85, 0.55, 0.85)
	_root.add_child(radio_label)

	_toast = _label("")
	_toast.position = Vector2(30, 22)
	_toast.modulate.a = 0.0
	_root.add_child(_toast)

	Events.state_changed.connect(_on_state_changed)


func _on_state_changed(state: Dictionary) -> void:
	# Sun distance on the transfer ellipse (same model as ShipLighting): sunlight falls as 1/r^2.
	var day: float = state.get("day", 0.0)
	var au := ShipLighting.TRANSFER_A * (1.0 - ShipLighting.TRANSFER_E ** 2) \
			/ (1.0 + ShipLighting.TRANSFER_E * cos(PI * clampf(day / ShipLighting.CRUISE_DAYS, 0.0, 1.0)))
	_day_label.text = "DAY %d  %.2f AU" % [int(day), au]
	for key: String in _bars:
		_bars[key].set_value(float(state.get(key, 0)), _first_state)  # no animation on spawn
	_first_state = false
	_tickets.events = state.get("events", [])
	_update_banner(state)

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


## Big blinking line for space weather; counts down locally between sim updates.
func _update_banner(state: Dictionary) -> void:
	var cme: Dictionary = state.get("cme", {})
	var dust: Dictionary = state.get("dust", {})
	var blackout: float = state.get("blackout", 0.0)
	_banner_text = ""
	var protected: bool = cme.get("shields", false) or cme.get("safe", false)
	if cme.get("phase", "") == "warning" and protected:
		_banner_text = ("SHIELDS UP" if cme.get("shields", false) else "SAFE MODE") + " - RADIATION STORM IN %ds"
		_banner_left = cme.time_left
		_banner_color = Color("8cd8ff")
	elif cme.get("phase", "") == "warning":
		var todo := "RAISE THE SHIELDS (MISSION HUB)" if cme.get("shielding", false) else "ENGINEER: SAFE MODE (ENGINE ROOM)"
		_banner_text = "/!\\ RADIATION STORM IN %ds - " + todo
		_banner_left = cme.time_left
		_banner_color = Color("ffe14a")
	elif cme.get("phase", "") == "wave":
		if cme.get("shields", false):
			_banner_text = "RADIATION WAVE - SHIELDS HOLDING"
		elif cme.get("safe", false):
			_banner_text = "RADIATION WAVE - SHIP IN SAFE MODE"
		else:
			_banner_text = "RADIATION WAVE - SHIP UNPROTECTED!"
		_banner_color = Color("8cffb0") if protected else Color("ff5050")
	elif blackout > 0.0:
		_banner_text = "BLACKOUT - SOLAR BUS TRIPPED (%ds)"
		_banner_left = blackout
		_banner_color = Color("ff5050")
	elif dust.get("phase", "") == "warning":
		_banner_text = "COMET DEBRIS IN %ds - NAVIGATOR TO THE BRIDGE"
		_banner_left = dust.time_left
		_banner_color = Color("e8c890")
	elif dust.get("phase", "") == "stream":
		_banner_text = "DEBRIS! NAVIGATOR: DOCK AT THE BRIDGE TO FLY (%ds)"
		_banner_left = dust.time_left
		_banner_color = Color("ff8a5c")
	elif dust.get("phase", "") == "flying":
		_banner_text = "NAVIGATOR IS FLYING THROUGH THE DEBRIS"
		_banner_color = Color("e8c890")


func _process(delta: float) -> void:
	_time += delta
	_banner_left = maxf(_banner_left - delta, 0.0)
	if _banner_text == "":
		_banner.text = ""
		return
	_banner.text = _banner_text % ceili(_banner_left) if "%d" in _banner_text else _banner_text
	_banner.modulate = _banner_color if fmod(_time, 0.6) < 0.42 else Color(_banner_color, 0.45)


## Bottom-left hint; `role_text` (e.g. "NAV+PWR") is shown first in co-op.
func show_role(role_text: String) -> void:
	var keys := "WASD move · SHIFT run · SPACE use · K skin · H help · ESC menu"
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
	return UiFont.label(text, FONT_SIZE)
