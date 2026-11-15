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

const ROLE_COLORS := {
	"navigator": Color("4fd8ff"),
	"engineer": Color("ff9a3c"),
	"comms": Color("5cf07a"),
	"scientist": Color("b77bff"),
	"team": Color("d8f4ff"),
}
const ALERT_COLOR := Color("ff4040")
const FONT_SIZE := 8

var role := ""
var label_text := ""
var radius := 14.0

var _visitors: Array[Node] = []
var _docked: Node = null
var _time := 0.0

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
	return _offline or not _ticket.is_empty() or _dodging() or _send_alert()


## Comms while a DSN station is in view and science is waiting in the recorder: the downlink is
## not a ticket, so without this nothing pulls anyone to the Comms room (playtest: SENT 0 all game).
func _send_alert() -> bool:
	return role == "comms" and str(_state.get("dsn", {}).get("site", "")) != "" \
			and float(_state.get("data", 0)) > 25.0 and _state.get("loads", {}).get("transmitter", false) \
			and not _downlinking and not _state.get("cme", {}).get("shields", false)


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
	_watch_games()
	if _work_id != -1:
		if _ticket.is_empty() or int(_ticket.id) != _work_id:
			_work_id = -1  # ticket expired or was replaced while we worked
			_progress = 0.0
		else:
			var pace: float = Astronauts.dose("sick_slowdown") if (_docked and _docked.get("sick")) else 1.0
			_progress += delta * pace / maxf(float(_ticket.work_time), 0.1)
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
		game.mass = float(_dust.get("mass", DodgeGame.REF_MASS))
		game.hull = float(_dust.get("hull", 100.0))
		game.density = float(_dust.get("density", 1.0))
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
	# A running storm minigame shows the sim's real countdown, not its own drifting copy.
	if (_game is ShieldGame or _game is SafeModeGame) and _ticket.get("kind", "") in ["shields", "safe_mode"]:
		_game.deadline = float(_ticket.time_left)


func _load_names() -> Array:
	return _state.get("loads", {}).keys()


# --- drawing ---------------------------------------------------------------------------

func _draw() -> void:
	var c := color()
	if has_alert():
		_draw_bubble()
	if _docked and not _docked.get("remote"):
		_draw_panel()
		if _work_id != -1:
			draw_arc(Vector2(0, -2), 9, -PI / 2, -PI / 2 + TAU * _progress, 24, c, 2.0)
	elif _docked:
		if not _visitors.is_empty():  # someone else is on it (co-op)
			_text_centered(Vector2(0, -radius - 2), "IN USE", Color(c, 0.7))
	elif not _visitors.is_empty():
		var pulse := 0.6 + 0.4 * sin(_time * 6.0)
		draw_arc(Vector2.ZERO, radius, 0, TAU, 24, Color(c, pulse), 1.0)
		_text_centered(Vector2(0, -radius - 2), label_text, c)
	elif _offline:
		draw_arc(Vector2.ZERO, radius, 0, TAU, 24, Color(ALERT_COLOR, 0.6), 1.0)


## "!" bubble above the station with a countdown ring (or a blinking OFFLINE wrench).
func _draw_bubble() -> void:
	var center := Vector2(0, -radius - 10)
	var ticket := _ticket
	if ticket.is_empty() and role == "comms":  # DSN pass: the ring runs out with the pass
		var pass_left: float = _state.get("dsn", {}).get("time_left", 0.0)
		ticket = {time_left = pass_left, duration = maxf(pass_left, 9.0)}
	elif ticket.is_empty():  # alert from the dust stream: show its countdown instead
		var total: float = _dust.get("time_left", 0.0)
		ticket = {time_left = total, duration = maxf(total, 12.0)}
	var urgent: bool = _offline or (ticket.time_left >= 0.0 and ticket.time_left < 4.0)
	var blink: bool = not urgent or fmod(_time, 0.4) < 0.25
	var fill := ALERT_COLOR if _offline else color()
	draw_circle(center, 6, Color(0, 0, 0, 0.75))
	if blink:
		draw_circle(center, 4, fill)
	if not _offline and ticket.time_left >= 0.0:
		var left := clampf(ticket.time_left / ticket.duration, 0.0, 1.0)
		draw_arc(center, 6, -PI / 2, -PI / 2 + TAU * left, 20, Color.WHITE, 1.0)
	_text_centered(center + Vector2(0, 3), "X" if _offline else "!", Color.BLACK)


## Small panel above the docked crew: what USE and ←/→ do right now.
func _draw_panel() -> void:
	var lines: Array[String] = []
	if _ticket.get("kind", "") == "shields":
		lines.append("RADIATION STORM IN %ds" % ceili(_ticket.time_left))
		lines.append("SPACE: RAISE SHIELDS")
	elif _ticket.get("kind", "") == "science_window" and not _state.get("loads", {}).get("instruments", false):
		lines.append(_ticket.title.to_upper())
		lines.append("INSTRUMENTS OFF - ENGINEER!")
	elif _ticket.get("kind", "") == "science_window" and float(_state.get("data", 0)) > 95.0:
		lines.append("STORAGE FULL - IT'D BE LOST")
		lines.append("HOLD SPACE: OBSERVE ANYWAY")
	elif _ticket.get("kind", "") == "safe_mode":
		lines.append("RADIATION STORM IN %ds" % ceili(_ticket.time_left))
		lines.append("SPACE: SAFE MODE")
	elif _ticket.get("kind", "") == "moi":
		lines.append("MARS! BRAKE IN %ds" % ceili(_ticket.time_left))
		if float(_state.get("power", 0)) < 10.0:
			lines.append("BATTERY TOO LOW - ENGINEER!")
		else:
			lines.append("HOLD SPACE: BRAKE (FUEL %d%%)" % int(_state.get("fuel", 0)))
	elif _ticket.get("kind", "") == "power_up":
		lines.append("SYSTEMS OFF %ds" % ceili(_ticket.time_left))
		lines.append("HOLD SPACE: POWER UP")
	elif not _ticket.is_empty():
		lines.append(_ticket.title.to_upper())
		lines.append("HOLD SPACE: " + ("REPAIR" if _ticket.repair else "FIX"))
	elif _dodging() and not _offline:
		match _dust.get("phase", ""):
			"warning":
				lines.append("DEBRIS IN %ds" % ceili(_dust.get("time_left", 0)))
				lines.append("E: RADAR · A/D: BURN")
			_:
				lines.append("FLYING THROUGH DEBRIS")
	elif _offline:
		lines.append("OFFLINE")
	else:
		match role:
			"navigator":
				lines.append("< BURN >")
				lines.append("E: RADAR")
			"engineer":
				var loads := _load_names()
				if not loads.is_empty():
					var load: String = loads[_load_index]
					var on: bool = _state.loads[load]
					lines.append("< %s: %s >" % [load.to_upper(), "ON" if on else "OFF"])
					lines.append("SPACE: SWITCH")
			"comms":
				var dsn: Dictionary = _state.get("dsn", {})
				if _state.get("cme", {}).get("shields", false):
					lines.append("SHIELDS UP")
					lines.append("NO RADIO TILL STORM ENDS")
				elif not _state.get("loads", {}).get("transmitter", true):
					# Safe mode / blackout / brownout switch it off and it stays off: say so here.
					lines.append("TRANSMITTER OFF")
					lines.append("ASK THE ENGINEER")
				elif dsn.get("site", "") != "":
					lines.append("DSN %s %ds" % [dsn.site, ceili(dsn.time_left)])
					lines.append("HOLD SPACE: DOWNLINK")
				else:
					lines.append("NO DSN - NEXT %ds" % ceili(dsn.get("time_left", 0)))
			"scientist":
				if not _state.get("loads", {}).get("instruments", false):
					lines.append("INSTRUMENTS OFF")
					lines.append("ASK THE ENGINEER")
				elif float(_state.get("data", 0)) > 25.0:
					# Playtest: players looked for "send" here. Sending is the Comms room's job.
					lines.append("STORAGE %d%%" % int(_state.get("data", 0)))
					lines.append("SEND IT FROM COMMS ROOM")
				else:
					lines.append("NO TARGET")
					lines.append("STORAGE %d%%" % int(_state.get("data", 0)))
			_:
				lines.append(label_text)

	var font := UiFont.font()
	var width := 0.0
	for line in lines:
		width = maxf(width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(FONT_SIZE)).x)
	var line_h := maxf(8.0, UiFont.px(FONT_SIZE) + 1.0)   # grows with the TEXT SIZE setting
	var box := Rect2(-width / 2.0 - 3, -radius - 6 - line_h * lines.size() - 2,
			width + 6, line_h * lines.size() + 3)
	if has_alert():
		box.position.y -= 14  # keep the bubble visible
	# Keep the panel on screen near the hull edges.
	var screen_x := global_position.x + box.position.x
	var shift := maxf(2.0 - screen_x, 0.0) - maxf(screen_x + box.size.x - 478.0, 0.0)
	box.position.x += shift
	draw_rect(box, Color(0, 0, 0, 0.8))
	draw_rect(box, color(), false, 1.0)
	for i in lines.size():
		var hint := lines[i].begins_with("HOLD") or lines[i].begins_with("SPACE")
		var col := Color("9aa4b8") if hint else Color.WHITE
		_text_centered(Vector2(shift, box.position.y + line_h + line_h * i), lines[i], col)


func _text_centered(pos: Vector2, text: String, col: Color) -> void:
	var font := UiFont.font()
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(FONT_SIZE)).x
	draw_string(font, Vector2(roundf(pos.x - w / 2.0), roundf(pos.y)), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.px(FONT_SIZE), col)
