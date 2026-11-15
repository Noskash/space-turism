extends Node
## FAKE MISSION — stand-in for Person A's Mission.gd so the ship map, stations and HUD
## can be built and tested now. Implements the contract draft in CLAUDE.md
## ("Cruise gameplay"). Its numbers come from the design (DesignRules.mission_params):
## battery size, solar, loads, storage, downlink, fault rates... Same public API as the real one:
##   start(design), tick(dt), predict_path() -> PackedVector2Array
## When the real Mission.gd lands, swap the script on the "Mission" node and delete this file.

const DAYS_PER_SECOND := 2.9  # ~259-day cruise in ~90 s

const DSN_SITES := ["GOLDSTONE", "MADRID", "CANBERRA"]
const DSN_GAP := 4.0    # seconds with no site in view

const LOADS := ["instruments", "transmitter", "heater"]

# --- space weather (real phenomena, SIMPLIFIED timing) ---
# Solar radiation storm (solar particle event / CME): the base-kit weather sensor warns 9 s ahead
# (solar particle monitor: +7 s). With RADIATION SHIELDING bought, one crew member raises the shield
# at the Mission Hub holo-table (ShieldGame minigame). Without it, the Engineer can only put the ship
# in SAFE MODE (SafeModeGame at the Engineer station: cut the breakers in order): everything powers
# down, so the wave does no damage
# but science and downlink stop until it has passed. Neither done when the wave hits = the ship is
# disabled: solar bus trips (blackout) and stations are knocked out.
const CME_FIRST := 24.0
const CME_GAP := Vector2(42.0, 58.0)
const CME_WARN := 9.0              # base weather sensor; + params.cme_warning (particle monitor)
const SAFE_MODE_BREAKERS := 4      # breakers to cut in SafeModeGame (rad-hard CPU: one fewer)
const CME_WAVE := 6.0
const BLACKOUT_TIME := 10.0
const SHIELD_CHARGES := 3          # capacitor charges in the minigame (rad-hard CPU: one fewer)
# Comet debris stream: chunks from a comet's trail. The Navigator docks at the Bridge and flies the
# ship through it (DodgeGame, full screen, ~6 s). Nobody flying = the ship takes the hits.
const DUST_FIRST := 50.0
const DUST_GAP := Vector2(45.0, 60.0)
const DUST_WARN := 7.0
const PILOT_WAIT := 8.0            # stream: seconds to get a pilot into the Bridge
const DODGE_TIME := 6.0            # minigame length
const UNPILOTED_HITS := 3

const EVENT_TYPES := {
	"solar_storm": {"role": "engineer", "title": "Solar storm fault", "duration": 14.0, "work": 2.0, "fault": true},
	"thruster_leak": {"role": "navigator", "title": "Thruster leak", "duration": 14.0, "work": 2.0, "fault": true},
	"antenna_glitch": {"role": "comms", "title": "Antenna glitch", "duration": 14.0, "work": 1.5, "fault": true},
	"science_window": {"role": "scientist", "title": "Dust storm on Mars", "duration": 12.0, "work": 2.5, "fault": false},
}
var state := {}
var params := {}            # DesignRules.mission_params(design)
var _data_units := 0.0      # stored science; state.data = % of storage
var _next_id := 1
var _event_timer := 4.0
var _emit_timer := 0.0
var _dsn_clock := 0.0
var _downlinking := false
var _overflow_warned := false
var _rng := RandomNumberGenerator.new()
var crew_size := 1          # set by the game before start(); more crew = more prep work
var _cme_timer := CME_FIRST
var _dust_timer := DUST_FIRST


func start(design: Dictionary) -> void:
	params = DesignRules.mission_params(design)
	_data_units = params.storage * 0.2
	var launch: Dictionary = design.get("launch", {})
	state = {
		day = 0.0,
		power = 80.0,
		fuel = float(launch.get("fuel_left", 100.0)),  # what the launch left in the tank
		data = 20.0,  # % of storage
		science_sent = 0.0,
		science_lost = 0.0,
		dsn = {site = "", time_left = 0.0},
		loads = {instruments = true, transmitter = true, heater = false},
		offline = [],
		events = [],
		cme = _cme_idle(),   # phase "" | "warning" | "wave"; shields / safe = protected
		blackout = 0.0,                               # seconds the solar bus stays tripped
		dust = _dust_idle(0),   # phase "" | "warning" | "stream" (waiting for a pilot) | "flying"
		radio = {on = true, track = _rng.randi() % 5},  # the Mission Hub radio (RadioSet / Radio)
		last_action = "",
		action_seq = 0,
		design = design,
	}
	# Launch damage: each hit starts the cruise with a station knocked out.
	var roles := ["engineer", "navigator", "comms", "scientist"]
	roles.shuffle()
	for i in mini(int(launch.get("damage", 0)), roles.size()):
		state.offline.append(roles[i])
		state.events.append({id = _next_id, kind = "repair", role = roles[i],
				title = "Launch damage: " + roles[i], time_left = -1.0, duration = -1.0,
				work_time = params.repair_work, repair = true})
		_next_id += 1
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
	_tick_cme(dt)
	_tick_dust(dt)
	_emit_timer -= dt
	if _emit_timer <= 0.0:
		_emit()


func predict_path() -> PackedVector2Array:
	return PackedVector2Array()


# --- background pressure -------------------------------------------------------------

## Watts in and out of the battery; % per second = watts / battery_wh.
func _tick_power(dt: float) -> void:
	var draw: float = params.base_w
	for load: String in LOADS:
		if state.loads[load]:
			draw += params[load + "_w"]
	var gen: float = params.solar_w
	if state.cme.get("safe", false):   # safe mode: everything but the base load stays off
		for load: String in LOADS:
			state.loads[load] = false
		draw = params.base_w
	if state.blackout > 0.0:
		gen = params.storm_proof_w  # solar bus tripped: only an RTG still makes power
		for load: String in LOADS:
			state.loads[load] = false
		draw = params.base_w
	state.power = clampf(state.power + (gen - draw) / params.battery_wh * dt, 0.0, 100.0)
	if state.power <= 0.0 and (state.loads.instruments or state.loads.transmitter):
		for load: String in LOADS:
			state.loads[load] = false
		_say("BROWNOUT: all loads tripped")


func _tick_data(dt: float) -> void:
	var storage: float = params.storage
	if state.loads.instruments:
		_data_units += params.data_rate * dt
	if _data_units > storage:
		state.science_lost += _data_units - storage
		_data_units = storage
		if not _overflow_warned:
			_overflow_warned = true
			_say("DATA OVERFLOW: science is being lost")
	elif _data_units < storage * 0.95:
		_overflow_warned = false
	if _downlinking and _can_downlink():
		var sent := minf(params.downlink_rate * dt, _data_units)
		_data_units -= sent
		state.science_sent += sent
	state.data = _data_units / storage * 100.0


func _tick_dsn(dt: float) -> void:
	_dsn_clock += dt
	var pass_time: float = params.dsn_pass
	var period := pass_time + DSN_GAP
	var phase := fmod(_dsn_clock, period)
	if phase < pass_time:
		state.dsn = {site = DSN_SITES[int(_dsn_clock / period) % DSN_SITES.size()],
				time_left = pass_time - phase}
	else:
		state.dsn = {site = "", time_left = period - phase}


func _tick_events(dt: float) -> void:
	_event_timer -= dt
	if _event_timer <= 0.0:
		_event_timer = _rng.randf_range(5.0, 9.0) * (1.5 if crew_size <= 1 else 1.0)
		if state.cme.phase == "" and state.dust.phase not in ["stream", "flying"]:
			_spawn_random_event()
	for event: Dictionary in state.events.duplicate():
		if event.time_left < 0.0 or event.kind in ["shields", "safe_mode", "dust"]:
			continue  # repairs have no timer; space-weather tickets are run by their own tick
		event.time_left -= dt
		if event.time_left <= 0.0:
			_expire(event)


func _spawn_random_event() -> void:
	var busy := {}
	for event: Dictionary in state.events:
		busy[event.role] = true
	# Weighted pick: the design makes some events rarer (rad-hard CPU, reaction wheels)
	# and science windows commoner (more instruments).
	var weights := {
		solar_storm = params.storm_weight, thruster_leak = params.leak_weight,
		antenna_glitch = 1.0, science_window = 1.0 + 0.3 * params.instrument_count,
	}
	var total := 0.0
	for k: String in weights.keys():
		if busy.has(EVENT_TYPES[k].role):
			weights.erase(k)
		else:
			total += weights[k]
	if weights.is_empty():
		return
	var roll := _rng.randf() * total
	var kind: String = weights.keys()[-1]
	for k: String in weights:
		roll -= weights[k]
		if roll <= 0.0:
			kind = k
			break
	var info: Dictionary = EVENT_TYPES[kind]
	var event := {
		id = _next_id, kind = kind, role = info.role, title = info.title,
		time_left = info.duration, duration = info.duration, work_time = info.work, repair = false,
	}
	_next_id += 1
	state.events.append(event)
	Events.event_started.emit(event)
	_emit()


# --- space weather ------------------------------------------------------------------------

func _tick_cme(dt: float) -> void:
	var cme: Dictionary = state.cme
	if state.blackout > 0.0:
		state.blackout = maxf(state.blackout - dt, 0.0)
		if state.blackout == 0.0:
			_say("Solar bus back on - Engineer: switch loads on")
	match cme.phase:
		"":
			_cme_timer -= dt
			if _cme_timer <= 0.0:
				_start_cme()
		"warning":
			cme.time_left -= dt
			for e: Dictionary in state.events:
				if e.kind in ["shields", "safe_mode"]:
					e.time_left = cme.time_left
			if cme.time_left <= 0.0:
				_cme_hits()
		"wave":
			cme.time_left -= dt
			if cme.time_left <= 0.0:
				var was_safe: bool = cme.get("safe", false)
				state.cme = _cme_idle()
				_cme_timer = _rng.randf_range(CME_GAP.x, CME_GAP.y)
				_say("Storm passed - Engineer: switch loads back on" if was_safe else "Radiation storm passed - shields down")


static func _cme_idle() -> Dictionary:
	return {phase = "", time_left = 0.0, duration = 0.0, shields = false, safe = false, shielding = false}


func _start_cme() -> void:
	var warn: float = CME_WARN + float(params.cme_warning)
	var shielding: bool = params.shields
	state.cme = {phase = "warning", time_left = warn, duration = warn, shields = false, safe = false,
			shielding = shielding}
	var e := {id = _next_id, time_left = warn, duration = warn, repair = false}
	if shielding:   # radiation shielding bought: anyone raises it at the Mission Hub (ShieldGame)
		e.merge({kind = "shields", role = "team", title = "Raise the shields", work_time = 0.0,
				charges = maxi(SHIELD_CHARGES + int(params.cme_tasks), 1)})
		_say("SOLAR RADIATION STORM IN %ds - RAISE THE SHIELDS!" % int(warn))
	else:           # no shielding: the Engineer powers the ship down (hold-to-work ticket)
		e.merge({kind = "safe_mode", role = "engineer", title = "Enter safe mode", work_time = 0.0,
				breakers = maxi(SAFE_MODE_BREAKERS + int(params.cme_tasks), 2)})
		_say("SOLAR RADIATION STORM IN %ds - ENGINEER: SAFE MODE!" % int(warn))
	_next_id += 1
	state.events.append(e)
	Events.event_started.emit(e)
	_emit()


## The wave arrives: shields up = safe (and the instruments record the storm); down = disabled.
func _cme_hits() -> void:
	var shields: bool = state.cme.shields
	var safe: bool = state.cme.get("safe", false)
	state.cme = {phase = "wave", time_left = CME_WAVE, duration = CME_WAVE, shields = shields, safe = safe,
			shielding = state.cme.get("shielding", false)}
	for e: Dictionary in state.events.duplicate():
		if e.kind in ["shields", "safe_mode"]:
			_remove_event(e)
	if shields:
		_data_units += params.science * 0.5
		_say("SHIELDS HELD - storm data recorded!")
	elif safe:
		_say("SAFE MODE - the ship rides out the storm (science paused)")
	else:
		state.blackout = BLACKOUT_TIME
		for load: String in LOADS:
			state.loads[load] = false
		state.power = maxf(state.power - 15.0, 0.0)
		_knock_offline("engineer", "Radiation: power bus")
		var others := ["comms", "scientist", "navigator"]
		_knock_offline(others[_rng.randi() % others.size()], "Radiation damage")
		_say("SHIELDS DOWN! SHIP DISABLED - BLACKOUT")
	_emit()


static func _dust_idle(hits: int) -> Dictionary:
	return {phase = "", time_left = 0.0, hits = hits, wheels = false, tracker = false}


func _tick_dust(dt: float) -> void:
	var dust: Dictionary = state.dust
	match dust.phase:
		"":
			_dust_timer -= dt
			if _dust_timer <= 0.0 and state.cme.phase == "":
				var warn: float = DUST_WARN + float(params.dust_warning)
				# What the minigame gets from the design (sent in the state, so clients know too).
				state.dust = {phase = "warning", time_left = warn, hits = 0,
						wheels = bool(params.steer_free), tracker = float(params.dust_warning) > 0.0}
				var e := {id = _next_id, kind = "dust", role = "navigator", title = "Comet debris",
						time_left = warn + PILOT_WAIT, duration = warn + PILOT_WAIT, work_time = -1.0, repair = false}
				_next_id += 1
				state.events.append(e)
				Events.event_started.emit(e)
				_say("COMET DEBRIS AHEAD - NAVIGATOR TO THE BRIDGE")
				_emit()
		"warning", "stream", "flying":
			dust.time_left -= dt
			for e: Dictionary in state.events:
				if e.kind == "dust":
					e.time_left = dust.time_left + (PILOT_WAIT if dust.phase == "warning" else 0.0)
			if dust.time_left > 0.0:
				return
			match dust.phase:
				"warning":
					dust.phase = "stream"
					dust.time_left = PILOT_WAIT
					_say("DEBRIS! Navigator: dock at the Bridge to fly")
					_emit()
				"stream":
					_end_dust(UNPILOTED_HITS, 0.0, 0.0)   # nobody flew it
				"flying":
					_end_dust(2, 0.0, 0.0)                # pilot never reported back (disconnect)


## Result of a flight (or of nobody flying): each hit damages something; thrusters cost fuel.
func _end_dust(hits: int, thrust: float, turning: float) -> void:
	var wheels: bool = state.dust.get("wheels", false)
	hits = clampi(hits, 0, 4)
	for i in hits:
		var roles := ["engineer", "comms", "scientist", "navigator"]
		if _rng.randf() < 0.35:
			state.fuel = maxf(state.fuel - 8.0, 0.0)
		else:
			_knock_offline(roles[_rng.randi() % roles.size()], "Debris impact")
	var fuel_used := thrust * (0.5 if wheels else 1.0) + (0.0 if wheels else turning * 0.6)
	state.fuel = maxf(state.fuel - fuel_used, 0.0)
	state.dust = _dust_idle(int(state.dust.get("hits", 0)) + hits)
	for e: Dictionary in state.events.duplicate():
		if e.kind == "dust":
			_remove_event(e)
	_dust_timer = _rng.randf_range(DUST_GAP.x, DUST_GAP.y)
	_say("Debris cleared - %s" % ("no hits!" if hits == 0 else "%d hit(s)" % hits))
	_emit()


func _knock_offline(role: String, title: String) -> void:
	if role in state.offline:
		return
	state.offline.append(role)
	var repair := {
		id = _next_id, kind = "repair", role = role, title = title,
		time_left = -1.0, duration = -1.0, work_time = params.repair_work, repair = true,
	}
	_next_id += 1
	state.events.append(repair)
	Events.event_started.emit(repair)


func _expire(event: Dictionary) -> void:
	_remove_event(event)
	if EVENT_TYPES[event.kind].fault:
		if event.role not in state.offline:
			state.offline.append(event.role)
		var repair := {
			id = _next_id, kind = "repair", role = event.role, title = "Repair " + event.role,
			time_left = -1.0, duration = -1.0, work_time = params.repair_work, repair = true,
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
			state.fuel = maxf(state.fuel - params.burn_fuel, 0.0)
			state.power = maxf(state.power - 3.0, 0.0)
			_say("NAV: burn " + str(action.get("dir", "")))
		"radio":
			state.radio.on = not state.radio.on
			if state.radio.on:
				state.radio.track = int(state.radio.track) + 1  # tunes to the next track
			_say("Radio " + ("ON" if state.radio.on else "OFF"))
		"dodge_start":
			if state.dust.phase == "stream" and role not in state.offline:
				state.dust.phase = "flying"
				state.dust.time_left = DODGE_TIME + 3.0   # grace for the result to arrive
				_say("Navigator is flying through the debris!")
		"dodge_result":
			if state.dust.phase == "flying":
				_end_dust(int(action.get("hits", 0)), float(action.get("thrust", 0.0)), float(action.get("turning", 0.0)))
				return
		"toggle_load":
			if _refuse_if_offline(role):
				return
			if state.blackout > 0.0:
				_say("NO POWER: solar bus tripped (%ds)" % ceili(state.blackout))
				_emit()
				return
			if state.cme.get("safe", false):
				_say("SAFE MODE: loads stay off until the storm passes")
				_emit()
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
				elif state.blackout > 0.0:
					_say("COM: no power - blackout")
				elif state.dust.phase == "flying":
					_say("COM: ship turned away from Earth (dodging)")
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
		elif event.kind == "dust":
			return  # not workable: it is dodged at the Bridge
		elif event.kind == "shields":
			state.cme.shields = true
			_say("SHIELDS UP!")
		elif event.kind == "safe_mode":
			state.cme.safe = true
			for load: String in LOADS:
				state.loads[load] = false
			_downlinking = false
			_say("SAFE MODE: ship powered down for the storm")
		elif event.kind == "science_window":
			if not state.loads.instruments:
				_say("SCI: instruments are OFF - ask Engineer")
				return  # ticket stays, try again
			_data_units += params.science
			state.power = maxf(state.power - 5.0, 0.0)
			_say("SCI: observation captured")
		else:
			_say("Fixed: " + event.title)
		_remove_event(event)
		return


func _can_downlink() -> bool:
	return state.dsn.site != "" and state.loads.transmitter and "comms" not in state.offline \
			and state.blackout <= 0.0 and state.dust.phase != "flying"


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
