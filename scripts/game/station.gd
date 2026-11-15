class_name Station
extends Node2D
## A console on the ship map, built by ShipMap from ship_layout.json.
##
## Crew dock here (CrewMember handles walking/docking) and then drive it with:
##   control("left" / "right")  - the station's choices (burn, pick load)
##   set_holding(true / false)  - USE held: works the pending ticket, else the station's
##                                hold verb (Comms downlink, Engineer load toggle on tap)
## The station reads the sim only through Events.state_changed and talks back only
## through Events.action_requested.

const ROLE_COLORS := UiKit.ROLE_COLORS  # one palette for the whole UI (UiKit)
const ALERT_COLOR := Color("ff4040")
const FONT_SIZE := 7

var role := ""
var label_text := ""
var radius := 14.0

var _visitors: Array[Node] = []
var _docked: Node = null
var _time := 0.0
var _juice := UiJuice.new()
var _shown_ticket := -1  # ticket id the bubble last popped for

# Latest sim state relevant to this station.
var _state := {}
var _ticket := {}        # oldest pending ticket for this role ({} = none)
var _offline := false
var _dust := {}          # state.dust (Navigator flies through comet debris from the Bridge)
var _game: Node = null   # minigame this station opened for the local player (DodgeGame / ShieldGame)

# Hold-to-work.
var _holding := false
var _work_id := -1       # ticket being worked, -1 = none
var _progress := 0.0     # 0..1
var _downlinking := false
var _load_index := 0     # Engineer: selected load
var _tick_left := 0.0    # time to the next work tick sound


func setup(data: Dictionary) -> void:
	role = str(data.get("role", ""))
	label_text = str(data.get("label", role))
	radius = float(data.get("interact_radius", 14))
	position = Vector2(float(data.x), float(data.y))
	name = "Station_" + role


func _ready() -> void:
	z_index = 45  # bubbles and panels draw over the crew and over the lighting (ShipLighting)
	Events.state_changed.connect(_on_state_changed)


func color() -> Color:
	return ROLE_COLORS.get(role, Color.WHITE)


func can_reach(point: Vector2) -> bool:
	return point.distance_to(global_position) <= radius


func has_alert() -> bool:
	return _offline or not _ticket.is_empty() or _dodging()


## Navigator while comet debris is coming (warning, or waiting for a pilot).
func _dodging() -> bool:
	return role == "navigator" and _dust.get("phase", "") in ["warning", "stream", "flying"]


func _local_docked() -> bool:
	return _docked != null and not _docked.get("remote")


## Minigame open for the local player at this station (null = none).
func minigame() -> Node:
	return _game if is_instance_valid(_game) else null


func work_progress() -> float:
	return _progress if _work_id != -1 else 0.0


# --- visitors / docking ---------------------------------------------------------------

func add_visitor(who: Node) -> void:
	if who not in _visitors:
		_visitors.append(who)


func remove_visitor(who: Node) -> void:
	_visitors.erase(who)


func is_free() -> bool:
	return _docked == null


func dock(who: Node) -> void:
	_docked = who


func undock(who: Node) -> void:
	if _docked == who:
		set_holding(false)
		_docked = null


# --- controls --------------------------------------------------------------------------

func control(verb: String) -> void:
	if _offline:
		Sfx.play("denied")
	match role:
		"navigator":
			_send({type = "burn", dir = verb})
		"engineer":
			var loads := _load_names()
			if not loads.is_empty():
				_load_index = wrapi(_load_index + (1 if verb == "right" else -1), 0, loads.size())
				Sfx.play("select")


func set_holding(on: bool) -> void:
	if on == _holding:
		return
	_holding = on
	if on and _ticket.get("kind", "") == "shields" and _game == null and not _offline:
		_open_shield_game()
		return
	if on and _ticket.get("kind", "") == "safe_mode" and _game == null and not _offline:
		_open_safe_mode_game()
		return
	if on:
		if not _ticket.is_empty():
			_work_id = int(_ticket.id)
			_progress = 0.0
			_tick_left = 0.0
		elif _offline:
			Sfx.play("denied")
		elif role == "comms":
			_downlinking = true
			_send({type = "downlink", on = true})
		elif role == "engineer":
			var loads := _load_names()
			if not loads.is_empty():
				_send({type = "toggle_load", load = loads[_load_index]})
				Sfx.play("toggle")
	else:
		_work_id = -1
		_progress = 0.0
		if _downlinking:
			_downlinking = false
			_send({type = "downlink", on = false})


func _process(delta: float) -> void:
	_time += delta
	_juice.step(delta)
	_watch_games()
	if _work_id != -1:
		if _ticket.is_empty() or int(_ticket.id) != _work_id:
			_work_id = -1  # ticket expired or was replaced while we worked
			_progress = 0.0
		else:
			_progress += delta / maxf(float(_ticket.work_time), 0.1)
			_tick_left -= delta
			if _tick_left <= 0.0:
				_tick_left = 0.12
				Sfx.play("work_tick", 0.8 + _progress * 0.8)  # rises as the ring fills
			if _progress >= 1.0:
				_send({type = "resolve", id = _work_id})
				_work_id = -1  # needs a fresh press for the next ticket
				_progress = 0.0
	queue_redraw()


# --- minigames --------------------------------------------------------------------------

func _watch_games() -> void:
	if not is_instance_valid(_game):
		_game = null
	# Debris is here and our player sits at the Bridge: they fly it, full screen.
	if role == "navigator" and _game == null and _local_docked() and not _offline \
			and _dust.get("phase", "") == "stream":
		var game := DodgeGame.new()
		game.wheels = _dust.get("wheels", false)
		game.tracker = _dust.get("tracker", false)
		game.finished.connect(func(result: Dictionary) -> void:
			_send({type = "dodge_result", hits = result.hits, thrust = result.thrust, turning = result.turning}))
		_open(game)
		_send({type = "dodge_start"})
	# The wave arrived (ticket gone) while someone was still charging the shields.
	if _game is ShieldGame and _ticket.get("kind", "") != "shields":
		_game.abort()
	if _game is SafeModeGame and _ticket.get("kind", "") != "safe_mode":
		_game.abort()


func _open_shield_game() -> void:
	var game := ShieldGame.new()
	game.charges_needed = int(_ticket.get("charges", 3))
	game.deadline = float(_ticket.get("time_left", 15.0))
	var id: int = int(_ticket.id)
	game.finished.connect(func(result: Dictionary) -> void:
		if result.ok:
			_send({type = "resolve", id = id}))
	_open(game)


func _open_safe_mode_game() -> void:
	var game := SafeModeGame.new()
	game.breakers_needed = int(_ticket.get("breakers", 4))
	game.deadline = float(_ticket.get("time_left", 9.0))
	var id: int = int(_ticket.id)
	game.finished.connect(func(result: Dictionary) -> void:
		if result.ok:
			_send({type = "resolve", id = id}))
	_open(game)


func _open(game: Node) -> void:
	_game = game
	set_holding(false)
	var scene := get_tree().current_scene
	if scene == null:
		scene = get_parent().get_parent()  # Game root (stations live under ShipMap)
	scene.add_child(game)


func _send(action: Dictionary) -> void:
	Events.action_requested.emit(role, action)


func _on_state_changed(state: Dictionary) -> void:
	_state = state
	_dust = state.get("dust", {})
	_offline = role in state.get("offline", [])
	_ticket = {}
	for event: Dictionary in state.get("events", []):
		if event.role != role or event.get("kind", "") == "dust":
			continue  # the dust stream is dodged, not worked
		# Repairs first: an offline station can do nothing else.
		if _ticket.is_empty() or (event.repair and not _ticket.repair):
			_ticket = event


func _load_names() -> Array:
	return _state.get("loads", {}).keys()


## What the big action button (HUD, bottom right) shows while the local player is docked here:
## {icon, verb, enabled, hold, sides, progress}. `sides` = the verb is on LEFT/RIGHT, not USE.
func action_info() -> Dictionary:
	var info := {icon = "use", verb = "USE", enabled = true, hold = false, sides = false, progress = work_progress()}
	var kind: String = _ticket.get("kind", "")
	if kind == "shields":
		info.merge({icon = "shield", verb = "SHIELDS"}, true)
	elif kind == "safe_mode":
		info.merge({icon = "safe", verb = "SAFE MODE"}, true)
	elif not _ticket.is_empty():
		if _ticket.repair:
			info.merge({icon = "repair", verb = "REPAIR", hold = true}, true)
		elif kind == "science_window":
			info.merge({icon = "observe", verb = "OBSERVE", hold = true}, true)
		else:
			info.merge({icon = "work", verb = "FIX", hold = true}, true)
	elif _dodging() and not _offline:
		info.merge({icon = "fly", verb = "YOU FLY", enabled = false}, true)
	elif _offline:
		info.merge({icon = "repair", verb = "OFFLINE", enabled = false}, true)
	else:
		match role:
			"navigator":
				info.merge({icon = "burn", verb = "BURN", sides = true}, true)
			"engineer":
				info.merge({icon = "switch", verb = "SWITCH"}, true)
			"comms":
				var in_view: bool = _state.get("dsn", {}).get("site", "") != ""
				info.merge({icon = "downlink", verb = "DOWNLINK" if in_view else "NO DSN", hold = true, enabled = in_view}, true)
			"scientist":
				info.merge({icon = "observe", verb = "NO TARGET", enabled = false}, true)
			_:
				info.merge({verb = label_text, enabled = false}, true)
	return info


# --- drawing (UI kit) ------------------------------------------------------------------

func _draw() -> void:
	var c := color()
	var ticket_id := int(_ticket.get("id", -1))
	if ticket_id != _shown_ticket:
		_shown_ticket = ticket_id
		if ticket_id != -1:
			_juice.kick("bubble", 0.3)
	if has_alert():
		_draw_bubble()
	if _docked and not _docked.get("remote"):
		_draw_panel()
		if _work_id != -1:
			draw_arc(Vector2(0, -2), 9, -PI / 2, -PI / 2 + TAU * _progress, 24, c, 2.0)
	elif _docked:
		if not _visitors.is_empty():  # someone else is on it (co-op)
			_tag(Vector2(0, -radius - 4), "", "IN USE", Color(c, 0.6))
	elif not _visitors.is_empty():
		var pulse := 0.6 + 0.4 * sin(_time * 6.0)
		draw_arc(Vector2.ZERO, radius, 0, TAU, 24, Color(c, pulse), 1.0)
		_tag(Vector2(0, -radius - 4), UiKit.ROLE_ICONS.get(role, ""), label_text, c)
	elif _offline:
		draw_arc(Vector2.ZERO, radius, 0, TAU, 24, Color(ALERT_COLOR, 0.6), 1.0)


## Alert bubble above the station: a role-coloured block with "!" (or a red wrench when the
## station is OFFLINE) and a 4-segment countdown under it. Pops in when a new ticket arrives.
func _draw_bubble() -> void:
	var ticket := _ticket
	if ticket.is_empty():  # alert from the dust stream: show its countdown instead
		var total: float = _dust.get("time_left", 0.0)
		ticket = {time_left = total, duration = maxf(total, 12.0)}
	var urgent: bool = _offline or (ticket.time_left >= 0.0 and ticket.time_left < 4.0)
	var blink: bool = not urgent or fmod(_time, 0.4) < 0.25
	var fill := ALERT_COLOR if _offline else color()
	var s := _juice.pop("bubble", 0.6)
	var center := Vector2(0, -radius - 11 + _juice.bounce("bubble", 3.0))
	draw_set_transform(center, 0.0, Vector2(s, s))
	var box := Rect2(-6, -6, 12, 12)
	UiKit.panel(self, box, fill if blink else fill.darkened(0.45))
	if _offline:
		UiKit.icon(self, "wrench", Vector2(-4, -4), 1, Color.WHITE)
	else:
		draw_rect(Rect2(-1, -4, 2, 5), UiKit.INK)   # "!"
		draw_rect(Rect2(-1, 2, 2, 2), UiKit.INK)
	draw_set_transform(Vector2.ZERO)
	if not _offline and ticket.time_left >= 0.0 and ticket.duration > 0.0:
		var left := clampf(ticket.time_left / ticket.duration, 0.0, 1.0)
		var bar_col := Color.WHITE if urgent and fmod(_time, 0.3) < 0.15 else fill
		UiKit.seg_bar(self, Rect2(center.x - 8, center.y + 7, 17, 5), left, bar_col, 4)


## Lines for the docked panel: what USE and LEFT/RIGHT do right now.
func _panel_lines() -> Array[String]:
	var lines: Array[String] = []
	if _ticket.get("kind", "") == "shields":
		lines.append("RADIATION STORM IN %ds" % ceili(_ticket.time_left))
		lines.append("SPACE: RAISE SHIELDS")
	elif _ticket.get("kind", "") == "safe_mode":
		lines.append("RADIATION STORM IN %ds" % ceili(_ticket.time_left))
		lines.append("SPACE: SAFE MODE")
	elif not _ticket.is_empty():
		lines.append(_ticket.title.to_upper())
		lines.append("HOLD SPACE: " + ("REPAIR" if _ticket.repair else "FIX"))
	elif _dodging() and not _offline:
		match _dust.get("phase", ""):
			"warning":
				lines.append("DEBRIS IN %ds" % ceili(_dust.get("time_left", 0)))
				lines.append("STAY DOCKED: YOU FLY")
			_:
				lines.append("FLYING THROUGH DEBRIS")
	elif _offline:
		lines.append("OFFLINE")
	else:
		match role:
			"navigator":
				lines.append("< BURN >")
			"engineer":
				var loads := _load_names()
				if not loads.is_empty():
					var load: String = loads[_load_index]
					var on: bool = _state.loads[load]
					lines.append("< %s: %s >" % [load.to_upper(), "ON" if on else "OFF"])
					lines.append("SPACE: SWITCH")
			"comms":
				var dsn: Dictionary = _state.get("dsn", {})
				if dsn.get("site", "") != "":
					lines.append("DSN %s %ds" % [dsn.site, ceili(dsn.time_left)])
					lines.append("HOLD SPACE: DOWNLINK")
				else:
					lines.append("NO DSN - NEXT %ds" % ceili(dsn.get("time_left", 0)))
			"scientist":
				lines.append("NO TARGET")
			_:
				lines.append(label_text)
	return lines


## Panel above the docked crew (below the station if a HUD block is in the way).
## "SPACE" in a hint line is drawn as a key cap.
func _draw_panel() -> void:
	var lines := _panel_lines()
	var key := Controls.key_name("p1", "interact")
	var line_h := maxf(9.0, UiKit.line_h(FONT_SIZE) + 1)
	var width := 0.0
	for line in lines:
		width = maxf(width, _line_width(line, key))
	var box := Rect2(-roundf(width / 2.0) - 4, 0, roundf(width) + 8, line_h * lines.size() + 5)
	box.position.y = -radius - 6 - box.size.y
	if has_alert():
		box.position.y -= 20  # keep the bubble visible
	# Keep the panel on screen near the hull edges, and out from under the HUD blocks.
	var screen_x := global_position.x + box.position.x
	var shift := maxf(2.0 - screen_x, 0.0) - maxf(screen_x + box.size.x - 478.0, 0.0)
	box.position.x += shift
	if UiKit.hits_hud(Rect2(global_position + box.position, box.size)):
		box.position.y = 6
	UiKit.panel(self, box, UiKit.PANEL, color())
	for i in lines.size():
		_draw_line(Vector2(shift, box.position.y + 3 + line_h * (i + 1) - 2), lines[i], key, line_h)


func _line_width(line: String, key: String) -> float:
	if line.begins_with("HOLD SPACE: ") or line.begins_with("SPACE: "):
		var rest := line.trim_prefix("HOLD SPACE: ").trim_prefix("SPACE: ")
		var hold := UiKit.text_w("HOLD ", FONT_SIZE) if line.begins_with("HOLD") else 0.0
		return hold + UiKit.keycap_size(key, 6).x + 3 + UiKit.text_w(rest, FONT_SIZE)
	return UiKit.text_w(line, FONT_SIZE)


## One centred panel line at baseline `pos.y`; hint lines get a key cap.
func _draw_line(pos: Vector2, line: String, key: String, line_h: float) -> void:
	var w := _line_width(line, key)
	var x := roundf(pos.x - w / 2.0)
	if line.begins_with("HOLD SPACE: ") or line.begins_with("SPACE: "):
		if line.begins_with("HOLD"):
			UiKit.text(self, Vector2(x, pos.y), "HOLD", FONT_SIZE, UiKit.DIM, 0)
			x += UiKit.text_w("HOLD ", FONT_SIZE)
		var cap := UiKit.keycap_size(key, 6)
		UiKit.keycap(self, Vector2(x, pos.y - cap.y + 1), key, 6)
		x += cap.x + 3
		UiKit.text(self, Vector2(x, pos.y), line.trim_prefix("HOLD SPACE: ").trim_prefix("SPACE: "), FONT_SIZE, UiKit.WARN, 0)
	else:
		UiKit.text(self, Vector2(x, pos.y), line, FONT_SIZE, UiKit.TEXT, 0)


## Small floating label (icon + text) centred on `bottom_center`.
func _tag(bottom_center: Vector2, icon_name: String, text: String, col: Color) -> void:
	var tw := UiKit.text_w(text, 7)
	var w := tw + 6 + (10 if icon_name != "" else 0)
	var h := maxf(10.0, UiKit.line_h(7) + 2)
	var r := Rect2(roundf(bottom_center.x - w / 2.0), bottom_center.y - h, roundf(w), h)
	UiKit.panel(self, r, UiKit.PANEL_DARK, col)
	var x := r.position.x + 3
	if icon_name != "":
		UiKit.icon(self, icon_name, Vector2(x, r.position.y + roundf((h - 8) / 2.0)), 1, col)
		x += 10
	UiKit.text(self, Vector2(x, r.end.y - 2), text, 7, col, 0)
