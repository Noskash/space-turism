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
# Disabled ship = it can't steer: chance that a stray meteoroid (real, sand-to-pebble sized; here a
# chunk, SIMPLIFIED) hits during the blackout. Shown approaching for METEOR_SHOW s before impact.
const METEOR_CHANCE := 0.35
const METEOR_SHOW := 2.5
const SHIELD_CHARGES := 3          # capacitor charges in the minigame (rad-hard CPU: one fewer)
# Comet debris stream: chunks from a comet's trail. The Navigator docks at the Bridge and flies the
# ship through it (DodgeGame, full screen, ~6 s). Nobody flying = the ship takes the hits.
const DUST_FIRST := 50.0
const DUST_GAP := Vector2(45.0, 60.0)
const DUST_WARN := 12.0           # the Bridge radar sees it this early (+ star tracker)
# Course change around the cloud (Bridge radar): the cloud sits across the path at a lateral offset;
# each Navigator burn (A/D at the Bridge, costs fuel) turns the heading by COURSE_STEP. Clear of the
# cloud at arrival = it passes by. Partly inside = a thinner field to fly through (dodge minigame).
const COURSE_STEP := 0.25          # lateral units per burn (shown as 5 degrees)
const DEG_PER_UNIT := 20.0
const CLOUD_W := 0.3               # cloud half-width (lateral units): 1-2 burns to clear it
const SHIP_W := 0.12               # ship half-width
const PILOT_WAIT := 8.0            # stream: seconds to get a pilot into the Bridge
const DODGE_TIME := 6.0            # minigame length
const UNPILOTED_HITS := 3

# Hull + oxygen. Every debris / meteoroid hit wears the hull (state.hull, 100 -> 0; damage per hit from
# the ship class, halved by a Whipple shield). The weaker the hull, the likelier a hit punches a BREACH:
# a hole somewhere in the ship that vents air. Crew grab a toolbox (lockers in Cargo + Engine Room),
# walk to the hole and hold USE to patch it. Each open breach drains oxygen; at 0 the mission is lost.
const LAYOUT_PATH := "res://sprites/lab_assets/ship_layout.json"
const BREACH_BASE := 0.15          # breach chance per hit at full hull...
const BREACH_WORN := 0.8           # ...plus this much more as the hull wears to 0
const MAX_BREACHES := 4
const O2_DRAIN := 1.4              # % per second per open breach
const O2_REFILL := 0.6             # % per second while sealed (life support)
const PATCH_HULL := 3.0            # hull points back for each sealed breach

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
var _tx_warned := false
var _rng := RandomNumberGenerator.new()
var crew_size := 1          # set by the game before start(); more crew = more prep work
var _cme_timer := CME_FIRST
var _layout := {}           # ship_layout.json: where breaches can open
var _dust_timer := DUST_FIRST

# --- campaign mission (Missions.current(), data/missions.json) ---
# The mission's "sim" block switches hazards on/off and sets their timing; cruise_days > 0 gives the
# flight an end: at arrival the Navigator gets the Mars Orbit Insertion ticket, then state.finished.
# No mission (sandbox / tests) = every hazard on, endless cruise, like before.
const MOI_WINDOW := 22.0           # seconds to brake once Mars is reached
const POWER_UP_TIME := 20.0        # power-up ticket after safe mode / blackout (x pace)
const POWER_UP_WORK := 2.0         # seconds of holding USE
const MOI_WORK := 4.0              # hold time for the brake burn
const MOI_POWER := 10.0            # % battery the burn needs
const ARRIVING := 0.92             # no new hazards after this share of the cruise
const CONJ_WARN := 15.0            # solar conjunction: warning, then no radio contact
const CONJ_TIME := 16.0
const BIG_STORM_EXTRA_WARN := 6.0  # Halloween-class storm: longer warning, longer wave, harder minigame
var _sim := {}
var _days_per_second := DAYS_PER_SECOND
# Pace by crew size (fewer players = fewer hands to run between stations). Index = players (0/1 = solo).
# PACE stretches storm / debris gaps, ticket timers and the cruise itself (so solo still meets enough
# storms for the goals); TICKET_PACE spaces out the random tickets (base 6-10 s with a full crew).
const PACE := [1.35, 1.35, 1.2, 1.1, 1.0]
const TICKET_PACE := [1.6, 1.6, 1.3, 1.15, 1.0]
const TICKET_GAP := Vector2(6.0, 10.0)
var _pace := 1.0
var _ticket_pace := 1.0
var _big_storm_done := false

# --- astronauts (data/astronauts.json): radiation dose per crew member + the Cargo storm shelter ---
# The sim can't see the map, so the host's game reports each crew member's room every frame
# (crew_rooms) and the roster once (set_crew). state.crew[key] = {astronaut, dose, sick, room}.
const SHELTER_ROOM := "cargo"
const SHELTER_EXTRA_WARN := 6.0    # no shielding = the crew must also reach the shelter: longer warning
const LEAK_CHANCE := 0.3           # a debris hit that breaches nothing may puncture a propellant line
const LEAK_RATE := 0.45            # fuel % per second until the Navigator seals it
const LEAK_WORK := 2.5
var crew_rooms := {}               # crew key -> room id, written by the host's game each frame

# --- burn shove, pings, ticket grades, fire (2026-11-15 fun pass) ---
# Burns: a course burn spools up BRACE_TIME s (state.brace, klaxon) before it fires; then state.shove
# throws every crew member who is walking (docked = holding on). The ship's nose points right (+x):
# a LEFT burn pushes the ship up the map, so the crew slide down, and the reverse; the Mars brake
# throws everyone forward, towards the Bridge. Each peer moves its own crew member (CrewMember).
const BRACE_TIME := 1.5
const SHOVE_COURSE := 1.0
const SHOVE_BRAKE := 1.8
const PING_TIME := 3.0             # state.pings: one "HELP!" / "NEED ENGINEER" marker per player
const MAX_PINGS := 6
const GRADE_PERFECT := 0.5         # share of a ticket's time still left when it was done
const GRADE_GOOD := 0.2
# Fire (SIMPLIFIED): the power bus overheats while the loads draw more than the panels make
# (state.bus_heat), and debris / meteoroid hits can spark one. Flames (state.fires [{id, room, x, y}])
# grow in their room, spread through the doors, block the room's station and eat oxygen. Put each
# flame out with an extinguisher (racks in the Mission Hub + Bridge): HOLD USE next to it -> douse.
const FIRE_GROW := 9.0             # a burning room gains a flame this often...
const FIRE_MAX := 4                # ...up to this many
const FIRE_SPREAD := 10.0          # a room with FIRE_SPREAD_AT+ flames lights a neighbour this often
const FIRE_SPREAD_AT := 3
const FIRE_KNOCKOUT := 12.0        # the room's station goes OFFLINE after burning this long
const FIRE_O2 := 0.5               # O2 % per second per flame (missions with the hull system)
const FIRE_ON_HIT := 0.25          # chance a hit that breaches nothing starts a fire
const HEAT_TIME := 20.0            # seconds of a 40 W deficit until the bus catches fire
const HEAT_COOL := 8.0             # heat % lost per second without a deficit
const HEAT_WARN := 50.0
const STATION_ROOMS := {comms = "comms", scientist = "science", engineer = "engineering",
		navigator = "bridge", team = "hub"}
const LOAD_ROOMS := {instruments = "science", transmitter = "comms", heater = "engineering"}
const ROOM_NAMES := {comms = "COMMS", science = "SCIENCE LAB", bridge = "BRIDGE", engineering = "ENGINE ROOM",
		hub = "MISSION HUB", cargo = "CARGO"}
# Frozen propellant (real: hydrazine freezes around 1-2 C, so tanks and fuel lines are heated all the way to
# Mars). SIMPLIFIED thermal model: state.tank_temp drifts (time constant TANK_TAU) towards an equilibrium set
# by sunlight (1/r^2 on the transfer ellipse, as ShipLighting), the HEATER load (+HEATER_GAIN) and part waste
# heat (params.tank_warm: RTG, radiator). Early on the Sun keeps the tanks warm; past ~1.25 AU they cool below
# freezing without the heater. Below COLD_C the Engineer gets a "freeze" ticket counting down to FREEZE_C
# (hold USE = heater ON). Frozen: no burns, no Mars brake, until the tanks are back above THAW_C. The heater
# draws power (and can overheat the bus -> fire), so the Engineer cycles it: the trade-off.
const FREEZE_C := 2.0
const THAW_C := 4.0
const COLD_C := 10.0              # below this (and still cooling) the Engineer gets a ticket: ~14 s at Mars
const WARM_C := 15.0               # warm enough: hint that the heater can go off
const TANK_TAU := 25.0
const HEATER_GAIN := 30.0
var _warm_said := false
var _room_burn := {}               # room -> seconds on fire (station knock-out)
var _room_grow := {}               # room -> seconds to its next flame
var _room_spread := {}             # room -> seconds to lighting a neighbour
var _heat_warned := false


func _on(flag: String) -> bool:
	return bool(_sim.get(flag, true))


func _arriving() -> bool:
	return state.cruise_days > 0.0 and state.day >= state.cruise_days * ARRIVING


func start(design: Dictionary) -> void:
	params = DesignRules.mission_params(design)
	_data_units = params.storage * 0.2
	var launch: Dictionary = design.get("launch", {})
	var mission := Missions.current()
	_sim = Missions.sim()   # the mission's block (+ the sandbox's hazard switches)
	var crew := clampi(crew_size, 0, PACE.size() - 1)
	_pace = PACE[crew]
	_ticket_pace = TICKET_PACE[crew]
	var cruise_days := float(mission.get("cruise_days", 0.0))
	var cruise_seconds := float(mission.get("cruise_seconds", 150.0))
	var trip := LaunchWindow.trip_days(design)   # launch window planner: STANDARD 259 d / FAST 180 d
	if cruise_days > 0.0 and trip > 0.0:
		cruise_seconds *= trip / float(LaunchWindow.PATHS.standard.trip)   # FAST is also shorter to play
		cruise_days = trip
	if cruise_days > 0.0:
		_days_per_second = cruise_days / maxf(cruise_seconds * _pace, 1.0)
	_cme_timer = float(_sim.get("storm_first", CME_FIRST)) * _pace
	_dust_timer = float(_sim.get("debris_first", DUST_FIRST)) * _pace
	_event_timer = 4.0 * _ticket_pace
	state = {
		mission = Missions.current_id(),
		cruise_days = cruise_days,          # 0 = endless (sandbox)
		storms_recorded = 0,                # radiation storms measured (instruments ON as the wave hit)
		conjunction = {phase = "", time_left = 0.0, duration = 0.0},   # "" | "warning" | "active" | "done"
		moi = {phase = "", time_left = 0.0},                            # "" | "window" | "done"
		finished = {},                      # {outcome = orbit|flyby|miss, ...} when the mission is over
		stats = {storms = 0, safe_modes = 0, disabled = 0, knockouts = 0, debris_hits = 0, breaches = 0,
				big_storm = "", fuel_at_moi = -1.0, caught_outside = 0, sheltered = 0,
				leaks = 0, leak_fuel = 0.0, leak_day = -1.0, sick = [],
				fires = 0, fire_overload = 0, fire_knockouts = 0, freezes = 0, frozen_time = 0.0},
		crew = {},              # key -> {astronaut, dose (mSv), sick, room} (set_crew + _tick_crew)
		day = 0.0,
		power = 80.0,
		# what the launch left in the tank, minus what the ship burned itself off the launch window
		fuel = maxf(float(launch.get("fuel_left", 100.0)) - LaunchWindow.fuel_cost(design), 0.0),
		data = 20.0,  # % of storage
		science_sent = 0.0,     # SCORE: science that reached Earth (Comms downlink)
		science_lost = 0.0,     # overflowed a full recorder
		science_stored = 0.0,   # waiting in the recorder (= data bar), not scored yet
		observations = 0,       # science windows captured (event walkthrough checks it)
		dsn = {site = "", time_left = 0.0},
		loads = {instruments = true, transmitter = true, heater = false},
		offline = [],
		events = [],
		cme = _cme_idle(),   # phase "" | "warning" | "wave"; shields / safe = protected
		blackout = 0.0,                               # seconds the solar bus stays tripped
		meteor = {time_left = -1.0, y = 135.0, seq = 0},   # incoming meteoroid during a blackout (-1 = none)
		hull = 100.0,           # durability %: lower = hits punch breaches more often
		oxygen = 100.0,         # cabin air %; 0 = mission lost
		breaches = [],          # [{id, x, y}] holes venting air (patched with a toolbox)
		toolboxes = [],         # [{id, x, y}] toolboxes someone dropped on the floor
		lost = "",              # why the mission was lost ("" = still flying)
		dust = _dust_idle(0),   # phase "" | "warning" | "stream" (waiting for a pilot) | "flying"
		radio = {on = true, track = _rng.randi() % 5},  # the Mission Hub radio (RadioSet / Radio)
		brace = _brace_idle(),  # a burn spooling up: {time_left (-1 = none), duration, dir}
		shove = {seq = 0, x = 0.0, y = 0.0, strength = 0.0},   # the burn fired: crew get thrown (seq bumps)
		pings = [],             # [{id, from, x, y, text, role}] crew call-outs (PING_TIME s)
		grades = {perfect = 0, good = 0, late = 0, missed = 0, streak = 0, best = 0, seq = 0},
		grade_log = [],         # last few [{seq, id, grade, role, streak}] (stamps; read entries with seq > seen)
		fires = [],             # [{id, room, x, y}] flames (put out with an extinguisher)
		bus_heat = 0.0,         # % power bus overheating (draw > solar); 100 = fire
		tank_temp = 20.0,       # propellant tank / fuel line temperature, C (SIMPLIFIED)
		fuel_frozen = false,    # below FREEZE_C: no burns until thawed above THAW_C
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
	if state.is_empty() or state.lost != "" or not state.finished.is_empty():
		return
	var day_before: float = state.day
	state.day += dt * _days_per_second
	if state.cruise_days > 0.0:
		state.day = minf(state.day, state.cruise_days)
	_tick_crew(state.day - day_before)
	_tick_leak(dt)
	_tick_brace(dt)
	_tick_pings(dt)
	if _on("fire"):
		_tick_heat(dt)
		_tick_fire(dt)
	_tick_power(dt)
	if _on("freeze"):
		_tick_tanks(dt)
	_tick_data(dt)
	_tick_conjunction(dt)
	_tick_dsn(dt)
	_tick_events(dt)
	if _on("storms"):
		_tick_cme(dt)
	if _on("debris"):
		_tick_dust(dt)
	if _on("hull"):
		_tick_oxygen(dt)
	_tick_moi(dt)
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
	# Recorder filling while nothing can ever be sent: the usual trap after a storm switched it off.
	if _data_units > storage * 0.7 and not state.loads.transmitter and state.blackout <= 0.0 \
			and not state.cme.get("safe", false):
		if not _tx_warned:
			_tx_warned = true
			_say("RECORDER %d%% but TRANSMITTER OFF - Engineer: switch it ON!" % int(_data_units / storage * 100.0))
	else:
		_tx_warned = false
	if _downlinking and _can_downlink():
		var sent := minf(params.downlink_rate * dt, _data_units)
		_data_units -= sent
		state.science_sent += sent
	state.data = _data_units / storage * 100.0
	state.science_stored = _data_units


func _tick_dsn(dt: float) -> void:
	_dsn_clock += dt
	if state.conjunction.phase == "active":   # the Sun blocks the radio: no station can hear us
		state.dsn = {site = "", time_left = state.conjunction.time_left}
		return
	var pass_time: float = params.dsn_pass
	var period := pass_time + DSN_GAP
	var phase := fmod(_dsn_clock, period)
	if phase < pass_time:
		var site: String = DSN_SITES[int(_dsn_clock / period) % DSN_SITES.size()]
		if state.dsn.site != site and state.data > 50.0 and not _downlinking and state.loads.transmitter \
				and not state.cme.get("shields", false):
			_say("DSN %s in view - COMMS: hold SPACE at the Comms station to send home %d data" % [site, int(_data_units)])
		state.dsn = {site = site, time_left = pass_time - phase}
	else:
		state.dsn = {site = "", time_left = period - phase}


func _tick_events(dt: float) -> void:
	_event_timer -= dt
	if _event_timer <= 0.0:
		_event_timer = _rng.randf_range(TICKET_GAP.x, TICKET_GAP.y) * _ticket_pace
		if state.cme.phase == "" and state.dust.phase not in ["stream", "flying"] and not _arriving():
			_spawn_random_event()
	for event: Dictionary in state.events.duplicate():
		if event.time_left < 0.0 or event.kind in ["shields", "safe_mode", "dust", "freeze"]:
			continue  # repairs have no timer; space-weather + freeze tickets are run by their own tick
		event.time_left -= dt
		if event.time_left <= 0.0:
			if event.kind == "moi":
				_grade_missed(event)
				_remove_event(event)
				_finish("miss")
				return
			_expire(event)


func _spawn_random_event() -> void:
	var busy := {}
	for event: Dictionary in state.events:
		busy[event.role] = true
	# Weighted pick: the design makes some events rarer (rad-hard CPU, reaction wheels)
	# and science windows commoner (more instruments).
	# The mission scales them too (MRO: lots of science windows).
	var faults := float(_sim.get("fault_weight", 1.0))
	var weights := {
		solar_storm = params.storm_weight * faults, thruster_leak = params.leak_weight * faults,
		antenna_glitch = 1.0 * faults,
		science_window = (1.0 + 0.3 * params.instrument_count) * float(_sim.get("science_weight", 1.0)),
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
	var duration: float = info.duration * _pace   # more time to walk over with fewer players
	var event := {
		id = _next_id, kind = kind, role = info.role, title = info.title,
		time_left = duration, duration = duration, work_time = info.work, repair = false,
	}
	_next_id += 1
	state.events.append(event)
	Events.event_started.emit(event)
	if kind == "science_window":   # say up front if it can't pay off
		if not state.loads.instruments:
			_say("SCIENCE WINDOW - instruments are OFF! Engineer: switch them on")
		elif state.data > 90.0:
			_say("SCIENCE WINDOW - but storage is FULL. Comms: downlink first!")
	_emit()


# --- space weather ------------------------------------------------------------------------

func _tick_cme(dt: float) -> void:
	var cme: Dictionary = state.cme
	var meteor: Dictionary = state.meteor
	if meteor.time_left >= 0.0:
		meteor.time_left -= dt
		if meteor.time_left <= 0.0:
			_meteor_hits()
	if state.blackout > 0.0:
		state.blackout = maxf(state.blackout - dt, 0.0)
		if state.blackout == 0.0:
			_spawn_power_up("Solar bus back on")
	match cme.phase:
		"":
			_cme_timer -= dt
			if _cme_timer <= 0.0 and not _arriving():
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
				var gap: Array = _sim.get("storm_gap", [CME_GAP.x, CME_GAP.y])
				_cme_timer = _rng.randf_range(float(gap[0]), float(gap[1])) * _pace
				if was_safe:
					_spawn_power_up("Storm passed")
				else:
					_say("Radiation storm passed - shields down")


static func _cme_idle() -> Dictionary:
	return {phase = "", time_left = 0.0, duration = 0.0, shields = false, safe = false, shielding = false, big = false}


func _start_cme() -> void:
	# Halloween-class storm (Odyssey mission): the first storm after `big_storm_at` of the cruise.
	var big_at := float(_sim.get("big_storm_at", -1.0))
	var big: bool = big_at > 0.0 and not _big_storm_done and state.cruise_days > 0.0 \
			and state.day >= state.cruise_days * big_at
	_big_storm_done = _big_storm_done or big
	var shielding: bool = params.shields
	var warn: float = CME_WARN + float(params.cme_warning) + (BIG_STORM_EXTRA_WARN if big else 0.0) \
			+ (0.0 if shielding else SHELTER_EXTRA_WARN)
	state.cme = {phase = "warning", time_left = warn, duration = warn, shields = false, safe = false,
			shielding = shielding, big = big}
	state.stats.storms = int(state.stats.storms) + 1
	var e := {id = _next_id, time_left = warn, duration = warn, repair = false}
	var what := "HALLOWEEN-CLASS STORM" if big else "SOLAR RADIATION STORM"
	if shielding:   # radiation shielding bought: anyone raises it at the Mission Hub (ShieldGame)
		e.merge({kind = "shields", role = "team", title = "Raise the shields", work_time = 0.0,
				charges = maxi(SHIELD_CHARGES + int(params.cme_tasks), 1) + (1 if big else 0)})
		_say("%s IN %ds - RAISE THE SHIELDS!" % [what, int(warn)])
	else:           # no shielding: the Engineer powers the ship down (hold-to-work ticket)
		e.merge({kind = "safe_mode", role = "engineer", title = "Enter safe mode", work_time = 0.0,
				breakers = maxi(SAFE_MODE_BREAKERS + int(params.cme_tasks), 2) + (1 if big else 0)})
		_say("%s IN %ds - ENGINEER: SAFE MODE! EVERYONE: TO CARGO!" % [what, int(warn)])
	_next_id += 1
	state.events.append(e)
	Events.event_started.emit(e)
	_emit()


## The wave arrives: shields up = safe (and the instruments record the storm); down = disabled.
func _cme_hits() -> void:
	var shields: bool = state.cme.shields
	var safe: bool = state.cme.get("safe", false)
	var big: bool = state.cme.get("big", false)
	var wave := CME_WAVE * (1.5 if big else 1.0)
	state.cme = {phase = "wave", time_left = wave, duration = wave, shields = shields, safe = safe,
			shielding = state.cme.get("shielding", false), big = big}
	for e: Dictionary in state.events.duplicate():
		if e.kind in ["shields", "safe_mode"]:
			_grade_missed(e)   # still open as the wave hit (a done one was removed by _resolve)
			_remove_event(e)
	# A storm READING (mission goal): the instruments were on and the lab working as the wave hit.
	# Safe mode switches them off, so it protects the ship but records nothing - the trade-off.
	var recorded: bool = state.loads.instruments and "scientist" not in state.offline
	var outside := _dose_storm(shields, big)
	if recorded:
		state.storms_recorded = int(state.storms_recorded) + 1
	if big:
		state.stats.big_storm = "shields" if shields else ("safe" if safe else "hit")
	if shields:
		_data_units += params.science * 0.5
		_say("SHIELDS HELD - storm data recorded!" if recorded else "SHIELDS HELD - but the instruments were OFF (no reading)")
	elif safe:
		state.stats.safe_modes = int(state.stats.safe_modes) + 1
		_say("SAFE MODE - the ship rides out the storm (no reading)" + _outside_text(outside))
	else:
		state.stats.disabled = int(state.stats.disabled) + 1
		state.blackout = BLACKOUT_TIME
		for load: String in LOADS:
			state.loads[load] = false
		state.power = maxf(state.power - (25.0 if big else 15.0), 0.0)
		_knock_offline("engineer", "Radiation: power bus")
		var others := ["comms", "scientist", "navigator"]
		if big:   # like MARIE in 2003: the instruments take the worst of it
			_knock_offline("scientist", "Storm fried the instruments")
			others.erase("scientist")
		_knock_offline(others[_rng.randi() % others.size()], "Radiation damage")
		_say(("STORM RECORDED - " if recorded else "") + "SHIELDS DOWN! SHIP DISABLED - BLACKOUT" + _outside_text(outside))
		if _rng.randf() < METEOR_CHANCE:   # dead in space, nobody can steer
			state.meteor.time_left = _rng.randf_range(METEOR_SHOW + 0.5, BLACKOUT_TIME - 1.5)
			state.meteor.y = _rng.randf_range(40.0, 230.0)
	_emit()


## A meteoroid hits the powerless ship: hull breach near the tank + one more station knocked out.
func _meteor_hits() -> void:
	state.meteor.time_left = -1.0
	state.meteor.seq = int(state.meteor.seq) + 1
	state.power = maxf(state.power - 5.0, 0.0)
	var breach := _impact(1.5, 0.25, "Meteoroid impact")
	_say("METEOROID IMPACT! " + ("HULL BREACH - grab a toolbox!" if breach else "Hull %d%%" % int(state.hull)))
	_emit()


static func _dust_idle(hits: int) -> Dictionary:
	return {phase = "", time_left = 0.0, hits = hits, wheels = false, tracker = false, mass = 0.0, hull = 100.0}


func _tick_dust(dt: float) -> void:
	var dust: Dictionary = state.dust
	match dust.phase:
		"":
			_dust_timer -= dt
			if _dust_timer <= 0.0 and state.cme.phase == "" and not _arriving():
				var warn: float = DUST_WARN + float(params.dust_warning)
				# What the minigame gets from the design (sent in the state, so clients know too).
				var side := 1.0 if _rng.randf() < 0.5 else -1.0
				state.dust = {phase = "warning", time_left = warn, duration = warn, hits = 0,
						wheels = bool(params.steer_free), tracker = float(params.dust_warning) > 0.0,
						mass = float(params.mass), hull = float(state.hull),
						cloud_y = side * _rng.randf_range(0.0, 0.25), cloud_w = CLOUD_W, course = 0.0,
						density = 1.0}
				var e := {id = _next_id, kind = "dust", role = "navigator", title = "Comet debris",
						time_left = warn + PILOT_WAIT, duration = warn + PILOT_WAIT, work_time = -1.0, repair = false}
				_next_id += 1
				state.events.append(e)
				Events.event_started.emit(e)
				_say("DEBRIS ON RADAR - NAVIGATOR: STEER AROUND IT OR FLY THROUGH")
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
					dust.density = _dust_density(dust)
					if dust.density <= 0.0:
						_dust_missed()
						return
					dust.phase = "stream"
					dust.time_left = PILOT_WAIT
					_say("DEBRIS! Navigator: dock at the Bridge to fly" if dust.density > 0.9
							else "Edge of the debris field (%d%%) - Navigator: fly it" % int(dust.density * 100))
					_emit()
				"stream":
					_end_dust(maxi(roundi(UNPILOTED_HITS * float(dust.density)), 1), 0.0, 0.0)   # nobody flew it
				"flying":
					_end_dust(2, 0.0, 0.0)                # pilot never reported back (disconnect)


## How much of the field the ship flies through: 0 = clear of it, 1 = dead centre.
func _dust_density(dust: Dictionary) -> float:
	var d := absf(float(dust.course) - float(dust.cloud_y))
	var reach := float(dust.cloud_w) + SHIP_W
	if d >= reach:
		return 0.0
	return clampf(1.0 - maxf(d - float(dust.cloud_w) * 0.4, 0.0) / (reach - float(dust.cloud_w) * 0.4), 0.3, 1.0)


## The course change worked: the cloud passes by, no flying, no hits.
func _dust_missed() -> void:
	state.dust = _dust_idle(int(state.dust.get("hits", 0)))
	for e: Dictionary in state.events.duplicate():
		if e.kind == "dust":
			_remove_event(e)
	_dust_timer = _debris_gap()
	_say("COURSE CHANGE PAID OFF - the debris passed us by")
	_emit()


## Result of a flight (or of nobody flying): each hit damages something; thrusters cost fuel.
func _end_dust(hits: int, thrust: float, turning: float) -> void:
	var wheels: bool = state.dust.get("wheels", false)
	hits = clampi(hits, 0, 4)
	var breached := 0
	for i in hits:
		breached += 1 if _impact(1.0, 0.0, "Debris impact") else 0
	var fuel_used := thrust * (0.5 if wheels else 1.0) + (0.0 if wheels else turning * 0.6)
	state.fuel = maxf(state.fuel - fuel_used, 0.0)
	state.dust = _dust_idle(int(state.dust.get("hits", 0)) + hits)
	for e: Dictionary in state.events.duplicate():
		if e.kind == "dust":
			_remove_event(e)
	_dust_timer = _debris_gap()
	state.stats.debris_hits = int(state.stats.debris_hits) + hits
	if hits == 0:
		_say("Debris cleared - no hits!")
	elif breached > 0:
		_say("%d hit(s) - HULL BREACH! Grab a toolbox and patch it" % hits)
	else:
		_say("Debris cleared - %d hit(s), hull %d%%" % [hits, int(state.hull)])
	_emit()


# --- hull, breaches, oxygen -------------------------------------------------------------------

## One hit on the hull. Wears it down; the weaker it is, the likelier this punches a breach.
## No breach = the old damage (a station knocked out, a dented tank, or just a dent). Returns breached.
func _impact(force: float, extra_breach: float, title: String) -> bool:
	state.hull = maxf(state.hull - params.hull_hit * force, 0.0)
	var chance: float = (BREACH_BASE + BREACH_WORN * (1.0 - state.hull / 100.0) + extra_breach) * params.breach_mult
	# Missions without the hull system (mission "hull": false) never breach: hits do the old damage.
	if _on("hull") and state.breaches.size() < MAX_BREACHES and _rng.randf() < clampf(chance, 0.05, 0.95):
		_open_breach()
		return true
	if _on("fire") and _rng.randf() < FIRE_ON_HIT:
		_start_fire("", title.to_lower() + " sparked it")
		return false
	var roll := _rng.randf()
	if roll < 0.5:
		var roles := ["engineer", "comms", "scientist", "navigator"].filter(func(r: String) -> bool: return r not in state.offline)
		if not roles.is_empty():
			_knock_offline(roles[_rng.randi() % roles.size()], title)
	elif roll < 0.5 + LEAK_CHANCE and _open_leak():
		pass   # cascade: leak -> fuel drains -> maybe not enough for the brake burn at Mars
	elif roll < 0.85:
		state.fuel = maxf(state.fuel - 8.0, 0.0)
	return false


func _open_breach() -> void:
	var at := _floor_point()
	state.stats.breaches = int(state.stats.breaches) + 1
	state.breaches.append({id = _next_id, x = at.x, y = at.y})
	_next_id += 1


func _load_layout() -> void:
	if _layout.is_empty():
		var f := FileAccess.open(LAYOUT_PATH, FileAccess.READ)
		_layout = JSON.parse_string(f.get_as_text()) if f else {}


## A free floor spot inside a room (`room_id`, "" = any): not on an obstacle, a station, a breach
## or a flame.
func _floor_point(room_id := "") -> Vector2:
	_load_layout()
	var rooms: Array = _layout.get("rooms", [])
	if room_id != "":
		rooms = rooms.filter(func(r: Dictionary) -> bool: return r.get("id", "") == room_id)
	var best := Vector2(240, 190)
	for attempt in 40:
		if rooms.is_empty():
			break
		var r: Dictionary = rooms[_rng.randi() % rooms.size()]
		var p := Vector2(_rng.randf_range(r.x + 10, r.x + r.w - 10), _rng.randf_range(r.y + 12, r.y + r.h - 8))
		var ok := true
		for o: Dictionary in _layout.get("obstacles", []):
			if Rect2(o.x, o.y, o.w, o.h).grow(7).has_point(p):
				ok = false
		for st: Dictionary in _layout.get("stations", []):
			if p.distance_to(Vector2(st.x, st.y)) < 18.0:
				ok = false
		for b: Dictionary in state.breaches:
			if p.distance_to(Vector2(b.x, b.y)) < 24.0:
				ok = false
		for fl: Dictionary in state.get("fires", []):
			if p.distance_to(Vector2(fl.x, fl.y)) < 14.0:
				ok = false
		if ok:
			return p
		best = p
	return best


func _tick_oxygen(dt: float) -> void:
	var open: int = state.breaches.size()
	var flames: int = state.fires.size() if _on("fire") else 0
	if open > 0 or flames > 0:
		state.oxygen = maxf(state.oxygen - (O2_DRAIN * open + FIRE_O2 * flames) * dt, 0.0)
		if state.oxygen <= 0.0:
			state.lost = "OXYGEN RAN OUT - " + ("the hull breaches were not sealed in time" if open > 0
					else "the fire burned up the cabin air")
			_say("MISSION LOST - " + state.lost)
			_emit()
			Events.mission_finished.emit({outcome = "lost", reason = state.lost,
					science_sent = state.science_sent, day = state.day})
	else:
		state.oxygen = minf(state.oxygen + O2_REFILL * dt, 100.0)


func _knock_offline(role: String, title: String) -> void:
	if role in state.offline:
		return
	state.offline.append(role)
	state.stats.knockouts = int(state.stats.knockouts) + 1
	var repair := {
		id = _next_id, kind = "repair", role = role, title = title,
		time_left = -1.0, duration = -1.0, work_time = params.repair_work, repair = true,
	}
	_next_id += 1
	state.events.append(repair)
	Events.event_started.emit(repair)


# --- astronauts ---------------------------------------------------------------------------

## Roster from the game: crew key ("P1" / "Crew_<peer id>") -> crew role. Keeps doses of known keys.
func set_crew(roster: Dictionary) -> void:
	if state.is_empty():
		return
	for key: String in roster:
		if not state.crew.has(key):
			state.crew[key] = {astronaut = Astronauts.id_for_role(str(roster[key])), dose = 0.0, sick = false, room = ""}
	_emit()


## Background dose (galactic cosmic rays, ~1.8 mSv per cruise day) + rooms from the host.
func _tick_crew(days: float) -> void:
	for key: String in state.crew:
		var a: Dictionary = state.crew[key]
		a.room = str(crew_rooms.get(key, a.room))
		_add_dose(key, Astronauts.dose("per_day") * days)


func _add_dose(key: String, msv: float) -> void:
	var a: Dictionary = state.crew[key]
	a.dose = float(a.dose) + msv
	if not a.sick and a.dose >= Astronauts.dose("sick_at"):
		a.sick = true
		state.stats.sick.append(a.astronaut)
		_say("%s has RADIATION SICKNESS - slower for the rest of the flight" % Astronauts.info(a.astronaut).name)


## The wave hits: shields up or inside the Cargo shelter = a small dose; caught outside = a big one.
## Returns the astronauts caught outside.
func _dose_storm(shields: bool, big: bool) -> Array:
	var outside := []
	for key: String in state.crew:
		var a: Dictionary = state.crew[key]
		if shields or a.room == SHELTER_ROOM:
			_add_dose(key, Astronauts.dose("storm_sheltered"))
			state.stats.sheltered = int(state.stats.sheltered) + 1
		else:
			_add_dose(key, Astronauts.dose("storm_big_outside" if big else "storm_outside"))
			state.stats.caught_outside = int(state.stats.caught_outside) + 1
			outside.append(a.astronaut)
	return outside


func _outside_text(outside: Array) -> String:
	if outside.is_empty():
		return " - crew safe in the shelter" if not state.crew.is_empty() else ""
	return " - CAUGHT OUTSIDE: " + ", ".join(outside.map(func(id: String) -> String: return Astronauts.short_name(id)))


## Cascade: a debris hit punctures a propellant line. No timer - it drains fuel until sealed.
func _open_leak() -> bool:
	for e: Dictionary in state.events:
		if e.kind == "fuel_leak":
			return false
	var e := {id = _next_id, kind = "fuel_leak", role = "navigator", title = "Fuel leak - seal it",
			time_left = -1.0, duration = -1.0, work_time = LEAK_WORK, repair = false}
	_next_id += 1
	state.events.append(e)
	state.stats.leaks = int(state.stats.leaks) + 1
	if float(state.stats.leak_day) < 0.0:
		state.stats.leak_day = state.day
	Events.event_started.emit(e)
	_say("DEBRIS PUNCTURED A FUEL LINE - NAVIGATOR: seal the leak! (-%.1f%% fuel / s)" % LEAK_RATE)
	return true


func _tick_leak(dt: float) -> void:
	for e: Dictionary in state.events:
		if e.kind == "fuel_leak":
			var lost := minf(LEAK_RATE * dt, state.fuel)
			state.fuel -= lost
			state.stats.leak_fuel = float(state.stats.leak_fuel) + lost
			return


# --- burn shove ------------------------------------------------------------------------------

static func _brace_idle() -> Dictionary:
	return {time_left = -1.0, duration = BRACE_TIME, dir = ""}


## The spooled-up course burn fires: fuel + power, the debris course change, and the crew get thrown.
func _tick_brace(dt: float) -> void:
	var brace: Dictionary = state.brace
	if float(brace.time_left) < 0.0:
		return
	brace.time_left = float(brace.time_left) - dt
	if float(brace.time_left) > 0.0:
		return
	var dir := str(brace.dir)
	state.brace = _brace_idle()
	state.fuel = maxf(state.fuel - params.burn_fuel, 0.0)
	state.power = maxf(state.power - 3.0, 0.0)
	_shove(Vector2(0.0, 1.0 if dir == "left" else -1.0), SHOVE_COURSE)
	if state.dust.phase == "warning":   # steering around the debris cloud
		var step := COURSE_STEP * (-1.0 if dir == "left" else 1.0)
		state.dust.course = clampf(float(state.dust.course) + step, -1.2, 1.2)
		var clear := _dust_density(state.dust) <= 0.0
		_say("NAV: heading %+.0f deg - %s" % [float(state.dust.course) * DEG_PER_UNIT,
				"CLEAR OF THE DEBRIS" if clear else "still in the field"])
	else:
		_say("NAV: %s burn - crew thrown (inertia)" % dir)
	_emit()


func _shove(dir: Vector2, strength: float) -> void:
	state.shove = {seq = int(state.shove.seq) + 1, x = dir.x, y = dir.y, strength = strength}


# --- pings + ticket grades ---------------------------------------------------------------------

func _tick_pings(dt: float) -> void:
	if state.pings.is_empty():
		return
	for p: Dictionary in state.pings:
		p.time_left = float(p.time_left) - dt
	state.pings = state.pings.filter(func(p: Dictionary) -> bool: return float(p.time_left) > 0.0)


## A timed ticket was done: PERFECT (half its time or more left) / GOOD / LATE. Repairs and other
## tickets without a timer are not graded. Juice + the report's CREW RATING only, never the score.
func _grade(event: Dictionary) -> void:
	if not _timed(event):
		return
	var frac := maxf(float(event.time_left), 0.0) / float(event.duration)
	var grade := "perfect" if frac >= GRADE_PERFECT else ("good" if frac >= GRADE_GOOD else "late")
	var g: Dictionary = state.grades
	g[grade] = int(g[grade]) + 1
	g.streak = int(g.streak) + 1
	g.best = maxi(int(g.best), int(g.streak))
	_log_grade(event, grade)


## A timed ticket ran out (or the storm hit with it still open): breaks the streak.
func _grade_missed(event: Dictionary) -> void:
	if not _timed(event):
		return
	state.grades.missed = int(state.grades.missed) + 1
	state.grades.streak = 0
	_log_grade(event, "missed")


## Has a countdown (repairs, leaks and fires have duration -1). time_left is already < 0 at expiry.
static func _timed(event: Dictionary) -> bool:
	return not bool(event.get("repair", false)) and float(event.get("duration", -1.0)) > 0.0


func _log_grade(event: Dictionary, grade: String) -> void:
	state.grades.seq = int(state.grades.seq) + 1
	state.grade_log.append({seq = state.grades.seq, id = int(event.id), grade = grade,
			role = str(event.get("role", "")), streak = int(state.grades.streak)})
	while state.grade_log.size() > 6:
		state.grade_log.pop_front()


# --- fire --------------------------------------------------------------------------------------

## Watts the base load + every switched-on load draw.
func _load_draw() -> float:
	var draw: float = params.base_w
	for load: String in LOADS:
		if state.loads[load]:
			draw += params[load + "_w"]
	return draw


## The power bus heats up while the loads draw more than the solar panels make (the battery covers
## the rest) and catches fire at 100%, in the room of the hungriest load. Cools when back in balance.
func _tick_heat(dt: float) -> void:
	var deficit := _load_draw() - float(params.solar_w)
	if state.blackout > 0.0 or state.cme.get("safe", false):
		deficit = 0.0   # everything is off anyway
	var heat: float = state.bus_heat
	if deficit > 0.0:
		heat += 100.0 / HEAT_TIME * clampf(deficit / 40.0, 0.5, 2.0) * dt
	else:
		heat = maxf(heat - HEAT_COOL * dt, 0.0)
	if heat >= HEAT_WARN and not _heat_warned:
		_heat_warned = true
		_say("POWER BUS OVERHEATING (+%d W) - ENGINEER: load OFF!" % int(deficit))
	elif heat < HEAT_WARN * 0.6:
		_heat_warned = false
	if heat >= 100.0:
		heat = 40.0
		var room := "engineering"
		var hungriest := 0.0
		for load: String in LOADS:
			if state.loads[load] and float(params[load + "_w"]) > hungriest:
				hungriest = float(params[load + "_w"])
				room = LOAD_ROOMS[load]
		state.stats.fire_overload = int(state.stats.fire_overload) + 1
		_start_fire(room, "overloaded wiring")
	state.bus_heat = heat


func _flames_in(room: String) -> int:
	var n := 0
	for f: Dictionary in state.fires:
		if f.room == room:
			n += 1
	return n


## A fire starts in `room` ("" = a random room). A room already burning just gets one more flame.
func _start_fire(room: String, why: String) -> void:
	if room == "":
		var ids: Array = ROOM_NAMES.keys()
		room = ids[_rng.randi() % ids.size()]
	var new_fire := _flames_in(room) == 0
	if not new_fire and _flames_in(room) >= FIRE_MAX:
		return
	_add_flame(room)
	if not new_fire:
		return
	_room_burn[room] = 0.0
	_room_grow[room] = FIRE_GROW
	_room_spread[room] = FIRE_SPREAD
	state.stats.fires = int(state.stats.fires) + 1
	var e := {id = _next_id, kind = "fire", role = "team", room = room, title = "FIRE: " + str(ROOM_NAMES[room]),
			time_left = -1.0, duration = -1.0, work_time = -1.0, repair = false}
	_next_id += 1
	state.events.append(e)
	Events.event_started.emit(e)
	_say("FIRE IN THE %s! Extinguishers: HUB / BRIDGE" % ROOM_NAMES[room])
	state.stats.last_fire = why
	_emit()


func _add_flame(room: String) -> void:
	var p := _floor_point(room)
	state.fires.append({id = _next_id, room = room, x = p.x, y = p.y})
	_next_id += 1


## Fires grow, spread through the doors and knock out the room's station if left burning.
func _tick_fire(dt: float) -> void:
	if state.fires.is_empty():
		return
	var rooms := {}
	for f: Dictionary in state.fires:
		rooms[f.room] = int(rooms.get(f.room, 0)) + 1
	for room: String in rooms:
		_room_burn[room] = float(_room_burn.get(room, 0.0)) + dt
		var role := _room_role(room)
		if role != "" and role != "team" and float(_room_burn[room]) >= FIRE_KNOCKOUT:
			_room_burn[room] = 0.0
			if role not in state.offline:
				state.stats.fire_knockouts = int(state.stats.fire_knockouts) + 1
				_knock_offline(role, "Fire damage: " + str(ROOM_NAMES[room]).to_lower())
				_say("FIRE burned out the %s station" % role.to_upper())
		_room_grow[room] = float(_room_grow.get(room, FIRE_GROW)) - dt
		if float(_room_grow[room]) <= 0.0:
			_room_grow[room] = FIRE_GROW
			if int(rooms[room]) < FIRE_MAX:
				_add_flame(room)
		if int(rooms[room]) >= FIRE_SPREAD_AT:
			_room_spread[room] = float(_room_spread.get(room, FIRE_SPREAD)) - dt
			if float(_room_spread[room]) <= 0.0:
				_room_spread[room] = FIRE_SPREAD
				var next := _neighbour(room)
				if next != "":
					_start_fire(next, "spread from the " + str(ROOM_NAMES[room]).to_lower())
		else:
			_room_spread[room] = FIRE_SPREAD


## One flame put out. The last one in a room ends that room's fire ticket.
func _douse(id: int) -> void:
	for f: Dictionary in state.fires.duplicate():
		if int(f.id) != id:
			continue
		state.fires.erase(f)
		var room := str(f.room)
		var left := _flames_in(room)
		if left > 0:
			_say("Flame out - %d more in the %s" % [left, ROOM_NAMES[room]])
			return
		_room_burn.erase(room)
		_room_grow.erase(room)
		_room_spread.erase(room)
		for e: Dictionary in state.events.duplicate():
			if e.kind == "fire" and e.get("room", "") == room:
				_remove_event(e)
		_say("FIRE IN THE %s IS OUT" % ROOM_NAMES[room])
		return


## A random neighbouring room (through a door) that is not burning yet, or "".
func _neighbour(room: String) -> String:
	_load_layout()
	var out := []
	for d: Dictionary in _layout.get("doors", []):
		var ends := str(d.get("id", "")).split("-")
		if ends.size() == 2 and room in ends:
			var other := ends[1] if ends[0] == room else ends[0]
			if _flames_in(other) == 0:
				out.append(other)
	return out[_rng.randi() % out.size()] if not out.is_empty() else ""


static func _room_role(room: String) -> String:
	for role: String in STATION_ROOMS:
		if STATION_ROOMS[role] == room:
			return role
	return ""


# --- frozen propellant -------------------------------------------------------------------------

## Sunlight at the ship (1 at Earth -> ~0.43 at Mars), the same transfer-ellipse model as ShipLighting.
func _sunlight() -> float:
	var p := clampf(ShipLighting.progress_of(state), 0.0, 1.0)
	var e := ShipLighting.TRANSFER_E
	var r := ShipLighting.TRANSFER_A * (1.0 - e * e) / (1.0 + e * cos(PI * p))
	return 1.0 / (r * r)


## Temperature the tanks drift towards right now: ~20 C in full sunlight, ~-8 C at Mars, + heater, + parts.
func _tank_equilibrium() -> float:
	return -30.0 + 50.0 * _sunlight() + float(params.get("tank_warm", 0.0)) \
			+ (HEATER_GAIN if state.loads.heater else 0.0)


func _tick_tanks(dt: float) -> void:
	var eq := _tank_equilibrium()
	var t: float = state.tank_temp
	t += (eq - t) * (1.0 - exp(-dt / TANK_TAU))
	state.tank_temp = t
	if state.fuel_frozen:
		state.stats.frozen_time = float(state.stats.frozen_time) + dt
	if not state.fuel_frozen and t <= FREEZE_C:
		state.fuel_frozen = true
		state.stats.freezes = int(state.stats.freezes) + 1
		for e: Dictionary in state.events.duplicate():
			if e.kind == "freeze":
				_grade_missed(e)
				_remove_event(e)
		_say("FUEL LINES FROZEN! No burns - ENGINEER: HEATER ON!")
		_emit()
	elif state.fuel_frozen and t >= THAW_C:
		state.fuel_frozen = false
		_say("Fuel lines thawed - burns work again")
		_emit()
	# Warm again with the heater still on: it is now just burning power (and heating the bus).
	if state.loads.heater and t >= WARM_C and not _warm_said:
		_warm_said = true
		_say("Tanks warm (%d C) - Engineer: heater can go OFF" % roundi(t))
	elif not state.loads.heater:
		_warm_said = false
	# The Engineer's ticket: open while the tanks are cooling towards freezing (or frozen) with the heater off.
	var cooling := t < COLD_C and eq < FREEZE_C
	var need: bool = not state.loads.heater and (state.fuel_frozen or cooling)
	var ticket := {}
	for e: Dictionary in state.events:
		if e.kind == "freeze":
			ticket = e
	if need:
		var eta := -1.0
		if not state.fuel_frozen:
			eta = TANK_TAU * log(maxf(t - eq, 0.01) / maxf(FREEZE_C - eq, 0.01))   # seconds until FREEZE_C
		if ticket.is_empty():
			ticket = {id = _next_id, kind = "freeze", role = "engineer", time_left = eta, duration = eta,
					title = "Fuel frozen - heater ON" if state.fuel_frozen else "Fuel lines freezing",
					work_time = 1.0, repair = false}
			_next_id += 1
			state.events.append(ticket)
			Events.event_started.emit(ticket)
			if not state.fuel_frozen:
				_say("FUEL LINES %d C AND COOLING - ENGINEER: HEATER ON!" % roundi(t))
			_emit()
		elif (float(ticket.duration) < 0.0) != state.fuel_frozen:
			_remove_event(ticket)   # froze (or thawed) under it: next tick opens the right kind
		else:
			ticket.time_left = minf(eta, float(ticket.duration)) if eta >= 0.0 else -1.0
	elif not ticket.is_empty():
		if state.loads.heater:
			_grade(ticket)   # switched on by hand at the Engineer station: counts too
		_remove_event(ticket)
		_emit()


func _refuse_if_frozen() -> bool:
	if not state.get("fuel_frozen", false):
		return false
	_say("FUEL FROZEN (%d C) - ENGINEER: HEATER ON!" % roundi(state.tank_temp))
	_emit()
	return true


## A station in a burning room can't be used ("TOO HOT"). Returns true (and says why) if refused.
func _refuse_if_burning(role: String) -> bool:
	var room: String = STATION_ROOMS.get(role, "")
	if room == "" or _flames_in(room) == 0:
		return false
	_say("TOO HOT - FIRE IN THE %s!" % ROOM_NAMES[room])
	_emit()
	return true


## After safe mode or a blackout everything is off. Instead of switching each load back on, the
## Engineer gets one ticket: hold USE once = instruments + transmitter ON (the real-world version is
## the ground team sending a single safe-mode recovery sequence). Missing it breaks nothing - the
## ship just stays dark (loads can still be switched by hand).
func _spawn_power_up(reason: String) -> void:
	for e: Dictionary in state.events:
		if e.kind == "power_up":
			_say(reason + " - Engineer: POWER UP the systems!")
			return
	var t := POWER_UP_TIME * _pace
	var e := {id = _next_id, kind = "power_up", role = "engineer", title = "Power up systems",
			time_left = t, duration = t, work_time = POWER_UP_WORK, repair = false}
	_next_id += 1
	state.events.append(e)
	Events.event_started.emit(e)
	_say(reason + " - Engineer: POWER UP the systems!")


func _expire(event: Dictionary) -> void:
	_grade_missed(event)
	_remove_event(event)
	if event.kind == "power_up":
		_say("Systems still OFF - Engineer: switch instruments + transmitter on by hand")
		return
	if EVENT_TYPES[event.kind].fault:
		if event.role not in state.offline:
			state.offline.append(event.role)
			state.stats.knockouts = int(state.stats.knockouts) + 1
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
		"burn":   # spools up first (BRACE), fires in _tick_brace
			if _refuse_if_offline(role) or _refuse_if_burning(role) or _refuse_if_frozen():
				return
			if float(state.brace.time_left) >= 0.0:
				_say("NAV: burn already spooling - BRACE!")
			else:
				var dir := str(action.get("dir", ""))
				state.brace = {time_left = BRACE_TIME, duration = BRACE_TIME, dir = dir}
				_say("NAV: %s BURN IN %.1f s - EVERYONE BRACE!" % [dir.to_upper(), BRACE_TIME])
		"ping":   # a crew call-out: one marker per player, newest replaces their old one
			var from := str(action.get("from", ""))
			state.pings = state.pings.filter(func(p: Dictionary) -> bool: return p.from != from)
			state.pings.append({id = _next_id, from = from, x = float(action.get("x", 0)), y = float(action.get("y", 0)),
					text = str(action.get("text", "HELP!")).left(24), role = str(action.get("role", "")),
					time_left = PING_TIME})
			_next_id += 1
			while state.pings.size() > MAX_PINGS:
				state.pings.pop_front()
		"douse":   # a crew member with an extinguisher put out one flame
			_douse(int(action.get("id", -1)))
		"drop_tool":
			state.toolboxes.append({id = _next_id, x = float(action.get("x", 0)), y = float(action.get("y", 0)),
					kind = str(action.get("kind", "toolbox"))})
			_next_id += 1
		"take_tool":   # first come, first served (co-op): the crew member checks the list before taking
			for t: Dictionary in state.toolboxes.duplicate():
				if int(t.id) == int(action.get("id", -1)):
					state.toolboxes.erase(t)
		"patch":   # a crew member with a toolbox sealed a hull breach
			for b: Dictionary in state.breaches.duplicate():
				if int(b.id) == int(action.get("id", -1)):
					state.breaches.erase(b)
					state.hull = minf(state.hull + PATCH_HULL, 100.0)
					_say("Hull breach sealed" + (" - %d more!" % state.breaches.size() if not state.breaches.is_empty() else ""))
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
			if _refuse_if_offline(role) or _refuse_if_burning(role):
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
				# Switched both back on by hand: the power-up ticket is done too.
				if state.loads.instruments and state.loads.transmitter:
					for e: Dictionary in state.events.duplicate():
						if e.kind == "power_up":
							_remove_event(e)
		"downlink":
			_downlinking = bool(action.get("on", false))
			if _downlinking and _refuse_if_burning("comms"):
				_downlinking = false
				return
			if _downlinking and not _can_downlink():
				if "comms" in state.offline:
					_say("COM: antenna OFFLINE")
				elif state.blackout > 0.0:
					_say("COM: no power - blackout")
				elif state.dust.phase == "flying":
					_say("COM: ship turned away from Earth (dodging)")
				elif state.cme.get("shields", false):
					_say("COM: shields are up - they block the radio until the storm passes")
				elif not state.loads.transmitter:
					_say("COM: transmitter is OFF - ask Engineer")
				else:
					_say("COM: no DSN station in view")
	_emit()


func _resolve(id: int) -> void:
	for event: Dictionary in state.events:
		if event.id != id:
			continue
		if event.kind == "fire":
			return  # not workable: each flame is put out with an extinguisher
		if _refuse_if_burning(str(event.role)):
			return  # ticket stays: put the fire out first
		if event.repair:
			state.offline.erase(event.role)
			_say("%s back ONLINE" % event.role.to_upper())
		elif event.kind == "dust":
			return  # not workable: it is dodged at the Bridge
		elif event.kind == "moi":
			if _refuse_if_frozen():
				return   # ticket stays: thaw the fuel, then brake
			if state.power < MOI_POWER:
				_say("MOI: battery too low for the burn (%d%% < %d%%) - ENGINEER: switch loads off!" % [int(state.power), int(MOI_POWER)])
				return   # ticket stays: try again once there is power
			var need := Orbits.moi_fuel(state.design)   # mission base x chosen orbit x tank
			state.stats.fuel_at_moi = state.fuel
			_grade(event)
			_remove_event(event)
			_shove(Vector2.RIGHT, SHOVE_BRAKE)   # braking: everyone keeps flying forward
			if state.fuel >= need:
				state.fuel -= need
				state.power = maxf(state.power - MOI_POWER, 0.0)
				_finish("orbit")
			else:
				state.fuel = 0.0
				_finish("flyby")
			return
		elif event.kind == "fuel_leak":
			_say("LEAK SEALED - it cost %d%% fuel" % int(state.stats.leak_fuel))
		elif event.kind == "freeze":   # the Engineer switches the heater on from the ticket
			if state.blackout > 0.0 or state.cme.get("safe", false):
				_say("NO POWER for the heater - %s" % ("blackout" if state.blackout > 0.0 else "safe mode"))
				_emit()
				return   # ticket stays
			state.loads.heater = true
			_say("HEATER ON - warming the fuel lines (%d C)" % roundi(state.tank_temp))
		elif event.kind == "power_up":
			if state.blackout > 0.0 or state.cme.get("safe", false):
				_say("Can't power up yet - %s" % ("solar bus still tripped" if state.blackout > 0.0 else "safe mode until the storm passes"))
				_emit()
				return   # ticket stays
			state.loads.instruments = true
			state.loads.transmitter = true
			_say("SYSTEMS ON: instruments + transmitter")
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
			# Goes into the recorder; only what Comms sends home scores. A full recorder loses it.
			var room: float = maxf(params.storage - _data_units, 0.0)
			var gained := minf(params.science, room)
			var lost: float = params.science - gained
			_data_units += gained
			state.science_lost += lost
			state.science_stored = _data_units
			state.observations = int(state.observations) + 1
			state.power = maxf(state.power - 5.0, 0.0)
			if gained <= 0.0:
				_say("STORAGE FULL - observation LOST! Comms: downlink first")
			elif lost > 0.0:
				_say("+%d science stored, %d LOST (storage full)" % [int(gained), int(lost)])
			else:
				_say("+%d SCIENCE stored - send it home from the COMMS ROOM (top left) in a DSN pass" % int(gained))
		else:
			_say("Fixed: " + event.title)
		_grade(event)
		_remove_event(event)
		return


func _can_downlink() -> bool:
	return state.dsn.site != "" and state.loads.transmitter and "comms" not in state.offline \
			and state.blackout <= 0.0 and state.dust.phase != "flying" and state.conjunction.phase != "active" \
			and not state.cme.get("shields", false)   # SIMPLIFIED: the shield bubble blocks the radio too


func _debris_gap() -> float:
	var gap: Array = _sim.get("debris_gap", [DUST_GAP.x, DUST_GAP.y])
	return _rng.randf_range(float(gap[0]), float(gap[1])) * _pace


# --- mission: solar conjunction, orbit insertion, the end ----------------------------------------

## Solar conjunction (MRO mission): the Sun passes between the ship and Earth and drowns the radio.
## A warning to empty the recorder, then CONJ_TIME s with no downlink at all (SIMPLIFIED: really ~2 weeks).
func _tick_conjunction(dt: float) -> void:
	var c: Dictionary = state.conjunction
	var at := float(_sim.get("conjunction_at", -1.0))
	match c.phase:
		"":
			if at > 0.0 and state.cruise_days > 0.0 and state.day >= state.cruise_days * at:
				state.conjunction = {phase = "warning", time_left = CONJ_WARN, duration = CONJ_WARN}
				_say("SOLAR CONJUNCTION IN %ds - COMMS: SEND EVERYTHING HOME NOW!" % int(CONJ_WARN))
				_emit()
		"warning", "active":
			c.time_left -= dt
			if c.time_left > 0.0:
				return
			if c.phase == "warning":
				state.conjunction = {phase = "active", time_left = CONJ_TIME, duration = CONJ_TIME}
				_downlinking = false
				_say("CONJUNCTION - the Sun blocks the radio. Recorder only!")
			else:
				state.conjunction = {phase = "done", time_left = 0.0, duration = 0.0}
				_say("Conjunction over - DSN contact is back")
			_emit()


## Arrival: the Mars Orbit Insertion burn. The Navigator holds the brake (MOI_WORK s); it needs
## MOI_POWER % battery and the mission's moi_fuel. Not enough fuel = a flyby; no burn in time = a miss.
func _tick_moi(_dt: float) -> void:
	if state.cruise_days <= 0.0 or state.moi.phase != "" or state.day < state.cruise_days:
		return
	state.moi = {phase = "window", time_left = MOI_WINDOW}
	var e := {id = _next_id, kind = "moi", role = "navigator", title = "Mars Orbit Insertion",
			time_left = MOI_WINDOW, duration = MOI_WINDOW, work_time = MOI_WORK, repair = false}
	_next_id += 1
	state.events.append(e)
	Events.event_started.emit(e)
	_say("ARRIVING AT MARS - NAVIGATOR: HOLD THE BRAKE AT THE BRIDGE! (fuel %d%% / need %d%% for %s orbit)" % [
			int(state.fuel), ceili(Orbits.moi_fuel(state.design)), str(Orbits.info(Orbits.id_of(state.design)).short).to_upper()])
	_emit()


## The mission is over: every peer's report reads state.finished.
func _finish(outcome: String) -> void:
	state.moi = {phase = "done", time_left = 0.0}
	var stars := 0
	state.finished = {outcome = outcome}
	stars = Missions.stars(state)
	state.finished = {outcome = outcome, stars = stars, day = state.day, fuel = state.fuel,
			science_sent = state.science_sent, science_lost = state.science_lost,
			storms_recorded = state.storms_recorded,
			bonus = Missions.bonus_data(state), healthy = Missions.healthy_crew(state),
			orbit_science = int(Orbits.result(state).sent), score = Missions.score(state)}
	match outcome:
		"orbit":
			_say("ORBIT! Welcome to Mars")
		"flyby":
			_say("Not enough fuel - FLYBY: we swing past Mars")
		_:
			_say("No brake burn - we MISSED Mars")
	_emit()
	Events.mission_finished.emit(state.finished)


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
