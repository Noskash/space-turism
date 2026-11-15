extends CanvasLayer
## Mission HUD: resource bars + ticket chips along the top hull strip, DSN / science status
## and controls hint along the bottom, and a short toast for sim messages.
## Reads only Events.state_changed.

const BARS := [
	["power", "PWR", Color("ff9a3c")],
	["fuel", "FUEL", Color("4fd8ff")],
	["data", "DATA", Color("b77bff")],
]
## Second row under the tickets: hull durability + cabin oxygen.
const LIFE_BARS := [
	["hull", "HULL", Color("c8ccd8")],
	["oxygen", "O2", Color("7fe0ff")],
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
var _life_labels := {}       # "hull"/"oxygen" -> Label (turn red when low)
var _life_box: HBoxContainer # hull + O2 row, hidden on missions without the hull system
var _goals: Label
var _goals_bg: ColorRect
var _toast_bg: ColorRect


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

	var life := HBoxContainer.new()
	_life_box = life
	life.position = Vector2(318, 21)
	life.add_theme_constant_override("separation", 5)
	_root.add_child(life)
	for bar_info in LIFE_BARS:
		var l := _label(bar_info[1])
		life.add_child(l)
		_life_labels[bar_info[0]] = l
		var bar := ResourceBar.new()
		bar.color = bar_info[2]
		bar.custom_minimum_size = Vector2(40, 5)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		life.add_child(bar)
		_bars[bar_info[0]] = bar

	_tickets = TicketStrip.new()
	_tickets.position = Vector2(330, 8)
	_tickets.size = Vector2(120, 12)
	_root.add_child(_tickets)

	_status = _label("")
	_status.position = Vector2(220, 243)
	_status.size = Vector2(230, 10)
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
	radio_label.clip_text = true   # long track names stop short of the status line
	radio_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_root.add_child(radio_label)

	# Mission goals under the top bar (campaign missions only), e.g.
	# "GOALS  [x] STORMS 1/3  [ ] SENT 12/30  [ ] MARS: DAY 80/200".
	_goals_bg = ColorRect.new()
	_goals_bg.color = Color(0.02, 0.03, 0.08, 0.78)
	_goals_bg.position = Vector2(28, 20)
	_goals_bg.size = Vector2(0, 11)
	_goals_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_goals_bg)
	_goals = _label("")
	_goals.position = Vector2(30, 21)
	_root.add_child(_goals)

	# Sim messages: their own dark strip under the banner (the goal line took their old row).
	_toast_bg = ColorRect.new()
	_toast_bg.color = Color(0.02, 0.03, 0.08, 0.72)
	_toast_bg.position = Vector2(28, 45)
	_toast_bg.size = Vector2(10, 11)
	_toast_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_bg.modulate.a = 0.0
	_root.add_child(_toast_bg)
	_toast = _label("")
	_toast.position = Vector2(30, 46)
	_toast.modulate.a = 0.0
	_root.add_child(_toast)

	Events.state_changed.connect(_on_state_changed)


func _on_state_changed(state: Dictionary) -> void:
	# Sun distance on the transfer ellipse (same model as ShipLighting): sunlight falls as 1/r^2.
	var day: float = state.get("day", 0.0)
	var au: float = ShipLighting.TRANSFER_A * (1.0 - ShipLighting.TRANSFER_E ** 2) \
			/ (1.0 + ShipLighting.TRANSFER_E * cos(PI * clampf(ShipLighting.progress_of(state), 0.0, 1.0)))
	_day_label.text = "DAY %d  %.2f AU" % [int(day), au]
	_life_box.visible = bool(Missions.sim().get("hull", true))
	_update_goals(state)
	for key: String in _bars:
		_bars[key].set_value(float(state.get(key, 0)), _first_state)  # no animation on spawn
	_first_state = false
	var o2 := float(state.get("oxygen", 100.0))
	_life_labels.oxygen.modulate = Color("ff5050") if o2 < 35.0 and fmod(_time, 0.5) < 0.3 else Color.WHITE
	_life_labels.hull.modulate = Color("ff5050") if float(state.get("hull", 100.0)) < 40.0 else Color.WHITE
	_tickets.events = state.get("events", [])
	_update_banner(state)

	var dsn: Dictionary = state.get("dsn", {})
	var dsn_text := "DSN --"
	if dsn.get("site", "") != "":
		dsn_text = "DSN %s %ds" % [dsn.site, ceili(dsn.time_left)]
	_status.text = "%s · STORED %d · SENT %d · LOST %d" % [dsn_text, int(state.get("science_stored", 0)),
			int(state.get("science_sent", 0)), int(state.get("science_lost", 0))]
	# Keep the right edge fixed at 450 whatever the text length / TEXT SIZE setting.
	var status_w := maxf(230.0, _status.get_minimum_size().x)
	_status.size = Vector2(status_w, 10)
	_status.position.x = 450.0 - status_w
	radio_label.size = Vector2(maxf(_status.position.x - 36.0, 40.0), 10)

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
	var meteor_left := float(state.get("meteor", {}).get("time_left", -1.0))
	var breaches: int = state.get("breaches", []).size()
	var o2 := float(state.get("oxygen", 100.0))
	var conj: Dictionary = state.get("conjunction", {})
	var moi: Dictionary = state.get("moi", {})
	if state.get("lost", "") != "" or not state.get("finished", {}).is_empty():
		return  # the game-over panel / mission report says it
	if moi.get("phase", "") == "window":
		_banner_text = "MARS ARRIVAL - NAVIGATOR: HOLD THE BRAKE AT THE BRIDGE! (%ds)"
		_banner_left = _ticket_left(state, "moi")
		_banner_color = Color("ff8a4c")
	elif breaches > 0 and o2 < 40.0:
		_banner_text = "/!\\ OXYGEN %d%% - PATCH THE HULL BREACH%s NOW!" % [int(o2), "ES" if breaches > 1 else ""]
		_banner_color = Color("ff5050")
	elif meteor_left > 0.0 and meteor_left < 2.6:
		_banner_text = "/!\\ METEOROID INCOMING - NO POWER TO DODGE!"
		_banner_color = Color("ff5050")
	elif cme.get("phase", "") == "warning" and protected:
		_banner_text = "SHIELDS UP - RADIATION STORM IN %ds" if cme.get("shields", false) \
				else "SAFE MODE - STORM IN %ds - EVERYONE TO CARGO!"
		_banner_left = cme.time_left
		_banner_color = Color("8cd8ff")
	elif cme.get("phase", "") == "warning":
		var todo := "RAISE THE SHIELDS (MISSION HUB)" if cme.get("shielding", false) else "SAFE MODE (ENGINE ROOM), THEN ALL TO CARGO"
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
		_banner_text = "DEBRIS IN %ds - NAVIGATOR: STEER AROUND IT AT THE BRIDGE"
		_banner_left = dust.time_left
		_banner_color = Color("e8c890")
	elif dust.get("phase", "") == "stream":
		_banner_text = "DEBRIS! NAVIGATOR: DOCK AT THE BRIDGE TO FLY (%ds)"
		_banner_left = dust.time_left
		_banner_color = Color("ff8a5c")
	elif dust.get("phase", "") == "flying":
		_banner_text = "NAVIGATOR IS FLYING THROUGH THE DEBRIS"
		_banner_color = Color("e8c890")
	elif breaches > 0:
		_banner_text = "HULL BREACH%s - GRAB A TOOLBOX, HOLD SPACE ON THE HOLE" % ("ES" if breaches > 1 else "")
		_banner_color = Color("ffb04a")
	elif conj.get("phase", "") == "warning":
		_banner_text = "SOLAR CONJUNCTION IN %ds - COMMS: EMPTY THE RECORDER NOW"
		_banner_left = conj.time_left
		_banner_color = Color("ffe14a")
	elif conj.get("phase", "") == "active":
		_banner_text = "SOLAR CONJUNCTION - NO RADIO CONTACT (%ds)"
		_banner_left = conj.time_left
		_banner_color = Color("ffb04a")


func _ticket_left(state: Dictionary, kind: String) -> float:
	for e: Dictionary in state.get("events", []):
		if e.get("kind", "") == kind:
			return float(e.time_left)
	return 0.0


## "GOALS  [x] STORMS 1/3  [ ] SENT 12/30  [ ] MARS: DAY 80/200" (green when met).
func _update_goals(state: Dictionary) -> void:
	var goals := Missions.goals(state)
	if goals.is_empty():
		_goals.text = ""
		_goals_bg.size.x = 0
		return
	var parts := PackedStringArray()
	var all := true
	for g: Dictionary in goals:
		parts.append(("[x] " if g.done else "[ ] ") + str(g.short))
		all = all and g.done
	_goals.text = "GOALS  " + "   ".join(parts)
	_goals.modulate = Color("8cffb0") if all else Color(1, 1, 1, 0.95)
	_goals_bg.size.x = UiFont.width(_goals.text, FONT_SIZE) + 4


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
	var keys := "WASD move · SHIFT run · SPACE use · Q leave · K skin · H help · ESC menu"
	_hint.text = keys if role_text == "" else "YOU: %s · %s" % [role_text, keys]


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast_bg.size.x = UiFont.width(text, FONT_SIZE) + 4
	if _toast_tween:
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_bg.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(2.0)
	_toast_tween.set_parallel(true)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)
	_toast_tween.tween_property(_toast_bg, "modulate:a", 0.0, 0.5)


func _label(text: String) -> Label:
	return UiFont.label(text, FONT_SIZE)
