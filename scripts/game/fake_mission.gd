extends Node
## FAKE MISSION — stand-in for Person A's Mission.gd so the ship map, stations and HUD
## can be built and tested now. Implements the contract draft in CLAUDE.md
## ("Cruise gameplay") with made-up numbers. Same public API as the real one:
##   start(design), tick(dt), predict_path() -> PackedVector2Array
## When the real Mission.gd lands, swap the script on the "Mission" node and delete this file.

const DAYS_PER_SECOND := 2.9  # ~259-day cruise in ~90 s

const DSN_SITES := ["GOLDSTONE", "MADRID", "CANBERRA"]
const DSN_PASS := 9.0   # seconds a site is in view
const DSN_GAP := 4.0    # seconds with no site in view

const LOADS := ["instruments", "transmitter", "heater"]
const LOAD_DRAW := {"instruments": 1.2, "transmitter": 0.8, "heater": 0.6}  # % per second
const BASE_DRAW := 0.3
const SOLAR_CHARGE := 1.8
const DATA_RATE := 1.0       # % per second while instruments are on
const DOWNLINK_RATE := 9.0   # % per second while downlinking in a pass

const EVENT_TYPES := {
	"solar_storm": {"role": "engineer", "title": "Solar storm fault", "duration": 14.0, "work": 2.0, "fault": true},
	"thruster_leak": {"role": "navigator", "title": "Thruster leak", "duration": 14.0, "work": 2.0, "fault": true},
	"antenna_glitch": {"role": "comms", "title": "Antenna glitch", "duration": 14.0, "work": 1.5, "fault": true},
	"science_window": {"role": "scientist", "title": "Dust storm on Mars", "duration": 12.0, "work": 2.5, "fault": false},
}
const REPAIR_WORK := 3.0
const SCIENCE_GAIN := 20.0

var state := {}
var _next_id := 1
var _event_timer := 4.0
var _emit_timer := 0.0
var _dsn_clock := 0.0
var _downlinking := false
var _overflow_warned := false
var _rng := RandomNumberGenerator.new()


func start(design: Dictionary) -> void:
	state = {
		day = 0.0,
		power = 80.0,
		fuel = 100.0,
		data = 20.0,
		science_sent = 0.0,
		science_lost = 0.0,
		dsn = {site = "", time_left = 0.0},
		loads = {instruments = true, transmitter = true, heater = false},
		offline = [],
		events = [],
		last_action = "",
		action_seq = 0,
		design = design,
	}
	if not Events.action_requested.is_connected(_on_action):
		Events.action_requested.connect(_on_action)
	_emit()


func tick(dt: float) -> void:
	if state.is_empty():
		return
	state.day += dt * DAYS_PER_SECOND
	_tick_power(dt)
	_tick_data(dt)
	_tick_dsn(dt)
	_tick_events(dt)
	_emit_timer -= dt
	if _emit_timer <= 0.0:
		_emit()


func predict_path() -> PackedVector2Array:
	return PackedVector2Array()


# --- background pressure -------------------------------------------------------------

func _tick_power(dt: float) -> void:
	var draw := BASE_DRAW
	for load: String in LOADS:
		if state.loads[load]:
			draw += LOAD_DRAW[load]
	state.power = clampf(state.power + (SOLAR_CHARGE - draw) * dt, 0.0, 100.0)
	if state.power <= 0.0 and (state.loads.instruments or state.loads.transmitter):
		for load: String in LOADS:
			state.loads[load] = false
		_say("BROWNOUT: all loads tripped")


func _tick_data(dt: float) -> void:
	if state.loads.instruments:
		state.data += DATA_RATE * dt
	if state.data > 100.0:
		state.science_lost += state.data - 100.0
		state.data = 100.0
		if not _overflow_warned:
			_overflow_warned = true
			_say("DATA OVERFLOW: science is being lost")
	elif state.data < 95.0:
		_overflow_warned = false
	if _downlinking and _can_downlink():
		var sent := minf(DOWNLINK_RATE * dt, state.data)
		state.data -= sent
		state.science_sent += sent


func _tick_dsn(dt: float) -> void:
	_dsn_clock += dt
	var period := DSN_PASS + DSN_GAP
	var phase := fmod(_dsn_clock, period)
	if phase < DSN_PASS:
		state.dsn = {site = DSN_SITES[int(_dsn_clock / period) % DSN_SITES.size()],
				time_left = DSN_PASS - phase}
	else:
		state.dsn = {site = "", time_left = period - phase}


func _tick_events(dt: float) -> void:
	_event_timer -= dt
	if _event_timer <= 0.0:
		_event_timer = _rng.randf_range(5.0, 9.0)
		_spawn_random_event()
	for event: Dictionary in state.events.duplicate():
		if event.time_left < 0.0:
			continue  # repairs have no timer
		event.time_left -= dt
		if event.time_left <= 0.0:
			_expire(event)


func _spawn_random_event() -> void:
	var busy := {}
	for event: Dictionary in state.events:
		busy[event.role] = true
	var options := []
	for kind: String in EVENT_TYPES:
		if not busy.has(EVENT_TYPES[kind].role):
			options.append(kind)
	if options.is_empty():
		return
	var kind: String = options[_rng.randi() % options.size()]
	var info: Dictionary = EVENT_TYPES[kind]
	var event := {
		id = _next_id, kind = kind, role = info.role, title = info.title,
		time_left = info.duration, duration = info.duration, work_time = info.work, repair = false,
	}
	_next_id += 1
	state.events.append(event)
	Events.event_started.emit(event)
	_emit()


func _expire(event: Dictionary) -> void:
	_remove_event(event)
	if EVENT_TYPES[event.kind].fault:
		if event.role not in state.offline:
			state.offline.append(event.role)
		var repair := {
			id = _next_id, kind = "repair", role = event.role, title = "Repair " + event.role,
			time_left = -1.0, duration = -1.0, work_time = REPAIR_WORK, repair = true,
		}
		_next_id += 1
		state.events.append(repair)
		Events.event_started.emit(repair)
		_say("%s OFFLINE: %s" % [event.role.to_upper(), event.title])
	else:
		_say("Missed: " + event.title)


func _remove_event(event: Dictionary) -> void:
	state.events.erase(event)
	Events.event_ended.emit(str(event.id))


# --- actions ---------------------------------------------------------------------------

func _on_action(role: String, action: Dictionary) -> void:
	if state.is_empty():
		return
	match action.get("type", ""):
		"resolve":
			_resolve(int(action.get("id", -1)))
		"burn":
			if _refuse_if_offline(role):
				return
			state.fuel = maxf(state.fuel - 4.0, 0.0)
			state.power = maxf(state.power - 3.0, 0.0)
			_say("NAV: burn " + str(action.get("dir", "")))
		"toggle_load":
			if _refuse_if_offline(role):
				return
			var load: String = action.get("load", "")
			if state.loads.has(load):
				state.loads[load] = not state.loads[load]
				_say("PWR: %s %s" % [load, "ON" if state.loads[load] else "OFF"])
		"downlink":
			_downlinking = bool(action.get("on", false))
			if _downlinking and not _can_downlink():
				if "comms" in state.offline:
					_say("COM: antenna OFFLINE")
				elif not state.loads.transmitter:
					_say("COM: transmitter is OFF - ask Engineer")
				else:
					_say("COM: no DSN station in view")
	_emit()


func _resolve(id: int) -> void:
	for event: Dictionary in state.events:
		if event.id != id:
			continue
		if event.repair:
			state.offline.erase(event.role)
			_say("%s back ONLINE" % event.role.to_upper())
		elif event.kind == "science_window":
			if not state.loads.instruments:
				_say("SCI: instruments are OFF - ask Engineer")
				return  # ticket stays, try again
			state.data += SCIENCE_GAIN
			state.power = maxf(state.power - 5.0, 0.0)
			_say("SCI: observation captured")
		else:
			_say("Fixed: " + event.title)
		_remove_event(event)
		return


func _can_downlink() -> bool:
	return state.dsn.site != "" and state.loads.transmitter and "comms" not in state.offline


func _refuse_if_offline(role: String) -> bool:
	if role in state.offline:
		_say("%s is OFFLINE - repair it first" % role.to_upper())
		_emit()
		return true
	return false


func _say(text: String) -> void:
	state.last_action = text
	state.action_seq += 1


func _emit() -> void:
	_emit_timer = 0.25
	Events.state_changed.emit(state)
